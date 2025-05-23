import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart'; // Import the config file

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _scanning = false;
  String _extractText = '';
  int _scanTime = 0;
  XFile? _selectedImage;
  bool _debugMode = true;
  OCREngine _selectedEngine = OCREngine.defaultEngine; // Added state for engine selection

  @override
  void initState() {
    super.initState();
    // We'll check the tesseract assets after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTesseractAssets();
    });
  }

  Future<void> _checkTesseractAssets() async {
    try {
      // Check if we have the tessdata_config.json file
      try {
        final config = await DefaultAssetBundle.of(context).loadString('assets/tessdata_config.json');
        print('DEBUG: Found tessdata_config.json: $config');
      } catch (e) {
        print('ERROR: Could not load tessdata_config.json: $e');
      }

      // Check if we have the eng.traineddata file
      try {
        await DefaultAssetBundle.of(context).load('assets/tessdata/eng.traineddata');
        print('DEBUG: Found eng.traineddata file');
      } catch (e) {
        print('ERROR: Could not load eng.traineddata: $e');
      }
    } catch (e) {
      print('ERROR checking Tesseract assets: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Tesseract OCR Example'),
          ),
          body: Container(
            padding: EdgeInsets.all(16),
            child: ListView(
              children: <Widget>[
                // Engine Selection
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose OCR Engine:'),
                    DropdownButton<OCREngine>(
                      value: _selectedEngine,
                      onChanged: (OCREngine? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedEngine = newValue;
                          });
                        }
                      },
                      items: OCREngine.values.map<DropdownMenuItem<OCREngine>>((OCREngine engine) {
                        String text;
                        switch (engine) {
                          case OCREngine.defaultEngine:
                            text = 'Default';
                            break;
                          case OCREngine.vision:
                            text = 'Vision (iOS)';
                            break;
                          case OCREngine.tesseract:
                            text = 'Tesseract';
                            break;
                        }
                        return DropdownMenuItem<OCREngine>(
                          value: engine,
                          child: Text(text),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Image Selection and Scan Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      child: Text('Select image'),
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image == null) return;

                        setState(() {
                          _selectedImage = image;
                          _scanning = true;
                          _extractText = ''; // Clear previous result
                          _scanTime = 0; // Reset scan time
                        });

                        try {
                          print('DEBUG: Starting OCR on image: ${image.path}');
                          print('DEBUG: Image exists: ${await File(image.path).exists()}');
                          print('DEBUG: Image size: ${await File(image.path).length()} bytes');

                          // Get tesseract language (used for Tesseract engine)
                          const language = 'eng'; // You can change this to match your trained data
                          print('DEBUG: Using language: $language');
                           print('DEBUG: Using engine: ${_selectedEngine.toString().split('.').last}');

                          // Define OCR configuration based on selected engine
                          final ocrConfig = OCRConfig(
                            language: language,
                            engine: _selectedEngine,
                            // Add options if needed, e.g., for Tesseract:
                            // options: {
                            //   TesseractConfig.preserveInterwordSpaces: '1',
                            //   TesseractConfig.pageSegMode: PageSegmentationMode.autoOsd,
                            // },
                          );

                          var watch = Stopwatch()..start();
                          // Use the config parameter
                          _extractText = await TesseractOcr.extractText(
                            image.path,
                            config: ocrConfig,
                          );
                          _scanTime = watch.elapsedMilliseconds;

                          print('DEBUG: OCR complete, result length: ${_extractText.length}');
                          print('DEBUG: Scanning took $_scanTime ms');

                          if (_debugMode) {
                            print('DEBUG: Text length: ${_extractText.length}');
                            print('DEBUG: Full text: "$_extractText"');
                          }
                        } catch (e) {
                          print('ERROR: OCR processing failed: $e');
                          _extractText = "Error processing image: $e";
                        } finally {
                          setState(() {
                            _scanning = false;
                          });
                        }
                      },
                    ),
                    _scanning
                        ? CircularProgressIndicator()
                        : Icon(Icons.done),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Scanning took $_scanTime ms',
                      style: TextStyle(color: Colors.red),
                    ),
                    TextButton(
                      child: Text('Debug: ${_debugMode ? "ON" : "OFF"}'),
                      onPressed: () {
                        setState(() {
                          _debugMode = !_debugMode;
                        });
                        if (_debugMode && _extractText.isNotEmpty) {
                          print('DEBUG: Text length: ${_extractText.length}');
                          print('DEBUG: Full text: "$_extractText"');
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Raw OCR Text:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    _extractText.isEmpty ? "No text detected" : _extractText,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(height: 16),
                if (_selectedImage != null)
                  Container(
                    height: 300,
                    child: Center(
                      child: Image.file(
                        File(_selectedImage!.path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
              ],
            ),
          )),
    );
  }
}
