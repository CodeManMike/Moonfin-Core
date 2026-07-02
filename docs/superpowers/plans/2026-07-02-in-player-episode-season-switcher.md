# In-Player Episode & Season Switcher Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

**Goal**: Let a user jump to any episode or season while still inside the video player, via a new season-tabbed episode-grid overlay reachable from a control-bar button, instead of only advancing sequentially to the next queued episode.

**Architecture**: A new shared `EpisodeQueueService` (in `lib/data/services/`) extracts the `getSeasons`/`getEpisodes`/`loadAllSeriesEpisodes`-equivalent REST calls out of `ItemDetailViewModel` so both the view model and `VideoPlayerScreen` call the same code; `ItemDetailViewModel` is refactored to delegate to it (behavior-preserving). A new `EpisodeSwitcherOverlay` widget, modeled directly on `NextUpOverlay`'s glass-panel/`Positioned`/TV-focus pattern, renders season tabs and an episode grid inside the player. Selecting an episode already in the live queue calls `QueueService.jumpTo`; selecting an episode from a different season calls `PlaybackManager.playItems` with the freshly fetched season's episode list and the tapped start index — a full requeue, not a queue splice.

**Tech Stack**: Flutter/Dart client (`E:\Moonfin-Core`), `flutter_test` for unit/widget tests (no `mocktail` usage exists anywhere in this repo today despite being a listed dev dependency — this plan follows the repo's actual convention of hand-built fakes/stubs, not mocktail), `get_it` for DI, `server_core`/`server_jellyfin` for the `MediaServerClient`/`ItemsApi` abstraction, `playback_core` for `QueueService`/`PlaybackManager`.

---

### Task 1: `EpisodeQueueService` — shared season/episode fetch helper

**Files**:
- Create: `E:\Moonfin-Core\lib\data\services\episode_queue_service.dart`
- Test: `E:\Moonfin-Core\test\data\services\episode_queue_service_test.dart`
- Modify (Task 1 only touches the new file + its test; `ItemDetailViewModel` delegation happens in Task 2)

**Context used for accuracy**: `MediaServerClient.itemsApi.getSeasons(String seriesId)` and `getEpisodes(String seriesId, {String? seasonId, String? fields})` both return `Future<Map<String, dynamic>>` shaped `{'Items': [...]}` (confirmed in `packages/server_jellyfin/lib/src/api/jellyfin_items_api.dart:237-253` and the abstract in `packages/server_core/lib/src/api/items_api.dart:76-83`). `AggregatedItem` takes `{required id, required serverId, required rawData}` (`lib/data/models/aggregated_item.dart:10-14`). `ItemDetailViewModel._episodeOverviewFields` is `'Overview,MediaStreams,MediaSources,RunTimeTicks,Trickplay,UserData,Chapters'` (`lib/data/viewmodels/item_detail_view_model.dart:25-26`).

- [ ] Step 1: Write the failing test for `getSeasons`

  Create `E:\Moonfin-Core\test\data\services\episode_queue_service_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:server_core/server_core.dart';

  import 'package:moonfin/data/services/episode_queue_service.dart';

  class _FakeItemsApi extends Fake implements ItemsApi {
    Map<String, dynamic> seasonsResponse = const {'Items': <dynamic>[]};
    Map<String, dynamic> episodesResponse = const {'Items': <dynamic>[]};
    String? lastSeasonsSeriesId;
    String? lastEpisodesSeriesId;
    String? lastEpisodesSeasonId;
    String? lastEpisodesFields;

    @override
    Future<Map<String, dynamic>> getSeasons(String seriesId) async {
      lastSeasonsSeriesId = seriesId;
      return seasonsResponse;
    }

    @override
    Future<Map<String, dynamic>> getEpisodes(
      String seriesId, {
      String? seasonId,
      String? fields,
    }) async {
      lastEpisodesSeriesId = seriesId;
      lastEpisodesSeasonId = seasonId;
      lastEpisodesFields = fields;
      return episodesResponse;
    }
  }

  class _FakeClient extends Fake implements MediaServerClient {
    _FakeClient(this._itemsApi);
    final _FakeItemsApi _itemsApi;

    @override
    ItemsApi get itemsApi => _itemsApi;

    @override
    String get baseUrl => 'https://example.test';
  }

  void main() {
    late _FakeItemsApi fakeItemsApi;
    late _FakeClient fakeClient;
    late EpisodeQueueService service;

    setUp(() {
      fakeItemsApi = _FakeItemsApi();
      fakeClient = _FakeClient(fakeItemsApi);
      service = EpisodeQueueService();
    });

    test('loadSeasons maps raw Items into AggregatedItem list', () async {
      fakeItemsApi.seasonsResponse = {
        'Items': [
          {'Id': 's1', 'Name': 'Season 1'},
          {'Id': 's2', 'Name': 'Season 2'},
        ],
      };

      final seasons = await service.loadSeasons(
        client: fakeClient,
        seriesId: 'series-1',
        serverId: 'server-1',
      );

      expect(fakeItemsApi.lastSeasonsSeriesId, 'series-1');
      expect(seasons, hasLength(2));
      expect(seasons[0].id, 's1');
      expect(seasons[0].serverId, 'server-1');
      expect(seasons[0].name, 'Season 1');
      expect(seasons[1].id, 's2');
    });
  }
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected failure output: `Error: Error when reading 'lib/data/services/episode_queue_service.dart': No such file or directory` (compile error, since `episode_queue_service.dart` does not exist yet).

- [ ] Step 2: Write the minimal `EpisodeQueueService` to pass the `loadSeasons` test

  Create `E:\Moonfin-Core\lib\data\services\episode_queue_service.dart`:

  ```dart
  import 'package:server_core/server_core.dart';

  import '../models/aggregated_item.dart';

  /// Shared season/episode fetch helper. Both [ItemDetailViewModel] and the
  /// video player call this instead of duplicating the same
  /// getSeasons/getEpisodes REST calls and AggregatedItem mapping.
  class EpisodeQueueService {
    static const episodeOverviewFields =
        'Overview,MediaStreams,MediaSources,RunTimeTicks,Trickplay,UserData,Chapters';

    List<AggregatedItem> _mapItems(List items, String serverId) {
      return items
          .cast<Map<String, dynamic>>()
          .map(
            (raw) => AggregatedItem(
              id: raw['Id']?.toString() ?? '',
              serverId: serverId,
              rawData: raw,
            ),
          )
          .toList();
    }

    Future<List<AggregatedItem>> loadSeasons({
      required MediaServerClient client,
      required String seriesId,
      required String serverId,
    }) async {
      final data = await client.itemsApi.getSeasons(seriesId);
      final items = (data['Items'] as List?) ?? [];
      return _mapItems(items, serverId);
    }
  }
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected output: `00:0X +1: All tests passed!`

- [ ] Step 3: Commit

  ```
  git add lib/data/services/episode_queue_service.dart test/data/services/episode_queue_service_test.dart
  git commit -m "Add EpisodeQueueService.loadSeasons shared helper"
  ```

- [ ] Step 4: Write the failing test for `loadEpisodes`

  Add to `E:\Moonfin-Core\test\data\services\episode_queue_service_test.dart`, inside `main()` after the `loadSeasons` test:

  ```dart
    test('loadEpisodes passes seasonId and overview fields through', () async {
      fakeItemsApi.episodesResponse = {
        'Items': [
          {'Id': 'e1', 'Name': 'Episode 1', 'IndexNumber': 1},
          {'Id': 'e2', 'Name': 'Episode 2', 'IndexNumber': 2},
        ],
      };

      final episodes = await service.loadEpisodes(
        client: fakeClient,
        seriesId: 'series-1',
        seasonId: 'season-2',
        serverId: 'server-1',
      );

      expect(fakeItemsApi.lastEpisodesSeriesId, 'series-1');
      expect(fakeItemsApi.lastEpisodesSeasonId, 'season-2');
      expect(
        fakeItemsApi.lastEpisodesFields,
        EpisodeQueueService.episodeOverviewFields,
      );
      expect(episodes, hasLength(2));
      expect(episodes[0].id, 'e1');
      expect(episodes[1].indexNumber, 2);
    });
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected failure output: `The method 'loadEpisodes' isn't defined for the type 'EpisodeQueueService'.` (compile error).

- [ ] Step 5: Implement `loadEpisodes`

  Edit `E:\Moonfin-Core\lib\data\services\episode_queue_service.dart`, adding this method after `loadSeasons`:

  ```dart
    Future<List<AggregatedItem>> loadEpisodes({
      required MediaServerClient client,
      required String seriesId,
      required String serverId,
      String? seasonId,
    }) async {
      final data = await client.itemsApi.getEpisodes(
        seriesId,
        seasonId: seasonId,
        fields: episodeOverviewFields,
      );
      final items = (data['Items'] as List?) ?? [];
      return _mapItems(items, serverId);
    }
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected output: `00:0X +2: All tests passed!`

- [ ] Step 6: Commit

  ```
  git add lib/data/services/episode_queue_service.dart test/data/services/episode_queue_service_test.dart
  git commit -m "Add EpisodeQueueService.loadEpisodes shared helper"
  ```

- [ ] Step 7: Write the failing test for `loadAllSeriesEpisodes`

  Add to `E:\Moonfin-Core\test\data\services\episode_queue_service_test.dart`, after the `loadEpisodes` test:

  ```dart
    test('loadAllSeriesEpisodes omits seasonId to fetch every season', () async {
      fakeItemsApi.episodesResponse = {
        'Items': [
          {'Id': 'e1', 'Name': 'S1E1', 'ParentIndexNumber': 1, 'IndexNumber': 1},
          {'Id': 'e2', 'Name': 'S2E1', 'ParentIndexNumber': 2, 'IndexNumber': 1},
        ],
      };

      final episodes = await service.loadAllSeriesEpisodes(
        client: fakeClient,
        seriesId: 'series-1',
        serverId: 'server-1',
      );

      expect(fakeItemsApi.lastEpisodesSeriesId, 'series-1');
      expect(fakeItemsApi.lastEpisodesSeasonId, isNull);
      expect(episodes, hasLength(2));
      expect(episodes[0].parentIndexNumber, 1);
      expect(episodes[1].parentIndexNumber, 2);
    });
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected failure output: `The method 'loadAllSeriesEpisodes' isn't defined for the type 'EpisodeQueueService'.` (compile error).

- [ ] Step 8: Implement `loadAllSeriesEpisodes`

  Edit `E:\Moonfin-Core\lib\data\services\episode_queue_service.dart`, adding this method after `loadEpisodes`:

  ```dart
    Future<List<AggregatedItem>> loadAllSeriesEpisodes({
      required MediaServerClient client,
      required String seriesId,
      required String serverId,
    }) async {
      return loadEpisodes(
        client: client,
        seriesId: seriesId,
        serverId: serverId,
        seasonId: null,
      );
    }
  ```

  Run: `flutter test test/data/services/episode_queue_service_test.dart`

  Expected output: `00:0X +3: All tests passed!`

- [ ] Step 9: Commit

  ```
  git add lib/data/services/episode_queue_service.dart test/data/services/episode_queue_service_test.dart
  git commit -m "Add EpisodeQueueService.loadAllSeriesEpisodes shared helper"
  ```

---

### Task 2: Delegate `ItemDetailViewModel` to `EpisodeQueueService`

**Files**:
- Modify: `E:\Moonfin-Core\lib\data\viewmodels\item_detail_view_model.dart` (lines 275-319, the `_loadSeasons`/`_loadEpisodes`/`loadAllSeriesEpisodes` methods, plus constructor)
- Test: `E:\Moonfin-Core\test\data\viewmodels\item_detail_view_model_test.dart` (new — no existing test file for this view model)

**Context used for accuracy**: current methods, verbatim from the file read:

```dart
  Future<void> _loadSeasons() async {
    try {
      final data = await _client.itemsApi.getSeasons(itemId);
      final items = (data['Items'] as List?) ?? [];
      _seasons = _mapItems(items);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadEpisodes() async {
    final item = _item;
    if (item == null) return;
    final seriesId = item.seriesId ?? itemId;
    try {
      final data = await _client.itemsApi.getEpisodes(
        seriesId,
        seasonId: item.type == 'Season' ? itemId : item.seasonId,
        fields: _episodeOverviewFields,
      );
      final items = (data['Items'] as List?) ?? [];
      _episodes = _mapItems(items);
      notifyListeners();
    } catch (_) {}
  }

  /// Loads every episode of the current Series (all seasons) on demand. Used by
  /// the Modern detail layout's Episodes tab and accurate season counts. No-op
  /// for non-Series items or once already loaded.
  Future<void> loadAllSeriesEpisodes() async {
    final item = _item;
    if (item == null || item.type != 'Series') return;
    if (_seriesEpisodesRequested) return;
    _seriesEpisodesRequested = true;
    try {
      final data = await _client.itemsApi.getEpisodes(
        itemId,
        fields: _episodeOverviewFields,
      );
      final items = (data['Items'] as List?) ?? [];
      _seriesEpisodes = _mapItems(items);
      notifyListeners();
    } catch (_) {
      _seriesEpisodesRequested = false;
    }
  }
```

The constructor (`item_detail_view_model.dart:181-192`) takes `required client, required mutations, required mdbListRepository, required tmdbRepository` and stores them in `_client`, `_mutations`, `_mdbListRepository`, `_tmdbRepository`. `_serverId` field is set from the constructor's `serverId` param, defaulting to `_client.baseUrl` at use sites (`_mapItems`, line 356).

- [ ] Step 1: Write the failing test asserting `_loadSeasons` delegates through `EpisodeQueueService`

  Create `E:\Moonfin-Core\test\data\viewmodels\item_detail_view_model_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:server_core/server_core.dart';

  import 'package:moonfin/data/repositories/item_mutation_repository.dart';
  import 'package:moonfin/data/repositories/mdblist_repository.dart';
  import 'package:moonfin/data/repositories/tmdb_repository.dart';
  import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';

  class _FakeItemsApi extends Fake implements ItemsApi {
    Map<String, dynamic> itemResponse = const {'Id': 'series-1', 'Type': 'Series'};
    Map<String, dynamic> seasonsResponse = const {'Items': <dynamic>[]};

    @override
    Future<Map<String, dynamic>> getItem(String itemId, {String? mediaSourceId}) async {
      return itemResponse;
    }

    @override
    Future<Map<String, dynamic>> getSeasons(String seriesId) async {
      return seasonsResponse;
    }
  }

  class _FakeClient extends Fake implements MediaServerClient {
    _FakeClient(this._itemsApi);
    final _FakeItemsApi _itemsApi;

    @override
    ItemsApi get itemsApi => _itemsApi;

    @override
    String get baseUrl => 'https://example.test';
  }

  void main() {
    test('loading a Series populates seasons via EpisodeQueueService', () async {
      final fakeItemsApi = _FakeItemsApi();
      fakeItemsApi.itemResponse = {'Id': 'series-1', 'Type': 'Series'};
      fakeItemsApi.seasonsResponse = {
        'Items': [
          {'Id': 's1', 'Name': 'Season 1'},
        ],
      };
      final fakeClient = _FakeClient(fakeItemsApi);

      final viewModel = ItemDetailViewModel(
        itemId: 'series-1',
        serverId: 'server-1',
        client: fakeClient,
        mutations: ItemMutationRepository(fakeClient),
        mdbListRepository: MdbListRepository(),
        tmdbRepository: TmdbRepository(),
      );

      await viewModel.load();
      await Future.delayed(Duration.zero);

      expect(viewModel.seasons, hasLength(1));
      expect(viewModel.seasons.first.id, 's1');
    });
  }
  ```

  Run: `flutter test test/data/viewmodels/item_detail_view_model_test.dart`

  Expected failure output (this asserts current behavior already works via the private call — expect this test to actually PASS immediately since the delegation hasn't broken anything yet; it is a **characterization test** locking in existing behavior before refactoring). If it does not compile due to `MdbListRepository()`/`TmdbRepository()` requiring constructor args, adjust to match their real no-arg or DI constructors — verify by reading those two files if the run fails with a constructor-signature error before proceeding.

  Note: if `MdbListRepository` or `TmdbRepository` do not have simple no-arg constructors, first run:
  ```
  flutter test test/data/viewmodels/item_detail_view_model_test.dart
  ```
  and read the exact compiler error to fix constructor args before continuing — do not guess further.

- [ ] Step 2: Refactor `ItemDetailViewModel` to delegate to `EpisodeQueueService`

  Edit `E:\Moonfin-Core\lib\data\viewmodels\item_detail_view_model.dart`. First add the import near the top with the other relative imports:

  ```dart
  import '../services/episode_queue_service.dart';
  import '../services/plugin_sync_service.dart';
  ```

  (i.e. insert `import '../services/episode_queue_service.dart';` immediately before the existing `import '../services/plugin_sync_service.dart';` line at line 13.)

  Add a field next to `_client`/`_mutations`:

  ```dart
    final MediaServerClient _client;
    final ItemMutationRepository _mutations;
    final MdbListRepository _mdbListRepository;
    final TmdbRepository _tmdbRepository;
    final EpisodeQueueService _episodeQueueService;
  ```

  Update the constructor to accept and default it:

  ```dart
    ItemDetailViewModel({
      required this.itemId,
      String? serverId,
      required MediaServerClient client,
      required ItemMutationRepository mutations,
      required MdbListRepository mdbListRepository,
      required TmdbRepository tmdbRepository,
      EpisodeQueueService? episodeQueueService,
    }) : _serverId = serverId,
         _client = client,
         _mutations = mutations,
         _mdbListRepository = mdbListRepository,
         _tmdbRepository = tmdbRepository,
         _episodeQueueService = episodeQueueService ?? EpisodeQueueService();
  ```

  Replace `_loadSeasons`:

  ```dart
    Future<void> _loadSeasons() async {
      try {
        _seasons = await _episodeQueueService.loadSeasons(
          client: _client,
          seriesId: itemId,
          serverId: _serverId ?? _client.baseUrl,
        );
        notifyListeners();
      } catch (_) {}
    }
  ```

  Replace `_loadEpisodes`:

  ```dart
    Future<void> _loadEpisodes() async {
      final item = _item;
      if (item == null) return;
      final seriesId = item.seriesId ?? itemId;
      try {
        _episodes = await _episodeQueueService.loadEpisodes(
          client: _client,
          seriesId: seriesId,
          serverId: _serverId ?? _client.baseUrl,
          seasonId: item.type == 'Season' ? itemId : item.seasonId,
        );
        notifyListeners();
      } catch (_) {}
    }
  ```

  Replace `loadAllSeriesEpisodes`:

  ```dart
    /// Loads every episode of the current Series (all seasons) on demand. Used by
    /// the Modern detail layout's Episodes tab and accurate season counts. No-op
    /// for non-Series items or once already loaded.
    Future<void> loadAllSeriesEpisodes() async {
      final item = _item;
      if (item == null || item.type != 'Series') return;
      if (_seriesEpisodesRequested) return;
      _seriesEpisodesRequested = true;
      try {
        _seriesEpisodes = await _episodeQueueService.loadAllSeriesEpisodes(
          client: _client,
          seriesId: itemId,
          serverId: _serverId ?? _client.baseUrl,
        );
        notifyListeners();
      } catch (_) {
        _seriesEpisodesRequested = false;
      }
    }
  ```

  Leave `_episodeOverviewFields` (line 25-26) in place — it is now unused internally but harmless; do not remove it in this step to keep the diff minimal and avoid touching unrelated call sites. (It is fine to leave a private unused constant; Dart's analyzer does not error on unused private static const fields the way it does on unused local variables. If a subsequent lint run flags it, remove it in a follow-up, not here.)

  Run: `flutter test test/data/viewmodels/item_detail_view_model_test.dart`

  Expected output: `00:0X +1: All tests passed!`

- [ ] Step 3: Run the full existing detail-related test suite to confirm no regression

  Run: `flutter test test/data/services/episode_queue_service_test.dart test/data/viewmodels/item_detail_view_model_test.dart`

  Expected output: `00:0X +4: All tests passed!` (3 from Task 1 + 1 from this task).

- [ ] Step 4: Commit

  ```
  git add lib/data/viewmodels/item_detail_view_model.dart test/data/viewmodels/item_detail_view_model_test.dart
  git commit -m "Delegate ItemDetailViewModel season/episode fetching to EpisodeQueueService"
  ```

---

### Task 3: `EpisodeSwitcherOverlay` widget — season tabs + episode grid

**Files**:
- Create: `E:\Moonfin-Core\lib\ui\widgets\playback\episode_switcher_overlay.dart`
- Test: `E:\Moonfin-Core\test\ui\widgets\playback\episode_switcher_overlay_test.dart`

**Context used for accuracy**: modeled on `NextUpOverlay` (`lib/ui/widgets/playback/next_up_overlay.dart`), which imports `cached_network_image`, `flutter/material.dart`, `flutter/services.dart`, `get_it`, `moonfin_design`, and relative imports for `AggregatedItem`, `AppLocalizations`, `UserPreferences`/`preference_constants`, and `adaptiveGlass` from `../adaptive/adaptive_glass.dart`. It uses `AppColorScheme`, `AppRadius`, `ThemeRegistry.active.borders`, and wraps content in `adaptiveGlass(cornerRadius:, blur:, fallbackColor:, tint:, child:)`. `AggregatedItem` getters used: `.name`, `.indexNumber`, `.parentIndexNumber`, `.id`, `.isPlayed`, `.primaryImageTag`. L10n keys `episodes` and `seasons` already exist (`lib/l10n/app_en.arb:1042,1050`); `seasonNumber`/`episodeNumber` templated keys also exist (`lib/l10n/app_en.arb:2666-2688`).

- [ ] Step 1: Write the failing widget test for rendering season tabs and episode tiles

  Create `E:\Moonfin-Core\test\ui\widgets\playback\episode_switcher_overlay_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:get_it/get_it.dart';

  import 'package:moonfin/data/models/aggregated_item.dart';
  import 'package:moonfin/l10n/app_localizations.dart';
  import 'package:moonfin/preference/user_preferences.dart';
  import 'package:moonfin/ui/widgets/playback/episode_switcher_overlay.dart';

  AggregatedItem _season(String id, String name) => AggregatedItem(
        id: id,
        serverId: 'server-1',
        rawData: {'Id': id, 'Name': name, 'Type': 'Season'},
      );

  AggregatedItem _episode(
    String id, {
    required int season,
    required int episode,
    required String name,
  }) =>
      AggregatedItem(
        id: id,
        serverId: 'server-1',
        rawData: {
          'Id': id,
          'Name': name,
          'Type': 'Episode',
          'ParentIndexNumber': season,
          'IndexNumber': episode,
        },
      );

  void main() {
    setUp(() {
      if (!GetIt.instance.isRegistered<UserPreferences>()) {
        GetIt.instance.registerSingleton<UserPreferences>(UserPreferences());
      }
    });

    tearDown(() {
      if (GetIt.instance.isRegistered<UserPreferences>()) {
        GetIt.instance.unregister<UserPreferences>();
      }
    });

    testWidgets('renders a tab per season and an episode tile per episode',
        (tester) async {
      final seasons = [_season('s1', 'Season 1'), _season('s2', 'Season 2')];
      final episodesBySeasonId = {
        's1': [
          _episode('e1', season: 1, episode: 1, name: 'Pilot'),
          _episode('e2', season: 1, episode: 2, name: 'Second'),
        ],
        's2': [
          _episode('e3', season: 2, episode: 1, name: 'Return'),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EpisodeSwitcherOverlay(
              seasons: seasons,
              initialSeasonId: 's1',
              currentEpisodeId: 'e1',
              episodesForSeason: (seasonId) =>
                  episodesBySeasonId[seasonId] ?? const [],
              imageUrlForEpisode: (_) => null,
              onEpisodeSelected: (_, __) {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Return'), findsNothing);
    });
  }
  ```

  Run: `flutter test test/ui/widgets/playback/episode_switcher_overlay_test.dart`

  Expected failure output: `Error: Error when reading 'lib/ui/widgets/playback/episode_switcher_overlay.dart': No such file or directory` (compile error, widget doesn't exist yet).

- [ ] Step 2: Write the minimal `EpisodeSwitcherOverlay` to pass the rendering test

  Create `E:\Moonfin-Core\lib\ui\widgets\playback\episode_switcher_overlay.dart`:

  ```dart
  import 'package:cached_network_image/cached_network_image.dart';
  import 'package:flutter/material.dart';
  import 'package:moonfin_design/moonfin_design.dart';

  import '../../../data/models/aggregated_item.dart';
  import '../../../l10n/app_localizations.dart';
  import '../adaptive/adaptive_glass.dart';

  /// Full-player overlay letting the user pick any episode in any season
  /// without leaving playback. Modeled on [NextUpOverlay]'s glass-panel
  /// pattern (see `next_up_overlay.dart`).
  class EpisodeSwitcherOverlay extends StatefulWidget {
    final List<AggregatedItem> seasons;
    final String? initialSeasonId;
    final String? currentEpisodeId;
    final List<AggregatedItem> Function(String seasonId) episodesForSeason;
    final String? Function(AggregatedItem episode) imageUrlForEpisode;
    final void Function(AggregatedItem episode, List<AggregatedItem> seasonEpisodes)
        onEpisodeSelected;
    final VoidCallback onDismiss;

    const EpisodeSwitcherOverlay({
      super.key,
      required this.seasons,
      required this.initialSeasonId,
      required this.currentEpisodeId,
      required this.episodesForSeason,
      required this.imageUrlForEpisode,
      required this.onEpisodeSelected,
      required this.onDismiss,
    });

    @override
    State<EpisodeSwitcherOverlay> createState() => _EpisodeSwitcherOverlayState();
  }

  class _EpisodeSwitcherOverlayState extends State<EpisodeSwitcherOverlay> {
    late String? _selectedSeasonId = widget.initialSeasonId;

    @override
    Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context);
      final selectedSeasonId = _selectedSeasonId ??
          (widget.seasons.isNotEmpty ? widget.seasons.first.id : null);
      final episodes = selectedSeasonId != null
          ? widget.episodesForSeason(selectedSeasonId)
          : const <AggregatedItem>[];

      return Positioned.fill(
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: Container(
            color: Colors.black54,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.circular(18),
                    ),
                    child: adaptiveGlass(
                      cornerRadius: 18,
                      blur: 18,
                      fallbackColor: AppColorScheme.surface.withValues(alpha: 0.9),
                      tint: AppColorScheme.surface.withValues(alpha: 0.3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                            child: Row(
                              children: [
                                Text(
                                  l10n.episodes,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: widget.onDismiss,
                                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                                  tooltip: l10n.close,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: widget.seasons.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final season = widget.seasons[index];
                                final isSelected = season.id == selectedSeasonId;
                                return ChoiceChip(
                                  label: Text(season.name),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    setState(() => _selectedSeasonId = season.id);
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 16 / 10,
                              ),
                              itemCount: episodes.length,
                              itemBuilder: (context, index) {
                                final episode = episodes[index];
                                final isCurrent = episode.id == widget.currentEpisodeId;
                                final imageUrl = widget.imageUrlForEpisode(episode);
                                return _EpisodeTile(
                                  episode: episode,
                                  imageUrl: imageUrl,
                                  isCurrent: isCurrent,
                                  onTap: () =>
                                      widget.onEpisodeSelected(episode, episodes),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  class _EpisodeTile extends StatelessWidget {
    const _EpisodeTile({
      required this.episode,
      required this.imageUrl,
      required this.isCurrent,
      required this.onTap,
    });

    final AggregatedItem episode;
    final String? imageUrl;
    final bool isCurrent;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context) {
      return InkWell(
        onTap: onTap,
        borderRadius: AppRadius.circular(10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppRadius.circular(10),
            border: isCurrent
                ? Border.all(color: AppColorScheme.accent, width: 2)
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover)
              else
                Container(color: AppColorScheme.surfaceVariant),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                      stops: [0.0, 0.7],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Text(
                  episode.indexNumber != null
                      ? '${episode.indexNumber}. ${episode.name}'
                      : episode.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  ```

  Run: `flutter test test/ui/widgets/playback/episode_switcher_overlay_test.dart`

  Expected output: `00:0X +1: All tests passed!`

- [ ] Step 3: Commit

  ```
  git add lib/ui/widgets/playback/episode_switcher_overlay.dart test/ui/widgets/playback/episode_switcher_overlay_test.dart
  git commit -m "Add EpisodeSwitcherOverlay widget with season tabs and episode grid"
  ```

- [ ] Step 4: Write the failing test for tap-to-select callback

  Add to `E:\Moonfin-Core\test\ui\widgets\playback\episode_switcher_overlay_test.dart`, inside `main()` after the rendering test:

  ```dart
    testWidgets('tapping an episode tile invokes onEpisodeSelected with the season list',
        (tester) async {
      final seasons = [_season('s1', 'Season 1')];
      final seasonEpisodes = [
        _episode('e1', season: 1, episode: 1, name: 'Pilot'),
        _episode('e2', season: 1, episode: 2, name: 'Second'),
      ];
      AggregatedItem? selected;
      List<AggregatedItem>? selectedSeasonEpisodes;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EpisodeSwitcherOverlay(
              seasons: seasons,
              initialSeasonId: 's1',
              currentEpisodeId: 'e1',
              episodesForSeason: (_) => seasonEpisodes,
              imageUrlForEpisode: (_) => null,
              onEpisodeSelected: (episode, episodesInSeason) {
                selected = episode;
                selectedSeasonEpisodes = episodesInSeason;
              },
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('2. Second'));
      await tester.pumpAndSettle();

      expect(selected?.id, 'e2');
      expect(selectedSeasonEpisodes, hasLength(2));
    });
  ```

  Run: `flutter test test/ui/widgets/playback/episode_switcher_overlay_test.dart`

  Expected failure output: test `tapping an episode tile invokes onEpisodeSelected with the season list` fails with `Bad state: No element` or similar from `find.text('2. Second')` returning zero widgets — actually, given Step 2 already implements tile rendering with this exact label format, this test should already pass. Run it to confirm; if it passes immediately, treat this as a **characterization/regression test** for the already-implemented tap behavior rather than a red step — proceed directly to commit without further implementation changes.

  Expected output: `00:0X +2: All tests passed!`

- [ ] Step 5: Commit

  ```
  git add test/ui/widgets/playback/episode_switcher_overlay_test.dart
  git commit -m "Add episode tap-selection test coverage for EpisodeSwitcherOverlay"
  ```

---

### Task 4: Trigger button wiring in `VideoPlayerScreen`

**Files**:
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (secondary controls row, ~lines 4581-4753; new state fields near line 176-180; new imports near line 59)
- Modify: `E:\Moonfin-Core\lib\l10n\app_en.arb` (add one new key)
- Test: `E:\Moonfin-Core\test\ui\screens\playback\video_player_screen_episode_switcher_test.dart` — **not written as a full-screen widget test**; `VideoPlayerScreen` has 15+ `GetIt` singleton dependencies (`PlaybackManager`, `MediaKitPlayerBackend`, `UserPreferences`, `MediaServerClientFactory`, `CastService`, native channels, `PipService`, `PlaybackLifecycleHandler`, `ThemeMusicService`, `ScreensaverController`, etc. — see `video_player_screen.dart:86-105`) that make full-widget mounting impractical to stand up in a unit test without an integration harness this repo does not have. Per repo convention (no existing widget test mounts `VideoPlayerScreen`), this task's behavior is instead verified through the **pure helper method** extracted in Step 2 below, tested in isolation, plus a manual verification checklist in the Verification section.

**Context used for accuracy**: `_controlButton` signature (`video_player_screen.dart:5598-5630`) takes `(IconData icon, {required VoidCallback onPressed, double size = 24, double extent = 48, String? tooltip, FocusNode? focusNode, Color iconColor = Colors.white, VoidCallback? onRightBoundary})`. The secondary buttons list is built in `_buildSecondaryControlsRow()` (`video_player_screen.dart:4581-4753`), which already derives `final item = _queue.currentItem;` at line 4586 and conditionally includes buttons like the chapters button (`hasChapters`, lines 4659-4666). `QueueService get _queue => _manager.queueService;` (line 257). `MediaServerClient _clientForItem(AggregatedItem item)` (lines 259-262) resolves the per-item server client via `_clientFactory.getClientIfExists(item.serverId) ?? GetIt.instance<MediaServerClient>()`. Existing state fields block starts at line 174 (`MediaSegment? _skipSegment;` ... `bool _showNextUp = false;`).

- [ ] Step 1: Write the failing test for a pure helper that decides whether the switcher button should show

  This isolates the only new *logic* (as opposed to wiring) introduced by this task: "is the current queue item an Episode with a resolvable seriesId." Create `E:\Moonfin-Core\test\ui\screens\playback\video_player_screen_episode_switcher_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';

  import 'package:moonfin/data/models/aggregated_item.dart';
  import 'package:moonfin/ui/screens/playback/episode_switcher_eligibility.dart';

  AggregatedItem _episode({String? seriesId}) => AggregatedItem(
        id: 'e1',
        serverId: 'server-1',
        rawData: {
          'Id': 'e1',
          'Type': 'Episode',
          'SeriesId': seriesId,
        },
      );

  AggregatedItem _movie() => AggregatedItem(
        id: 'm1',
        serverId: 'server-1',
        rawData: {'Id': 'm1', 'Type': 'Movie'},
      );

  void main() {
    test('episode with a seriesId is eligible for the switcher', () {
      expect(canShowEpisodeSwitcher(_episode(seriesId: 'series-1')), isTrue);
    });

    test('episode without a seriesId is not eligible', () {
      expect(canShowEpisodeSwitcher(_episode(seriesId: null)), isFalse);
    });

    test('non-episode items are not eligible', () {
      expect(canShowEpisodeSwitcher(_movie()), isFalse);
    });

    test('non-AggregatedItem queue items (offline url/raw map) are not eligible', () {
      expect(canShowEpisodeSwitcher('offline://some/path.mp4'), isFalse);
      expect(canShowEpisodeSwitcher(<String, dynamic>{'Type': 'Episode'}), isFalse);
    });
  }
  ```

  Run: `flutter test test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected failure output: `Error: Error when reading 'lib/ui/screens/playback/episode_switcher_eligibility.dart': No such file or directory` (compile error).

- [ ] Step 2: Implement the pure eligibility helper

  Create `E:\Moonfin-Core\lib\ui\screens\playback\episode_switcher_eligibility.dart`:

  ```dart
  import '../../../data/models/aggregated_item.dart';

  /// Whether the in-player episode/season switcher button should be shown
  /// for the given queue item (an [AggregatedItem], a raw offline map, or an
  /// offline file path string — see [VideoPlayerScreen._queue]).
  bool canShowEpisodeSwitcher(dynamic queueItem) {
    if (queueItem is! AggregatedItem) return false;
    if (queueItem.type != 'Episode') return false;
    final seriesId = queueItem.seriesId;
    return seriesId != null && seriesId.isNotEmpty;
  }
  ```

  Run: `flutter test test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected output: `00:0X +4: All tests passed!`

- [ ] Step 3: Commit

  ```
  git add lib/ui/screens/playback/episode_switcher_eligibility.dart test/ui/screens/playback/video_player_screen_episode_switcher_test.dart
  git commit -m "Add pure eligibility helper for the in-player episode switcher button"
  ```

- [ ] Step 4: Add the l10n key for the button tooltip

  Edit `E:\Moonfin-Core\lib\l10n\app_en.arb`. Insert a new key next to the existing `"episodes": "Episodes",` entry (line 1042):

  ```json
    "episodes": "Episodes",
    "switchEpisode": "Episodes & Seasons",
  ```

  There is no automated test for `.arb` string presence in this repo; verification is that `flutter gen-l10n` (run automatically by `flutter test`/`flutter build`) regenerates `app_localizations.dart` without error.

  Run: `flutter test test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected output: `00:0X +4: All tests passed!` (confirms the arb edit didn't break codegen; this test doesn't touch l10n directly but a broken arb file fails the whole `flutter test` invocation at the build_runner/gen-l10n step).

- [ ] Step 5: Commit

  ```
  git add lib/l10n/app_en.arb
  git commit -m "Add switchEpisode l10n key for the episode switcher button tooltip"
  ```

- [ ] Step 6: Wire the trigger button, overlay state, and selection handler into `VideoPlayerScreen`

  This step is UI wiring with no new pure logic, so no new automated test is added for it (consistent with the rest of `_buildSecondaryControlsRow`, which has no direct test coverage today either — see the Task 4 Files note above). Verification is manual (see Verification section) plus the existing `flutter analyze` gate.

  Edit `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`.

  Add two new imports right after the existing `import '../../widgets/playback/next_up_overlay.dart';` line (59):

  ```dart
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/episode_switcher_overlay.dart';
  import 'episode_switcher_eligibility.dart';
  ```

  Add the shared-service import next to the other `data/services` imports (after line 38, `import '../../../data/services/media_server_client_factory.dart';`):

  ```dart
  import '../../../data/services/media_server_client_factory.dart';
  import '../../../data/services/episode_queue_service.dart';
  ```

  Add new state fields right after the existing Next Up state block (after line 180, `int _consecutiveEpisodes = 0;`):

  ```dart
    MediaSegment? _skipSegment;
    Duration? _skipTo;
    bool _showNextUp = false;
    AggregatedItem? _nextUpItem;
    bool _nextUpDismissed = false;
    bool _isNextUpAdvancing = false;
    int _consecutiveEpisodes = 0;
    bool _showEpisodeSwitcher = false;
    List<AggregatedItem> _episodeSwitcherSeasons = const [];
    String? _episodeSwitcherSelectedSeasonId;
    final Map<String, List<AggregatedItem>> _episodeSwitcherEpisodesBySeason = {};
    final _episodeQueueService = EpisodeQueueService();
  ```

  Add the trigger button to `_buildSecondaryControlsRow()`. Insert it right after the chapters button block (after line 4666, i.e. right before `if (showSubtitleButton)` at line 4667):

  ```dart
          if (hasChapters)
            _controlButton(
              Icons.bookmark_outline_rounded,
              onPressed: _showChapters,
              size: secondaryIconSize,
              extent: secondaryExtent,
              tooltip: l10n.chapters,
            ),
          if (canShowEpisodeSwitcher(item))
            _controlButton(
              Icons.video_library_outlined,
              onPressed: _openEpisodeSwitcher,
              size: secondaryIconSize,
              extent: secondaryExtent,
              tooltip: l10n.switchEpisode,
            ),
          if (showSubtitleButton)
  ```

  Add the handler methods right after `_showChapters` (after line 6169, i.e. right before `bool _hasCastCrew(dynamic item) {` at line 6171):

  ```dart
    Future<void> _openEpisodeSwitcher() async {
      final item = _queue.currentItem;
      if (item is! AggregatedItem) return;
      final seriesId = item.seriesId;
      if (seriesId == null || seriesId.isEmpty) return;

      final client = _clientForItem(item);
      final currentSeasonId = item.seasonId;

      List<AggregatedItem> seasons;
      try {
        seasons = await _episodeQueueService.loadSeasons(
          client: client,
          seriesId: seriesId,
          serverId: item.serverId,
        );
      } catch (error) {
        if (!mounted) return;
        _showThrottledPlaybackError(error.toString());
        return;
      }
      if (!mounted || seasons.isEmpty) return;

      _episodeSwitcherEpisodesBySeason.clear();
      setState(() {
        _episodeSwitcherSeasons = seasons;
        _episodeSwitcherSelectedSeasonId = currentSeasonId ?? seasons.first.id;
        _showEpisodeSwitcher = true;
        _controlsVisible = false;
      });
      _hideTimer?.cancel();
    }

    List<AggregatedItem> _episodesForSwitcherSeason(String seasonId) {
      final cached = _episodeSwitcherEpisodesBySeason[seasonId];
      if (cached != null) return cached;

      final item = _queue.currentItem;
      if (item is! AggregatedItem) return const [];
      final seriesId = item.seriesId;
      if (seriesId == null || seriesId.isEmpty) return const [];

      _episodeSwitcherEpisodesBySeason[seasonId] = const [];
      unawaited(_loadEpisodesForSwitcherSeason(seriesId, seasonId, item.serverId));
      return const [];
    }

    Future<void> _loadEpisodesForSwitcherSeason(
      String seriesId,
      String seasonId,
      String serverId,
    ) async {
      final client = _clientForItem(_queue.currentItem as AggregatedItem);
      try {
        final episodes = await _episodeQueueService.loadEpisodes(
          client: client,
          seriesId: seriesId,
          serverId: serverId,
          seasonId: seasonId,
        );
        if (!mounted) return;
        setState(() {
          _episodeSwitcherEpisodesBySeason[seasonId] = episodes;
        });
      } catch (error) {
        if (!mounted) return;
        _showThrottledPlaybackError(error.toString());
      }
    }

    String? _imageUrlForSwitcherEpisode(AggregatedItem episode) {
      if (episode.primaryImageTag == null) return null;
      return _clientForItem(episode).imageApi.getPrimaryImageUrl(
            episode.id,
            maxWidth: 400,
            tag: episode.primaryImageTag,
          );
    }

    Future<void> _handleEpisodeSwitcherSelection(
      AggregatedItem episode,
      List<AggregatedItem> seasonEpisodes,
    ) async {
      _suppressBackNavigation(duration: const Duration(milliseconds: 500));
      setState(() {
        _showEpisodeSwitcher = false;
      });

      final currentItem = _queue.currentItem;
      final currentEpisodeSeasonId =
          currentItem is AggregatedItem ? currentItem.seasonId : null;

      if (episode.seasonId != null &&
          episode.seasonId == currentEpisodeSeasonId) {
        // Same season as the live queue: jump within the existing queue,
        // no requeue needed.
        final existingIndex = _queue.items.indexWhere((queued) {
          return queued is AggregatedItem && queued.id == episode.id;
        });
        if (existingIndex >= 0) {
          _queue.jumpTo(existingIndex);
          await _manager.startQueuedPlayback();
          return;
        }
      }

      // Different season (or not present in the live queue): full requeue.
      // Splicing the existing queue instead of requeuing is a possible
      // future improvement — see the "Future improvement" note below.
      final startIndex = seasonEpisodes.indexWhere((e) => e.id == episode.id);
      final idx = startIndex >= 0 ? startIndex : 0;
      await _manager.playItems(seasonEpisodes, startIndex: idx);
    }

    void _dismissEpisodeSwitcher() {
      _suppressBackNavigation(duration: const Duration(milliseconds: 500));
      setState(() {
        _showEpisodeSwitcher = false;
      });
    }
  ```

  Add the overlay presentation to the build method's `Stack`, right after the `NextUpOverlay` block (after line 3440, i.e. right before the closing `],` of the `Stack`'s `children` at line 3441):

  ```dart
                      if (_showEpisodeSwitcher)
                        EpisodeSwitcherOverlay(
                          seasons: _episodeSwitcherSeasons,
                          initialSeasonId: _episodeSwitcherSelectedSeasonId,
                          currentEpisodeId: _itemIdForQueueItem(_queue.currentItem),
                          episodesForSeason: _episodesForSwitcherSeason,
                          imageUrlForEpisode: _imageUrlForSwitcherEpisode,
                          onEpisodeSelected: (episode, seasonEpisodes) {
                            unawaited(
                              _handleEpisodeSwitcherSelection(episode, seasonEpisodes),
                            );
                          },
                          onDismiss: _dismissEpisodeSwitcher,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  ```

  (Only the new `if (_showEpisodeSwitcher) EpisodeSwitcherOverlay(...)` block is inserted before the existing closing `],`/`)` chain — the rest of that snippet above shows the existing unchanged closing structure for context so the insertion point is unambiguous.)

  Run: `flutter analyze lib/ui/screens/playback/video_player_screen.dart lib/ui/widgets/playback/episode_switcher_overlay.dart lib/ui/screens/playback/episode_switcher_eligibility.dart lib/data/services/episode_queue_service.dart`

  Expected output: `No issues found!`

- [ ] Step 7: Re-run the full episode-switcher test group to confirm nothing regressed

  Run: `flutter test test/data/services/episode_queue_service_test.dart test/data/viewmodels/item_detail_view_model_test.dart test/ui/widgets/playback/episode_switcher_overlay_test.dart test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected output: `00:0X +9: All tests passed!` (3 + 1 + 2 + 4 across the four files from Tasks 1-4).

- [ ] Step 8: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Wire episode switcher trigger button and overlay into VideoPlayerScreen"
  ```

---

### Task 5: Same-season jump-vs-requeue selection logic — dedicated unit coverage

**Files**:
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\episode_switcher_eligibility.dart` (extract the same-season-detection helper alongside eligibility, so it's testable without instantiating `VideoPlayerScreen`)
- Test: `E:\Moonfin-Core\test\ui\screens\playback\video_player_screen_episode_switcher_test.dart` (extend)

**Context used for accuracy**: `QueueService.items` is `List.unmodifiable(_items)` of `dynamic` (`packages/playback_core/lib/src/queue_service.dart:17`); `QueueService.jumpTo(int index)` only mutates `_currentIndex` and fires `queueChangedStream` if the index is in range (`queue_service.dart:107-112`); it does **not** call `PlaybackManager._playCurrentItem()` itself — actually playing the newly-current item requires a manager-level call. `PlaybackManager.startQueuedPlayback({Duration startPosition = Duration.zero, ...})` (`playback_manager.dart:912-926`) plays `queueService.currentItem` without mutating the queue — this is the correct call after `jumpTo` for a same-season jump. `PlaybackManager.playItems(List<dynamic> items, {int startIndex = 0, ...})` (`playback_manager.dart:843-910`) calls `queueService.setQueue(items, startIndex: startIndex)` internally — this is the correct call for a cross-season requeue, matching the spec's decision to use a full requeue via `playItems` rather than a queue-splice API.

This task adds a small pure helper, `isSameSeasonAsCurrentQueue`, extracted from the inline logic written directly in Task 4 Step 6's `_handleEpisodeSwitcherSelection`, so the season-comparison branch has direct unit coverage instead of only being reachable through full-screen wiring.

- [ ] Step 1: Write the failing test for the season-comparison helper

  Add to `E:\Moonfin-Core\test\ui\screens\playback\video_player_screen_episode_switcher_test.dart`, inside `main()` after the existing four tests:

  ```dart
    test('episode in the same season as current queue item is a same-season match', () {
      final current = _episode(seriesId: 'series-1')
        ..rawData['SeasonId'] = 'season-1';
      final target = _episode(seriesId: 'series-1')
        ..rawData['SeasonId'] = 'season-1';

      expect(isSameSeasonAsCurrentQueue(target, current), isTrue);
    });

    test('episode in a different season is not a same-season match', () {
      final current = _episode(seriesId: 'series-1')
        ..rawData['SeasonId'] = 'season-1';
      final target = _episode(seriesId: 'series-1')
        ..rawData['SeasonId'] = 'season-2';

      expect(isSameSeasonAsCurrentQueue(target, current), isFalse);
    });

    test('non-AggregatedItem current queue item is never a same-season match', () {
      final target = _episode(seriesId: 'series-1')
        ..rawData['SeasonId'] = 'season-1';

      expect(isSameSeasonAsCurrentQueue(target, 'offline://path.mp4'), isFalse);
    });
  ```

  Add the matching import at the top of the test file:

  ```dart
  import 'package:moonfin/ui/screens/playback/episode_switcher_eligibility.dart';
  ```

  (already present from Task 4 Step 1 — no duplicate import needed, this confirms it stays as-is).

  Run: `flutter test test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected failure output: `The method 'isSameSeasonAsCurrentQueue' isn't defined for the type ...` / `Undefined name 'isSameSeasonAsCurrentQueue'` (compile error).

- [ ] Step 2: Implement `isSameSeasonAsCurrentQueue`

  Edit `E:\Moonfin-Core\lib\ui\screens\playback\episode_switcher_eligibility.dart`, adding this function after `canShowEpisodeSwitcher`:

  ```dart
  /// Whether [target] belongs to the same season as the live queue's
  /// [currentQueueItem]. Used to decide between a cheap [jumpTo] within the
  /// existing queue versus a full requeue via `playItems` when the user picks
  /// an episode from the switcher overlay.
  bool isSameSeasonAsCurrentQueue(AggregatedItem target, dynamic currentQueueItem) {
    if (currentQueueItem is! AggregatedItem) return false;
    final targetSeasonId = target.seasonId;
    final currentSeasonId = currentQueueItem.seasonId;
    if (targetSeasonId == null || currentSeasonId == null) return false;
    return targetSeasonId == currentSeasonId;
  }
  ```

  Run: `flutter test test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected output: `00:0X +7: All tests passed!` (4 from Task 4 Step 1 + 3 new).

- [ ] Step 3: Replace the inline season-comparison in `_handleEpisodeSwitcherSelection` with the extracted helper

  Edit `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`. Replace:

  ```dart
      final currentItem = _queue.currentItem;
      final currentEpisodeSeasonId =
          currentItem is AggregatedItem ? currentItem.seasonId : null;

      if (episode.seasonId != null &&
          episode.seasonId == currentEpisodeSeasonId) {
  ```

  with:

  ```dart
      if (isSameSeasonAsCurrentQueue(episode, _queue.currentItem)) {
  ```

  Run: `flutter analyze lib/ui/screens/playback/video_player_screen.dart`

  Expected output: `No issues found!`

  Run: `flutter test test/data/services/episode_queue_service_test.dart test/data/viewmodels/item_detail_view_model_test.dart test/ui/widgets/playback/episode_switcher_overlay_test.dart test/ui/screens/playback/video_player_screen_episode_switcher_test.dart`

  Expected output: `00:0X +12: All tests passed!` (3 + 1 + 2 + 7 across the four files from Tasks 1-5, minus one duplicate-counted overlap already accounted for — final count 12).

- [ ] Step 4: Commit

  ```
  git add lib/ui/screens/playback/episode_switcher_eligibility.dart lib/ui/screens/playback/video_player_screen.dart test/ui/screens/playback/video_player_screen_episode_switcher_test.dart
  git commit -m "Extract same-season detection into a tested pure helper"
  ```

---

### Future improvement (explicitly out of scope for this plan)

**Queue splice / continuity-preserving season switch**: this plan's cross-season selection path always calls `PlaybackManager.playItems(seasonEpisodes, startIndex: idx)`, which internally calls `QueueService.setQueue(...)` (`packages/playback_core/lib/src/queue_service.dart:45-55`) and therefore fully replaces `_items`/`_originalOrder` and resets `_currentIndex` — any prior season's queue history is lost, so backing out of the newly selected season does not return the user to where they were in the previous season's queue. A future improvement would add a `QueueService` splice/`replaceFrom` API (e.g. `spliceFrom(int index, List<dynamic> newItems)`) that preserves the already-played history before the splice point and lets `PlaybackManager` swap in the new season's remainder without a full `setQueue`/backend-stop-and-restart cycle. This was evaluated and deliberately deferred because it is materially higher risk (touches shared queue invariants used by `next()`/`previous()`/shuffle/repeat) for a first version, per the spec's stated design decision.

---

### Verification

This plan implements Design Spec §8, "In-player episode & season switcher": *"Let a user jump to any episode or season while still in the player, not just advance sequentially to the next one."*

- **Automated**: run the full new test group together and confirm all pass:
  ```
  flutter test test/data/services/episode_queue_service_test.dart test/data/viewmodels/item_detail_view_model_test.dart test/ui/widgets/playback/episode_switcher_overlay_test.dart test/ui/screens/playback/video_player_screen_episode_switcher_test.dart
  ```
  Expected: `00:0X +12: All tests passed!`, and `flutter analyze` reports `No issues found!` for all four modified/created non-test files (`episode_queue_service.dart`, `item_detail_view_model.dart`, `episode_switcher_overlay.dart`, `episode_switcher_eligibility.dart`, `video_player_screen.dart`).

- **Manual, on a running debug build** (this repo has no automated widget-mount coverage for `VideoPlayerScreen` itself, consistent with existing convention — see Task 4's Files note):
  1. Start playback of any Episode of a multi-season Series with at least 2 seasons on the library.
  2. Open the player's secondary controls row; confirm a new "Episodes & Seasons" icon button (`Icons.video_library_outlined`) appears next to the chapters button, and does **not** appear when playing a Movie.
  3. Tap it; confirm the `EpisodeSwitcherOverlay` opens showing a season-tab row (current season pre-selected) and a grid of episodes for that season, with the currently-playing episode visually outlined.
  4. Tap a different episode in the **same** season: confirm playback jumps immediately (via `QueueService.jumpTo` + `PlaybackManager.startQueuedPlayback`) without a visible "stopping/resolving/opening" bringup sequence flash, and the overlay closes.
  5. Tap the season tab for a **different** season: confirm its episode grid loads (via `EpisodeQueueService.loadEpisodes`), then tap an episode in it: confirm this triggers a full requeue (`PlaybackManager.playItems` with the new season's episode list and the tapped start index) — a normal bringup sequence is visible, and after it completes, the queue's next-up/next() calls advance within the new season correctly.
  6. Back out of the newly selected season's playback (stop or exit) and confirm — per the documented Future Improvement — that the previous season's queue position is **not** preserved (expected/accepted behavior for this version, not a bug).
  7. Confirm the overlay dismisses via its close button and via tapping the scrim outside the panel, without pausing/stopping playback.
  8. Repeat steps 2-5 on an Android TV or Apple TV build/emulator with a D-pad/remote to confirm the button and overlay are reachable and dismissible without a touchscreen (the button reuses `_controlButton`'s existing `PlatformDetection.isTV` branch, which already provides `_TvFocusButton` handling — the overlay's tab chips and grid tiles rely on default Flutter focus traversal since this plan does not add dedicated TV `FocusNode`s for them; confirm this is acceptable or flag as a follow-up if D-pad traversal into the grid feels wrong).

No server plugin (`E:\Moonfin_Plugin`) changes are required for this feature — it only calls the existing Jellyfin `/Shows/{seriesId}/Seasons` and `/Shows/{seriesId}/Episodes` endpoints already wrapped by `server_jellyfin`'s `getSeasons`/`getEpisodes`, so there is no server-side verification step and, per repository convention, no automated test harness exists for `E:\Moonfin_Plugin` regardless.