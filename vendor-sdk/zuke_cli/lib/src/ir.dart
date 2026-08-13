/// Private CLI proof-graph facade.
///
/// The public adapter contract is [package:zuke_core/zuke_core.dart]. A
/// framework adapter emits the public topology DTO and the CLI projects that
/// DTO once into this internal proof graph. There is no reverse projection or
/// second runtime evidence model.
library;

export 'package:zuke_core/src/internal_ir.dart';
export 'package:zuke_core/src/internal_adapter.dart';
