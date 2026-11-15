package io.paratoner.tesseract_ocr;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.File;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

/**
 * Lifecycle rules of the native recognition path (issue #49): a handle is only
 * ever touched by the thread that created it, a failure is answered through the
 * reply instead of crashing the host, and a detached plugin neither accepts new
 * work nor replies to a dead engine.
 */
public class RecognitionRunnerTest {

    private static final String TESS_DATA = "/data/data/app/files/tessdata";
    private static final String IMAGE = "/data/data/app/cache/scan.png";
    private static final byte[] IMAGE_BYTES = {137, 80, 78, 71, 13};
    private static final String LANGUAGE = "eng";
    private static final long TIMEOUT_SECONDS = 5;

    private RecognitionRunner runner;
    private FakeApi api;
    private RecordingReply reply;

    @Before
    public void setUp() {
        api = new FakeApi();
        reply = new RecordingReply();
        runner = new RecognitionRunner(() -> api);
    }

    @After
    public void tearDown() {
        runner.stop();
    }

    @Test
    public void recognizesTextAndRecyclesTheHandle() {
        api.text = "recognized";

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("recognized", reply.awaitSuccess());
        assertEquals(LANGUAGE, api.initLanguage.get());
        assertEquals(TESS_DATA, api.initDataPath.get());
        assertEquals(1, api.recycleCount());
        assertEquals(1, api.imageCount());
    }

    @Test
    public void usesTheHocrPathForHocrRequests() {
        api.hocrText = "<span class='ocr_line'>hi</span>";

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, true, OcrOptions.NONE, reply);

        assertEquals("<span class='ocr_line'>hi</span>", reply.awaitSuccess());
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void missingArgumentsAreRejectedWithoutTouchingTheEngine() {
        runner.recognize(null, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);
        runner.recognize(TESS_DATA, null, LANGUAGE, false, OcrOptions.NONE, reply);

        assertNull(api.initLanguage.get());
        assertEquals(0, api.recycleCount());
        assertEquals(2, reply.errorCount());
        assertEquals("INVALID_ARGUMENT", reply.lastErrorCode());
    }

