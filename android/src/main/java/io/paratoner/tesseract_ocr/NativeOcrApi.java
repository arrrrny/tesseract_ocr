package io.paratoner.tesseract_ocr;

import java.io.File;
import java.util.Map;

/**
 * The slice of the native Tesseract API this plugin drives.
 *
 * <p>Keeping the surface this narrow is what lets the lifecycle rules be tested
 * on a plain JVM: {@link RecognitionRunner} owns the rules and only talks to the
 * engine through these six calls.
 */
interface NativeOcrApi {

    /** Loads the trained data. Returns false when the data or language is unusable. */
    boolean init(String dataPath, String language);

    /**
     * Applies the options the caller sent, after a successful {@link #init}.
     *
     * <p>The page segmentation mode is one call and every other variable is
     * another, which is why they are separated here: {@code tessedit_pageseg_mode}
     * would be meaningless as a Tesseract variable, and passing it that way is
     * how it used to be dropped.
     *
     * <p>Implementations must not throw for an option the engine refuses — an
     * unrecognised variable is the caller's mistake, not a failed recognition.
     *
     * @param pageSegMode the PSM to apply, or {@code null} to keep the engine's
     *     own default
     * @param variables every other option, as {@code key=value} strings
     */
    void applyOptions(Integer pageSegMode, Map<String, String> variables);

    /** Selects the image to recognize. */
    void setImage(File image);

    /** Recognized text as UTF-8. */
    String getUtf8Text();

    /** Recognized text as hOCR. */
    String getHocrText();

    /** Releases the native handle. Idempotent: a second call is a no-op. */
    void recycle();
}
