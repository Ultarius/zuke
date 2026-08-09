import 'package:zuke_core/zuke_core.dart';

void main() {
  const span = SourceSpan(
    path: 'example.dart',
    startLine: 1,
    startColumn: 1,
    endLine: 1,
    endColumn: 10,
  );
  print(span.toJson());
}
