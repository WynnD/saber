import 'package:perfect_freehand/perfect_freehand.dart';

import 'package:sbn2pdf/src/models.dart';

/// Converts strokes to SVG path strings for PDF rendering.
class StrokePath {
  /// Convert a freehand stroke's points into an SVG path string.
  ///
  /// Uses perfect_freehand to generate the outline polygon, then
  /// converts to SVG M/L commands with Y-axis flipped for PDF coordinates.
  static String freehandToSvgPath(SbnStroke stroke, double pageHeight) {
    if (stroke.points.isEmpty) return '';

    final opts = stroke.options;
    final simulatePressure =
        stroke.pressureEnabled ? opts.simulatePressure : false;

    // Convert SbnPoints to perfect_freehand v1 Points
    final pfPoints = stroke.points
        .where((p) => p.x.isFinite && p.y.isFinite)
        .map((p) => Point(p.x, p.y, p.pressure ?? 0.5))
        .toList();

    if (pfPoints.isEmpty) return '';

    final polygon = getStroke(
      pfPoints,
      size: opts.size,
      thinning: opts.thinning,
      smoothing: opts.smoothing,
      streamline: opts.streamline,
      taperStart: opts.taperStart,
      capStart: opts.capStart,
      taperEnd: opts.taperEnd,
      capEnd: opts.capEnd,
      simulatePressure: simulatePressure,
      isComplete: opts.isComplete,
    );

    final svgPoints = polygon
        .where((p) => p.x.isFinite && p.y.isFinite)
        .map((p) => '${p.x} ${pageHeight - p.y}');

    return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
  }
}
