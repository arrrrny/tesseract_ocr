package io.paratoner.tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;
import java.io.File;
import android.os.Handler;
import android.os.Looper;

/** TesseractOcrPlugin */
public class MainMethodCallHandler implements MethodCallHandler {
   private final Context applicationContext;
    private final BinaryMessenger messenger;

  private static final int DEFAULT_PAGE_SEG_MODE = TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK;

  public MainMethodCallHandler(Context applicationContext,
            BinaryMessenger messenger) {
        this.applicationContext = applicationContext;
        this.messenger = messenger;
    }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if (call.method.equals("extractText")) {
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
      baseApi.setPageSegMode(DEFAULT_PAGE_SEG_MODE);

      Thread t = new Thread(new MyRunnable(baseApi, tempFile, recognizedText, result));
      t.start();

    } else {
      result.notImplemented();
    }
  }
}

class MyRunnable implements Runnable {
  private TessBaseAPI baseApi;
  private File tempFile;
  private String[] recognizedText;
  private Result result;

  public MyRunnable(TessBaseAPI baseApi, File tempFile, String[] recognizedText, Result result) {
    this.baseApi = baseApi;
    this.tempFile = tempFile;
    this.recognizedText = recognizedText;
    this.result = result;
  }

  @Override
  public void run() {
    this.baseApi.setImage(this.tempFile);
    recognizedText[0] = this.baseApi.getUTF8Text();
    this.baseApi.end();
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
