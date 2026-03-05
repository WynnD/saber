import 'dart:io';

import 'package:args/args.dart';
import 'package:sbn2pdf/sbn2pdf.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    _printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  if (args.rest.isEmpty) {
    stderr.writeln('Error: No input file specified.');
    _printUsage(parser);
    exit(1);
  }

  final inputPath = args.rest[0];
  final verbose = args['verbose'] as bool;

  if (!inputPath.endsWith('.sbn2')) {
    stderr.writeln('Error: Input file must be a .sbn2 file.');
    exit(1);
  }

  if (!File(inputPath).existsSync()) {
    stderr.writeln('Error: File not found: $inputPath');
    exit(1);
  }

  final outputPath = args.rest.length > 1
      ? args.rest[1]
      : inputPath.replaceAll(RegExp(r'\.sbn2$'), '.pdf');

  if (verbose) {
    stderr.writeln('Input:  $inputPath');
    stderr.writeln('Output: $outputPath');
  }

  try {
    final doc = SbnParser.parseFile(inputPath);

    if (verbose) {
      stderr.writeln('Parsed: ${doc.pages.length} pages, '
          'version ${doc.fileVersion}');
    }

    final warnings =
        await PdfRenderer.renderToFile(doc, outputPath, verbose: verbose);
    stderr.writeln('Written: $outputPath');

    if (warnings.isNotEmpty) {
      stderr.writeln();
      for (final w in warnings) {
        stderr.writeln('Warning: $w');
      }
    }
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (verbose) stderr.writeln(st);
    exit(1);
  }
}

void _printUsage(ArgParser parser) {
  stderr.writeln('Usage: sbn2pdf [options] <input.sbn2> [output.pdf]');
  stderr.writeln();
  stderr.writeln('Converts Saber .sbn2 notes to PDF.');
  stderr.writeln();
  stderr.writeln('Options:');
  stderr.writeln(parser.usage);
}
