import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  test(
    'resolveSeriesForSeerrRequest is skipped for non-Series items',
    () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'movie-1',
        serverId: 'server-1',
        rawData: const {
          'Type': 'Movie',
          'ProviderIds': {'Tvdb': '12345'},
        },
      );

      // resolveSeriesForSeerrRequest itself guards on item.type, so a Movie
      // must never reach the repository, regardless of any caller-side check
      // in item_detail_screen.dart's _loadSeerrSeriesResolution.
      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );

      expect(result, isNull);
      verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
    },
  );

  test('resolveSeriesForSeerrRequest resolves for a Series item', () async {
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
  });
}
