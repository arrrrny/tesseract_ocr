package io.paratoner.tesseract_ocr;

import java.io.File;

/**
 * The slice of the native Tesseract API this plugin drives.
 *
 * <p>Keeping the surface this narrow is what lets the lifecycle rules be tested
 * on a plain JVM: {@link RecognitionRunner} owns the rules and only talks to the
 * engine through these five calls.
 */
interface NativeOcrApi {

    /** Loads the trained data. Returns false when the data or language is unusable. */
    boolean init(String dataPath, String language);

    /** Selects the image to recognize. */
    void setImage(File image);

    /** Recognized text as UTF-8. */
    String getUtf8Text();

    /** Recognized text as hOCR. */
    String getHocrText();

    /** Releases the native handle. Idempotent: a second call is a no-op. */
    void recycle();
}