    @Test
    public void imageBytesAreRecognizedWithoutAnImagePath() {
        api.text = "recognized";

        runner.recognize(
            TESS_DATA,
            null,
            IMAGE_BYTES,
            LANGUAGE,
            false,
            OcrOptions.NONE,
            reply
        );

        assertEquals("recognized", reply.awaitSuccess());
        assertEquals(LANGUAGE, api.initLanguage.get());
        assertEquals(TESS_DATA, api.initDataPath.get());
        assertEquals(0, api.imageCount());
        assertEquals(1, api.imageBytesCount());
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void aCallWithoutAnImageIsRejectedWithoutTouchingTheEngine() {
        runner.recognize(TESS_DATA, null, null, LANGUAGE, false, OcrOptions.NONE, reply);
        runner.recognize(
            TESS_DATA,
            null,
            new byte[0],
            LANGUAGE,
            false,
            OcrOptions.NONE,
            reply
        );

        assertNull(api.initLanguage.get());
        assertEquals(0, api.recycleCount());
        assertEquals(2, reply.errorCount());
        assertEquals("INVALID_ARGUMENT", reply.lastErrorCode());
    }

    @Test
    public void undecodableImageBytesAreReportedAsARecognitionError() {
        api.setImageFailure =
            new IllegalArgumentException("Image bytes could not be decoded as a bitmap.");

        runner.recognize(
            TESS_DATA,
            null,
            IMAGE_BYTES,
            LANGUAGE,
            false,
            OcrOptions.NONE,
            reply
        );

        assertEquals("RECOGNITION_ERROR", reply.awaitError());
        assertTrue(reply.lastErrorMessage().contains("could not be decoded"));
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void failedInitIsReportedThroughTheReply() {
        api.initResult = false;

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("INIT_ERROR", reply.awaitError());
        assertEquals(1, api.recycleCount());
        assertEquals(0, api.imageCount());
    }

    /**
     * A tessdata directory on the device (issue #56) is resolved to the datapath
     * {@code TessBaseAPI.init} reads, while a datapath is passed through: the two
     * layouts differ by one path segment, and the engine only accepts one.
     */
    @Test
    public void aTessdataDirectoryIsResolvedToItsParentForInit() throws Exception {
        final File root = temporaryDirectory();
        final File tessdata = new File(root, "tessdata");
        assertTrue(tessdata.mkdirs());
        assertTrue(new File(tessdata, "eng.traineddata").createNewFile());

        assertEquals(root.getPath(), RecognitionRunner.dataPathFor(tessdata.getPath()));
    }

    @Test
    public void aDataPathIsPassedThroughUnchanged() throws Exception {
        final File root = temporaryDirectory();
        final File tessdata = new File(root, "tessdata");
        assertTrue(tessdata.mkdirs());
        assertTrue(new File(tessdata, "eng.traineddata").createNewFile());

        assertEquals(root.getPath(), RecognitionRunner.dataPathFor(root.getPath()));
    }

    @Test
    public void aPathWithNoTrainedDataIsPassedThroughForTheEngineToJudge() {
        assertEquals(
            TESS_DATA,
            RecognitionRunner.dataPathFor(TESS_DATA)
        );
    }

    /**
     * The direct layout — files in a directory not named "tessdata" — has no
     * datapath the engine can read (issue #56 review): the parent's
     * {@code tessdata/} does not hold the files, and {@code TessBaseAPI.init}
     * reads nothing else. Taking the parent anyway would point the engine at a
     * tessdata set that does not exist.
     */
    @Test
    public void aDirectLayoutDirectoryHasNoDatapathTheEngineCanRead() throws Exception {
        final File root = temporaryDirectory();
        final File direct = new File(root, "tessfiles");
        assertTrue(direct.mkdirs());
        assertTrue(new File(direct, "eng.traineddata").createNewFile());

        assertNull(RecognitionRunner.dataPathFor(direct.getPath()));
    }

    /** The refused direct layout never reaches the engine at all. */
    @Test
    public void aDirectLayoutTessdataDirectoryIsRefusedBeforeTheEngine() throws Exception {
        final File root = temporaryDirectory();
        final File direct = new File(root, "tessfiles");
        assertTrue(direct.mkdirs());
        assertTrue(new File(direct, "eng.traineddata").createNewFile());

        runner.recognize(direct.getPath(), IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals(RecognitionRunner.TESSDATA_PATH_INVALID, reply.awaitError());
        assertNull(api.initDataPath.get());
        assertEquals(0, api.recycleCount());
        assertEquals(0, api.imageCount());
    }

    private static File temporaryDirectory() throws Exception {
        final File root = File.createTempFile("tessdata_runner_", "");
        assertTrue(root.delete());
        assertTrue(root.mkdirs());
        root.deleteOnExit();
        return root;
    }

    @Test
    public void failedRecognitionIsReportedInsteadOfCrashing() {
        api.readFailure = new IllegalStateException("native read failed");

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("RECOGNITION_ERROR", reply.awaitError());
        assertTrue(reply.lastErrorMessage().contains("native read failed"));
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void initThrowsAnErrorIsReportedAsANativeError() {
        api.initFailure = new UnsatisfiedLinkError("libtesseract.so missing");

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("NATIVE_ERROR", reply.awaitError());
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void missingTessdataIsReportedAsAnInitErrorNotARecognitionError() {
        // TessBaseAPI.init rejects a bad datapath by throwing IllegalArgumentException
        // rather than returning false, which is the case the review flagged: it must
        // still arrive as INIT_ERROR, not RECOGNITION_ERROR.
        api.initException = new IllegalArgumentException(
            "Data path must contain subfolder tessdata!"
        );

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("INIT_ERROR", reply.awaitError());
        assertTrue(reply.lastErrorMessage().contains("tessdata"));
        assertEquals(1, api.recycleCount());
        assertEquals(0, api.imageCount());
    }

    @Test
    public void aSaturatedIntakeIsAnsweredAsBusyInsteadOfDetached() {
        api.releaseRead = new CountDownLatch(1);

        // One recognition runs, the intake holds its bound, the rest are refused.
        for (int i = 0; i <= RecognitionRunner.MAX_QUEUED_RECOGNITIONS + 1; i++) {
            runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);
        }
        assertTrue(api.awaitReadStarted());

        assertEquals(1, reply.errorCount());
        assertEquals("BUSY", reply.lastErrorCode());

        api.releaseRead.countDown();
        assertEquals(0, reply.successCount());
    }

    @Test
    public void missingEngineHandleIsAnErrorNotACrash() {
        runner.stop();
        runner = new RecognitionRunner(() -> null);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("NATIVE_ERROR", reply.awaitError());
    }

    @Test
    public void anEngineThrowWhileApplyingOptionsIsReportedRatherThanCrashing() {
        // An unrecognised variable never gets here — setVariable returns false
        // for one — so this pins the runner's containment of an unexpected
        // throw from the engine during applyOptions (a native bridge can fail
        // with an Error here as well as an Exception).
        api.optionsFailure = new IllegalStateException("engine threw");

        runner.recognize(
            TESS_DATA,
            IMAGE,
            LANGUAGE,
            false,
            new OcrOptions(7, java.util.Collections.<String, String>emptyMap()),
            reply
        );

        assertEquals("RECOGNITION_ERROR", reply.awaitError());
        assertTrue(reply.lastErrorMessage().contains("engine threw"));
        assertEquals(1, api.recycleCount());
        assertEquals(0, api.imageCount());
    }

    @Test
    public void workRunsOffTheCallingThread() {
        final String caller = Thread.currentThread().getName();

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        reply.awaitSuccess();
        assertFalse(caller.equals(api.threadName.get()));
    }

    @Test
    public void theRequestedOptionsReachTheEngineAfterInit() {
        final Map<String, String> variables = new LinkedHashMap<>();
        variables.put("preserve_interword_spaces", "1");
        runner.recognize(
            TESS_DATA,
            IMAGE,
            LANGUAGE,
            false,
            new OcrOptions(7, variables),
            reply
        );

        reply.awaitSuccess();
        assertEquals(Integer.valueOf(7), api.appliedPageSegMode.get());
        assertEquals(variables, api.appliedVariables.get());
    }

    @Test
    public void noOptionsStillReachTheEngineAsAnEmptyMap() {
        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        reply.awaitSuccess();
        assertNull(api.appliedPageSegMode.get());
        assertTrue(api.appliedVariables.get().isEmpty());
    }

    @Test
    public void everyRecognitionRecyclesItsOwnHandle() {
        api.text = "first";

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);
        reply.awaitSuccesses(1);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);
        reply.awaitSuccesses(2);

        assertEquals(2, api.recycleCount());
    }

    @Test
    public void detachDropsTheReplyOfAnInFlightRecognition() {
        api.releaseRead = new CountDownLatch(1);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);
        assertTrue(api.awaitReadStarted());

        runner.stop();
        api.releaseRead.countDown();

        // The native read is already running: it is never recycled from another
        // thread, it simply finishes and its reply is dropped with the engine.
        assertEquals(1, api.awaitRecycleCount());
        assertEquals(0, reply.successCount());
        assertEquals(0, reply.errorCount());
    }

    @Test
    public void noWorkIsAcceptedAfterDetach() {
        runner.stop();
        api.reset();

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, OcrOptions.NONE, reply);

        assertEquals("DETACHED", reply.awaitError());
        assertNull(api.initLanguage.get());
        assertEquals(0, api.recycleCount());
    }

