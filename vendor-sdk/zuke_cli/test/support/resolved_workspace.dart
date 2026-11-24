import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';

/// Makes temporary source fixtures resolve the same real dependencies as the
/// test runner, without invoking pub or fabricating annotation declarations.
Future<void> configureFixturePackages(Directory root) async {
  final configUri = (await Isolate.packageConfig)!;
  final config = jsonDecode(File.fromUri(configUri).readAsStringSync()) as Map;
  final pubspec = File('${root.path}/pubspec.yaml');
  final name = pubspec.existsSync()
      ? (loadYaml(pubspec.readAsStringSync()) as Map)['name'] as String
      : 'fixture';
  final packages = [
    for (final package in config['packages'] as List)
      if (package['name'] != name)
        {
          ...package as Map,
          'rootUri': configUri.resolve(package['rootUri'] as String).toString(),
        },
    {
      'name': name,
      'rootUri': root.absolute.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    },
  ];
  final file = File('${root.path}/.dart_tool/package_config.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({'configVersion': 2, 'packages': packages}),
  );
}
