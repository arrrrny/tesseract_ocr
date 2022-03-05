import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
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
                        FilePickerResult result = await FilePicker.platform
                            .pickFiles(type: FileType.image);

                        setState(() {
                          _scanning = true;
                        });

                        var watch = Stopwatch()..start();
                        _extractText = await TesseractOcr.extractText(
                            result.files.single.path);
                        _scanTime = watch.elapsedMilliseconds;

                        setState(() {
                          _scanning = false;
                        });
                      },
                    ),
                    // It doesn't spin, because scanning hangs thread for now
                    _scanning
                        ? SpinKitCircle(
                            color: Colors.black,
                          )
                        : Icon(Icons.done),
                  ],
                ),
                SizedBox(height: 16),
                Text(
                  'Scanning took $_scanTime ms',
                  style: TextStyle(color: Colors.red),
                ),
                SizedBox(height: 16),
                Center(child: SelectableText(_extractText)),
              ],
            ),
          )),
    );
  }
}
