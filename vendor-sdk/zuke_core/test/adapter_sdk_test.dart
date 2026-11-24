import 'package:zuke_core/src/internal_adapter.dart';
import 'package:zuke_core/zuke_core.dart' show SourceSnapshotDigest;
import 'package:test/test.dart';

void main() {
  const bare =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  const otherBare =
      'a3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  IrAdapterOutput outputWith({
    required String inputDigest,
    SourceSnapshotDigest? provenanceDigest,
    String? packageName = 'test_package',
  }) => IrAdapterOutput(
    adapter: AdapterDescriptor(
      id: 'test-adapter',
      version: '1.0.0',
      compatibilityId: 'test',
    ),
    completeness: IrAdapterCompleteness(),
    symbols: [],
    inputDigest: inputDigest,
    provenanceDigest: provenanceDigest,
    packageName: packageName,
    packageRoot: '/tmp/test',
  );

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

  group('published source identity', () {
    test('publishes the provenance identity over the adapter read-digest', () {
      final output = outputWith(
        inputDigest: otherBare,
        provenanceDigest: SourceSnapshotDigest.parse(bare),
      );
      expect(output.publishedSourceDigest, 'sha256:$bare');
      expect(output.requirePublishedSourceDigest(), 'sha256:$bare');
    });

    test('falls back to a well-formed adapter read-digest', () {
      // An adapter invoked directly never passes through the extraction
      // service, so its read-digest is the only identity available.
      final output = outputWith(inputDigest: bare);
      expect(output.provenanceDigest, isNull);
      expect(output.publishedSourceDigest, 'sha256:$bare');
      expect(output.requirePublishedSourceDigest(), 'sha256:$bare');
    });

    test('a lenient read yields null where a durable write must fail', () {
      for (final unusable in const ['', 'abc123', 'sha256:$bare']) {
        final output = outputWith(inputDigest: unusable);
        expect(
          output.publishedSourceDigest,
          isNull,
          reason: 'validation treats an unusable identity as stale: $unusable',
        );
        expect(
          () => output.requirePublishedSourceDigest(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('test_package'), contains(unusable)),
            ),
          ),
          reason: 'a durable artifact must never record $unusable',
        );
      }
    });

    test('names the adapter when the output declares no package', () {
      final output = outputWith(inputDigest: '', packageName: null);
      expect(
        () => output.requirePublishedSourceDigest(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('test-adapter'),
          ),
        ),
      );
    });
  });
}
