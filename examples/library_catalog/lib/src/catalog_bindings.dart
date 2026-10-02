import 'package:zuke_annotations/zuke_annotations.dart';

import 'generated/feat_library_001_contracts.g.dart';

/// Runtime binding keys for the pure-Dart catalog desk (no Flutter).
class CatalogBindingKey {
  final String id;
  const CatalogBindingKey.single(this.id);
}

/// Catalog membership keys declared in `specs/features/library_catalog.feature`.
///
/// Each getter is the single source of truth for a required binding ID; the
/// analyzer plugin rejects IDs that are not in `.zuke/analyzer-index.json`.
class CatalogBindings
    implements FeatLibrary001FlutterBindings<CatalogBindingKey> {
  @override
  @ZukeBinding('library.isbnInput')
  CatalogBindingKey get isbnInput =>
      const CatalogBindingKey.single('library.isbnInput');

  @override
  @ZukeBinding('library.checkoutButton')
  CatalogBindingKey get checkoutButton =>
      const CatalogBindingKey.single('library.checkoutButton');

  @override
  @ZukeBinding('library.loanList')
  CatalogBindingKey get loanList =>
      const CatalogBindingKey.single('library.loanList');

  @override
  @ZukeBinding('library.loanCountDisplay')
  CatalogBindingKey get loanCountDisplay =>
      const CatalogBindingKey.single('library.loanCountDisplay');

  @override
  @ZukeBinding('library.errorMessage')
  CatalogBindingKey get errorMessage =>
      const CatalogBindingKey.single('library.errorMessage');

  @override
  @ZukeBinding('library.statusMessage')
  CatalogBindingKey get statusMessage =>
      const CatalogBindingKey.single('library.statusMessage');
}