    @Test
    public void detachIsIdempotent() {
        runner.stop();

        runner.stop();

        assertEquals(0, api.recycleCount());
    }

    private static final class FakeApi implements NativeOcrApi {

        final AtomicReference<String> threadName = new AtomicReference<>();
        final AtomicReference<String> initLanguage = new AtomicReference<>();
        final AtomicReference<String> initDataPath = new AtomicReference<>();
        final AtomicReference<Integer> appliedPageSegMode = new AtomicReference<>();
        final AtomicReference<Map<String, String>> appliedVariables =
            new AtomicReference<>();
        final CountDownLatch readEntered = new CountDownLatch(1);
        final AtomicInteger recycleCount = new AtomicInteger();
        final AtomicInteger imageCount = new AtomicInteger();
        final AtomicInteger imageBytesCount = new AtomicInteger();

        volatile CountDownLatch releaseRead;
        volatile boolean initResult = true;
        volatile String text = "";
        volatile String hocrText = "";
        volatile RuntimeException readFailure;
        volatile Error initFailure;
        volatile RuntimeException initException;
        volatile RuntimeException setImageFailure;
        volatile RuntimeException readException;
        volatile RuntimeException optionsFailure;

        @Override
        public boolean init(String dataPath, String language) {
            threadName.compareAndSet(null, Thread.currentThread().getName());
            initDataPath.set(dataPath);
            initLanguage.set(language);
            if (initFailure != null) {
                throw initFailure;
            }
            if (initException != null) {
                throw initException;
            }
            return initResult;
        }

