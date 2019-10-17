package io.paratoner.tesseract_ocr;

import com.googlecode.tesseract.android.TessBaseAPI;

import java.io.File;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/** TesseractOcrPlugin */
public class TesseractOcrPlugin implements MethodCallHandler {

  private static final int DEFAULT_PAGE_SEG_MODE = TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK;

  /** Plugin registration. */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "tesseract_ocr");
    channel.setMethodCallHandler(new TesseractOcrPlugin());
  }


  @Override
  public void onMethodCall(MethodCall call, Result result) {

    if (call.method.equals("extractText")) {
      final String tessDataPath = call.argument("tessData");
      final String imagePath = call.argument("imagePath");
      String DEFAULT_LANGUAGE = "eng";
      if(call.argument("language") != null){
        DEFAULT_LANGUAGE = call.argument("language");
      }
      final String[] recognizedText = new String[1];
      final TessBaseAPI baseApi = new TessBaseAPI();
      baseApi.init(tessDataPath, DEFAULT_LANGUAGE);
      final File tempFile = new File(imagePath);
      baseApi.setPageSegMode(DEFAULT_PAGE_SEG_MODE);

      Thread t = new Thread(new Runnable() {
        public void run() {
          baseApi.setImage(tempFile);
          recognizedText[0] = baseApi.getUTF8Text();
          baseApi.end();
        }
      });
      t.start();
      try { t.join(); } catch (InterruptedException e) { e.printStackTrace(); }
      result.success(recognizedText[0]);
    } else {
      result.notImplemented();
    }
  }


}
