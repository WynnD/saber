import 'dart:io';

import 'package:sbn2pdf/sbn2pdf.dart';
import 'package:test/test.dart';

final _examplesDir = '${Directory.current.path}/../../test/sbn_examples';

void main() {
  group('PdfRenderer', () {
    test('renders v17_squiggles to valid PDF', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v17_squiggles.sbn2');
      final result = PdfRenderer.render(doc);
      final bytes = await result.pdf.save();

      // PDF header check
      expect(bytes.length, greaterThan(100));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders v19_pens to valid PDF', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v19_pens.sbn2');
      final result = PdfRenderer.render(doc);
      final bytes = await result.pdf.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders v19_shape_strokes to valid PDF', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v19_shape_strokes.sbn2');
      final result = PdfRenderer.render(doc);
      final bytes = await result.pdf.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders v19_separate_assets to valid PDF with image', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v19_separate_assets.sbn2');
      final result = PdfRenderer.render(doc);
      final bytes = await result.pdf.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Should be larger due to embedded image
      expect(bytes.length, greaterThan(1000));
    });

    test('renders v19_quill_languages to valid PDF', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v19_quill_languages.sbn2');
      final result = PdfRenderer.render(doc);
      final bytes = await result.pdf.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders all fixtures without errors', () async {
      final fixtures = [
        'v17_squiggles.sbn2',
        'v18_highlighter.sbn2',
        'v18_pencil.sbn2',
        'v19_pens.sbn2',
        'v19_quill_languages.sbn2',
        'v19_separate_assets.sbn2',
        'v19_shape_strokes.sbn2',
      ];

      for (final fixture in fixtures) {
        final doc = SbnParser.parseFile('$_examplesDir/$fixture');
        final result = PdfRenderer.render(doc);
        final bytes = await result.pdf.save();
        expect(
          String.fromCharCodes(bytes.take(5)),
          '%PDF-',
          reason: '$fixture should produce valid PDF',
        );
      }
    });

    test('renderToFile writes to disk', () async {
      final doc = SbnParser.parseFile('$_examplesDir/v17_squiggles.sbn2');
      final tempDir = Directory.systemTemp.createTempSync('sbn2pdf_test_');
      final outPath = '${tempDir.path}/sbn2pdf_test_output.pdf';
      try {
        await PdfRenderer.renderToFile(doc, outPath);

        final file = File(outPath);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(100));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
