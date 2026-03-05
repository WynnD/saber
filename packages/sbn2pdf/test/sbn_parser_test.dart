import 'dart:io';

import 'package:sbn2pdf/sbn2pdf.dart';
import 'package:test/test.dart';

final _examplesDir = '${Directory.current.path}/../../test/sbn_examples';

void main() {
  group('SbnParser', () {
    test('parses v17_squiggles.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v17_squiggles.sbn2');
      expect(doc.fileVersion, 17);
      expect(doc.pages.length, 2);
      expect(doc.pages[0].strokes.length, 9);
      expect(doc.pages[0].width, 1000);
      expect(doc.pages[0].height, 1400);

      // All strokes should be freehand
      for (final stroke in doc.pages[0].strokes) {
        expect(stroke.shape, SbnStrokeShape.freehand);
        expect(stroke.points, isNotEmpty);
      }
    });

    test('parses v19_pens.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v19_pens.sbn2');
      expect(doc.fileVersion, 19);
      expect(doc.pages[0].strokes.length, 16);

      // Should have various tool types
      final toolIds = doc.pages[0].strokes.map((s) => s.toolId).toSet();
      expect(toolIds, contains(SbnToolId.fountainPen));
    });

    test('parses v19_shape_strokes.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v19_shape_strokes.sbn2');
      expect(doc.fileVersion, 19);

      final shapes = doc.pages[0].strokes.map((s) => s.shape).toSet();
      expect(shapes, contains(SbnStrokeShape.circle));
      expect(shapes, contains(SbnStrokeShape.rect));

      // Circle strokes should have center and radius
      final circles =
          doc.pages[0].strokes.where((s) => s.shape == SbnStrokeShape.circle);
      for (final c in circles) {
        expect(c.radius, isNotNull);
        expect(c.radius, greaterThan(0));
      }
    });

    test('parses v19_separate_assets.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v19_separate_assets.sbn2');
      expect(doc.fileVersion, 19);
      expect(doc.pages[0].images.length, 1);

      // Asset should have been loaded from .sbn2.0 file
      final image = doc.pages[0].images[0];
      expect(image.assetIndex, isNotNull);
      expect(image.bytes, isNotNull);
      expect(image.bytes!.length, greaterThan(0));
    });

    test('parses v18_highlighter.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v18_highlighter.sbn2');
      expect(doc.fileVersion, 18);

      final highlighters =
          doc.pages[0].strokes.where((s) => s.toolId == SbnToolId.highlighter);
      expect(highlighters, isNotEmpty);
    });

    test('parses v19_quill_languages.sbn2', () {
      final doc = SbnParser.parseFile('$_examplesDir/v19_quill_languages.sbn2');
      expect(doc.fileVersion, 19);

      // Should have quill delta on at least one page
      final pagesWithQuill = doc.pages
          .where((p) => p.quillDelta != null && p.quillDelta!.isNotEmpty);
      expect(pagesWithQuill, isNotEmpty);
    });
  });
}
