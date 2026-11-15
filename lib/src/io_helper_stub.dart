Future<bool> fileExists(String path) async => path.trim().isNotEmpty;

Future<String?> loadTessDataToAppDocuments(
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  return null;
}

/// Web has no filesystem to resolve: [path] is the `langPath` the Tesseract.js
/// worker fetches its traineddata from, so it travels untouched (issue #56).
Future<String> resolveTessDataDirectory(
  String path, {
  required String language,
}) async {
  return path;
}
