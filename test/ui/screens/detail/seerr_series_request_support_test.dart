import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  group('resolveSeriesForSeerrRequest', () {
    test('returns null when the series has no TVDB provider id', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {'Type': 'Series', 'ProviderIds': <String, dynamic>{}},
      );

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );

      expect(result, isNull);
      verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
    });

    test('returns null when Seerr is not available', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {
          'Type': 'Series',
          'ProviderIds': {'Tvdb': '12345'},
        },
      );

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: false,
        repository: repo,
      );

      expect(result, isNull);
      verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
    });

    test('resolves via the TVDB id when available', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {
          'Type': 'Series',
          'ProviderIds': {'Tvdb': '12345'},
        },
      );
      const tvDetails = SeerrTvDetails(id: 999, name: 'Test Show');
      when(
        () => repo.resolveTvdbToSeerrTv(12345),
      ).thenAnswer((_) async => tvDetails);

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );

      expect(result, same(tvDetails));
      verify(() => repo.resolveTvdbToSeerrTv(12345)).called(1);
    });
  });
}
