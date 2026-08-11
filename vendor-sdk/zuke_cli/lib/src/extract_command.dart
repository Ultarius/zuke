import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_extractor/dart_extractor.dart';
import 'package:zuke_core/zuke_core.dart';

class ExtractDartCommand {
  final ArgResults args;
  ExtractDartCommand(this.args);

  Future<int> execute() async {
    final root = Directory(
      args['root'] as String? ?? Directory.current.path,
    ).absolute.resolveSymbolicLinksSync();
    final packagePath = args['package'] as String?;
    if (packagePath == null) {
      stderr.writeln('zuke extract dart requires --package <path>');
      return 1;
    }
    final packageRoot = Directory(
      '$root${Platform.pathSeparator}$packagePath',
    ).absolute.resolveSymbolicLinksSync();
    final output = await DartExtractor().extract(packageRoot);
    for (final error in output.errors) {
      stderr.writeln('ERROR: $error');
    }
    final fragment = CanonicalFragment.fromOutput(output, workspaceRoot: root);
    final json =
        const JsonEncoder.withIndent('  ').convert(fragment.toJson()) + '\n';
    final emit = args['emit'] as String?;
    if (emit != null) {
      final file = File(emit);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(json);
      stdout.writeln('Wrote ${file.path}');
    } else {
      stdout.write(json);
    }
    return output.errors.isEmpty ? 0 : 1;
  }
}
