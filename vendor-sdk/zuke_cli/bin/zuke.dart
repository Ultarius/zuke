#!/usr/bin/env dart

import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';

Future<void> main(List<String> args) async {
  final cli = ZukeCli();
  exitCode = await cli.run(args);
}
