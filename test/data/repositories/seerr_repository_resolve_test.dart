import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

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
  });
}
