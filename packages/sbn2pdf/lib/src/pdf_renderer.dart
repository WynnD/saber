import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:sbn2pdf/src/models.dart';
import 'package:sbn2pdf/src/stroke_path.dart';

/// Result of rendering, containing the PDF and any warnings.
class RenderResult {
  final pw.Document pdf;
  final List<String> warnings;

  RenderResult(this.pdf, this.warnings);
}

/// Renders an [SbnDocument] to a PDF document.
class PdfRenderer {
  /// Default background color (white).
  static const _defaultBgColor = 0xFFFFFFFF;

  /// Render an [SbnDocument] to a [pw.Document].
  ///
  /// Returns a [RenderResult] with the PDF and any warnings about
  /// content that could not be rendered.
  static RenderResult render(SbnDocument doc, {bool verbose = false}) {
    final pdf = pw.Document();
    final warnings = <String>[];

    // Skip trailing empty pages (matching Saber's behavior)
    var pages = doc.pages;
    if (pages.isNotEmpty && _isPageEmpty(pages.last)) {
      pages = pages.sublist(0, pages.length - 1);
    }

    final bgArgb = doc.backgroundColor ?? _defaultBgColor;
    final bgPdfColor = PdfColor.fromInt(bgArgb).flatten();

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (verbose) {
        stderr.writeln('Rendering page ${i + 1}/${pages.length} '
            '(${page.width}x${page.height}, '
            '${page.strokes.length} strokes, '
            '${page.images.length} images)');
      }
      _addPage(pdf, page, bgPdfColor, warnings: warnings, verbose: verbose);
    }

    return RenderResult(pdf, warnings);
  }

  static bool _isPageEmpty(SbnPage page) {
    return page.strokes.isEmpty &&
        page.images.isEmpty &&
        (page.quillDelta == null || page.quillDelta!.isEmpty) &&
        page.backgroundImage == null;
  }

  static void _addPage(
    pw.Document pdf,
    SbnPage page,
    PdfColor bgColor, {
    required List<String> warnings,
    bool verbose = false,
  }) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height),
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          final children = <pw.Widget>[];

          // Background fill
          children.add(
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.Container(
                width: page.width,
                height: page.height,
                color: bgColor,
              ),
            ),
          );

          // Background image
          if (page.backgroundImage != null) {
            final bgImg = _buildImageWidget(
              page.backgroundImage!,
              page.height,
              warnings: warnings,
            );
            if (bgImg != null) children.add(bgImg);
          }

          // Images
          for (final image in page.images) {
            final imgWidget = _buildImageWidget(
              image,
              page.height,
              warnings: warnings,
            );
            if (imgWidget != null) children.add(imgWidget);
          }

          // Quill text (plain text extraction)
          if (page.quillDelta != null && page.quillDelta!.isNotEmpty) {
            final text = _extractPlainText(page.quillDelta!);
            if (text.isNotEmpty) {
              children.add(
                pw.Positioned(
                  left: 10,
                  top: 10,
                  child: pw.SizedBox(
                    width: page.width - 20,
                    child: pw.Text(
                      text,
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              );
            }
          }

          // Vector strokes (using CustomPaint for PDF graphics)
          children.add(
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.SizedBox(
                width: page.width,
                height: page.height,
                child: pw.CustomPaint(
                  painter: (PdfGraphics gfx, PdfPoint size) {
                    _drawStrokes(gfx, page, bgColor, verbose: verbose);
                  },
                ),
              ),
            ),
          );

          return pw.SizedBox(
            width: page.width,
            height: page.height,
            child: pw.Stack(children: children),
          );
        },
      ),
    );
  }

  static void _drawStrokes(
    PdfGraphics gfx,
    SbnPage page,
    PdfColor bgColor, {
    bool verbose = false,
  }) {
    for (final stroke in page.strokes) {
      // Skip rasterized stroke types (highlighter, pencil)
      if (stroke.toolId.shouldRasterize) {
        if (verbose) {
          stderr.writeln(
            '  Skipping ${stroke.toolId.id} stroke (would need rasterization)',
          );
        }
        continue;
      }

      final strokeColor =
          PdfColor.fromInt(stroke.color).flatten(background: bgColor);

      final bool shouldFill;
      switch (stroke.shape) {
        case SbnStrokeShape.circle:
          shouldFill = false;
          gfx.drawEllipse(
            stroke.centerX ?? 0,
            page.height - (stroke.centerY ?? 0),
            stroke.radius ?? 0,
            stroke.radius ?? 0,
            clockwise: false,
          );

        case SbnStrokeShape.rect:
          shouldFill = false;
          final strokeSize = stroke.options.size;
          final l = stroke.rectLeft ?? 0;
          final t = stroke.rectTop ?? 0;
          final w = stroke.rectWidth ?? 0;
          final h = stroke.rectHeight ?? 0;
          gfx.drawRRect(
            l,
            page.height - t - h, // flip Y: PDF origin is bottom-left
            w,
            h,
            strokeSize / 4,
            strokeSize / 4,
          );

        case SbnStrokeShape.freehand:
          shouldFill = true;
          final svgPath = StrokePath.freehandToSvgPath(stroke, page.height);
          if (svgPath.isEmpty) continue;
          gfx.drawShape(svgPath);
      }

      if (shouldFill) {
        gfx.setFillColor(strokeColor);
        gfx.fillPath();
      } else {
        gfx.setStrokeColor(strokeColor);
        gfx.setLineWidth(stroke.options.size);
        gfx.strokePath();
      }
    }
  }

  static pw.Widget? _buildImageWidget(
    SbnImage image,
    double pageHeight, {
    required List<String> warnings,
  }) {
    if (image.bytes == null || image.bytes!.isEmpty) return null;

    final ext = image.extension.toLowerCase();
    if (ext == '.pdf') {
      warnings.add(
        'Skipped embedded PDF (asset ${image.assetIndex ?? image.id}). '
        'Notes created by importing a PDF cannot be fully converted — '
        'use the original PDF file instead.',
      );
      return null;
    }
    if (ext == '.svg') {
      warnings.add(
        'Skipped embedded SVG image (asset ${image.assetIndex ?? image.id}).',
      );
      return null;
    }

    try {
      final pdfImage = pw.MemoryImage(image.bytes!);
      return pw.Positioned(
        left: image.x,
        top: image.y,
        child: pw.Image(
          pdfImage,
          width: image.width,
          height: image.height,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static String _extractPlainText(List<dynamic> delta) {
    final buf = StringBuffer();
    for (final op in delta) {
      if (op is Map && op.containsKey('insert')) {
        final insert = op['insert'];
        if (insert is String) {
          buf.write(insert);
        }
      }
    }
    return buf.toString().trimRight();
  }

  /// Convenience: render and save to file.
  static Future<List<String>> renderToFile(
    SbnDocument doc,
    String outputPath, {
    bool verbose = false,
  }) async {
    final result = render(doc, verbose: verbose);
    final file = File(outputPath);
    await file.writeAsBytes(await result.pdf.save());
    return result.warnings;
  }
}
