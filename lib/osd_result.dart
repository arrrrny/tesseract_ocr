/// The orientation and script Tesseract's OSD (orientation & script detection)
/// reports for an image.
///
/// Mirrors the fields `pytesseract.image_to_osd(..., output_type=Output.DICT)`
/// returns: how far the page is rotated, the writing script it uses, and the
/// confidence of each. Apps can rotate an image by [orientationDegrees] before
/// running `TesseractOcr.extractText`, or decline an image whose detected
/// [scriptName] they cannot read.
class OsdResult {
  /// The detected orientation of the page, in degrees clockwise (0, 90, 180 or
  /// 270). A caller rotates the image by this many degrees to make it upright.
  final int orientationDegrees;

  /// Confidence of [orientationDegrees] on Tesseract's own scale (the
  /// `orientation_conf` of `image_to_osd`).
  final double orientationConfidence;

  /// The detected writing script, e.g. `Latin` (the `script` field). Empty when
  /// detection failed.
  final String scriptName;

  /// Confidence of [scriptName] (the `script_conf` of `image_to_osd`).
  final double scriptConfidence;

  /// Creates a result from its four OSD fields.
  const OsdResult({
    this.orientationDegrees = 0,
    this.orientationConfidence = 0,
    this.scriptName = '',
    this.scriptConfidence = 0,
  });

  /// Parses the map a native engine returns on the `tesseract_ocr` channel.
  ///
  /// Values are coerced from whatever a platform handed back — a Dart `int`,
  /// `double`, a numeric `String`, or a missing key (which defaults rather than
  /// throwing). A malformed map must not cost the caller the OSD read.
  factory OsdResult.fromMap(Map<Object?, Object?> map) {
    return OsdResult(
      orientationDegrees: _asInt(map['orientation']),
      orientationConfidence: _asDouble(map['orientation_conf']),
      scriptName: _asString(map['script']),
      scriptConfidence: _asDouble(map['script_conf']),
    );
  }

  /// The four OSD fields as the map the method channel carries.
  Map<String, Object> toMap() => <String, Object>{
        'orientation': orientationDegrees,
        'orientation_conf': orientationConfidence,
        'script': scriptName,
        'script_conf': scriptConfidence,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.isFinite ? value.toInt() : 0;
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) return value.isFinite ? value : 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      return (parsed != null && parsed.isFinite) ? parsed : 0;
    }
    return 0;
  }

  // A non-finite double from a native side must not stringify into the script
  // name — "NaN"/"Infinity" there would read as a detected script.
  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is double && !value.isFinite) return '';
    return value.toString();
  }

  @override
  String toString() => 'OsdResult(orientation: $orientationDegrees°, '
      'orientationConfidence: $orientationConfidence, '
      'script: $scriptName, scriptConfidence: $scriptConfidence)';
}
