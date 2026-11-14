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

        if (imagePath == null) {
            reply.error(
                INVALID_ARGUMENT,
                "Image path must not be null!",
                null
            );
            return;
        }

        final String languageOrDefault = language == null ? "eng" : language;
        final File image = new File(imagePath);

        try {
            executor.execute(
                () ->
                    recognizeOnWorkerThread(
                        tessDataPath,
                        image,
                        languageOrDefault,
                        hocr,
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
        String language,
        boolean hocr,
        Reply reply
    ) {
        NativeOcrApi baseApi = null;
        try {
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
                if (!baseApi.init(tessDataPath, language)) {
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
            baseApi.setImage(image);
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
}
