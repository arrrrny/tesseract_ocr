import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

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
  List<TextBlock> _textBlocks = [];
  bool _debugMode = true;
  
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
            title: const Text('Tesseract OCR'),
          ),
          body: Container(
            padding: EdgeInsets.all(16),
            child: ListView(
              children: <Widget>[
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
                        });

                        try {
                          print('DEBUG: Starting OCR on image: ${image.path}');
                          print('DEBUG: Image exists: ${await File(image.path).exists()}');
                          print('DEBUG: Image size: ${await File(image.path).length()} bytes');
                          
                          // Get tesseract language
                          const language = 'eng'; // You can change this to match your trained data
                          print('DEBUG: Using language: $language');
                          
                          var watch = Stopwatch()..start();
                          _extractText = await TesseractOcr.extractText(image.path, language: language);
                          _scanTime = watch.elapsedMilliseconds;
                          
                          print('DEBUG: OCR complete, result length: ${_extractText.length}');
                          print('DEBUG: Scanning took $_scanTime ms');
                          
                          // Parse text into blocks
                          _textBlocks = _parseTextIntoBlocks(_extractText);
                          
                          if (_debugMode) {
                            print('DEBUG: OCR complete, text length: ${_extractText.length}');
                            print('DEBUG: Found ${_textBlocks.length} text blocks');
                            print('DEBUG: Full text: "$_extractText"');
                          }
                        } catch (e) {
                          print('ERROR: OCR processing failed: $e');
                          _extractText = "Error processing image: $e";
                          _textBlocks = [
                            TextBlock(
                              text: "Error processing image: $e",
                              confidence: 0,
                              boundingBox: Rect.fromLTWH(0, 0, 100, 50),
                            )
                          ];
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
                    child: Stack(
                      children: [
                        Center(
                          child: Image.file(
                            File(_selectedImage!.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 16),
                Text(
                  'Detected Text Blocks:', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                _textBlocks.isEmpty
                    ? Text('No text blocks detected', style: TextStyle(fontStyle: FontStyle.italic))
                    : Column(children: _buildTextBlockWidgets()),
              ],
            ),
          )),
    );
  }

  List<Widget> _buildTextBlockWidgets() {
    return _textBlocks.map((block) {
      return Card(
        margin: EdgeInsets.only(bottom: 8),
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confidence: ${block.confidence.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 4),
              SelectableText(
                block.text,
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<TextBlock> _parseTextIntoBlocks(String text) {
    if (text.contains("Error processing image:")) {
      return [
        TextBlock(
          text: text,
          confidence: 0,
          boundingBox: Rect.fromLTWH(0, 0, 100, 50),
        )
      ];
    }
    
    if (text.trim().isEmpty) {
      // Return at least one block even if empty to show something
      return [
        TextBlock(
          text: "No text detected. Please check:\n1. Is your image clear?\n2. Does it contain text?\n3. Is the 'eng.traineddata' file in assets/tessdata?",
          confidence: 0,
          boundingBox: Rect.fromLTWH(0, 0, 100, 50),
        )
      ];
    }
    
    // Split by any whitespace sequence as fallback if no double newlines
    List<String> blocks = [];
    
    if (text.contains('\n')) {
      // First try to split by paragraph breaks
      blocks = text.split('\n\n');
      if (blocks.length <= 1) {
        // If no paragraphs, split by single newlines
        blocks = text.split('\n');
      }
    } else {
      // If no newlines, split by sentences
      final sentenceRegex = RegExp(r'[.!?]+\s+');
      blocks = text.split(sentenceRegex);
      if (blocks.length <= 1 && text.length > 30) {
        // Last resort: just split into chunks of reasonable length
        blocks = [];
        for (var i = 0; i < text.length; i += 30) {
          blocks.add(text.substring(i, i + 30 > text.length ? text.length : i + 30));
        }
      } else if (blocks.length <= 1) {
        // Just use the whole text as one block
        blocks = [text];
      }
    }
    
    // Print debug info
    print('Original text: "$text"');
    print('Found ${blocks.length} blocks');
    
    return blocks.where((block) => block.trim().isNotEmpty).map((block) {
      // Simulate confidence values
      final confidence = 85.0 + (10 * blocks.indexOf(block) / blocks.length);
      print('Block: "${block.trim()}"');
      return TextBlock(
        text: block.trim(),
        confidence: confidence > 95 ? 95 : confidence,
        // In a real implementation, these would be actual coordinates
        boundingBox: Rect.fromLTWH(0, 0, 100, 50),
      );
    }).toList();
  }
}

class TextBlock {
  final String text;
  final double confidence;
  final Rect boundingBox;

  TextBlock({
    required this.text,
    required this.confidence,
    required this.boundingBox,
  });
}