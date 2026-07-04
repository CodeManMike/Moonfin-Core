import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  test('modern detail screen series resolve via the shared helper', () async {
    final repo = _MockSeerrRepository();
    final item = AggregatedItem(
      id: 'series-42',
      serverId: 'server-1',
      rawData: const {
        'Type': 'Series',
        'Name': 'Modern Show',
        'ProviderIds': {'Tvdb': '54321'},
      },
    );
    const tvDetails = SeerrTvDetails(id: 111, name: 'Modern Show');
    when(
      () => repo.resolveTvdbToSeerrTv(54321),
    ).thenAnswer((_) async => tvDetails);

    final result = await resolveSeriesForSeerrRequest(
      item: item,
      seerrAvailable: true,
      repository: repo,
    );

    expect(result, same(tvDetails));
  });
}
