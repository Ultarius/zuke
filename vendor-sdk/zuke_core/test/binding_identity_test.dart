import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/src/internal_ir.dart';

void main() {
  test('binding identity round-trips with explicit semantic fields', () {
    const identity = BindingIdentity(
      subjectKind: 'requirement',
      subjectId: 'RULE-ACCESS-NORMALIZATION',
      target: 'backend',
      role: 'implementation',
      variant: 'default',
      slot: 'create',
    );

    expect(BindingIdentity.fromJson(identity.toJson()).key, identity.key);
    expect(identity.key, contains('|create'));
  });

  test('slot validation accepts stable tokens and rejects ambiguous names', () {
    expect(isValidBindingSlot('primary'), isTrue);
    expect(isValidBindingSlot('create-lobby'), isTrue);
    expect(isValidBindingSlot('CreateLobby'), isFalse);
    expect(isValidBindingSlot('lib/service.dart'), isFalse);
    expect(isValidBindingSlot('0-create'), isFalse);
    expect(isValidBindingSlot('post'), isFalse);
    expect(() => requireBindingSlot('v0.4.0'), throwsA(isA<FormatException>()));
  });

  test('JSON rejects an invalid slot instead of normalizing it', () {
    expect(
      () => BindingIdentity.fromJson({
        'subjectKind': 'requirement',
        'subjectId': 'RULE-1',
        'target': 'backend',
        'role': 'implementation',
        'variant': 'default',
        'slot': 'CreateLobby',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('implementation coverage JSON round-trips its binding identity', () {
    const result = ImplementationCoverageResult(
      binding: BindingIdentity(
        subjectKind: 'requirement',
        subjectId: 'RULE-ACCESS-NORMALIZATION',
        target: 'backend',
        role: 'implementation',
        slot: 'join',
      ),
      mode: PlacementMode.annotationGoverned,
      status: ProofStatus.verified,
      evidenceDigests: ['sha256:abc'],
    );

    final decoded = ImplementationCoverageResult.fromJson(result.toJson());
    expect(decoded.binding.key, result.binding.key);
    expect(decoded.mode, PlacementMode.annotationGoverned);
    expect(decoded.status, ProofStatus.verified);
  });
}
