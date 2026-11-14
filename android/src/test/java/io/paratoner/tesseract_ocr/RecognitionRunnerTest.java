package io.paratoner.tesseract_ocr;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
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

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        assertEquals("recognized", reply.awaitSuccess());
        assertEquals(LANGUAGE, api.initLanguage.get());
        assertEquals(TESS_DATA, api.initDataPath.get());
        assertEquals(1, api.recycleCount());
        assertEquals(1, api.imageCount());
    }

    @Test
    public void usesTheHocrPathForHocrRequests() {
        api.hocrText = "<span class='ocr_line'>hi</span>";

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, true, reply);

        assertEquals("<span class='ocr_line'>hi</span>", reply.awaitSuccess());
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void missingArgumentsAreRejectedWithoutTouchingTheEngine() {
        runner.recognize(null, IMAGE, LANGUAGE, false, reply);
        runner.recognize(TESS_DATA, null, LANGUAGE, false, reply);

        assertNull(api.initLanguage.get());
        assertEquals(0, api.recycleCount());
        assertEquals(2, reply.errorCount());
        assertEquals("INVALID_ARGUMENT", reply.lastErrorCode());
    }

    @Test
    public void failedInitIsReportedThroughTheReply() {
        api.initResult = false;

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        assertEquals("INIT_ERROR", reply.awaitError());
        assertEquals(1, api.recycleCount());
        assertEquals(0, api.imageCount());
    }

    @Test
    public void failedRecognitionIsReportedInsteadOfCrashing() {
        api.readFailure = new IllegalStateException("native read failed");

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        assertEquals("RECOGNITION_ERROR", reply.awaitError());
        assertTrue(reply.lastErrorMessage().contains("native read failed"));
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void nativeLoadingFailureIsReportedAsANativeError() {
        api.initFailure = new UnsatisfiedLinkError("libtesseract.so missing");

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        assertEquals("NATIVE_ERROR", reply.awaitError());
        assertEquals(1, api.recycleCount());
    }

    @Test
    public void missingEngineHandleIsAnErrorNotACrash() {
        runner.stop();
        runner = new RecognitionRunner(() -> null);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        assertEquals("NATIVE_ERROR", reply.awaitError());
    }

    @Test
    public void workRunsOffTheCallingThread() {
        final String caller = Thread.currentThread().getName();

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

        reply.awaitSuccess();
        assertFalse(caller.equals(api.threadName.get()));
    }

    @Test
    public void everyRecognitionRecyclesItsOwnHandle() {
        api.text = "first";

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);
        reply.awaitSuccesses(1);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);
        reply.awaitSuccesses(2);

        assertEquals(2, api.recycleCount());
    }

    @Test
    public void detachDropsTheReplyOfAnInFlightRecognition() {
        api.releaseRead = new CountDownLatch(1);

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);
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

        runner.recognize(TESS_DATA, IMAGE, LANGUAGE, false, reply);

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
        final List<String> calls = new ArrayList<>();
        final CountDownLatch readEntered = new CountDownLatch(1);
        final AtomicInteger recycleCount = new AtomicInteger();
        final AtomicInteger imageCount = new AtomicInteger();

        volatile CountDownLatch releaseRead;
        volatile boolean initResult = true;
        volatile String text = "";
        volatile String hocrText = "";
        volatile RuntimeException readFailure;
        volatile Error initFailure;

        @Override
        public boolean init(String dataPath, String language) {
            calls.add("init");
            threadName.compareAndSet(null, Thread.currentThread().getName());
            initDataPath.set(dataPath);
            initLanguage.set(language);
            if (initFailure != null) {
                throw initFailure;
            }
            return initResult;
        }

        @Override
        public void setImage(File image) {
            calls.add("setImage");
            imageCount.incrementAndGet();
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
            calls.add("recycle");
            recycleCount.incrementAndGet();
        }

        int recycleCount() {
            return recycleCount.get();
        }

        int imageCount() {
            return imageCount.get();
        }

        void reset() {
            calls.clear();
            recycleCount.set(0);
            imageCount.set(0);
            initLanguage.set(null);
            initDataPath.set(null);
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
            return hocr ? hocrText : text;
        }
    }

    private static final class RecordingReply implements RecognitionRunner.Reply {

        private final List<String> errors = new ArrayList<>();
        private final AtomicInteger successCount = new AtomicInteger();
        private volatile Object lastSuccess;

        @Override
        public void success(Object value) {
            lastSuccess = value;
            successCount.incrementAndGet();
        }

        @Override
        public void error(String code, String message, Object details) {
            errors.add(code + ": " + message);
        }

        int errorCount() {
            return errors.size();
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
            while (successCount.get() < expectedSuccesses && errors.isEmpty()) {
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