package io.paratoner.tesseract_ocr;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.Test;

/**
 * The option values a caller's {@code OCRConfig.options} map resolves to
 * (issue #59): the page segmentation mode reaches the engine as a PSM, and the
 * remaining keys reach it as Tesseract variables instead of being dropped.
 */
public class OcrOptionsTest {

    @Test
    public void resolvesAPageSegModeFromAString() {
        final OcrOptions options =
            OcrOptions.from(single("tessedit_pageseg_mode", "7"));

        assertEquals(Integer.valueOf(7), options.pageSegMode());
        assertTrue(options.variables().isEmpty());
    }

    @Test
    public void resolvesAPageSegModeFromANumber() {
        final OcrOptions options =
            OcrOptions.from(single("tessedit_pageseg_mode", Integer.valueOf(13)));

        assertEquals(Integer.valueOf(13), options.pageSegMode());
        assertTrue(options.variables().isEmpty());
    }

    @Test
    public void noOptionsLeavesTheEngineDefault() {
        final OcrOptions options = OcrOptions.from(null);

        assertNull(options.pageSegMode());
        assertTrue(options.variables().isEmpty());
        assertTrue(options.isEmpty());
    }

    @Test
    public void everyOtherKeyIsKeptAsAVariable() {
        final Map<String, Object> raw = new LinkedHashMap<>();
        raw.put("preserve_interword_spaces", "1");
        raw.put("tessedit_char_whitelist", "0123456789");
        raw.put("user_defined_dpi", Integer.valueOf(300));

        final OcrOptions options = OcrOptions.from(raw);

        assertNull(options.pageSegMode());
        assertEquals("1", options.variables().get("preserve_interword_spaces"));
        assertEquals("0123456789", options.variables().get("tessedit_char_whitelist"));
        assertEquals("300", options.variables().get("user_defined_dpi"));
    }

    @Test
    public void theKeysThePluginConsumesItselfAreNeverVariables() {
        final Map<String, Object> raw = new LinkedHashMap<>();
        raw.put("language", "eng");
        raw.put("engine", "tesseract");
        raw.put("tessDataPath", "/data/tessdata");
        raw.put("tessedit_ocr_engine_mode", "1");
        raw.put("preserve_interword_spaces", "1");

        final OcrOptions options = OcrOptions.from(raw);

        assertEquals(1, options.variables().size());
        assertTrue(options.variables().containsKey("preserve_interword_spaces"));
    }

    @Test
    public void anOutOfRangePageSegModeIsDroppedRatherThanApplied() {
        // PSM_AUTO (3) is the default, so a caller sending "99" must not end up
        // on it: the value is unusable and is reported as such instead.
        final OcrOptions options = OcrOptions.from(single("tessedit_pageseg_mode", "99"));

        assertNull(options.pageSegMode());
        assertTrue(options.variables().isEmpty());
        assertTrue(options.isEmpty());
    }

    @Test
    public void anUnparsablePageSegModeIsDropped() {
        final OcrOptions options =
            OcrOptions.from(single("tessedit_pageseg_mode", "auto"));

        assertNull(options.pageSegMode());
        assertTrue(options.isEmpty());
    }

    @Test
    public void aNullValueIsDroppedRatherThanForwarded() {
        final Map<String, Object> raw = new LinkedHashMap<>();
        raw.put("preserve_interword_spaces", null);
        raw.put("user_defined_dpi", "300");

        final OcrOptions options = OcrOptions.from(raw);

        assertEquals(1, options.variables().size());
        assertEquals("300", options.variables().get("user_defined_dpi"));
    }

    @Test
    public void aModeAndVariablesTravelTogether() {
        final Map<String, Object> raw = new LinkedHashMap<>();
        raw.put("tessedit_pageseg_mode", "6");
        raw.put("preserve_interword_spaces", "1");

        final OcrOptions options = OcrOptions.from(raw);

        assertEquals(Integer.valueOf(6), options.pageSegMode());
        assertEquals(1, options.variables().size());
        assertEquals("1", options.variables().get("preserve_interword_spaces"));
    }

    private static Map<String, Object> single(String key, Object value) {
        final Map<String, Object> raw = new LinkedHashMap<>();
        raw.put(key, value);
        return raw;
    }
}