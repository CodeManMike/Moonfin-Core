import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:test/test.dart';

/// Records the last request seen and returns a canned response.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  RequestOptions? lastRequest;
  String? lastRequestBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      lastRequestBody = utf8.decode(bytes);
    }
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _status(int code) => ResponseBody.fromString('', code);

void main() {
  late Dio dio;
  late _RecordingAdapter adapter;
  late JellysleepApi api;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://host'));
    adapter = _RecordingAdapter((_) => _status(204));
    dio.httpClientAdapter = adapter;
    api = JellysleepApi(dio);
  });

  group('startTimer', () {
    test('posts duration type and minutes to StartTimer', () async {
      await api.startTimer(type: 'duration', duration: 30);

      expect(adapter.lastRequest!.method, 'POST');
      expect(
        adapter.lastRequest!.uri.toString(),
        'https://host/Plugin/Jellysleep/StartTimer',
      );
      final body = jsonDecode(adapter.lastRequestBody!) as Map;
      expect(body['type'], 'duration');
      expect(body['duration'], 30);
    });

    test('posts episode type and count to StartTimer', () async {
      await api.startTimer(type: 'episode', duration: 2);

      final body = jsonDecode(adapter.lastRequestBody!) as Map;
      expect(body['type'], 'episode');
      expect(body['duration'], 2);
    });
  });

  group('cancelTimer', () {
    test('posts to CancelTimer with no body', () async {
      await api.cancelTimer();

      expect(adapter.lastRequest!.method, 'POST');
      expect(
        adapter.lastRequest!.uri.toString(),
        'https://host/Plugin/Jellysleep/CancelTimer',
      );
    });
  });
}
