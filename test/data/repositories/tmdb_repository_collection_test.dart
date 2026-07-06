import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/repositories/tmdb_repository.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

/// Records the last request seen and returns a canned response.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('getCollection returns null when there is no access token', () async {
    final client = MockMediaServerClient();
    when(() => client.accessToken).thenReturn(null);
    when(() => client.baseUrl).thenReturn('https://example.test');

    final repo = TmdbRepository(client);
    final result = await repo.getCollection(10);

    expect(result, isNull);
  });

  test('getCollection sends the auth header and returns decoded parts on success', () async {
    final client = MockMediaServerClient();
    when(() => client.accessToken).thenReturn('abc123');
    when(() => client.baseUrl).thenReturn('https://example.test');

    final adapter = _RecordingAdapter((_) => _jsonResponse({
          'success': true,
          'parts': [
            {'id': 1, 'title': 'Part One'},
            {'id': 2, 'title': 'Part Two'},
          ],
        }, 200));
    final dio = Dio()..httpClientAdapter = adapter;

    final repo = TmdbRepository(client, dio: dio);
    final result = await repo.getCollection(10);

    expect(
      adapter.lastRequest!.uri.toString(),
      'https://example.test/Moonfin/Tmdb/Collection/10',
    );
    expect(
      adapter.lastRequest!.headers['Authorization'],
      'MediaBrowser Token="abc123"',
    );
    expect(result, isNotNull);
    expect(result!['success'], isTrue);
    final parts = result['parts'] as List;
    expect(parts, hasLength(2));
    expect((parts[0] as Map)['title'], 'Part One');
  });

  test('getCollection returns null when the response success flag is false', () async {
    final client = MockMediaServerClient();
    when(() => client.accessToken).thenReturn('abc123');
    when(() => client.baseUrl).thenReturn('https://example.test');

    final adapter = _RecordingAdapter((_) => _jsonResponse({
          'success': false,
          'error': 'not found',
        }, 200));
    final dio = Dio()..httpClientAdapter = adapter;

    final repo = TmdbRepository(client, dio: dio);
    final result = await repo.getCollection(10);

    expect(result, isNull);
  });

  test('getCollection returns null when the request throws', () async {
    final client = MockMediaServerClient();
    when(() => client.accessToken).thenReturn('abc123');
    when(() => client.baseUrl).thenReturn('https://example.test');

    final adapter = _RecordingAdapter((_) => _jsonResponse({}, 500));
    final dio = Dio()..httpClientAdapter = adapter;

    final repo = TmdbRepository(client, dio: dio);
    final result = await repo.getCollection(10);

    expect(result, isNull);
  });
}
