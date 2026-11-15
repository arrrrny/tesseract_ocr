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
     * <p>An option the engine does not know is not a failure and must not
     * throw: {@code setVariable} returns false for an unrecognised variable and
     * the implementation moves on, because the caller's spelling is their
     * mistake, not a failed recognition. A throw the engine raises despite that
     * is contained one level up — {@link RecognitionRunner} reports it as a
     * recognition error instead of letting it reach the host process.
     *
     * @param pageSegMode the PSM to apply, or {@code null} to keep the engine's
     *     own default
     * @param variables every other option, as {@code key=value} strings
     */
    void applyOptions(Integer pageSegMode, Map<String, String> variables);

    /** Selects the image to recognize. */
    void setImage(File image);

    /**
     * Selects the image to recognize from its encoded bytes.
     *
     * <p>The engine takes a bitmap, so decoding the encoded image is this call's
     * job: a caller that has the bytes must not have to write a temporary file
     * to get them recognized.
     *
     * @throws IllegalArgumentException when the bytes are not a decodable image
     */
    void setImageBytes(byte[] bytes);

    /** Recognized text as UTF-8. */
    String getUtf8Text();

    /** Recognized text as hOCR. */
    String getHocrText();

    /** Releases the native handle. Idempotent: a second call is a no-op. */
    void recycle();
}
