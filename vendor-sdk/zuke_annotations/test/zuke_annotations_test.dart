import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:test/test.dart';

enum _Scenario implements ZukeScenarioContract {
  success(
    ScenarioId('SCN-CART-SUCCESS-CHECKOUT'),
    'RULE-CART-SUCCESSFUL-CHECKOUT',
    'Successfully place order with items in cart',
  );

  const _Scenario(this.id, this.requirementId, this.title);
  @override
  final ScenarioId id;
  @override
  final String requirementId;
  @override
  final String title;
  @override
  Set<String> get controlIds => const {};
}

void main() {
  test('ImplementsRequirement stores requirement IDs', () {
    final impl = ImplementsRequirement(['RULE-001'], target: 'backend');
    expect(impl.requirementIds, contains('RULE-001'));
    expect(impl.target, 'backend');
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
    expect(contract.requirementId, 'RULE-CART-SUCCESSFUL-CHECKOUT');
    expect(contract.title, 'Successfully place order with items in cart');
    expect(contract.controlIds, isEmpty);
  });
}
