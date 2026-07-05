import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('https://example.test');
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const {});
    if (!GetIt.instance.isRegistered<UserPreferences>()) {
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(
        UserPreferences(store),
      );
    }
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<UserPreferences>()) {
      GetIt.instance.unregister<UserPreferences>();
    }
  });

  test('loading a Series populates seasons via EpisodeQueueService', () async {
    when(() => itemsApi.getItem(any(), mediaSourceId: any(named: 'mediaSourceId')))
        .thenAnswer((_) async => {'Id': 'series-1', 'Type': 'Series'});
    when(() => itemsApi.getSeasons('series-1')).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 's1', 'Name': 'Season 1'},
        ],
      },
    );
    when(() => itemsApi.getNextUp(
          seriesId: any(named: 'seriesId'),
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
        )).thenThrow(Exception('not stubbed'));
    when(() => itemsApi.getSimilarItems(any(), limit: any(named: 'limit')))
        .thenThrow(Exception('not stubbed'));
    when(() => itemsApi.getSpecialFeatures(any()))
        .thenThrow(Exception('not stubbed'));

    final viewModel = ItemDetailViewModel(
      itemId: 'series-1',
      serverId: 'server-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client),
      tmdbRepository: TmdbRepository(client),
    );

    await viewModel.load();
    await Future.delayed(Duration.zero);

    expect(viewModel.seasons, hasLength(1));
    expect(viewModel.seasons.first.id, 's1');
  });
}
