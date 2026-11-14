import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr_example/main.dart';

void main() {
  testWidgets('Example app renders engine selector and image picker button',
      (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.text('Tesseract OCR Example'), findsOneWidget);
    expect(find.text('Select image'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('Choose OCR Engine:'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  });
}
