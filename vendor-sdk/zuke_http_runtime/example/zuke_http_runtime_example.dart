import 'package:zuke_http_runtime/zuke_http_runtime.dart';

Future<void> main() async {
  final response = await const ZukeHttpApplication().dispatch(
    const ZukeHttpRequest(method: 'GET', path: '/health'),
  );
  print(response.statusCode);
}