        @Override
        public void applyOptions(Integer pageSegMode, Map<String, String> variables) {
            appliedPageSegMode.set(pageSegMode);
            appliedVariables.set(
                variables == null
                    ? new LinkedHashMap<String, String>()
                    : new LinkedHashMap<>(variables)
            );
            if (optionsFailure != null) {
                throw optionsFailure;
            }
        }

        @Override
        public void setImage(File image) {
            imageCount.incrementAndGet();
            if (setImageFailure != null) {
                throw setImageFailure;
            }
        }

        @Override
        public void setImageBytes(byte[] bytes) {
            imageBytesCount.incrementAndGet();
            if (setImageFailure != null) {
                throw setImageFailure;
            }
        }

        @Override
        public String getUtf8Text() {
            return read(false);
        }

        @Override
        public String getHocrText() {
            return read(true);
        }

        @Override
        public void recycle() {
            recycleCount.incrementAndGet();
        }

        int recycleCount() {
            return recycleCount.get();
        }

        int imageCount() {
            return imageCount.get();
        }

        int imageBytesCount() {
            return imageBytesCount.get();
        }

        void reset() {
            recycleCount.set(0);
            imageCount.set(0);
            imageBytesCount.set(0);
            initLanguage.set(null);
            initDataPath.set(null);
            appliedPageSegMode.set(null);
            appliedVariables.set(null);
        }

        boolean awaitReadStarted() {
            try {
                return readEntered.await(TIMEOUT_SECONDS, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return false;
            }
        }

        int awaitRecycleCount() {
            final long deadline = System.nanoTime()
                + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS);
            while (recycleCount.get() == 0) {
                if (System.nanoTime() > deadline) {
                    fail("handle was not recycled within " + TIMEOUT_SECONDS + "s");
                }
                try {
                    Thread.sleep(2);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
            return recycleCount.get();
        }

        private String read(boolean hocr) {
            readEntered.countDown();
            final CountDownLatch release = this.releaseRead;
            if (release != null) {
                try {
                    release.await(TIMEOUT_SECONDS, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            if (readFailure != null) {
                throw readFailure;
            }
            if (readException != null) {
                throw readException;
            }
            return hocr ? hocrText : text;
        }
    }

    private static final class RecordingReply implements RecognitionRunner.Reply {

        private final List<String> errors = new CopyOnWriteArrayList<>();
        private final AtomicInteger successCount = new AtomicInteger();
        private final AtomicInteger errorCount = new AtomicInteger();
        private volatile Object lastSuccess;

        @Override
        public void success(Object value) {
            lastSuccess = value;
            successCount.incrementAndGet();
        }

        @Override
        public void error(String code, String message, Object details) {
            // Written on the recognition thread and read by the test thread: the
            // list and the counter publish through thread-safe types, so the spin
            // below observes the reply instead of timing out on a loaded machine.
            errors.add(code + ": " + message);
            errorCount.incrementAndGet();
        }

        int errorCount() {
            return errorCount.get();
        }

        int successCount() {
            return successCount.get();
        }

        String lastErrorCode() {
            return errors.isEmpty()
                ? null
                : errors.get(errors.size() - 1).split(":", 2)[0];
        }

        String lastErrorMessage() {
            return errors.isEmpty() ? null : errors.get(errors.size() - 1);
        }

        String awaitSuccess() {
            return awaitSuccesses(1);
        }

        String awaitSuccesses(int expected) {
            awaitDelivery(expected);
            assertEquals(0, errors.size());
            return (String) lastSuccess;
        }

        String awaitError() {
            awaitDelivery();
            return lastErrorCode();
        }

        private void awaitDelivery() {
            awaitDelivery(1);
        }

        private void awaitDelivery(int expectedSuccesses) {
            final long deadline = System.nanoTime()
                + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS);
            while (successCount.get() < expectedSuccesses && errorCount.get() == 0) {
                if (System.nanoTime() > deadline) {
                    fail(
                        "fewer than " + expectedSuccesses + " replies within "
                            + TIMEOUT_SECONDS + "s"
                    );
                }
                try {
                    Thread.sleep(2);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
    }
}
