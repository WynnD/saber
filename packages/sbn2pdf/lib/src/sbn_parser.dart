import 'dart:io';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:fixnum/fixnum.dart';

import 'package:sbn2pdf/src/models.dart';

/// Parses a .sbn2 file (BSON format) into an [SbnDocument].
class SbnParser {
  /// Parse from raw bytes of a .sbn2 file.
  static SbnDocument parse(Uint8List bytes, {String? filePath}) {
    final bsonBinary = BsonBinary.from(bytes);
    final json = BsonCodec.deserialize(bsonBinary);
    return _fromJson(json, filePath: filePath);
  }

  /// Parse from a file path.
  static SbnDocument parseFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', path);
    }
    final bytes = file.readAsBytesSync();
    final doc = parse(bytes, filePath: path);
    return _loadAssets(doc, path);
  }

  static SbnDocument _fromJson(
    Map<String, dynamic> json, {
    String? filePath,
  }) {
    final fileVersion = (json['v'] as int?) ?? 0;

    final int? bgColor;
    switch (json['b']) {
      case final int v:
        bgColor = v;
      case final Int64 v:
        bgColor = v.toInt();
      default:
        bgColor = null;
    }

    final pagesJson = json['z'] as List? ?? [];
    final inlineAssets = _parseInlineAssets(json['a'] as List?);

    final pages = <SbnPage>[];
    for (final pageJson in pagesJson) {
      pages.add(_parsePage(
        pageJson as Map<String, dynamic>,
        fileVersion: fileVersion,
        inlineAssets: inlineAssets,
      ));
    }

    return SbnDocument(
      fileVersion: fileVersion,
      backgroundColor: bgColor,
      backgroundPattern: json['p'] as String?,
      lineHeight: (json['l'] as int?) ?? 40,
      lineThickness: (json['lt'] as int?) ?? 1,
      pages: pages,
    );
  }

  static List<Uint8List>? _parseInlineAssets(List? assetsJson) {
    if (assetsJson == null) return null;
    return assetsJson.map((a) {
      if (a is BsonBinary) return Uint8List.fromList(a.byteList);
      if (a is List<int>) return Uint8List.fromList(a);
      return Uint8List(0);
    }).toList();
  }

  static SbnPage _parsePage(
    Map<String, dynamic> json, {
    required int fileVersion,
    List<Uint8List>? inlineAssets,
  }) {
    final width = (json['w'] as num?)?.toDouble() ?? 1000.0;
    final height = (json['h'] as num?)?.toDouble() ?? 1400.0;

    final strokes = <SbnStroke>[];
    for (final s in (json['s'] as List?) ?? []) {
      final stroke = _parseStroke(
        s as Map<String, dynamic>,
        fileVersion: fileVersion,
      );
      if (stroke != null) strokes.add(stroke);
    }

    final images = <SbnImage>[];
    for (final img in (json['i'] as List?) ?? []) {
      images.add(_parseImage(
        img as Map<String, dynamic>,
        inlineAssets: inlineAssets,
      ));
    }

    SbnImage? bgImage;
    if (json['b'] is Map<String, dynamic>) {
      bgImage = _parseImage(
        json['b'] as Map<String, dynamic>,
        inlineAssets: inlineAssets,
      );
    }

    return SbnPage(
      width: width,
      height: height,
      strokes: strokes,
      images: images,
      quillDelta: json['q'] as List?,
      backgroundImage: bgImage,
    );
  }

  static SbnStroke? _parseStroke(
    Map<String, dynamic> json, {
    required int fileVersion,
  }) {
    final shapeStr = json['shape'] as String?;
    final SbnStrokeShape shape;
    switch (shapeStr) {
      case 'circle':
        shape = SbnStrokeShape.circle;
      case 'rect':
        shape = SbnStrokeShape.rect;
      case null:
        shape = SbnStrokeShape.freehand;
      default:
        return null; // unknown shape
    }

    final toolId = SbnToolId.parse(json['ty'] as String?);
    final color = _parseColor(json['c']);
    final pressureEnabled = (json['pe'] as bool?) ?? true;
    var options = SbnStrokeOptions.fromJson(json);

    if (shape == SbnStrokeShape.circle) {
      return SbnStroke(
        shape: shape,
        toolId: toolId,
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        centerX: (json['cx'] as num?)?.toDouble() ?? 0,
        centerY: (json['cy'] as num?)?.toDouble() ?? 0,
        radius: (json['r'] as num?)?.toDouble() ?? 0,
      );
    }

    if (shape == SbnStrokeShape.rect) {
      return SbnStroke(
        shape: shape,
        toolId: toolId,
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        rectLeft: (json['rl'] as num?)?.toDouble() ?? 0,
        rectTop: (json['rt'] as num?)?.toDouble() ?? 0,
        rectWidth: (json['rw'] as num?)?.toDouble() ?? 0,
        rectHeight: (json['rh'] as num?)?.toDouble() ?? 0,
      );
    }

    // Freehand: parse points
    final offsetX = (json['ox'] as num?)?.toDouble() ?? 0;
    final offsetY = (json['oy'] as num?)?.toDouble() ?? 0;
    final pointsJson = json['p'] as List? ?? [];

    final points = <SbnPoint>[];
    for (final p in pointsJson) {
      if (fileVersion >= 13 && p is BsonBinary) {
        final byteList = p.byteList;
        if (byteList.lengthInBytes < 8) continue; // need at least x,y
        final floats = byteList.buffer.asFloat32List(
          byteList.offsetInBytes,
          byteList.lengthInBytes ~/ 4,
        );
        points.add(SbnPoint(
          floats[0] + offsetX,
          floats[1] + offsetY,
          floats.length > 2 ? floats[2] : null,
        ));
      } else if (p is Map) {
        points.add(SbnPoint(
          ((p['x'] as num?)?.toDouble() ?? 0) + offsetX,
          ((p['y'] as num?)?.toDouble() ?? 0) + offsetY,
          (p['p'] as num?)?.toDouble(),
        ));
      }
    }

    if (toolId == SbnToolId.shapePen) {
      options = SbnStrokeOptions(
        size: options.size,
        thinning: options.thinning,
        smoothing: 0,
        streamline: 0,
        simulatePressure: options.simulatePressure,
        isComplete: options.isComplete,
        taperStart: options.taperStart,
        capStart: options.capStart,
        taperEnd: options.taperEnd,
        capEnd: options.capEnd,
      );
    }

    return SbnStroke(
      shape: shape,
      toolId: toolId,
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      points: points,
    );
  }

  static int _parseColor(dynamic value) {
    if (value is int) return value;
    if (value is Int64) return value.toInt();
    return 0xFF000000; // default black
  }

  static SbnImage _parseImage(
    Map<String, dynamic> json, {
    List<Uint8List>? inlineAssets,
  }) {
    final assetIndex = json['a'] as int?;
    Uint8List? bytes;
    if (assetIndex != null &&
        inlineAssets != null &&
        assetIndex < inlineAssets.length) {
      bytes = inlineAssets[assetIndex];
    }

    return SbnImage(
      id: (json['id'] as int?) ?? 0,
      extension: (json['e'] as String?) ?? '.png',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['w'] as num?)?.toDouble() ?? 0,
      height: (json['h'] as num?)?.toDouble() ?? 0,
      assetIndex: assetIndex,
      bytes: bytes,
    );
  }

  /// Load external asset files (file.sbn2.0, file.sbn2.1, etc.)
  static SbnDocument _loadAssets(SbnDocument doc, String sbn2Path) {
    final pages = <SbnPage>[];
    for (final page in doc.pages) {
      final images =
          page.images.map((img) => _loadAsset(img, sbn2Path)).toList();
      final bgImage = page.backgroundImage != null
          ? _loadAsset(page.backgroundImage!, sbn2Path)
          : null;
      pages.add(SbnPage(
        width: page.width,
        height: page.height,
        strokes: page.strokes,
        images: images,
        quillDelta: page.quillDelta,
        backgroundImage: bgImage,
      ));
    }
    return SbnDocument(
      fileVersion: doc.fileVersion,
      backgroundColor: doc.backgroundColor,
      backgroundPattern: doc.backgroundPattern,
      lineHeight: doc.lineHeight,
      lineThickness: doc.lineThickness,
      pages: pages,
    );
  }

  static SbnImage _loadAsset(SbnImage image, String sbn2Path) {
    if (image.assetIndex != null && image.bytes == null) {
      final assetPath = '$sbn2Path.${image.assetIndex}';
      final assetFile = File(assetPath);
      if (assetFile.existsSync()) {
        return image.copyWith(bytes: assetFile.readAsBytesSync());
      }
    }
    return image;
  }
}
