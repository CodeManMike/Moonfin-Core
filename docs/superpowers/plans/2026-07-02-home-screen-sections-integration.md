Now I have all necessary context. Let me write the complete plan.

# Home Screen Sections Real API Integration Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

Goal: Wire Moonfin's dynamic home-row pipeline to the real Home Screen Sections (HSS) Jellyfin plugin endpoints so admin-configured HSS rows (Because You Watched, Watch Again, Genre, Latest Movies/Shows, etc.) actually render content instead of staying empty, while explicitly excluding HSS's Discover section type.

Architecture: A new `HomeSectionPluginSource.homeScreenSections` value identifies HSS-backed dynamic rows in `HomeSectionConfig`. A new `JellyfinItemsApi` method pair calls the HSS plugin's REST routes (`GET /HomeScreen/Sections`, `GET /HomeScreen/Section/{sectionType}`) directly against the existing authenticated `Dio` client — no Moonbase/server-plugin proxy is involved, since HSS is a separate community Jellyfin plugin exposing routes on the Jellyfin server itself. `RowDataSource.loadDynamicSection` gets a new switch case that calls the discovery method (excluding `Discover`), fetches the section's items, and reuses the existing `_parseItems`/`AggregatedItem` pipeline unchanged, with graceful empty-row fallback when HSS is not installed (404).

Tech Stack: Dart 3 / Flutter, `dio` for HTTP, `mocktail` for mocking in tests, `flutter_test` for the Flutter-side app tests, plain `test` package for the pure-Dart `server_jellyfin` package (which currently has no test harness at all).

---

### Task 1: Add `HomeSectionPluginSource.homeScreenSections` enum value

Files:
- Modify: `E:\Moonfin-Core\lib\preference\home_section_config.dart` (lines 27-45)
- Test: `E:\Moonfin-Core\test\preference\home_section_config_test.dart` (new)

- [ ] Step 1: Write the failing test for the new enum value's serialization round-trip.

Create `E:\Moonfin-Core\test\preference\home_section_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/home_section_config.dart';

void main() {
  group('HomeSectionPluginSource.homeScreenSections', () {
    test('serializes to "homeScreenSections" and back', () {
      const source = HomeSectionPluginSource.homeScreenSections;
      expect(source.serializedName, 'homeScreenSections');
      expect(
        HomeSectionPluginSource.fromSerialized('homeScreenSections'),
        HomeSectionPluginSource.homeScreenSections,
      );
    });

    test('HomeSectionConfig.pluginDynamic round-trips through JSON with homeScreenSections source', () {
      final config = HomeSectionConfig.pluginDynamic(
        serverId: 'server-1',
        pluginSection: 'BecauseYouWatched',
        pluginAdditionalData: '',
        pluginDisplayText: 'Because You Watched',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      final json = config.toJson();
      expect(json['pluginSource'], 'homeScreenSections');

      final decoded = HomeSectionConfig.fromJson(json);
      expect(decoded.pluginSource, HomeSectionPluginSource.homeScreenSections);
      expect(decoded.pluginSection, 'BecauseYouWatched');
      expect(decoded.isPluginDynamic, isTrue);
    });
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Run:
```
flutter test test/preference/home_section_config_test.dart
```
Expected failure output (compile error, since the enum value doesn't exist yet):
```
Error: Member not found: 'HomeSectionPluginSource.homeScreenSections'.
```

- [ ] Step 3: Add the enum value. In `E:\Moonfin-Core\lib\preference\home_section_config.dart`, replace the `HomeSectionPluginSource` enum body:

```dart
enum HomeSectionPluginSource {
  collections('collections'),

  genres('genres'),

  playlists('playlists'),

  custom('custom'),

  homeScreenSections('homeScreenSections');

  const HomeSectionPluginSource(this.serializedName);
  final String serializedName;

