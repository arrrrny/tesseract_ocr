package io.paratoner.tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;
import java.util.Map;
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
                    OcrOptions.from(readOptions(call)),
                    new MethodChannelReply(result)
                );
                break;
            default:
                result.notImplemented();
        }
    }

    /**
     * The {@code options} map the Dart layer sent, or null when it sent none.
     *
     * <p>The map arrives as {@code Map<Object, Object>} on the channel, and a
     * malformed one is treated as absent rather than failing the recognition: an
     * option the caller could not spell must not cost them the OCR run.
     */
    private static java.util.Map<String, Object> readOptions(MethodCall call) {
        final Object raw = call.argument("options");
        if (!(raw instanceof java.util.Map)) {
            return null;
        }
        final java.util.Map<?, ?> map = (java.util.Map<?, ?>) raw;
        final java.util.Map<String, Object> options = new java.util.LinkedHashMap<>();
        for (java.util.Map.Entry<?, ?> entry : map.entrySet()) {
            if (entry.getKey() instanceof String) {
                options.put((String) entry.getKey(), entry.getValue());
            }
        }
        return options;
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
            // The engine's own default. A caller that asked for a mode replaces
            // it in applyOptions, which runs immediately after a successful init.
            handle.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);
            return true;
        }

        @Override
        public void applyOptions(Integer pageSegMode, Map<String, String> variables) {
            final TessBaseAPI handle = require();
            if (pageSegMode != null) {
                // OcrOptions already bounded the value to the PSM range, so this
                // lookup cannot throw for a caller's out-of-range input.
                handle.setPageSegMode(TessBaseAPI.PageSegMode.values()[pageSegMode]);
            }
            for (Map.Entry<String, String> variable : variables.entrySet()) {
                // An unknown variable is the caller's spelling, not a failed
                // recognition: skip it and keep the rest.
                handle.setVariable(variable.getKey(), variable.getValue());
            }
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
