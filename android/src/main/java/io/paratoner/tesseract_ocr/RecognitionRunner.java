package io.paratoner.tesseract_ocr;

import java.io.File;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Runs recognitions for one engine attachment.
 *
 * <p>The rules the native lifecycle needs (issue #49):
 *
 * <ul>
 *   <li>a handle belongs to the recognition thread that created it, so a detach
 *       can never recycle a handle another thread is still reading — the thread
 *       that read the image is the thread that releases it, in a {@code finally};
 *   <li>every native touch is null-guarded, so a missing, released or
 *       never-initialized handle is reported instead of raising an NPE;
 *   <li>a failure of any kind is answered through {@link Reply} rather than
 *       escaping into the host process.
 * </ul>
 */
class RecognitionRunner {

    private static final String THREAD_NAME = "tesseract-ocr-recognition";

    static final String BUSY = "BUSY";
    static final String DETACHED = "DETACHED";
    static final String INVALID_ARGUMENT = "INVALID_ARGUMENT";
    static final String INIT_ERROR = "INIT_ERROR";
    static final String NATIVE_ERROR = "NATIVE_ERROR";
    static final String RECOGNITION_ERROR = "RECOGNITION_ERROR";

    /**
     * A tessdata path the Android engine cannot read. Not UPPER_SNAKE like the
     * codes above on purpose: it is the same {@code tessdata-path-invalid} code
     * the Dart resolver refuses an unusable directory with, so a caller of
     * {@code extractText} switches on one code for every tessdata refusal.
     */
    static final String TESSDATA_PATH_INVALID = "tessdata-path-invalid";

    /** The subdirectory name {@code TessBaseAPI.init} reads its data from. */
    private static final String TESSDATA_DIRECTORY_NAME = "tessdata";

    /**
     * How many recognitions may wait for the worker thread.
     *
     * <p>An unbounded intake lets a caller that scans faster than OCR completes
     * park one full {@code init()} — a language-model load — per queued item,
     * each with a pending Dart future and no timeout. A full queue is answered
     * with {@link #BUSY} instead.
     */
    static final int MAX_QUEUED_RECOGNITIONS = 4;

    /** The reply channel of one recognition. */
    interface Reply {
        void success(Object value);

        void error(String code, String message, Object details);
    }

    /** Creates the native handle; runs on the recognition thread. */
    interface ApiFactory {
        NativeOcrApi create();
    }

    private final ApiFactory factory;

    private final ThreadPoolExecutor executor = new ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        new LinkedBlockingQueue<Runnable>(MAX_QUEUED_RECOGNITIONS),
        command -> {
            final Thread thread = new Thread(command, THREAD_NAME);
            thread.setDaemon(true);
            return thread;
        },
        new ThreadPoolExecutor.AbortPolicy()
    );

    private final AtomicBoolean attached = new AtomicBoolean(true);

    RecognitionRunner(ApiFactory factory) {
        this.factory = factory;
    }

    /** Stops accepting work. Safe to call twice, and from any thread. */
    void stop() {
        attached.set(false);
        executor.shutdown();
    }

    void recognize(
        String tessDataPath,
        String imagePath,
        String language,
        boolean hocr,
        OcrOptions options,
        Reply reply
    ) {
        recognize(
            tessDataPath,
            imagePath,
            null,
            language,
            hocr,
            options,
            reply
        );
    }

    /**
     * Recognizes either the image at {@code imagePath} or the encoded image in
     * {@code imageBytes}.
     *
     * <p>Exactly one of the two is given: the caller either has a file or has
     * the bytes, and an engine that could take either would have to guess. A
     * call carrying neither is a caller mistake, answered with
     * {@link #INVALID_ARGUMENT} before the engine is touched.
     *
     * <p>A call carrying both is a channel-contract violation rather than a
     * caller mistake, so it is not rejected here: the path wins, and the
     * {@code imageBytes} form only exists for callers that have no file.
     */
    void recognize(
        String tessDataPath,
        String imagePath,
        byte[] imageBytes,
        String language,
        boolean hocr,
        OcrOptions options,
        Reply reply
    ) {
        if (!attached.get()) {
            reply.error(
                DETACHED,
                "Tesseract OCR has been detached from the engine.",
                null
            );
            return;
        }

        if (tessDataPath == null) {
            reply.error(
                INVALID_ARGUMENT,
                "Data path must not be null! Ensure tessdata is properly loaded.",
                null
            );
            return;
        }

        final boolean hasBytes = imageBytes != null && imageBytes.length > 0;
        if (imagePath == null && !hasBytes) {
            reply.error(
                INVALID_ARGUMENT,
                "Either an image path or image bytes must be provided.",
                null
            );
            return;
        }

        final String languageOrDefault = language == null ? "eng" : language;
        final File image = imagePath == null ? null : new File(imagePath);
        final byte[] bytes = hasBytes ? imageBytes : null;
        final OcrOptions resolvedOptions = options == null ? OcrOptions.NONE : options;

        try {
            executor.execute(
                () ->
                    recognizeOnWorkerThread(
                        tessDataPath,
                        image,
                        bytes,
                        languageOrDefault,
                        hocr,
                        resolvedOptions,
                        reply
                    )
            );
        } catch (RejectedExecutionException e) {
            // Either detached between the check above and the submission, or the
            // intake is saturated. A saturated runner is busy, not gone: only a
            // refusal from a shut-down executor means the engine left.
            if (!attached.get()) {
                reply.error(
                    DETACHED,
                    "Tesseract OCR has been detached from the engine.",
                    null
                );
                return;
            }
            reply.error(
                BUSY,
                "Tesseract is still recognizing earlier images. Try again.",
                null
            );
        }
    }

    private void recognizeOnWorkerThread(
        String tessDataPath,
        File image,
        byte[] imageBytes,
        String language,
        boolean hocr,
        OcrOptions options,
        Reply reply
    ) {
        NativeOcrApi baseApi = null;
        try {
            final String dataPath = dataPathFor(tessDataPath);
            if (dataPath == null) {
                // A direct-layout directory (files not under a directory named
                // "tessdata") has no datapath the engine can read: refusing it
                // here keeps the failure actionable and the engine untouched,
                // where taking the parent would have init read a tessdata set
                // that does not exist (issue #56 review).
                reply.error(
                    TESSDATA_PATH_INVALID,
                    "Tesseract tessdata directory '"
                        + tessDataPath
                        + "' holds the .traineddata files directly but is not "
                        + "named 'tessdata'. On Android the engine reads "
                        + "<datapath>/tessdata/<lang>.traineddata, so pass the "
                        + "directory that holds a tessdata subdirectory (or "
                        + "name this directory tessdata).",
                    null
                );
                return;
            }

            baseApi = factory.create();
            if (baseApi == null) {
                reply.error(
                    NATIVE_ERROR,
                    "Tesseract could not create a native handle.",
                    null
                );
                return;
            }

            try {
                if (!baseApi.init(dataPath, language)) {
                    reply.error(
                        INIT_ERROR,
                        "Failed to initialize Tesseract for language '"
                            + language
                            + "'. Ensure the tessdata files are bundled.",
                        null
                    );
                    return;
                }
            } catch (IllegalArgumentException e) {
                // The adapter's init rejects an unusable datapath or language by
                // throwing rather than returning false, and that is still a
                // failed init: a caller switching on INIT_ERROR for "tessdata
                // missing" must keep seeing it.
                reply.error(
                    INIT_ERROR,
                    "Failed to initialize Tesseract for language '"
                        + language
                        + "'. Ensure the tessdata files are bundled. ("
                        + e.getMessage()
                        + ")",
                    null
                );
                return;
            }

            // The caller's options sit between init and the image: the PSM is
            // part of how the engine was configured. A throw from the engine
            // here — an Exception or, from a native bridge, an Error — is
            // contained by the catch below and reported as a recognition
            // error; it never reaches the host process.
            baseApi.applyOptions(options.pageSegMode(), options.variables());
            // Precedence when a call carries both forms: the path wins, since
            // the bytes form only exists for callers that have no file. The
            // Dart layer sends exactly one, so this documents the contract for
            // a future native caller rather than arbitrating a live case.
            if (image != null) {
                baseApi.setImage(image);
            } else {
                baseApi.setImageBytes(imageBytes);
            }
            final String recognizedText = hocr
                ? baseApi.getHocrText()
                : baseApi.getUtf8Text();

            // The engine may be gone by now: the reply is dropped, never
            // delivered to a detached channel.
            if (!attached.get()) {
                return;
            }
            reply.success(recognizedText);
        } catch (Throwable t) {
            // A native bridge can fail with an Error (UnsatisfiedLinkError) as
            // well as an Exception; neither may reach the host process.
            if (!attached.get()) {
                return;
            }
            final boolean nativeFailure = !(t instanceof Exception);
            reply.error(
                nativeFailure ? NATIVE_ERROR : RECOGNITION_ERROR,
                (nativeFailure ? "Tesseract native error: " : "Recognition failed: ")
                    + t,
                null
            );
        } finally {
            // Always on the thread that read the image, and never twice.
            recycle(baseApi);
        }
    }

    private static void recycle(NativeOcrApi baseApi) {
        if (baseApi == null) {
            return;
        }
        try {
            baseApi.recycle();
        } catch (Throwable ignored) {
            // Releasing a broken handle must not mask the recognition result.
        }
    }

    /**
     * The datapath {@link NativeOcrApi#init} expects for {@code tessDataPath},
     * or {@code null} when {@code tessDataPath} names a tessdata directory this
     * engine cannot read.
     *
     * <p>{@code TessBaseAPI.init} reads {@code <datapath>/tessdata/<lang>.traineddata},
     * while every other platform of this plugin reads the directory that holds
     * the {@code .traineddata} files itself — and that is the shape a caller
     * pointing recognition at a directory on the device hands us (issue #56: a
     * downloaded or shared tessdata directory, with no asset copy step). A
     * directory named {@code tessdata} is therefore resolved to its parent, and
     * a path that is already a datapath (the bundled asset copy's layout) is
     * passed through untouched.
     *
     * <p>What has no datapath is the <i>direct</i> layout — the files sitting in
     * a directory <i>not</i> named {@code tessdata}: the parent's
     * {@code tessdata/} does not hold them, and the engine reads nothing else,
     * so taking the parent would send init after a file that does not exist.
     * Such a directory resolves to {@code null} and the caller is refused with
     * {@link #TESSDATA_PATH_INVALID} instead of left to an opaque init failure.
     * iOS and macOS pass the file-holding directory to the engine directly, so
     * the same directory is fine there.
     */
    static String dataPathFor(String tessDataPath) {
        final File directory = new File(tessDataPath);
        if (!holdsTrainedData(directory)) {
            return tessDataPath;
        }
        if (!TESSDATA_DIRECTORY_NAME.equals(directory.getName())) {
            // Direct layout: the files are here, but the engine only ever reads
            // <datapath>/tessdata/<lang>.traineddata — the parent is not it.
            return null;
        }
        final String parent = directory.getParent();
        // A tessdata directory at the filesystem root has no parent to report.
        return parent == null ? tessDataPath : parent;
    }

    /** Whether {@code directory} holds at least one {@code .traineddata} file. */
    private static boolean holdsTrainedData(File directory) {
        final File[] trainedData = directory.listFiles(
            (File file) -> file.isFile()
                && file.getName().endsWith(".traineddata"));
        return trainedData != null && trainedData.length > 0;
    }
}
