import 'package:zuke_core/zuke_core.dart';

void main() {
  const identity = ExecutionSourceIdentity(
    sourcePackage: 'example',
    sourceAdapter: 'example.adapter',
    sourceCompatibilityId: 'example-adapter-v1',
  );
  print(identity.toJson());
}
