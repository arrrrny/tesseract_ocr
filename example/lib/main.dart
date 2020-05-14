import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _extractText = '';

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
                Center(
                  child: RaisedButton(
                    child: Text('Select image'),
                    onPressed: () async {
                      var file =
                          await FilePicker.getFilePath(type: FileType.image);
                      _extractText = await TesseractOcr.extractText(file);
                      setState(() {});
                    },
                  ),
                ),
                SizedBox(
                  height: 16,
                ),
                Center(child: SelectableText(_extractText)),
              ],
            ),
          )),
    );
  }
}
