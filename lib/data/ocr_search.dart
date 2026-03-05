import 'dart:io';
import 'dart:math';

import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

class OcrSearchResult {
  final String notePath;
  final String noteName;
  final int lineNumber;
  final String context;

  OcrSearchResult({
    required this.notePath,
    required this.noteName,
    required this.lineNumber,
    required this.context,
  });
}

class OcrSearchService {
  static const _ocrExtension = '${Editor.extension}.ocr';
  static const _contextLines = 2;

  static Future<List<OcrSearchResult>> search(
    String query, {
    int maxResults = 20,
  }) async {
    if (query.isEmpty) return [];

    final queryLower = query.toLowerCase();
    final results = <OcrSearchResult>[];
    final rootDir = Directory(FileManager.documentsDirectory);

    if (!rootDir.existsSync()) return [];

    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(_ocrExtension)) continue;

      final absolutePath = entity.path;
      final relativePath = absolutePath.substring(
        FileManager.documentsDirectory.length,
      );

      // Strip .sbn2.ocr to get the note path
      final notePath = relativePath.substring(
        0,
        relativePath.length - _ocrExtension.length,
      );
      final noteName = notePath.split('/').last;

      // Match on note name itself
      if (noteName.toLowerCase().contains(queryLower)) {
        results.add(OcrSearchResult(
          notePath: notePath,
          noteName: noteName,
          lineNumber: 0,
          context: notePath,
        ));
        if (results.length >= maxResults) return results;
      }

      try {
        final content = await entity.readAsString();
        final lines = content.split('\n');

        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].toLowerCase().contains(queryLower)) continue;

          final contextStart = max(0, i - _contextLines);
          final contextEnd = min(lines.length, i + _contextLines + 1);
          final contextSnippet = lines.sublist(contextStart, contextEnd).join('\n');

          results.add(OcrSearchResult(
            notePath: notePath,
            noteName: noteName,
            lineNumber: i + 1,
            context: contextSnippet,
          ));

          if (results.length >= maxResults) return results;
        }
      } on FileSystemException {
        // Skip unreadable files
        continue;
      }
    }

    return results;
  }
}
