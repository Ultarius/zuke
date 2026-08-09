import 'dart:convert';
import 'dart:io';

import 'package:calculator_api/calculator_api.dart';

Future<Map<String, Object?>> _post(
  CalculatorServer server,
  Map<String, Object?> body, {
  required String identity,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/calculations/evaluate'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('x-rate-limit-identity', identity);
    request.headers.set('x-correlation-id', 'rate-limit-demo');
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return {
      'status': response.statusCode,
      'retryAfter': response.headers.value('retry-after'),
      'body': jsonDecode(text),
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final server = CalculatorServer();
  await server.start();
  try {
    const body = <String, Object?>{
      'firstOperand': '2',
      'secondOperand': '3',
      'operator': '+',
    };

    final first = await _post(server, body, identity: 'client-a');
    final second = await _post(server, body, identity: 'client-a');
    final completedBeforeBlocked = server.application.events.length;
    final blocked = await _post(server, body, identity: 'client-a');
    final completedAfterBlocked = server.application.events.length;
    final otherIdentity = await _post(server, body, identity: 'client-b');

    final blockedBody = blocked['body'] as Map;
    final blockedError = blockedBody['error'] as Map;
    final valid =
        first['status'] == 200 &&
        second['status'] == 200 &&
        blocked['status'] == 429 &&
        blocked['retryAfter'] == '60' &&
        blockedError['code'] == 'RATE_LIMIT_EXCEEDED' &&
        otherIdentity['status'] == 200 &&
        completedBeforeBlocked == 2 &&
        completedAfterBlocked == completedBeforeBlocked &&
        server.application.events.length == completedBeforeBlocked + 1;

    if (!valid) {
      throw StateError('Local rate-limit demonstration did not pass.');
    }

    final summary =
        '''# Local rate-limit demonstration

This is the Calculator Product's application-owned request-boundary control.
It runs without APIM and is exercised through the real local HTTP server.

| Identity | Request 1 | Request 2 | Request 3 |
| --- | ---: | ---: | ---: |
| client-a | ${first['status']} | ${second['status']} | ${blocked['status']} |
| client-b | ${otherIdentity['status']} | — | — |

- Blocked response: `${blockedError['code']}`
- Retry-After: `${blocked['retryAfter']}` seconds
- Domain invocations before blocked request: `$completedBeforeBlocked`
- Domain invocations after blocked request: `$completedAfterBlocked`
- Result: **passed**

The third request from `client-a` is rejected by `RateLimitMiddleware` before
the calculator controller or domain service runs. A different identity remains
allowed. An APIM deployment can enforce the same contract at the gateway; see
`docs/apim-rate-limit.md`.
''';
    stdout.write(summary);
    final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summaryPath != null && summaryPath.isNotEmpty) {
      File(summaryPath).writeAsStringSync(summary, mode: FileMode.append);
    }
  } finally {
    await server.stop();
  }
}
