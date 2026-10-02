import 'package:library_catalog/library_catalog.dart';
import 'package:zuke/zuke.dart';

final class LibraryWorld extends ScenarioWorld {
  final CheckoutController controller;
  final CatalogBindings bindings;
  final Map<String, BranchPeerServer> branches = {};
  String pendingIsbn;

  LibraryWorld({
    CheckoutController? controller,
    CatalogBindings? bindings,
    this.pendingIsbn = '',
  }) : controller = controller ?? CheckoutController(),
       bindings = bindings ?? CatalogBindings();

  String displayFor(String bindingId) => switch (bindingId) {
    'library.loanCountDisplay' => controller.loanCountDisplay,
    'library.loanList' => controller.loanList,
    'library.errorMessage' => controller.errorMessage,
    'library.statusMessage' => controller.statusMessage,
    'library.isbnInput' => pendingIsbn,
    'library.checkoutButton' => 'checkout',
    _ => throw StateError('Unknown pure-Dart binding "$bindingId"'),
  };

  BranchPeerServer branch(String id) =>
      branches[id] ?? (throw StateError('No branch "$id" in this world.'));

  Future<void> dispose() async {
    for (final server in branches.values) {
      await server.close();
    }
    branches.clear();
  }
}
