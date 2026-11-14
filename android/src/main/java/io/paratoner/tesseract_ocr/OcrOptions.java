package io.paratoner.tesseract_ocr;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The Tesseract options one recognition carries.
 *
 * <p>The Dart layer sends {@code OCRConfig.options} as a plain string map, so the
 * two decisions the engine needs — which key is the page segmentation mode, and
 * what integer it maps to — are made here rather than by the native handle, which
 * cannot be tested off a device.
 */
final class OcrOptions {

    /** The key the Dart layer uses for the page segmentation mode. */
    static final String PAGE_SEG_MODE_KEY = "tessedit_pageseg_mode";

    /**
     * The range {@code TessBaseAPI.PageSegMode} covers.
     *
     * <p>Anything outside it would fail the enum lookup, so it is treated as
     * absent instead of reaching the recognition thread.
     */
    private static final int MIN_PAGE_SEG_MODE = 0;
    private static final int MAX_PAGE_SEG_MODE = 13;

    /** Keys the plugin consumes itself and must never forward as a variable. */
    private static final String[] RESERVED_KEYS = {
        "language",
        "engine",
        "tessDataPath",
        "tessedit_ocr_engine_mode",
    };

    private final Integer pageSegMode;
    private final Map<String, String> variables;

    /** The options with no page segmentation mode set. */
    static final OcrOptions NONE = new OcrOptions(null, Collections.<String, String>emptyMap());

    /**
     * The options as one value, for a caller that already resolved them.
     *
     * <p>Tests construct this directly to pin exactly what the runner forwards
     * to the engine; {@link #from(Map)} is the production path.
     */
    OcrOptions(Integer pageSegMode, Map<String, String> variables) {
        this.pageSegMode = pageSegMode;
        this.variables = Collections.unmodifiableMap(
            variables == null
                ? new LinkedHashMap<String, String>()
                : new LinkedHashMap<>(variables)
        );
    }

    /**
     * Resolves the {@code options} map the method call carried.
     *
     * <p>A null, empty or malformed value is dropped rather than forwarded: an
     * option the engine cannot apply must not cost the caller their recognition.
     */
    static OcrOptions from(Map<String, Object> rawOptions) {
        if (rawOptions == null || rawOptions.isEmpty()) {
            return NONE;
        }

        Integer pageSegMode = null;
        Map<String, String> variables = new LinkedHashMap<>();

        for (Map.Entry<String, Object> entry : rawOptions.entrySet()) {
            final String key = entry.getKey();
            final Object rawValue = entry.getValue();
            if (key == null || rawValue == null) {
                continue;
            }

            if (PAGE_SEG_MODE_KEY.equals(key)) {
                final Integer parsed = parsePageSegMode(rawValue);
                if (parsed != null) {
                    pageSegMode = parsed;
                }
                continue;
            }

            if (isReserved(key)) {
                continue;
            }

            variables.put(key, String.valueOf(rawValue));
        }

        if (pageSegMode == null && variables.isEmpty()) {
            return NONE;
        }
        return new OcrOptions(pageSegMode, variables);
    }

    /** The PSM to apply, or null when the caller requested none. */
    Integer pageSegMode() {
        return pageSegMode;
    }

    /** Every option other than the page segmentation mode. */
    Map<String, String> variables() {
        return variables;
    }

    boolean isEmpty() {
        return pageSegMode == null && variables.isEmpty();
    }

    private static boolean isReserved(String key) {
        for (String reserved : RESERVED_KEYS) {
            if (reserved.equals(key)) {
                return true;
            }
        }
        return false;
    }

    /** Parses a PSM from an integer, a numeric string, or nothing at all. */
    static Integer parsePageSegMode(Object value) {
        final int parsed;
        if (value instanceof Number) {
            parsed = ((Number) value).intValue();
        } else {
            try {
                parsed = Integer.parseInt(String.valueOf(value).trim());
            } catch (NumberFormatException e) {
                return null;
            }
        }
        if (parsed < MIN_PAGE_SEG_MODE || parsed > MAX_PAGE_SEG_MODE) {
            return null;
        }
        return parsed;
    }
}