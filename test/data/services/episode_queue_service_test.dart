import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/episode_queue_service.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late EpisodeQueueService service;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    service = EpisodeQueueService();
  });

  test('loadSeasons maps raw Items into AggregatedItem list', () async {
    when(() => itemsApi.getSeasons('series-1')).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 's1', 'Name': 'Season 1'},
          {'Id': 's2', 'Name': 'Season 2'},
        ],
      },
    );

    final seasons = await service.loadSeasons(
      client: client,
      seriesId: 'series-1',
      serverId: 'server-1',
    );

    verify(() => itemsApi.getSeasons('series-1')).called(1);
    expect(seasons, hasLength(2));
    expect(seasons[0].id, 's1');
    expect(seasons[0].serverId, 'server-1');
    expect(seasons[0].name, 'Season 1');
    expect(seasons[1].id, 's2');
  });

  test('loadEpisodes passes seasonId and overview fields through', () async {
    when(
      () => itemsApi.getEpisodes(
        'series-1',
        seasonId: 'season-2',
        fields: EpisodeQueueService.episodeOverviewFields,
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'e1', 'Name': 'Episode 1', 'IndexNumber': 1},
          {'Id': 'e2', 'Name': 'Episode 2', 'IndexNumber': 2},
        ],
      },
    );

    final episodes = await service.loadEpisodes(
      client: client,
      seriesId: 'series-1',
      seasonId: 'season-2',
      serverId: 'server-1',
    );

    verify(
      () => itemsApi.getEpisodes(
        'series-1',
        seasonId: 'season-2',
        fields: EpisodeQueueService.episodeOverviewFields,
      ),
    ).called(1);
    expect(episodes, hasLength(2));
    expect(episodes[0].id, 'e1');
    expect(episodes[1].indexNumber, 2);
  });
}
