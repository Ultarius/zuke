import 'dart:io';

void main(List<String> arguments) {
  final rootIndex = arguments.indexOf('--root');
  final root = Directory(
    rootIndex >= 0 && rootIndex + 1 < arguments.length
        ? arguments[rootIndex + 1]
        : Directory.current.path,
  ).absolute;
  Iterable<Directory> directoriesUnder(String relativePath) {
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$relativePath',
    );
    return directory.existsSync()
        ? directory.listSync().whereType<Directory>()
        : const <Directory>[];
  }

  final packageRoots = <Directory>[
    ...directoriesUnder('vendor-sdk'),
    ...directoriesUnder(
      'examples${Platform.pathSeparator}calculator-product${Platform.pathSeparator}apps',
    ),
    ...directoriesUnder(
      'examples${Platform.pathSeparator}calculator-product${Platform.pathSeparator}packages',
    ),
    ...directoriesUnder('examples'),
  ];
  for (final package in packageRoots) {
    final coverage = Directory(
      '${package.path}${Platform.pathSeparator}coverage',
    );
    if (coverage.existsSync()) {
      final normalized = coverage.absolute.path.replaceAll('\\', '/');
      if (!normalized.startsWith('${root.path.replaceAll('\\', '/')}/')) {
        throw StateError(
          'Refusing to remove coverage outside workspace: $normalized',
        );
      }
      coverage.deleteSync(recursive: true);
      stdout.writeln('Removed ${coverage.path}');
    }
    final report = Directory(
      '${package.path}${Platform.pathSeparator}generated${Platform.pathSeparator}report',
    );
    if (report.existsSync()) {
      final normalized = report.absolute.path.replaceAll('\\', '/');
      if (!normalized.startsWith('${root.path.replaceAll('\\', '/')}/')) {
        throw StateError(
          'Refusing to remove generated/report outside workspace: $normalized',
        );
      }
      report.deleteSync(recursive: true);
      stdout.writeln('Removed ${report.path}');
    }
  }
}
