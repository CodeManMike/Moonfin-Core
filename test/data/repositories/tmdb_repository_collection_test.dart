import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/repositories/tmdb_repository.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

void main() {
  test('getCollection returns null when there is no access token', () async {
    final client = MockMediaServerClient();
    when(() => client.accessToken).thenReturn(null);
    when(() => client.baseUrl).thenReturn('https://example.test');

    final repo = TmdbRepository(client);
    final result = await repo.getCollection(10);

    expect(result, isNull);
  });
}
