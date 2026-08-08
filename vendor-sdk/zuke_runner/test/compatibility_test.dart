import 'package:test/test.dart';
import 'package:zuke_runner/http.dart' as legacy_http;
import 'package:zuke_runner/runtime.dart' as legacy_runtime;
import 'package:zuke_runner/zuke_runner.dart' as legacy_runner;

void main() {
  test('legacy entry points forward to package:zuke', () {
    final registry =
        legacy_runner.StepRegistry<legacy_runner.MapScenarioWorld>();
    final flags = legacy_runtime.ZukeFeatureFlags({'compatibility': true});
    const response = legacy_http.HttpResponseSpec(statusCode: 200);

    expect(
      registry,
      isA<legacy_runner.StepRegistry<legacy_runner.MapScenarioWorld>>(),
    );
    expect(flags.isEnabled('compatibility'), isTrue);
    expect(response.statusCode, 200);
  });
}
