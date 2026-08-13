import 'package:test/test.dart';
import 'package:zuke_cli/zuke_cli.dart';

void main() {
  test('uses the release-matrix CLI version by default', () {
    expect(ZukeCli().version, '0.4.1');
  });

  test('allows callers and tests to override the displayed version', () {
    expect(ZukeCli(version: 'test-version').version, 'test-version');
  });
}
