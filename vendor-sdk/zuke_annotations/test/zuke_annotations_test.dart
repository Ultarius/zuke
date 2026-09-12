import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:test/test.dart';

enum _Scenario implements ZukeScenarioContract {
  success(
    ScenarioId('SCN-CART-SUCCESS-CHECKOUT'),
    RuleId('RULE-CART-SUCCESSFUL-CHECKOUT'),
    'Successfully place order with items in cart',
  );

  const _Scenario(this.id, this.requirementId, this.title);
  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  Set<ControlId> get controlIds => const {};
}

void main() {
  test('ImplementsRequirement stores requirement IDs', () {
    final impl = ImplementsRequirement(['RULE-001']);
    expect(impl.requirementIds, contains('RULE-001'));
    expect(impl.variant, 'default');
    expect(impl.slot, 'primary');
  });

  test('ProvidesControl stores control IDs', () {
    final ctrl = ProvidesControl(
      ['CTRL-001'],
      kind: ControlProviderKind.applicationValidator,
      layer: EnforcementLayer.application,
    );
    expect(ctrl.controlIds, contains('CTRL-001'));
    expect(ctrl.kind, ControlProviderKind.applicationValidator);
  });

  test('ProvidesControl has no workspace target override', () {
    // Target placement is resolved from package membership and the active
    // extraction target. `target:` and `targets:` are intentionally absent
    // named parameters, so leftover provider target metadata is rejected by
    // the Dart analyzer instead of becoming a second placement surface.
    const provider = ProvidesControl(['CTRL-001']);
    expect(provider.controlIds, ['CTRL-001']);
  });

  test('ControlProviderKind fromValue round-trips', () {
    expect(
      ControlProviderKind.fromValue('application-validator'),
      ControlProviderKind.applicationValidator,
    );
  });

  test('EnforcementLayer fromValue round-trips', () {
    expect(
      EnforcementLayer.fromValue('application'),
      EnforcementLayer.application,
    );
  });

  test('ZukeScenarioContract preserves generated scenario identity', () {
    const contract = _Scenario.success;

    expect(contract.id.value, 'SCN-CART-SUCCESS-CHECKOUT');
    expect(contract.requirementId.value, 'RULE-CART-SUCCESSFUL-CHECKOUT');
    expect(contract.title, 'Successfully place order with items in cart');
    expect(contract.controlIds, isEmpty);
  });
}
