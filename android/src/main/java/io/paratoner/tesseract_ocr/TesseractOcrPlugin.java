package io.paratoner.tesseract_ocr;

import android.os.Handler;
import android.os.Looper;
import com.googlecode.tesseract.android.TessBaseAPI;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;

// Remove: import io.flutter.plugin.common.PluginRegistry.Registrar;

public class TesseractOcrPlugin implements MethodCallHandler, FlutterPlugin {

    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(
            flutterPluginBinding.getBinaryMessenger(),
            "tesseract_ocr"
        );
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    // Remove the registerWith method
    @Override
    public void onMethodCall(MethodCall call, Result result) {
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

                // Validate tessDataPath is not null
                if (tessDataPath == null) {
                    result.error(
                        "INVALID_ARGUMENT",
                        "Data path must not be null! Ensure tessdata is properly loaded.",
                        null
                    );
                    return;
                }

                final String[] recognizedText = new String[1];
                final TessBaseAPI baseApi = new TessBaseAPI();

                try {
                    baseApi.init(tessDataPath, DEFAULT_LANGUAGE);
                    final File tempFile = new File(imagePath);
                    baseApi.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);

                    Thread t = new Thread(
                        new MyRunnable(
                            baseApi,
                            tempFile,
                            recognizedText,
                            result,
                            call.method.equals("extractHocr")
                        )
                    );
                    t.start();
                } catch (Exception e) {
                    result.error(
                        "INIT_ERROR",
                        "Failed to initialize Tesseract: " + e.getMessage(),
                        null
                    );
                    baseApi.recycle();
                }
                break;
            default:
                result.notImplemented();
        }
    }
}

class MyRunnable implements Runnable {

    private TessBaseAPI baseApi;
    private File tempFile;
    private String[] recognizedText;
    private Result result;
    private boolean isHocr;

    public MyRunnable(
        TessBaseAPI baseApi,
        File tempFile,
        String[] recognizedText,
        Result result,
        boolean isHocr
    ) {
        this.baseApi = baseApi;
        this.tempFile = tempFile;
        this.recognizedText = recognizedText;
        this.result = result;
        this.isHocr = isHocr;
    }

    @Override
    public void run() {
        this.baseApi.setImage(this.tempFile);
        if (isHocr) {
            recognizedText[0] = this.baseApi.getHOCRText(0);
        } else {
            recognizedText[0] = this.baseApi.getUTF8Text();
        }
        this.baseApi.recycle();
        this.sendSuccess(recognizedText[0]);
    }

    public void sendSuccess(String msg) {
        final String str = msg;
        final Result res = this.result;
        new Handler(Looper.getMainLooper()).post(
            new Runnable() {
                @Override
                public void run() {
                    res.success(str);
                }
            }
        );
    }
}
