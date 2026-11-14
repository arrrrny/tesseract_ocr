package io.paratoner.tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;
import java.util.concurrent.atomic.AtomicBoolean;

public class TesseractOcrPlugin implements MethodCallHandler, FlutterPlugin {

    private MethodChannel channel;

    private RecognitionRunner runner;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(
            flutterPluginBinding.getBinaryMessenger(),
            "tesseract_ocr"
        );
        channel.setMethodCallHandler(this);
        runner = new RecognitionRunner(new TessBaseApiFactory());
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        final RecognitionRunner detached = this.runner;
        this.runner = null;
        if (detached != null) {
            detached.stop();
        }
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        final RecognitionRunner active = this.runner;

        if (active == null) {
            result.error(
                "DETACHED",
                "Tesseract OCR is not attached to the engine.",
                null
            );
            return;
        }

        switch (call.method) {
            case "extractText":
            case "extractHocr":
                final String tessDataPath = call.argument("tessData");

                final String imagePath = call.argument("imagePath");
                String DEFAULT_LANGUAGE = "eng";

                // Check for language parameter first, then check config
                if (call.argument("language") != null) {
                    DEFAULT_LANGUAGE = call.argument("language");
                } else {
                    // Try to extract language from config object
                    Object configObj = call.argument("config");
                    if (configObj instanceof java.util.Map) {
                        java.util.Map<String, Object> config = (java.util.Map<
                                String,
                                Object
                            >) configObj;
                        Object languageObj = config.get("language");
                        if (languageObj != null) {
                            DEFAULT_LANGUAGE = languageObj.toString();
                        }
                    }
                }

                active.recognize(
                    tessDataPath,
                    imagePath,
                    DEFAULT_LANGUAGE,
                    call.method.equals("extractHocr"),
                    new MethodChannelReply(result)
                );
                break;
            default:
                result.notImplemented();
        }
    }

    /** Delivers one reply, and only one, to the calling Dart side. */
    private static final class MethodChannelReply implements RecognitionRunner.Reply {

        private final Result result;

        private final AtomicBoolean delivered = new AtomicBoolean();

        MethodChannelReply(Result result) {
            this.result = result;
        }

        @Override
        public void success(Object value) {
            if (!delivered.compareAndSet(false, true)) {
                return;
            }
            result.success(value);
        }

        @Override
        public void error(String code, String message, Object details) {
            if (!delivered.compareAndSet(false, true)) {
                return;
            }
            result.error(code, message, details);
        }
    }

    /** Adapts a native {@link TessBaseAPI} handle to {@link NativeOcrApi}. */
    private static final class TessBaseApiFactory implements RecognitionRunner.ApiFactory {

        @Override
        public NativeOcrApi create() {
            return new TessBaseApiHandle(new TessBaseAPI());
        }
    }

    private static final class TessBaseApiHandle implements NativeOcrApi {

        private TessBaseAPI api;

        TessBaseApiHandle(TessBaseAPI api) {
            this.api = api;
        }

        @Override
        public boolean init(String dataPath, String language) {
            final TessBaseAPI handle = this.api;
            if (handle == null) {
                return false;
            }
            if (!handle.init(dataPath, language)) {
                return false;
            }
            handle.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);
            return true;
        }

        @Override
        public void setImage(File image) {
            require().setImage(image);
        }

        @Override
        public String getUtf8Text() {
            return require().getUTF8Text();
        }

        @Override
        public String getHocrText() {
            return require().getHOCRText(0);
        }

        @Override
        public void recycle() {
            final TessBaseAPI handle = this.api;
            // Cleared before the native call so a second recycle can never double free.
            this.api = null;
            if (handle == null) {
                return;
            }
            handle.recycle();
        }

        private TessBaseAPI require() {
            final TessBaseAPI handle = this.api;
            if (handle == null) {
                throw new IllegalStateException(
                    "TessBaseAPI has already been recycled."
                );
            }
            return handle;
        }
    }
}
