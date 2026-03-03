import 'dart:typed_data';

/// Top-level document parsed from a .sbn2 file.
class SbnDocument {
  final int fileVersion;
  final int? backgroundColor; // ARGB32
  final String? backgroundPattern;
  final int lineHeight;
  final int lineThickness;
  final List<SbnPage> pages;

  SbnDocument({
    required this.fileVersion,
    this.backgroundColor,
    this.backgroundPattern,
    this.lineHeight = 40,
    this.lineThickness = 1,
    required this.pages,
  });
}

/// A single page in the document.
class SbnPage {
  final double width;
  final double height;
  final List<SbnStroke> strokes;
  final List<SbnImage> images;
  final List<dynamic>? quillDelta;
  final SbnImage? backgroundImage;

  SbnPage({
    this.width = 1000,
    this.height = 1400,
    this.strokes = const [],
    this.images = const [],
    this.quillDelta,
    this.backgroundImage,
  });
}

/// Tool ID matching Saber's ToolId enum string values.
enum SbnToolId {
  highlighter('Highlighter'),
  fountainPen('fountainPen'),
  ballpointPen('ballpointPen'),
  pencil('Pencil'),
  shapePen('ShapePen'),
  eraser('Eraser');

  final String id;
  const SbnToolId(this.id);

  static SbnToolId parse(String? value) {
    if (value == null || value == 'Pen') return SbnToolId.fountainPen;
    for (final tool in SbnToolId.values) {
      if (value == tool.id) return tool;
    }
    return SbnToolId.fountainPen;
  }

  /// Whether this tool type should be rasterized (skipped in vector rendering).
  bool get shouldRasterize =>
      this == SbnToolId.highlighter || this == SbnToolId.pencil;
}

/// The shape discriminator for strokes.
enum SbnStrokeShape { freehand, circle, rect }

/// Stroke options parsed from the sbn2 JSON (mirrors perfect_freehand StrokeOptions).
class SbnStrokeOptions {
  final double size;
  final double thinning;
  final double smoothing;
  final double streamline;
  final bool simulatePressure;
  final bool isComplete;
  final double taperStart;
  final bool capStart;
  final double taperEnd;
  final bool capEnd;

  const SbnStrokeOptions({
    this.size = 10,
    this.thinning = 0.5,
    this.smoothing = 0,
    this.streamline = 0.5,
    this.simulatePressure = true,
    this.isComplete = true,
    this.taperStart = 0,
    this.capStart = true,
    this.taperEnd = 0,
    this.capEnd = true,
  });

  /// Parse from the stroke's JSON map (same keys as perfect_freehand v2).
  factory SbnStrokeOptions.fromJson(Map<String, dynamic> json) {
    // Taper: -1.0 means taper enabled but no custom value
    double taperStart = 0;
    bool capStart = true;
    if (json.containsKey('ts')) {
      final ts = (json['ts'] as num?)?.toDouble() ?? -1.0;
      taperStart = ts < 0 ? 0 : ts;
    }
    if (json.containsKey('cs')) {
      capStart = (json['cs'] as bool?) ?? true;
    }

    double taperEnd = 0;
    bool capEnd = true;
    if (json.containsKey('te')) {
      final te = (json['te'] as num?)?.toDouble() ?? -1.0;
      taperEnd = te < 0 ? 0 : te;
    }
    if (json.containsKey('ce')) {
      capEnd = (json['ce'] as bool?) ?? true;
    }

    return SbnStrokeOptions(
      size: (json['s'] as num?)?.toDouble() ?? 10,
      thinning: (json['t'] as num?)?.toDouble() ?? 0.5,
      smoothing: (json['sm'] as num?)?.toDouble() ?? 0,
      streamline: (json['sl'] as num?)?.toDouble() ?? 0.5,
      simulatePressure: (json['sp'] as bool?) ?? true,
      isComplete: (json['f'] as bool?) ?? true,
      taperStart: taperStart,
      capStart: capStart,
      taperEnd: taperEnd,
      capEnd: capEnd,
    );
  }
}

/// A point with x, y and optional pressure.
class SbnPoint {
  final double x;
  final double y;
  final double? pressure;

  const SbnPoint(this.x, this.y, [this.pressure]);
}

/// A stroke on a page.
class SbnStroke {
  final SbnStrokeShape shape;
  final SbnToolId toolId;
  final int color; // ARGB32
  final bool pressureEnabled;
  final SbnStrokeOptions options;

  // Freehand stroke points
  final List<SbnPoint> points;

  // Circle stroke fields
  final double? centerX;
  final double? centerY;
  final double? radius;

  // Rectangle stroke fields
  final double? rectLeft;
  final double? rectTop;
  final double? rectWidth;
  final double? rectHeight;

  SbnStroke({
    required this.shape,
    required this.toolId,
    required this.color,
    this.pressureEnabled = true,
    required this.options,
    this.points = const [],
    this.centerX,
    this.centerY,
    this.radius,
    this.rectLeft,
    this.rectTop,
    this.rectWidth,
    this.rectHeight,
  });
}

/// An image embedded in a page.
class SbnImage {
  final int id;
  final String extension;
  final double x;
  final double y;
  final double width;
  final double height;
  final int? assetIndex;
  Uint8List? bytes;

  SbnImage({
    required this.id,
    required this.extension,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.assetIndex,
    this.bytes,
  });
}
