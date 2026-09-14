import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_cli/src/gate_command.dart';
import 'package:zuke_cli/src/init_preset.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  for (final mode in ['auto', 'cli', 'directSnapshot']) {
    test(
      'all-profile gate forwards $mode and retains child trust diagnostics',
      () async {
        final root = Directory.systemTemp.createTempSync('zuke-gate-compose-');
        addTearDown(() => root.deleteSync(recursive: true));
        File('${root.path}/zuke.yaml').writeAsStringSync(
          InitPreset.dart
              .configuration(root)
              .replaceAll(
                'profiles: [pullRequest, merge, release, nightly]',
                'profiles: [pullRequest, release]',
              ),
        );
        final summary = File('${root.path}/summary.json');
        final args = ZukeCli().parser.parse([
          'gate',
          '--root',
          root.path,
          '--all-profiles',
          '--runner-mode',
          mode,
          '--summary-file',
          summary.path,
        ]).command!;
        final profiles = <String>[];
        final command = GateCommand(
          args,
          processRunner: (executable, arguments, {workingDirectory}) async {
            expect(arguments[arguments.indexOf('--runner-mode') + 1], mode);
            final profile = arguments[arguments.indexOf('--profile') + 1];
            profiles.add(profile);
            final failed = profile == 'release';
            final result = CommandResult(
              command: 'gate',
              stage: 'gate',
              exitCode: failed ? 1 : 0,
              status: failed ? CommandStatus.failed : CommandStatus.passed,
              eligible: !failed,
              diagnostics: failed
                  ? [
                      const Diagnostic(
                        code: 'ZUKE-TRUST-001',
                        stage: 'trust',
                        severity: DiagnosticSeverity.error,
                        owner: DiagnosticOwner.project,
                        message: 'No active release signers',
                        remediation:
                            'Configure an authorized release public key',
                      ),
                    ]
                  : [],
            );
            File(
              arguments[arguments.indexOf('--summary-file') + 1],
            ).writeAsStringSync(jsonEncode(result.toJson()));
            return ProcessResult(1, failed ? 1 : 0, '', '');
          },
        );
        expect(await command.execute(), 1);
        expect(profiles, ['pullRequest', 'release']);
        expect(
          summary.readAsStringSync(),
          contains('No active release signers'),
        );
        expect(
          summary.readAsStringSync(),
          contains('Configure an authorized release public key'),
        );
      },
    );
  }
}
