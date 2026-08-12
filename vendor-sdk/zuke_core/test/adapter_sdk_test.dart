import 'package:zuke_core/zuke_core.dart';
import 'package:test/test.dart';

void main() {
  test('CanonicalFragment fromOutput creates fragment', () {
    final output = IrAdapterOutput(
      adapter: AdapterDescriptor(
        id: 'test-adapter',
        version: '1.0.0',
        compatibilityId: 'test',
      ),
      completeness: IrAdapterCompleteness(),
      symbols: [],
      inputDigest: 'abc123',
      packageName: 'test_package',
      packageRoot: '/tmp/test',
    );
    final fragment = CanonicalFragment.fromOutput(output);
    expect(fragment.kind, 'zuke.adapter-fragment');
    expect(fragment.packageName, 'test_package');
  });

  test('FrameworkAdapter typedef exists', () {
    expect(AdapterInfo, isNotNull);
  });
}
