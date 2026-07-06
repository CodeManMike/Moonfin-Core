import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Responds to every request with a canned response keyed by URL path,
/// mirroring the real Moonfin/Seerr proxy routes (`Status`, `Api/tv/tvdb/*`).
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._responses);

  final Map<String, ResponseBody Function()> _responses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    for (final entry in _responses.entries) {
      if (options.path.contains(entry.key)) return entry.value();
    }
    throw StateError('Unexpected request: ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late _MockPreferenceStore store;
  late _MockSessionRepository session;
  late _MockMediaServerClient client;
  late SeerrRepository repo;

  setUp(() {
    store = _MockPreferenceStore();
    session = _MockSessionRepository();
    client = _MockMediaServerClient();
    repo = SeerrRepository(store, session, client);
  });

  group('resolveTvdbToSeerrTv', () {
    test('returns null when the underlying lookup throws', () async {
      // No Seerr session/client is configured for this repo instance, so
      // getTvDetailsByTvdb will throw (StateError: Seerr HTTP client not
      // initialized) once ensureInitialized() runs with no active user.
      when(() => session.activeUserId).thenReturn(null);

      final result = await repo.resolveTvdbToSeerrTv(12345);

      expect(result, isNull);
    });

    test(
      'resolves through the real Moonfin proxy HTTP path when Seerr is connected',
      () async {
        when(() => session.activeUserId).thenReturn('user-1');
        when(() => client.baseUrl).thenReturn('https://example.test');
        when(() => client.accessToken).thenReturn('token-123');

        final adapter = _RecordingAdapter({
          '/Moonfin/Seerr/Status': () => _jsonResponse({
            'enabled': true,
            'authenticated': true,
          }),
          '/Moonfin/Seerr/Api/tv/tvdb/12345': () => _jsonResponse({
            'id': 42,
            'name': 'Example Show',
          }),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final connectedRepo = SeerrRepository(
          store,
          session,
          client,
          testDio: dio,
        );

        final result = await connectedRepo.resolveTvdbToSeerrTv(12345);

        expect(result, isNotNull);
        expect(result!.id, 42);
        expect(result.displayTitle, 'Example Show');
      },
    );
  });
}
