import 'package:test/test.dart';
import 'package:zuke/http.dart';

void main() {
  test('HTTP facade exposes logical request and response assertions', () {
    const response = HttpResponseSpec(statusCode: 200, body: {'result': 'ok'});

    HttpAssertions.expectStatus(response, 200);
    HttpAssertions.expectJson(response, '/result', 'ok');
  });
}
