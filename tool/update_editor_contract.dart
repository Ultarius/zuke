import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:zuke_cli/editor.dart';

import '../vendor-sdk/zuke_cli/test/support/index_schema.dart';

void main() {
  final cli = Directory('vendor-sdk/zuke_cli');
  final plugin =
      loadYaml(File('vendor-sdk/zuke_analyzer/pubspec.yaml').readAsStringSync())
          as Map;
  final golden = File('${cli.path}/test/goldens/index_contract.json');
  golden.parent.createSync(recursive: true);
  golden.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'contractVersion': zukeIndexContract, 'pluginVersion': plugin['version'], 'serializers': indexSerializerKeys(cli)})}\n',
  );
}
