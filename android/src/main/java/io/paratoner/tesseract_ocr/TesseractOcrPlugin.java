package io.paratoner.tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
// Remove: import io.flutter.plugin.common.PluginRegistry.Registrar;

public class TesseractOcrPlugin implements MethodCallHandler, FlutterPlugin {
  private MethodChannel channel;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "tesseract_ocr");
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
        if (call.argument("language") != null) {
          DEFAULT_LANGUAGE = call.argument("language");
        }
        final String[] recognizedText = new String[1];
        final TessBaseAPI baseApi = new TessBaseAPI();
        baseApi.init(tessDataPath, DEFAULT_LANGUAGE);
        final File tempFile = new File(imagePath);
        baseApi.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);

        Thread t = new Thread(new MyRunnable(baseApi, tempFile, recognizedText, result, call.method.equals("extractHocr")));
        t.start();
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

  public MyRunnable(TessBaseAPI baseApi, File tempFile, String[] recognizedText, Result result, boolean isHocr) {
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
    new Handler(Looper.getMainLooper()).post(new Runnable() {@Override
      public void run() {
        res.success(str);
      }
    });
  }
}