  static HomeSectionPluginSource fromSerialized(String? value) {
    for (final v in HomeSectionPluginSource.values) {
      if (v.serializedName == value) return v;
    }
    return HomeSectionPluginSource.collections;
  }
}
```

- [ ] Step 4: Run the test expecting pass.

Run:
```
flutter test test/preference/home_section_config_test.dart
```
Expected output: `All tests passed!`

- [ ] Step 5: Commit.

```
git add lib/preference/home_section_config.dart test/preference/home_section_config_test.dart
git commit -m "Add homeScreenSections HomeSectionPluginSource value"
```

---

### Task 2: Add `test`/`mocktail` dev dependencies and a test harness to `server_jellyfin`

The `server_jellyfin` package currently has zero dev_dependencies and no `test/` directory. This is a prerequisite before Task 3 can add a unit test for the new API client method.

Files:
- Modify: `E:\Moonfin-Core\packages\server_jellyfin\pubspec.yaml`
- Create: `E:\Moonfin-Core\packages\server_jellyfin\test\api\jellyfin_items_api_hss_test.dart`

- [ ] Step 1: Add dev_dependencies to the package pubspec. Current file content is:

```yaml
name: server_jellyfin
description: Jellyfin server API implementation.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.11.0

dependencies:
  server_core:
    path: ../server_core
  dio: ^5.9.2
  logger: ^2.6.2
```

Replace with:

```yaml
name: server_jellyfin
description: Jellyfin server API implementation.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.11.0

dependencies:
  server_core:
    path: ../server_core
  dio: ^5.9.2
  logger: ^2.6.2

dev_dependencies:
  test: ^1.25.0
  mocktail: ^1.0.5
```

- [ ] Step 2: Fetch packages for the sub-package so the new dev deps resolve.

Run:
```
cd packages/server_jellyfin && dart pub get
```
Expected output ends with:
```
Got dependencies!
```

- [ ] Step 3: Write a placeholder-free smoke test that will pass immediately, proving the harness works, before Task 3 adds real coverage.

Create `E:\Moonfin-Core\packages\server_jellyfin\test\api\jellyfin_items_api_hss_test.dart`:

```dart
import 'package:test/test.dart';

void main() {
  test('server_jellyfin test harness is wired up', () {
    expect(1 + 1, 2);
  });
}
```

- [ ] Step 4: Run the smoke test expecting pass (this is the harness-verification step, not a red/green TDD step, since there is no prior behavior to fail against).

Run:
```
cd packages/server_jellyfin && dart test test/api/jellyfin_items_api_hss_test.dart
```
Expected output:
```
+1: All tests passed!
```

- [ ] Step 5: Commit.

```
git add packages/server_jellyfin/pubspec.yaml packages/server_jellyfin/test/api/jellyfin_items_api_hss_test.dart
git commit -m "Add test harness (test + mocktail) to server_jellyfin package"
```

---

### Task 3: Add `getHomeScreenSections` and `getHomeScreenSectionItems` to `ItemsApi` / `JellyfinItemsApi`

Files:
- Modify: `E:\Moonfin-Core\packages\server_core\lib\src\api\items_api.dart` (append to abstract class, after line 161 `getLyrics`)
- Modify: `E:\Moonfin-Core\packages\server_jellyfin\lib\src\api\jellyfin_items_api.dart` (append methods, after `getLyrics` at line 531-534)
- Modify: `E:\Moonfin-Core\packages\server_jellyfin\test\api\jellyfin_items_api_hss_test.dart` (replace smoke test with real coverage)

- [ ] Step 1: Write the failing test for `getHomeScreenSections` (discovery endpoint), using `mocktail` to mock `Dio`. Replace the full content of `E:\Moonfin-Core\packages\server_jellyfin\test\api\jellyfin_items_api_hss_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_jellyfin/src/api/jellyfin_items_api.dart';
import 'package:test/test.dart';

class MockDio extends Mock implements Dio {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  setUpAll(() {
    registerFallbackType(FakeRequestOptions());
  });

  group('JellyfinItemsApi.getHomeScreenSections', () {
    late MockDio dio;
    late JellyfinItemsApi api;

    setUp(() {
      dio = MockDio();
      api = JellyfinItemsApi(dio, () => 'user-1');
    });

    test('GETs /HomeScreen/Sections with userId and returns the decoded list', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Sections');
      when(() => dio.get(
            '/HomeScreen/Sections',
            queryParameters: {'userId': 'user-1'},
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: [
              {
                'route': 'BecauseYouWatched',
                'displayText': 'Because You Watched',
                'additionalData': '',
              },
              {
                'route': 'Discover',
                'displayText': 'Discover',
                'additionalData': '',
              },
            ],
          ));

      final result = await api.getHomeScreenSections();

      expect(result, hasLength(2));
      expect(result[0]['route'], 'BecauseYouWatched');
      expect(result[1]['route'], 'Discover');
    });
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Run:
```
cd packages/server_jellyfin && dart test test/api/jellyfin_items_api_hss_test.dart
```
Expected failure output:
```
Error: The method 'getHomeScreenSections' isn't defined for the type 'JellyfinItemsApi'.
```

- [ ] Step 3: Add `getHomeScreenSections` to the `ItemsApi` abstract interface. In `E:\Moonfin-Core\packages\server_core\lib\src\api\items_api.dart`, find:

```dart
  Future<Map<String, dynamic>> getLyrics(String itemId);

  Future<List<Map<String, dynamic>>> getLocalTrailers(String itemId);
```

Replace with:

```dart
  Future<Map<String, dynamic>> getLyrics(String itemId);

  /// Discovers available Home Screen Sections plugin rows for the current
  /// user. Returns the raw list of section descriptors (each with `route`,
  /// `displayText`, `additionalData`) as reported by the HSS plugin. Throws
  /// a [DioException] with a 404 status if the HSS plugin is not installed
  /// on the server; callers are expected to catch that and degrade
  /// gracefully to "no dynamic HSS sections available".
  Future<List<Map<String, dynamic>>> getHomeScreenSections();

  /// Fetches the items for a single Home Screen Sections plugin row
  /// identified by [sectionType] (the `route` value from
  /// [getHomeScreenSections]). Returns a standard Jellyfin
  /// `QueryResult<BaseItemDto>` shape (`Items`/`TotalRecordCount`), the same
  /// shape returned by `getItems`.
  Future<Map<String, dynamic>> getHomeScreenSectionItems(
    String sectionType, {
    String? additionalData,
  });

  Future<List<Map<String, dynamic>>> getLocalTrailers(String itemId);
```

- [ ] Step 4: Add the `JellyfinItemsApi` implementation. In `E:\Moonfin-Core\packages\server_jellyfin\lib\src\api\jellyfin_items_api.dart`, find:

```dart
  @override
  Future<Map<String, dynamic>> getLyrics(String itemId) async {
    final response = await _dio.get('/Audio/$itemId/Lyrics');
    return response.data as Map<String, dynamic>;
  }
```

Replace with:

```dart
  @override
  Future<Map<String, dynamic>> getLyrics(String itemId) async {
    final response = await _dio.get('/Audio/$itemId/Lyrics');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> getHomeScreenSections() async {
    final userId = _getUserId();
    final response = await _dio.get(
      '/HomeScreen/Sections',
      queryParameters: {'userId': userId},
    );
    final data = response.data;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> getHomeScreenSectionItems(
    String sectionType, {
    String? additionalData,
  }) async {
    final userId = _getUserId();
    final response = await _dio.get(
      '/HomeScreen/Section/$sectionType',
      queryParameters: {
        'userId': userId,
        'additionalData': ?additionalData,
      },
    );
    final data = response.data;
    if (data is List) return {'Items': data, 'TotalRecordCount': data.length};
    return data as Map<String, dynamic>;
  }
```

- [ ] Step 5: Run the test expecting pass.

Run:
```
cd packages/server_jellyfin && dart test test/api/jellyfin_items_api_hss_test.dart
```
Expected output:
```
+1: All tests passed!
```

- [ ] Step 6: Write the failing test for `getHomeScreenSectionItems`. Append to `E:\Moonfin-Core\packages\server_jellyfin\test\api\jellyfin_items_api_hss_test.dart`, inside a new `group` after the existing one (before the final closing `}` of `main`):

```dart
  group('JellyfinItemsApi.getHomeScreenSectionItems', () {
    late MockDio dio;
    late JellyfinItemsApi api;

    setUp(() {
      dio = MockDio();
      api = JellyfinItemsApi(dio, () => 'user-1');
    });

    test('GETs /HomeScreen/Section/{sectionType} with userId and additionalData', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Section/BecauseYouWatched');
      when(() => dio.get(
            '/HomeScreen/Section/BecauseYouWatched',
            queryParameters: {
              'userId': 'user-1',
              'additionalData': 'seriesId-123',
            },
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: {
              'Items': [
                {'Id': 'abc', 'Name': 'Some Movie', 'Type': 'Movie'},
              ],
              'TotalRecordCount': 1,
            },
          ));

      final result = await api.getHomeScreenSectionItems(
        'BecauseYouWatched',
        additionalData: 'seriesId-123',
      );

      expect(result['TotalRecordCount'], 1);
      expect((result['Items'] as List), hasLength(1));
      expect((result['Items'] as List).first['Name'], 'Some Movie');
    });

    test('wraps a bare List response into an Items/TotalRecordCount map', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Section/LatestMovies');
      when(() => dio.get(
            '/HomeScreen/Section/LatestMovies',
            queryParameters: {
              'userId': 'user-1',
              'additionalData': null,
            },
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: [
              {'Id': 'xyz', 'Name': 'Another Movie', 'Type': 'Movie'},
            ],
          ));

      final result = await api.getHomeScreenSectionItems('LatestMovies');

      expect(result['TotalRecordCount'], 1);
      expect((result['Items'] as List).first['Id'], 'xyz');
    });
  });
```

- [ ] Step 7: Run the test file expecting the new group to pass immediately (implementation was already added in Step 4, so this step is confirmatory, not red/green — run it to be certain the query-parameter contract, including the `null` `additionalData` case, matches exactly).

Run:
```
cd packages/server_jellyfin && dart test test/api/jellyfin_items_api_hss_test.dart
```
Expected output:
```
+3: All tests passed!
```
If it fails on the `null` `additionalData` expectation (mocktail matches the map value `null` literally), that confirms the `?additionalData` cascade in Step 4 produces a literal `null` entry rather than omitting the key — this is expected Dio query-parameter behavior for `?` null-collapsing in this codebase's existing methods (e.g. `getItem`'s `mediaSourceId`), so no implementation change is needed once confirmed.

- [ ] Step 8: Commit.

```
git add packages/server_core/lib/src/api/items_api.dart packages/server_jellyfin/lib/src/api/jellyfin_items_api.dart packages/server_jellyfin/test/api/jellyfin_items_api_hss_test.dart
git commit -m "Add HSS plugin API client methods to ItemsApi/JellyfinItemsApi"
```

---

### Task 4: Add `HomeSectionPluginSource.homeScreenSections` dispatch case in `RowDataSource.loadDynamicSection`

Files:
- Modify: `E:\Moonfin-Core\lib\data\services\row_data_source.dart` (the `loadDynamicSection` switch, lines 1454-1608)
- Test: `E:\Moonfin-Core\test\data\services\row_data_source_hss_test.dart` (new)

- [ ] Step 1: Inspect the exact current switch tail and imports needed for the test (already read above). The switch's last case today is `HomeSectionPluginSource.custom` (lines 1548-1607), and the enclosing method signature is:

```dart
  Future<HomeRow> loadDynamicSection({
    required String rowId,
    required String section,
    required String title,
    required String serverId,
    String? additionalData,
    HomeSectionPluginSource pluginSource = HomeSectionPluginSource.collections,
    bool forceRefresh = false,
  }) async {
    switch (pluginSource) {
```

`RowDataSource` is constructed as `RowDataSource(this._client)` where `_client` is a `MediaServerClient` exposing `_client.itemsApi` (an `ItemsApi`). Write the failing test using `mocktail` to mock `MediaServerClient` and `ItemsApi`.

Create `E:\Moonfin-Core\test\data\services\row_data_source_hss_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/preference/home_section_config.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  group('RowDataSource.loadDynamicSection with homeScreenSections source', () {
    late MockMediaServerClient client;
    late MockItemsApi itemsApi;
    late RowDataSource dataSource;

    setUp(() {
      client = MockMediaServerClient();
      itemsApi = MockItemsApi();
      when(() => client.itemsApi).thenReturn(itemsApi);
      dataSource = RowDataSource(client);
    });

    test('fetches HSS section items and parses them via the standard item pipeline', () async {
      when(() => itemsApi.getHomeScreenSectionItems(
            'BecauseYouWatched',
            additionalData: null,
          )).thenAnswer((_) async => {
            'Items': [
              {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
              {'Id': 'item-2', 'Name': 'Movie Two', 'Type': 'Movie'},
            ],
            'TotalRecordCount': 2,
          });

      final row = await dataSource.loadDynamicSection(
        rowId: 'pluginDynamic:homeScreenSections:server-1:BecauseYouWatched:',
        section: 'BecauseYouWatched',
        title: 'Because You Watched',
        serverId: 'server-1',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      expect(row.rowType, HomeRowType.pluginDynamic);
      expect(row.items, hasLength(2));
      expect(row.items[0].id, 'item-1');
      expect(row.items[0].serverId, 'server-1');
      expect(row.title, 'Because You Watched');
    });

    test('returns an empty row when HSS is not installed (404)', () async {
      final requestOptions = RequestOptionsStub('/HomeScreen/Section/LatestMovies');
      when(() => itemsApi.getHomeScreenSectionItems(
            'LatestMovies',
            additionalData: null,
          )).thenThrow(DioExceptionStub(requestOptions, 404));

      final row = await dataSource.loadDynamicSection(
        rowId: 'pluginDynamic:homeScreenSections:server-1:LatestMovies:',
        section: 'LatestMovies',
        title: 'Latest Movies',
        serverId: 'server-1',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      expect(row.items, isEmpty);
      expect(row.rowType, HomeRowType.pluginDynamic);
    });
  });
}
```

This test references `RequestOptionsStub` and `DioExceptionStub` helpers that don't exist yet — they wrap `dio`'s real `RequestOptions`/`DioException` so the test file doesn't need a direct `dio` import conflict with `server_core`'s re-exports. Add them at the bottom of the same test file:

```dart
import 'package:dio/dio.dart' as dio_pkg;

class RequestOptionsStub extends dio_pkg.RequestOptions {
  RequestOptionsStub(String path) : super(path: path);
}

class DioExceptionStub extends dio_pkg.DioException {
  DioExceptionStub(dio_pkg.RequestOptions requestOptions, int statusCode)
      : super(
          requestOptions: requestOptions,
          response: dio_pkg.Response(
            requestOptions: requestOptions,
            statusCode: statusCode,
          ),
          type: dio_pkg.DioExceptionType.badResponse,
        );
}
```

(Place the `import 'package:dio/dio.dart' as dio_pkg;` line with the other imports at the top of the file, and the two stub classes after `main()`.)

- [ ] Step 2: Run the test expecting failure.

Run:
```
flutter test test/data/services/row_data_source_hss_test.dart
```
Expected failure output:
```
Error: The method 'getHomeScreenSectionItems' isn't defined for the type 'MockItemsApi'.
```
(This resolves once Task 3 lands in the working tree; if Task 3 is already merged, the failure instead comes from `loadDynamicSection` falling through the switch, producing a compile error: `The switch statement doesn't exhaustively cover all possible values... case 'HomeSectionPluginSource.homeScreenSections' not covered`.)

- [ ] Step 3: Add the new switch case. In `E:\Moonfin-Core\lib\data\services\row_data_source.dart`, find the end of the `custom` case and the switch's closing brace:

```dart
      case HomeSectionPluginSource.custom:
        try {
          final customService = GetIt.instance<CustomExternalListsService>();
          final config = HomeSectionConfig.pluginDynamic(
            serverId: serverId,
            pluginSection: section,
            pluginAdditionalData: additionalData,
            pluginDisplayText: title,
            pluginSource: pluginSource,
          );
          List<ImdbExternalListItem> items;
          if (forceRefresh) {
            items = await customService.fetchCustomRow(config, forceRefresh: true);
          } else {
            items = await customService.loadCustomRowFromCache(config);
            if (items.isEmpty) {
              items = await customService.fetchCustomRow(config);
            }
          }
          Map<String, dynamic> rowConfig = {};
          try {
            rowConfig = jsonDecode(additionalData ?? '{}') as Map<String, dynamic>;
          } catch (_) {}
          final showUserRatings = rowConfig['show_user_ratings'] == true;

          final aggregatedItems = items.map((item) {
            return AggregatedItem(
              id: item.imdbId.isNotEmpty ? item.imdbId : item.tmdbId,
              serverId: 'seerr',
              rawData: {
                'Name': item.title,
                'Type': item.type,
                'Overview': '',
                'PosterPath': item.posterUrl ?? '',
                'BackdropPath': item.backdropUrl ?? item.posterUrl ?? '',
                'ProductionYear': item.year,
                'SeerrMediaType': item.type == 'Series' ? 'tv' : 'movie',
                'UserRating': item.userRating ?? '',
                'ShowUserRatings': showUserRatings,
                'ProviderIds': {
                  if (item.imdbId.isNotEmpty) 'Imdb': item.imdbId,
                  if (item.tmdbId.isNotEmpty) 'Tmdb': item.tmdbId,
                },
              },
            );
          }).toList();
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
            items: aggregatedItems,
          );
        } catch (e) {
          debugPrint('[RowDataSource] Failed to load custom dynamic section: $e');
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
          );
        }
    }
  }
```

Replace with:

```dart
      case HomeSectionPluginSource.custom:
        try {
          final customService = GetIt.instance<CustomExternalListsService>();
          final config = HomeSectionConfig.pluginDynamic(
            serverId: serverId,
            pluginSection: section,
            pluginAdditionalData: additionalData,
            pluginDisplayText: title,
            pluginSource: pluginSource,
          );
          List<ImdbExternalListItem> items;
          if (forceRefresh) {
            items = await customService.fetchCustomRow(config, forceRefresh: true);
          } else {
            items = await customService.loadCustomRowFromCache(config);
            if (items.isEmpty) {
              items = await customService.fetchCustomRow(config);
            }
          }
          Map<String, dynamic> rowConfig = {};
          try {
            rowConfig = jsonDecode(additionalData ?? '{}') as Map<String, dynamic>;
          } catch (_) {}
          final showUserRatings = rowConfig['show_user_ratings'] == true;

          final aggregatedItems = items.map((item) {
            return AggregatedItem(
              id: item.imdbId.isNotEmpty ? item.imdbId : item.tmdbId,
              serverId: 'seerr',
              rawData: {
                'Name': item.title,
                'Type': item.type,
                'Overview': '',
                'PosterPath': item.posterUrl ?? '',
                'BackdropPath': item.backdropUrl ?? item.posterUrl ?? '',
                'ProductionYear': item.year,
                'SeerrMediaType': item.type == 'Series' ? 'tv' : 'movie',
                'UserRating': item.userRating ?? '',
                'ShowUserRatings': showUserRatings,
                'ProviderIds': {
                  if (item.imdbId.isNotEmpty) 'Imdb': item.imdbId,
                  if (item.tmdbId.isNotEmpty) 'Tmdb': item.tmdbId,
                },
              },
            );
          }).toList();
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
            items: aggregatedItems,
          );
        } catch (e) {
          debugPrint('[RowDataSource] Failed to load custom dynamic section: $e');
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
          );
        }

      case HomeSectionPluginSource.homeScreenSections:
        try {
          final response = await _client.itemsApi.getHomeScreenSectionItems(
            section,
            additionalData: additionalData,
          );
          final items = _parseItems(response, serverId);
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
            items: items,
          );
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode ?? 0;
          if (statusCode == 404) {
            // HSS plugin not installed on this server. Degrade gracefully.
            return HomeRow(
              id: rowId,
              title: title,
              rowType: HomeRowType.pluginDynamic,
            );
          }
          debugPrint('[RowDataSource] Failed to load HSS section "$section": $e');
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
          );
        } catch (e) {
          debugPrint('[RowDataSource] Failed to load HSS section "$section": $e');
          return HomeRow(
            id: rowId,
            title: title,
            rowType: HomeRowType.pluginDynamic,
          );
        }
    }
  }
```

- [ ] Step 4: Run the test expecting pass.

Run:
```
flutter test test/data/services/row_data_source_hss_test.dart
```
Expected output:
```
All tests passed!
```

- [ ] Step 5: Commit.

```
git add lib/data/services/row_data_source.dart test/data/services/row_data_source_hss_test.dart
git commit -m "Dispatch homeScreenSections dynamic rows through HSS API in loadDynamicSection"
```

---

### Task 5: Add HSS discovery helper that excludes the Discover section type

The design spec requires that `GET /HomeScreen/Sections` discovery results explicitly exclude the `Discover` route before any candidate section is offered to callers (the admin config UI and any future in-app picker). This task adds that filtering as a pure function next to `RowDataSource` so both current and future callers share one exclusion rule instead of re-implementing the check.

Files:
- Modify: `E:\Moonfin-Core\lib\data\services\row_data_source.dart` (add a static method near the top of the class, after the `RowDataSource(this._client);` constructor at line 75)
- Test: `E:\Moonfin-Core\test\data\services\row_data_source_hss_test.dart` (extend with a new group)

- [ ] Step 1: Write the failing test. Append a new `group` to `E:\Moonfin-Core\test\data\services\row_data_source_hss_test.dart`, inside `main()` after the existing `group('RowDataSource.loadDynamicSection with homeScreenSections source', ...)` block:

```dart
  group('RowDataSource.filterDiscoverableHomeScreenSections', () {
    test('excludes the Discover route and keeps library-backed routes', () {
      final raw = [
        {'route': 'BecauseYouWatched', 'displayText': 'Because You Watched', 'additionalData': ''},
        {'route': 'Discover', 'displayText': 'Discover', 'additionalData': ''},
        {'route': 'WatchAgain', 'displayText': 'Watch Again', 'additionalData': ''},
      ];

      final filtered = RowDataSource.filterDiscoverableHomeScreenSections(raw);

      expect(filtered, hasLength(2));
      expect(filtered.map((e) => e['route']), containsAll(['BecauseYouWatched', 'WatchAgain']));
      expect(filtered.any((e) => e['route'] == 'Discover'), isFalse);
    });

    test('is case-insensitive on the route value', () {
      final raw = [
        {'route': 'discover', 'displayText': 'discover lowercase', 'additionalData': ''},
      ];

      final filtered = RowDataSource.filterDiscoverableHomeScreenSections(raw);

      expect(filtered, isEmpty);
    });
  });
```

- [ ] Step 2: Run the test expecting failure.

Run:
```
flutter test test/data/services/row_data_source_hss_test.dart
```
Expected failure output:
```
Error: The method 'filterDiscoverableHomeScreenSections' isn't defined for the type 'RowDataSource'.
```

- [ ] Step 3: Add the static helper. In `E:\Moonfin-Core\lib\data\services\row_data_source.dart`, find:

```dart
  RowDataSource(this._client);

  ImageApi get imageApi => _client.imageApi;
```

Replace with:

```dart
  RowDataSource(this._client);

  /// HSS's "Discover" section type proxies a Jellyseerr-style discovery
  /// request and can return non-standard items outside the normal
  /// `BaseItemDto` shape `_parseItems` expects. Moonfin already has native
  /// Seerr discover screens covering that use case, so it is excluded here;
  /// only library-backed HSS section types (Because You Watched, Watch
  /// Again, Genre, Latest Movies/Shows, etc.) are surfaced.
  static const _excludedHomeScreenSectionRoutes = {'discover'};

  static List<Map<String, dynamic>> filterDiscoverableHomeScreenSections(
    List<Map<String, dynamic>> sections,
  ) {
    return sections.where((section) {
      final route = section['route']?.toString().toLowerCase() ?? '';
      return !_excludedHomeScreenSectionRoutes.contains(route);
    }).toList(growable: false);
  }

  ImageApi get imageApi => _client.imageApi;
```

- [ ] Step 4: Run the test expecting pass.

Run:
```
flutter test test/data/services/row_data_source_hss_test.dart
```
Expected output:
```
All tests passed!
```

- [ ] Step 5: Commit.

```
git add lib/data/services/row_data_source.dart test/data/services/row_data_source_hss_test.dart
git commit -m "Add Discover-route exclusion filter for HSS section discovery"
```

---

### Task 6: Manual integration verification against a real Jellyfin server with the HSS plugin

There is no automated test harness for the server plugin repository (`E:\Moonfin_Plugin`) today — it has no test project at all, and this task does not add one, per the constraint that no test infrastructure should be fabricated for that repo. This task instead verifies the new Dart-side HSS client against a real Jellyfin server, since the HSS plugin itself lives in the Jellyfin server's plugin directory (not in `E:\Moonfin_Plugin`, which is the separate Moonbase server plugin) and is out of scope to modify.

Files:
- None (manual verification only; no code changes in this task)

- [ ] Step 1: Confirm the HSS plugin is installed and reachable on a test Jellyfin server. Replace `<JELLYFIN_BASE_URL>`, `<API_KEY>`, and `<USER_ID>` with real values from the test server (an API key can be generated under Jellyfin Dashboard → API Keys; the user ID is visible in Dashboard → Users).

Run:
```
curl -s -H "X-Emby-Token: <API_KEY>" "<JELLYFIN_BASE_URL>/HomeScreen/Sections?userId=<USER_ID>"
```
Expected: HTTP 200 with a JSON array of section descriptor objects, each shaped like:
```json
[
  {
    "route": "BecauseYouWatched",
    "displayText": "Because You Watched",
    "additionalData": ""
  },
  {
    "route": "Discover",
    "displayText": "Discover",
    "additionalData": ""
  }
]
```

- [ ] Step 2: Verify a single library-backed section returns a standard `QueryResult<BaseItemDto>` shape (the same shape `_parseItems` already handles).

Run:
```
curl -s -H "X-Emby-Token: <API_KEY>" "<JELLYFIN_BASE_URL>/HomeScreen/Section/BecauseYouWatched?userId=<USER_ID>&additionalData="
```
Expected: HTTP 200 with a JSON object shaped like:
```json
{
  "Items": [
    {"Id": "...", "Name": "...", "Type": "Movie", "UserData": {...}, "ImageTags": {...}}
  ],
  "TotalRecordCount": 1
}
```

- [ ] Step 3: Verify the Discover route is excluded client-side (not server-side — HSS itself still returns it from `/HomeScreen/Sections`). Confirm by inspecting the JSON from Step 1 that `"route": "Discover"` is present in the raw server response, proving `filterDiscoverableHomeScreenSections` (Task 5) is doing real client-side filtering rather than relying on the server to omit it.

- [ ] Step 4: Verify graceful degradation when HSS is not installed. Point the same `curl` command at a Jellyfin server that does not have the HSS plugin installed.

Run:
```
curl -s -o /dev/null -w "%{http_code}" -H "X-Emby-Token: <API_KEY>" "<JELLYFIN_BASE_URL_WITHOUT_HSS>/HomeScreen/Sections?userId=<USER_ID>"
```
Expected output:
```
404
```
This confirms the `on DioException catch (e)` / `statusCode == 404` branch added in Task 4 Step 3 is reachable with a real server response, not just a mocked one.

- [ ] Step 5: Run the full app against the HSS-enabled test server, add a `homeScreenSections`-sourced row via the admin "Default Home Layout" builder in `configPage.html` (existing `dynamic` badge styling already supports this; wiring the picker UI itself is out of scope for this plan), and confirm on-device that the row renders real poster art and titles rather than staying empty. There is no automated harness for this step; it is a manual smoke test performed once per release candidate.

---

### Verification

This plan implements spec section 2 ("Home Screen Sections (HSS) real API integration") of `E:\Moonfin-Core\docs\superpowers\specs\2026-07-02-moonfin-experience-overhaul-design.md`. Each requirement maps to a task:

- "Add a new `HomeSectionPluginSource` value" → Task 1 (`homeScreenSections` added to `home_section_config.dart`, covered by `test/preference/home_section_config_test.dart`).
- "New API client method(s) in `packages/server_jellyfin` calling the two HSS endpoints... callable directly with the existing auth token, no Moonbase proxy needed" → Task 3 (`getHomeScreenSections`/`getHomeScreenSectionItems` added to `ItemsApi`/`JellyfinItemsApi`, calling `_dio.get(...)` directly against the already-configured `baseUrl` and `Authorization` interceptor, no new client or proxy involved), covered by `packages/server_jellyfin/test/api/jellyfin_items_api_hss_test.dart`.
- "New case in `RowDataSource.loadDynamicSection` dispatching to it, parsing the response with the existing `_parseItems` path" → Task 4 (`case HomeSectionPluginSource.homeScreenSections` calls `_parseItems(response, serverId)`, the identical helper every other case in the switch already uses), covered by `test/data/services/row_data_source_hss_test.dart`.
- "Scope exclusion: exclude Discover... only wire the library-backed section types" → Task 5 (`RowDataSource.filterDiscoverableHomeScreenSections` strips any `route` equal to `discover`, case-insensitively), covered by the `filterDiscoverableHomeScreenSections` test group, and reconfirmed against a live server's raw (unfiltered) response in Task 6 Step 3.
- "If HSS isn't installed on a given server, `GET /HomeScreen/Sections` 404s — treat as 'no dynamic HSS sections available' and degrade gracefully" → Task 4's `on DioException catch (e)` branch returns an empty `HomeRow` on `statusCode == 404` instead of throwing, covered by the "returns an empty row when HSS is not installed (404)" test, and reconfirmed manually in Task 6 Step 4 against a real non-HSS server.