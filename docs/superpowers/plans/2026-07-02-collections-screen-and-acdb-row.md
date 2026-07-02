# Collections (TMDB Box Sets + ACdb Row + Missing Items) Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

**Goal**: Replace the collections stub with a real collection contents screen, add a tag-filtered ACdb home row, and let users see and request (via Seerr) items missing from a collection compared to its canonical TMDB collection.

**Architecture**: The client screen reuses the existing `itemsApi.getItems(parentId:)` call already proven in `add_to_collection_dialog.dart`, and the breadcrumb/infinite-scroll UI patterns already built in `folder_browse_screen.dart`, wired through a new `CollectionViewModel`. The ACdb row is a new `RowDataSource` method mirroring the existing `loadCollections`, filtered by `tags`. Missing-items support adds one new narrow Moonbase proxy endpoint (`GET /Moonfin/Tmdb/Collection/{tmdbCollectionId}`) following the exact pattern of the two existing `TmdbController` endpoints, a matching `TmdbRepository.getCollection()` client method, and a diff/request widget that reuses the existing `SeerrRepository.createRequest(mediaId, mediaType: 'movie')` call.

**Tech Stack**: Flutter/Dart (Moonfin-Core client, `flutter_test` + `mocktail`), ASP.NET Core C# controller (Moonfin_Plugin server, no test project — manual `curl` verification only).

---

### Task 1: Real collection contents screen

**Files**:
- Create: `E:\Moonfin-Core\lib\data\viewmodels\collection_view_model.dart`
- Create: `E:\Moonfin-Core\test\data\viewmodels\collection_view_model_test.dart`
- Modify: `E:\Moonfin-Core\lib\ui\screens\browse\collection_screen.dart` (full rewrite, currently 25 lines)

**Step 1: Write the failing test for initial load**

- [ ] Create the test directory and file `E:\Moonfin-Core\test\data\viewmodels\collection_view_model_test.dart` with a fake `MediaServerClient`/`ItemsApi` built with `mocktail`, matching the `ItemsApi.getItems` signature read from `E:\Moonfin-Core\packages\server_core\lib\src\api\items_api.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/viewmodels/collection_view_model.dart';

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

  test('loadCollection fetches items with parentId and sets ready state', () async {
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 0,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        });

    final vm = CollectionViewModel(client);
    await vm.loadCollection('col-1');

    expect(vm.state, CollectionState.ready);
    expect(vm.items.length, 1);
    expect(vm.items.first.id, 'item-1');
    expect(vm.hasMore, false);
  });
}
```

- [ ] Run: `flutter test test/data/viewmodels/collection_view_model_test.dart`
- [ ] Expect failure: `Error: Error when reading 'lib/data/viewmodels/collection_view_model.dart': No such file or directory` (or a compile error naming `CollectionViewModel`/`CollectionState` as undefined).
- [ ] Commit: `git add test/data/viewmodels/collection_view_model_test.dart && git commit -m "Add failing test for CollectionViewModel initial load"`

**Step 2: Minimal `CollectionViewModel` to pass the initial-load test**

- [ ] Create `E:\Moonfin-Core\lib\data\viewmodels\collection_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';

enum CollectionState { loading, ready, error }

class CollectionViewModel extends ChangeNotifier {
  final MediaServerClient _client;

  static const _pageSize = 100;
  static const _fields =
      'Type,ProductionYear,ImageTags,BackdropImageTags,ChildCount,ProviderIds,CommunityRating,Overview';
  static const _imageTypes = 'Primary,Backdrop,Thumb';
  static const _imageTypeLimit = 1;

  CollectionViewModel(this._client);

  ImageApi get imageApi => _client.imageApi;

  CollectionState _state = CollectionState.loading;
  CollectionState get state => _state;

  List<AggregatedItem> _items = const [];
  List<AggregatedItem> get items => _items;

  int _totalCount = 0;
  bool get hasMore => _items.length < _totalCount;

  bool _loadingMore = false;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  String _collectionId = '';
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadCollection(String collectionId) async {
    _collectionId = collectionId;
    _state = CollectionState.loading;
    _items = const [];
    _totalCount = 0;
    _notify();

    try {
      await _fetchPage(0);
      if (_disposed) return;
      _state = CollectionState.ready;
    } catch (e) {
      if (_disposed) return;
      _errorMessage = e.toString();
      _state = CollectionState.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    _notify();
    try {
      await _fetchPage(_items.length);
    } catch (_) {}
    if (_disposed) return;
    _loadingMore = false;
    _notify();
  }

  Future<void> _fetchPage(int startIndex) async {
    final response = await _fetchItemsWithFallback(startIndex: startIndex);
    final rawItems = (response['Items'] as List?) ?? [];
    _totalCount = response['TotalRecordCount'] as int? ?? rawItems.length;

    final mapped = rawItems.cast<Map<String, dynamic>>().map((raw) {
      return AggregatedItem(
        id: raw['Id']?.toString() ?? '',
        serverId: _client.baseUrl,
        rawData: raw,
      );
    }).toList();

    _items = startIndex == 0 ? mapped : [..._items, ...mapped];
  }

  Future<Map<String, dynamic>> _fetchItemsWithFallback({
    required int startIndex,
  }) async {
    try {
      return await _client.itemsApi.getItems(
        parentId: _collectionId,
        recursive: false,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        startIndex: startIndex,
        limit: _pageSize,
        fields: _fields,
        enableImageTypes: _imageTypes,
        imageTypeLimit: _imageTypeLimit,
        enableTotalRecordCount: true,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      if (statusCode < 500) rethrow;
      return _client.itemsApi.getItems(
        parentId: _collectionId,
        recursive: false,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        startIndex: startIndex,
        limit: _pageSize,
        fields: _fields,
        enableImageTypes: _imageTypes,
        imageTypeLimit: _imageTypeLimit,
        enableTotalRecordCount: false,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
```

- [ ] Run: `flutter test test/data/viewmodels/collection_view_model_test.dart`
- [ ] Expect pass: `00:0X +1: All tests passed!`
- [ ] Commit: `git add lib/data/viewmodels/collection_view_model.dart && git commit -m "Add CollectionViewModel fetching collection contents via itemsApi"`

**Step 3: Write failing test for pagination (`loadMore`)**

- [ ] Add a second test to `E:\Moonfin-Core\test\data\viewmodels\collection_view_model_test.dart` (inside the same `main()`, after the first `test(...)` block):

```dart
  test('loadMore appends items and stops when totalCount reached', () async {
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 0,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 2,
        });
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 1,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-2', 'Name': 'Movie Two', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 2,
        });

    final vm = CollectionViewModel(client);
    await vm.loadCollection('col-1');
    expect(vm.hasMore, true);

    await vm.loadMore();

    expect(vm.items.length, 2);
    expect(vm.items.last.id, 'item-2');
    expect(vm.hasMore, false);
  });
```

- [ ] Run: `flutter test test/data/viewmodels/collection_view_model_test.dart`
- [ ] Expect: this test already passes because `_fetchPage`/`loadMore` were implemented in Step 2 (confirms behavior; no code change expected). If it fails, inspect the mocktail `startIndex` argument matcher mismatch before proceeding.
- [ ] Commit: `git add test/data/viewmodels/collection_view_model_test.dart && git commit -m "Add test coverage for CollectionViewModel pagination"`

**Step 4: Write failing widget test for the new `CollectionScreen`**

- [ ] Create `E:\Moonfin-Core\test\ui\screens\browse\collection_screen_test.dart` (mirrors the `test/` structure of `lib/`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/browse/collection_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}
class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(MockImageApi());
    when(() => client.baseUrl).thenReturn('https://example.test');
    when(() => itemsApi.getItems(
          parentId: any(named: 'parentId'),
          recursive: any(named: 'recursive'),
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: any(named: 'startIndex'),
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        });

    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      GetIt.instance.unregister<MediaServerClient>();
    }
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
      GetIt.instance.unregister<MediaServerClientFactory>();
    }
    GetIt.instance.registerSingleton<MediaServerClientFactory>(
      MediaServerClientFactory(deviceInfo: const DeviceInfo(
        deviceId: 'test',
        deviceName: 'test',
        clientName: 'test',
        clientVersion: '1.0',
      )),
    );
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('renders fetched collection item name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CollectionScreen(collectionId: 'col-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Movie One'), findsOneWidget);
  });
}
```

- [ ] Run: `flutter test test/ui/screens/browse/collection_screen_test.dart`
- [ ] Expect failure: `Expected: exactly one matching node in the widget tree / Actual: _TextWidgetFinder:<zero widgets with text "Movie One">` (current `CollectionScreen` only shows the placeholder text).
- [ ] Commit: `git add test/ui/screens/browse/collection_screen_test.dart && git commit -m "Add failing widget test for real CollectionScreen"`

**Step 5: Rewrite `CollectionScreen` to use `CollectionViewModel` and reuse `folder_browse_screen.dart`'s breadcrumb/grid/infinite-scroll patterns**

- [ ] Replace the full contents of `E:\Moonfin-Core\lib\ui\screens\browse\collection_screen.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/viewmodels/collection_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';

class CollectionScreen extends StatefulWidget {
  final String collectionId;
  final String? serverId;

  const CollectionScreen({
    super.key,
    required this.collectionId,
    this.serverId,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late final CollectionViewModel _vm;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final serverId = widget.serverId;
    final client = serverId != null && serverId.isNotEmpty
        ? GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                serverId,
              ) ??
              GetIt.instance<MediaServerClient>()
        : GetIt.instance<MediaServerClient>();
    _vm = CollectionViewModel(client);
    _vm.addListener(_onChanged);
    _scrollController.addListener(_onScroll);
    _vm.loadCollection(widget.collectionId);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _vm.loadMore();
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _imageUrl(AggregatedItem item, {int? maxWidth}) {
    final api = _vm.imageApi;
    final primaryTag = item.primaryImageTag;
    if (primaryTag != null) {
      return api.getPrimaryImageUrl(item.id, maxWidth: maxWidth, tag: primaryTag);
    }
    if (item.backdropImageTags.isNotEmpty) {
      return api.getBackdropImageUrl(
        item.id,
        maxWidth: maxWidth,
        tag: item.backdropImageTags.first,
      );
    }
    return null;
  }

  void _onItemTap(AggregatedItem item) {
    context.push(
      Destinations.itemOrPhoto(
        item.id,
        serverId: item.serverId,
        type: item.type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        showBackButton: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_vm.state) {
      case CollectionState.loading:
        return const Center(child: CircularProgressIndicator());
      case CollectionState.error:
        return Center(
          child: Text(
            AppLocalizations.of(context).failedToLoad,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready when _vm.items.isEmpty:
        return Center(
          child: Text(
            AppLocalizations.of(context).collectionPlaceholder,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready:
        return _buildGrid();
    }
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const spacing = 12.0;
        const targetCardWidth = 170.0;

        final crossAxisCount =
            ((constraints.maxWidth - horizontalPadding * 2 + spacing) /
                    (targetCardWidth + spacing))
                .floor()
                .clamp(2, 10);

        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                (crossAxisCount - 1) * spacing) /
            crossAxisCount;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            32,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: 16,
            children: [
              for (final item in _vm.items)
                SizedBox(
                  width: cardWidth,
                  child: _CollectionGridCard(
                    item: item,
                    imageUrl: _imageUrl(item, maxWidth: cardWidth.toInt()),
                    icon: MediaCard.iconForType(item.type),
                    onTap: () => _onItemTap(item),
                  ),
                ),
              if (_vm.hasMore)
                SizedBox(
                  width: cardWidth,
                  child: const AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CollectionGridCard extends StatelessWidget {
  final AggregatedItem item;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  const _CollectionGridCard({
    required this.item,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ar = MediaCard.aspectRatioForType(item.type);

    return InkWell(
      borderRadius: AppRadius.circular(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: ar,
            child: ClipRRect(
              borderRadius: AppRadius.circular(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColorScheme.onSurface.withAlpha(20),
                  border: Border.fromBorderSide(
                    ThemeRegistry.active.borders.chipBorder,
                  ),
                ),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Center(
                          child: Icon(
                            icon,
                            color: AppColorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            size: 30,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          icon,
                          color: AppColorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          size: 30,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            style: TextStyle(color: AppColorScheme.onSurface, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
```

- [ ] Run: `flutter test test/ui/screens/browse/collection_screen_test.dart`
- [ ] Expect pass: `00:0X +1: All tests passed!`
- [ ] Run the earlier viewmodel test too to confirm no regression: `flutter test test/data/viewmodels/collection_view_model_test.dart`
- [ ] Expect pass: `00:0X +2: All tests passed!`
- [ ] Commit: `git add lib/ui/screens/browse/collection_screen.dart && git commit -m "Replace collection screen stub with real grid backed by CollectionViewModel"`

---

### Task 2: Purpose-built ACdb home row (tag-filtered BoxSet query)

**Files**:
- Modify: `E:\Moonfin-Core\lib\data\services\row_data_source.dart` (add method near `loadCollections`, ~line 301-315)
- Create: `E:\Moonfin-Core\test\data\services\row_data_source_acdb_test.dart`

**Step 1: Write the failing test for `loadAcdbCollections`**

- [ ] Create `E:\Moonfin-Core\test\data\services\row_data_source_acdb_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/models/home_row.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
  });

  test('loadAcdbCollections queries BoxSet items filtered by the given tag', () async {
    when(() => itemsApi.getItems(
          parentId: null,
          includeItemTypes: const ['BoxSet'],
          excludeItemTypes: null,
          genreIds: null,
          filters: null,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          recursive: true,
          startIndex: null,
          limit: any(named: 'limit'),
          isFavorite: null,
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          tags: const ['acdb'],
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'box-1', 'Name': 'ACdb Curated Set', 'Type': 'BoxSet'},
          ],
          'TotalRecordCount': 1,
        });

    final source = RowDataSource(client);
    final row = await source.loadAcdbCollections('server-1', tag: 'acdb');

    expect(row.id, 'acdbCollections');
    expect(row.rowType, HomeRowType.collections);
    expect(row.items.length, 1);
    expect(row.items.first.id, 'box-1');
  });
}
```

- [ ] Run: `flutter test test/data/services/row_data_source_acdb_test.dart`
- [ ] Expect failure: `The method 'loadAcdbCollections' isn't defined for the type 'RowDataSource'.`
- [ ] Commit: `git add test/data/services/row_data_source_acdb_test.dart && git commit -m "Add failing test for tag-filtered ACdb collections row"`

**Step 2: Add `loadAcdbCollections` to `RowDataSource`, mirroring the existing `loadCollections`/`_getItemsWithFallback` pattern**

- [ ] In `E:\Moonfin-Core\lib\data\services\row_data_source.dart`, locate the existing `loadCollections` method (lines 301-315):

```dart
  Future<HomeRow> loadCollections(
    String serverId, {
    String sortBy = _defaultSortBy,
    String sortOrder = _defaultSortOrder,
  }) async {
    return _loadSortedItemsRow(
      serverId: serverId,
      id: 'collections',
      title: _l10n.collections,
      rowType: HomeRowType.collections,
      includeItemTypes: const ['BoxSet'],
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }
```

- [ ] Immediately after it, insert a new method that calls `_getItemsWithFallback` directly (since `_loadSortedItemsRow` has no `tags` parameter and this method needs one):

```dart
  Future<HomeRow> loadAcdbCollections(
    String serverId, {
    required String tag,
    String sortBy = _defaultSortBy,
    String sortOrder = _defaultSortOrder,
  }) async {
    final response = await _getItemsWithFallback(
      includeItemTypes: const ['BoxSet'],
      sortBy: sortBy,
      sortOrder: sortOrder,
      recursive: true,
      limit: _defaultLimit,
      tags: [tag],
    );
    return _buildRow(
      id: 'acdbCollections',
      title: 'ACdb Collections',
      response: response,
      serverId: serverId,
      rowType: HomeRowType.collections,
    );
  }
```

- [ ] Update `_getItemsWithFallback`'s signature (lines 1141-1153) to accept and forward a `tags` parameter, since it currently has no `tags` argument. Change:

```dart
  Future<Map<String, dynamic>> _getItemsWithFallback({
    String? parentId,
    List<String>? includeItemTypes,
    List<String>? excludeItemTypes,
    List<String>? genreIds,
    List<String>? filters,
    String? sortBy,
    String? sortOrder,
    bool? recursive,
    int? startIndex,
    int? limit,
    bool? isFavorite,
    String? fields,
  }) async {
```

to:

```dart
  Future<Map<String, dynamic>> _getItemsWithFallback({
    String? parentId,
    List<String>? includeItemTypes,
    List<String>? excludeItemTypes,
    List<String>? genreIds,
    List<String>? filters,
    String? sortBy,
    String? sortOrder,
    bool? recursive,
    int? startIndex,
    int? limit,
    bool? isFavorite,
    String? fields,
    List<String>? tags,
  }) async {
```

- [ ] In the same method's body (the try block calling `_client.itemsApi.getItems`, lines 1158-1174), add `tags: tags,` to both `getItems` calls (the primary call and the fallback call in the `catch` block), so both read:

```dart
      final response = await _client.itemsApi.getItems(
        parentId: parentId,
        includeItemTypes: includeItemTypes,
        excludeItemTypes: excludeItemTypes,
        genreIds: genreIds,
        filters: filters,
        sortBy: sortBy,
        sortOrder: sortOrder,
        recursive: recursive,
        startIndex: startIndex,
        limit: limit,
        isFavorite: isFavorite,
        fields: fields ?? _fields,
        enableImageTypes: _imageTypes,
        imageTypeLimit: _imageTypeLimit,
        tags: tags,
      );
```

and the fallback call:

```dart
      final response = await _client.itemsApi.getItems(
        parentId: parentId,
        includeItemTypes: includeItemTypes,
        excludeItemTypes: excludeItemTypes,
        genreIds: genreIds,
        filters: filters,
        sortBy: fallbackSort,
        sortOrder: sortOrder,
        recursive: recursive,
        startIndex: startIndex,
        limit: limit,
        isFavorite: isFavorite,
        fields: fields ?? _fallbackFields,
        enableImageTypes: _imageTypes,
        imageTypeLimit: _imageTypeLimit,
        enableTotalRecordCount: false,
        tags: tags,
      );
```

- [ ] Run: `flutter test test/data/services/row_data_source_acdb_test.dart`
- [ ] Expect pass: `00:0X +1: All tests passed!`
- [ ] Run the full `row_data_source`-adjacent suite for regressions (no dedicated existing test file was found for `RowDataSource` itself, so also run the broader test folder): `flutter test test/`
- [ ] Expect: all prior tests still pass alongside the two new ones.
- [ ] Commit: `git add lib/data/services/row_data_source.dart && git commit -m "Add tag-filtered ACdb collections row reusing loadCollections-style query"`

**Note on further home-screen wiring**: surfacing `loadAcdbCollections` as a selectable, orderable row in the drag-and-drop home layout builder requires adding a corresponding `HomeSectionType` enum case, which is consumed by five exhaustive `switch` statements across `home_section_config.dart`, `home_view_model.dart`, `home_screen.dart`, `home_rows_image_type_screen.dart`, and `home_sections_screen.dart`, plus the admin `configPage.html` builder in the server plugin. That enum-wiring pass is mechanical (follow the existing `collections` case in each of those five files) but is a separate, larger changeset than this task's TDD-testable data-layer unit — track it as a follow-on task once the ACdb tag value is confirmed against the user's real server (per the spec's open verification item in §3.2).

---

### Task 3: Server plugin — TMDB collection-by-id proxy endpoint

**Files**:
- Modify: `E:\Moonfin_Plugin\backend\Api\TmdbController.cs`
- No test project exists in this repository — verification is manual `curl` against a running Jellyfin server (see Step 3).

**Step 1: Add the response and raw-API models**

- [ ] In `E:\Moonfin_Plugin\backend\Api\TmdbController.cs`, locate the existing response models section starting at `// ===== Response Models =====` (line 307) and the `TmdbSeasonRatingsResponse` class (lines 346-359). Immediately after the closing brace of `TmdbSeasonRatingsResponse` (after line 359), insert a new response model:

```csharp
/// <summary>
/// TMDB collection ("box set") response returned to the client — the canonical
/// list of parts (movies) that belong to a TMDB collection.
/// </summary>
public class TmdbCollectionResponse
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("id")]
    public int? Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("overview")]
    public string? Overview { get; set; }

    [JsonPropertyName("posterPath")]
    public string? PosterPath { get; set; }

    [JsonPropertyName("backdropPath")]
    public string? BackdropPath { get; set; }

    [JsonPropertyName("parts")]
    public List<TmdbCollectionPart> Parts { get; set; } = new();
}

/// <summary>
/// A single movie part within a TMDB collection.
/// </summary>
public class TmdbCollectionPart
{
    [JsonPropertyName("id")]
    public int? Id { get; set; }

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("releaseDate")]
    public string? ReleaseDate { get; set; }

    [JsonPropertyName("posterPath")]
    public string? PosterPath { get; set; }

    [JsonPropertyName("overview")]
    public string? Overview { get; set; }
}
```

- [ ] In the `// ===== Raw TMDB API Models =====` section, immediately after `TmdbSeasonApiResponse`'s closing brace (after line 400), add the raw TMDB collection API shape:

```csharp
internal class TmdbCollectionApiResponse
{
    [JsonPropertyName("id")]
    public int? Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("overview")]
    public string? Overview { get; set; }

    [JsonPropertyName("poster_path")]
    public string? PosterPath { get; set; }

    [JsonPropertyName("backdrop_path")]
    public string? BackdropPath { get; set; }

    [JsonPropertyName("parts")]
    public List<TmdbCollectionPartApiResponse>? Parts { get; set; }
}

internal class TmdbCollectionPartApiResponse
{
    [JsonPropertyName("id")]
    public int? Id { get; set; }

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("release_date")]
    public string? ReleaseDate { get; set; }

    [JsonPropertyName("poster_path")]
    public string? PosterPath { get; set; }

    [JsonPropertyName("overview")]
    public string? Overview { get; set; }
}
```

- [ ] Since there's no test project for this repository, verify this compiles by building: `dotnet build "E:/Moonfin_Plugin/backend/Moonfin.Server.csproj"`
- [ ] Expect: `Build succeeded.` (the new model classes are unused at this point but must compile cleanly).
- [ ] Commit (run from inside `E:\Moonfin_Plugin`): `git add backend/Api/TmdbController.cs && git commit -m "Add TMDB collection response models to TmdbController"`

**Step 2: Add the `GetCollection` action, following the exact structure of `GetEpisodeRating`/`GetSeasonRatings`**

- [ ] In `E:\Moonfin_Plugin\backend\Api\TmdbController.cs`, immediately after the closing brace of `GetSeasonRatings` (after line 253, before `private async Task<string?> GetUserApiKey()` at line 255), insert the new controller action:

```csharp
    /// <summary>
    /// Fetches a canonical TMDB collection ("box set") by its TMDB collection id,
    /// including all parts (movies) that belong to it.
    /// Uses the authenticated user's TMDB API key from their settings.
    /// </summary>
    /// <param name="tmdbCollectionId">TMDB collection id.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    [HttpGet("Collection/{tmdbCollectionId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<TmdbCollectionResponse>> GetCollection(
        [FromRoute] int tmdbCollectionId,
        CancellationToken cancellationToken)
    {
        if (tmdbCollectionId <= 0)
        {
            return BadRequest(new { Error = "Invalid tmdbCollectionId" });
        }

        var apiKey = await GetUserApiKey();
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return Ok(new TmdbCollectionResponse
            {
                Success = false,
                Error = "No TMDB API key configured. Add your key in Moonfin Settings, or ask your server admin to set a server-wide key."
            });
        }

        var cacheKey = $"collection:{tmdbCollectionId}";
        if (_collectionCache.TryGetValue(cacheKey, out var cached) && DateTimeOffset.UtcNow - cached.CachedAt < CacheTtl)
        {
            return Ok(cached.Response);
        }

        try
        {
            var url = $"https://api.themoviedb.org/3/collection/{tmdbCollectionId}";
            var client = CreateClient();

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            ApplyAuth(request, apiKey);

            using var response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);

            if ((int)response.StatusCode == 429)
            {
                return Ok(new TmdbCollectionResponse
                {
                    Success = false,
                    Error = "TMDB rate limit reached. Try again later."
                });
            }

            if (!response.IsSuccessStatusCode)
            {
                return Ok(new TmdbCollectionResponse
                {
                    Success = false,
                    Error = $"TMDB returned status {(int)response.StatusCode}"
                });
            }

            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            var data = JsonSerializer.Deserialize<TmdbCollectionApiResponse>(json, JsonOptions);

            var parts = new List<TmdbCollectionPart>();
            if (data?.Parts != null)
            {
                foreach (var part in data.Parts)
                {
                    parts.Add(new TmdbCollectionPart
                    {
                        Id = part.Id,
                        Title = part.Title,
                        ReleaseDate = part.ReleaseDate,
                        PosterPath = part.PosterPath,
                        Overview = part.Overview
                    });
                }
            }

            var result = new TmdbCollectionResponse
            {
                Success = true,
                Id = data?.Id,
                Name = data?.Name,
                Overview = data?.Overview,
                PosterPath = data?.PosterPath,
                BackdropPath = data?.BackdropPath,
                Parts = parts
            };

            _collectionCache[cacheKey] = (result, DateTimeOffset.UtcNow);

            return Ok(result);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return Ok(new TmdbCollectionResponse
            {
                Success = false,
                Error = $"Failed to fetch from TMDB: {ex.Message}"
            });
        }
    }
```

- [ ] Add the matching cache field next to the existing `_seasonCache`/`_episodeCache` fields (lines 24-27):

```csharp
    // Cache: key = "tmdbId:season" => (response, timestamp)
    private static readonly ConcurrentDictionary<string, (TmdbSeasonRatingsResponse Response, DateTimeOffset CachedAt)> _seasonCache = new();
    // Cache: key = "tmdbId:season:episode" => (response, timestamp)
    private static readonly ConcurrentDictionary<string, (TmdbEpisodeRatingResponse Response, DateTimeOffset CachedAt)> _episodeCache = new();
    // Cache: key = "collection:tmdbCollectionId" => (response, timestamp)
    private static readonly ConcurrentDictionary<string, (TmdbCollectionResponse Response, DateTimeOffset CachedAt)> _collectionCache = new();
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);
```

- [ ] Run: `dotnet build "E:/Moonfin_Plugin/backend/Moonfin.Server.csproj"`
- [ ] Expect: `Build succeeded.`
- [ ] Commit: `git add backend/Api/TmdbController.cs && git commit -m "Add GET /Moonfin/Tmdb/Collection/{id} proxy endpoint"`

**Step 3: Manual integration verification (no automated test harness exists for this repository)**

- [ ] Deploy the built plugin DLL to the target Jellyfin server's plugin directory and restart Jellyfin (existing deployment process for this fork; not part of this plan).
- [ ] Obtain a valid Jellyfin auth token for a user with a configured TMDB API key (Moonfin Settings → TMDB API key).
- [ ] Run against a known-good TMDB collection id (e.g. `10` = "Star Wars Collection"):
```bash
curl -s -H 'Authorization: MediaBrowser Token="<TOKEN>"' \
  'http://<server>:8096/Moonfin/Tmdb/Collection/10'
```
- [ ] Expect JSON response shaped like:
```json
{"success":true,"error":null,"id":10,"name":"Star Wars Collection","overview":"...","posterPath":"/...","backdropPath":"/...","parts":[{"id":1891,"title":"Star Wars: Episode V - The Empire Strikes Back","releaseDate":"1980-05-20","posterPath":"/...","overview":"..."}, ...]}
```
- [ ] Run again immediately and confirm the second response is served from `_collectionCache` (same content, and server logs/timing show no outbound TMDB call the second time if request logging is enabled).
- [ ] Run against an invalid id to confirm the guard clause:
```bash
curl -s -H 'Authorization: MediaBrowser Token="<TOKEN>"' \
  'http://<server>:8096/Moonfin/Tmdb/Collection/0'
```
- [ ] Expect: HTTP 400 with body `{"Error":"Invalid tmdbCollectionId"}`.
- [ ] Run without the `Authorization` header to confirm the `[Authorize]` attribute is enforced:
```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://<server>:8096/Moonfin/Tmdb/Collection/10'
```
- [ ] Expect: `401`.
- [ ] There is no automated test harness for this repository today — this manual `curl` verification against a running Jellyfin server is the full verification for this task.

---

### Task 4: Client `TmdbRepository.getCollection()` method

**Files**:
- Modify: `E:\Moonfin-Core\lib\data\repositories\tmdb_repository.dart`
- Create: `E:\Moonfin-Core\test\data\repositories\tmdb_repository_collection_test.dart`

**Step 1: Write the failing test**

Since `TmdbRepository` builds its own internal `Dio()` instance rather than accepting an injectable HTTP client, the existing codebase has no test for this class today. Follow the same reachable-surface testing approach used elsewhere in this repo: test against a `MediaServerClient` mock that supplies `baseUrl`/`accessToken`, using `dio`'s `DioAdapter`-free approach is not available here, so this test verifies the caching/parsing behavior via a minimal fake client whose `baseUrl` points at nothing reachable, confirming the method's parameter contract and null-safety instead of a live network call — mirroring how `getEpisodeRating`/`getSeasonRatings` have no existing unit tests either (confirmed by inspecting the file's neighbors; no `tmdb_repository_test.dart` exists in `test/`). This task therefore adds the smallest meaningful unit test: that the method returns `null` gracefully when there is no access token, matching the existing `_get` early-return contract.

- [ ] Create `E:\Moonfin-Core\test\data\repositories\tmdb_repository_collection_test.dart`:

```dart
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
```

- [ ] Run: `flutter test test/data/repositories/tmdb_repository_collection_test.dart`
- [ ] Expect failure: `The method 'getCollection' isn't defined for the type 'TmdbRepository'.`
- [ ] Commit: `git add test/data/repositories/tmdb_repository_collection_test.dart && git commit -m "Add failing test for TmdbRepository.getCollection no-token guard"`

**Step 2: Add `getCollection` to `TmdbRepository`, following the exact `_get`-based pattern of `getEpisodeRating`**

- [ ] In `E:\Moonfin-Core\lib\data\repositories\tmdb_repository.dart`, locate `getSeasonRatings` (lines 68-122) and its closing brace at line 122, immediately before `Future<Map<String, dynamic>?> _get(` at line 124. Insert the new method there:

```dart
  Future<Map<String, dynamic>?> getCollection(int tmdbCollectionId) async {
    try {
      final response = await _get('/Moonfin/Tmdb/Collection/$tmdbCollectionId', const {});
      if (response == null) return null;

      final success = response['success'] as bool? ?? false;
      if (!success) return null;

      return response;
    } catch (e) {
      debugPrint('[Moonfin] TMDB collection fetch failed: $e');
      return null;
    }
  }
```

- [ ] Run: `flutter test test/data/repositories/tmdb_repository_collection_test.dart`
- [ ] Expect pass: `00:0X +1: All tests passed!`
- [ ] Commit: `git add lib/data/repositories/tmdb_repository.dart && git commit -m "Add TmdbRepository.getCollection proxying the new Moonbase collection endpoint"`

---

### Task 5: Missing-items diff and Seerr request UI

**Files**:
- Create: `E:\Moonfin-Core\lib\data\viewmodels\collection_missing_items_view_model.dart`
- Create: `E:\Moonfin-Core\test\data\viewmodels\collection_missing_items_view_model_test.dart`
- Modify: `E:\Moonfin-Core\lib\ui\screens\browse\collection_screen.dart` (add missing-items section)

**Step 1: Write the failing test for the diff logic**

- [ ] Create `E:\Moonfin-Core\test\data\viewmodels\collection_missing_items_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/viewmodels/collection_missing_items_view_model.dart';

class MockTmdbRepository extends Mock implements TmdbRepository {}
class MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  late MockTmdbRepository tmdbRepo;
  late MockSeerrRepository seerrRepo;

  setUp(() {
    tmdbRepo = MockTmdbRepository();
    seerrRepo = MockSeerrRepository();
  });

  AggregatedItem libraryItem(String tmdbId) => AggregatedItem(
        id: 'lib-$tmdbId',
        serverId: 'server-1',
        rawData: {
          'Id': 'lib-$tmdbId',
          'Name': 'Owned $tmdbId',
          'Type': 'Movie',
          'ProviderIds': {'Tmdb': tmdbId},
        },
      );

  test('diffs canonical TMDB parts against library items by tmdbId', () async {
    when(() => tmdbRepo.getCollection(10)).thenAnswer((_) async => {
          'success': true,
          'id': 10,
          'name': 'Star Wars Collection',
          'parts': [
            {'id': 1891, 'title': 'The Empire Strikes Back', 'releaseDate': '1980-05-20', 'posterPath': '/a.jpg', 'overview': ''},
            {'id': 1892, 'title': 'Return of the Jedi', 'releaseDate': '1983-05-25', 'posterPath': '/b.jpg', 'overview': ''},
          ],
        });

    final vm = CollectionMissingItemsViewModel(
      tmdbRepository: tmdbRepo,
      seerrRepository: seerrRepo,
    );
    await vm.loadMissingItems(
      tmdbCollectionId: 10,
      libraryItems: [libraryItem('1891')],
    );

    expect(vm.missingItems.length, 1);
    expect(vm.missingItems.first.tmdbId, 1892);
    expect(vm.missingItems.first.title, 'Return of the Jedi');
  });

  test('requestMissingItem calls SeerrRepository.createRequest for movie media type', () async {
    when(() => tmdbRepo.getCollection(10)).thenAnswer((_) async => {
          'success': true,
          'id': 10,
          'name': 'Star Wars Collection',
          'parts': [
            {'id': 1892, 'title': 'Return of the Jedi', 'releaseDate': '1983-05-25', 'posterPath': '/b.jpg', 'overview': ''},
          ],
        });
    when(() => seerrRepo.createRequest(
          mediaId: 1892,
          mediaType: 'movie',
        )).thenAnswer((_) async => SeerrRequest.fromJson({
          'id': 1,
          'status': 1,
          'media': {'id': 1, 'tmdbId': 1892, 'status': 3, 'mediaType': 'movie'},
        }));

    final vm = CollectionMissingItemsViewModel(
      tmdbRepository: tmdbRepo,
      seerrRepository: seerrRepo,
    );
    await vm.loadMissingItems(tmdbCollectionId: 10, libraryItems: const []);
    await vm.requestMissingItem(vm.missingItems.first);

    verify(() => seerrRepo.createRequest(mediaId: 1892, mediaType: 'movie')).called(1);
    expect(vm.requestedTmdbIds.contains(1892), true);
  });
}
```

- [ ] Run: `flutter test test/data/viewmodels/collection_missing_items_view_model_test.dart`
- [ ] Expect failure: `Error: Error when reading 'lib/data/viewmodels/collection_missing_items_view_model.dart': No such file or directory`
- [ ] Commit: `git add test/data/viewmodels/collection_missing_items_view_model_test.dart && git commit -m "Add failing tests for collection missing-items diff and request"`

**Step 2: Check `SeerrRequest.fromJson` and `SeerrRepository.createRequest` shapes match the test fixture**

- [ ] Before implementing, confirm the exact `SeerrRepository.createRequest` signature already read from `E:\Moonfin-Core\lib\data\repositories\seerr_repository.dart` (lines 465-487) — it takes named `mediaId` (`int`, required) and `mediaType` (`String`, required), with optional `seasons`, `allSeasons`, `is4k`, `profileId`, `rootFolder`, `serverId`, and returns `Future<SeerrRequest>`. The test above calls it with only the two required named params, which matches this signature exactly (all others are optional). No code change needed for this step — proceed to implementation.

**Step 3: Implement `CollectionMissingItemsViewModel`**

- [ ] Create `E:\Moonfin-Core\lib\data\viewmodels\collection_missing_items_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../models/aggregated_item.dart';
import '../repositories/seerr_repository.dart';
import '../repositories/tmdb_repository.dart';

enum MissingItemsState { idle, loading, ready, error }

class MissingCollectionItem {
  final int tmdbId;
  final String title;
  final String? posterPath;
  final String? releaseDate;

  const MissingCollectionItem({
    required this.tmdbId,
    required this.title,
    this.posterPath,
    this.releaseDate,
  });
}

class CollectionMissingItemsViewModel extends ChangeNotifier {
  final TmdbRepository tmdbRepository;
  final SeerrRepository seerrRepository;

  CollectionMissingItemsViewModel({
    required this.tmdbRepository,
    required this.seerrRepository,
  });

  MissingItemsState _state = MissingItemsState.idle;
  MissingItemsState get state => _state;

  List<MissingCollectionItem> _missingItems = const [];
  List<MissingCollectionItem> get missingItems => _missingItems;

  final Set<int> _requestedTmdbIds = <int>{};
  Set<int> get requestedTmdbIds => Set.unmodifiable(_requestedTmdbIds);

  final Set<int> _requestingTmdbIds = <int>{};
  bool isRequesting(int tmdbId) => _requestingTmdbIds.contains(tmdbId);

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  Future<void> loadMissingItems({
    required int tmdbCollectionId,
    required List<AggregatedItem> libraryItems,
  }) async {
    _state = MissingItemsState.loading;
    notifyListeners();

    try {
      final collection = await tmdbRepository.getCollection(tmdbCollectionId);
      if (collection == null) {
        _errorMessage = 'Collection unavailable';
        _state = MissingItemsState.error;
        notifyListeners();
        return;
      }

      final ownedTmdbIds = libraryItems
          .map((item) => int.tryParse(item.tmdbId ?? ''))
          .whereType<int>()
          .toSet();

      final parts = (collection['parts'] as List?) ?? const [];
      _missingItems = parts
          .whereType<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .where((part) {
            final id = part['id'] as int?;
            return id != null && !ownedTmdbIds.contains(id);
          })
          .map((part) => MissingCollectionItem(
                tmdbId: part['id'] as int,
                title: part['title'] as String? ?? '',
                posterPath: part['posterPath'] as String?,
                releaseDate: part['releaseDate'] as String?,
              ))
          .toList();

      _state = MissingItemsState.ready;
    } catch (e) {
      _errorMessage = e.toString();
      _state = MissingItemsState.error;
    }
    notifyListeners();
  }

  Future<void> requestMissingItem(MissingCollectionItem item) async {
    if (_requestingTmdbIds.contains(item.tmdbId)) return;
    _requestingTmdbIds.add(item.tmdbId);
    notifyListeners();

    try {
      await seerrRepository.createRequest(
        mediaId: item.tmdbId,
        mediaType: 'movie',
      );
      _requestedTmdbIds.add(item.tmdbId);
    } finally {
      _requestingTmdbIds.remove(item.tmdbId);
      notifyListeners();
    }
  }
}
```

- [ ] Run: `flutter test test/data/viewmodels/collection_missing_items_view_model_test.dart`
- [ ] Expect pass: `00:0X +2: All tests passed!`
- [ ] Commit: `git add lib/data/viewmodels/collection_missing_items_view_model.dart && git commit -m "Add CollectionMissingItemsViewModel diffing TMDB parts against library and wiring Seerr requests"`

**Step 4: Write failing widget test asserting the missing-items section and Request button appear on `CollectionScreen`**

- [ ] Append to `E:\Moonfin-Core\test\ui\screens\browse\collection_screen_test.dart` (new imports at top, new test at the bottom of `main()`):

```dart
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
```

then, inside `main()`, add:

```dart
  testWidgets('shows a Request button for a missing collection item', (tester) async {
    when(() => itemsApi.getItems(
          parentId: any(named: 'parentId'),
          recursive: any(named: 'recursive'),
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: any(named: 'startIndex'),
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        )).thenAnswer((_) async => {
          'Items': [
            {
              'Id': 'item-1',
              'Name': 'The Empire Strikes Back',
              'Type': 'Movie',
              'ProviderIds': {'Tmdb': '1891'},
            },
          ],
          'TotalRecordCount': 1,
        });

    if (GetIt.instance.isRegistered<TmdbRepository>()) {
      GetIt.instance.unregister<TmdbRepository>();
    }
    final tmdbRepo = MockTmdbRepository();
    when(() => tmdbRepo.getCollection(10)).thenAnswer((_) async => {
          'success': true,
          'id': 10,
          'name': 'Star Wars Collection',
          'parts': [
            {'id': 1891, 'title': 'The Empire Strikes Back', 'releaseDate': '1980-05-20', 'posterPath': null, 'overview': ''},
            {'id': 1892, 'title': 'Return of the Jedi', 'releaseDate': '1983-05-25', 'posterPath': null, 'overview': ''},
          ],
        });
    GetIt.instance.registerSingleton<TmdbRepository>(tmdbRepo);

    if (GetIt.instance.isRegistered<SeerrRepository>()) {
      GetIt.instance.unregister<SeerrRepository>();
    }
    GetIt.instance.registerSingleton<SeerrRepository>(MockSeerrRepository());

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CollectionScreen(collectionId: 'col-1', tmdbCollectionId: 10),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Return of the Jedi'), findsOneWidget);
    expect(find.text(AppLocalizations.of(tester.element(find.byType(CollectionScreen))).request), findsOneWidget);
  });
```

and add the two mock classes near the top of the file, alongside the existing mocks:

```dart
class MockTmdbRepository extends Mock implements TmdbRepository {}
class MockSeerrRepository extends Mock implements SeerrRepository {}
```

- [ ] Run: `flutter test test/ui/screens/browse/collection_screen_test.dart`
- [ ] Expect failure: `The named parameter 'tmdbCollectionId' isn't defined.` (compile error — `CollectionScreen` doesn't accept it yet).
- [ ] Commit: `git add test/ui/screens/browse/collection_screen_test.dart && git commit -m "Add failing widget test for missing-items section with Request button"`

**Step 5: Wire the missing-items section into `CollectionScreen`**

- [ ] In `E:\Moonfin-Core\lib\ui\screens\browse\collection_screen.dart`, update the imports at the top (added lines after the existing `navigation_layout.dart` import):

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/repositories/tmdb_repository.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/viewmodels/collection_missing_items_view_model.dart';
import '../../../data/viewmodels/collection_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
```

- [ ] Update the `CollectionScreen` widget constructor to accept `tmdbCollectionId`:

```dart
class CollectionScreen extends StatefulWidget {
  final String collectionId;
  final String? serverId;
  final int? tmdbCollectionId;

  const CollectionScreen({
    super.key,
    required this.collectionId,
    this.serverId,
    this.tmdbCollectionId,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}
```

- [ ] In `_CollectionScreenState`, add the missing-items view model and load it once collection items arrive. Update `initState`/`_onChanged`:

```dart
class _CollectionScreenState extends State<CollectionScreen> {
  late final CollectionViewModel _vm;
  CollectionMissingItemsViewModel? _missingItemsVm;
  final _scrollController = ScrollController();
  bool _missingItemsRequested = false;

  @override
  void initState() {
    super.initState();
    final serverId = widget.serverId;
    final client = serverId != null && serverId.isNotEmpty
        ? GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                serverId,
              ) ??
              GetIt.instance<MediaServerClient>()
        : GetIt.instance<MediaServerClient>();
    _vm = CollectionViewModel(client);
    _vm.addListener(_onChanged);
    _scrollController.addListener(_onScroll);
    if (widget.tmdbCollectionId != null) {
      _missingItemsVm = CollectionMissingItemsViewModel(
        tmdbRepository: GetIt.instance<TmdbRepository>(),
        seerrRepository: GetIt.instance<SeerrRepository>(),
      );
      _missingItemsVm!.addListener(_onChanged);
    }
    _vm.loadCollection(widget.collectionId);
  }

  void _onChanged() {
    if (!mounted) return;
    if (!_missingItemsRequested &&
        _vm.state == CollectionState.ready &&
        widget.tmdbCollectionId != null &&
        _missingItemsVm != null) {
      _missingItemsRequested = true;
      _missingItemsVm!.loadMissingItems(
        tmdbCollectionId: widget.tmdbCollectionId!,
        libraryItems: _vm.items,
      );
    }
    setState(() {});
  }
```

- [ ] Update `dispose`:

```dart
  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _missingItemsVm?.removeListener(_onChanged);
    _missingItemsVm?.dispose();
    _scrollController.dispose();
    super.dispose();
  }
```

- [ ] Update `_buildContent` to render the missing-items section below the grid:

```dart
  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        showBackButton: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }
```

Add a new `_buildBody` that composes the owned grid with the missing-items section when the `CollectionViewModel` is ready:

```dart
  Widget _buildBody() {
    switch (_vm.state) {
      case CollectionState.loading:
        return const Center(child: CircularProgressIndicator());
      case CollectionState.error:
        return Center(
          child: Text(
            AppLocalizations.of(context).failedToLoad,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready when _vm.items.isEmpty:
        return Center(
          child: Text(
            AppLocalizations.of(context).collectionPlaceholder,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready:
        return SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGrid(),
              if (_missingItemsVm != null) _buildMissingItemsSection(),
            ],
          ),
        );
    }
  }
```

- [ ] Update `_buildGrid` so it no longer owns its own `SingleChildScrollView`/`controller` (that scroll ownership now belongs to `_buildBody`'s outer `SingleChildScrollView`), replacing the previous `_buildGrid` implementation:

```dart
  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const spacing = 12.0;
        const targetCardWidth = 170.0;

        final crossAxisCount =
            ((constraints.maxWidth - horizontalPadding * 2 + spacing) /
                    (targetCardWidth + spacing))
                .floor()
                .clamp(2, 10);

        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                (crossAxisCount - 1) * spacing) /
            crossAxisCount;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            16,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: 16,
            children: [
              for (final item in _vm.items)
                SizedBox(
                  width: cardWidth,
                  child: _CollectionGridCard(
                    item: item,
                    imageUrl: _imageUrl(item, maxWidth: cardWidth.toInt()),
                    icon: MediaCard.iconForType(item.type),
                    onTap: () => _onItemTap(item),
                  ),
                ),
              if (_vm.hasMore)
                SizedBox(
                  width: cardWidth,
                  child: const AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
```

- [ ] Since `_buildGrid`'s scroll-triggered `loadMore` (`_onScroll`) previously depended on the inner `ScrollController` being attached to the grid's own `SingleChildScrollView`, and it now belongs to the outer one wrapping the whole body, no further change is needed there — `_scrollController` is already passed to the single outer `SingleChildScrollView` in `_buildBody`, and `_onScroll` (unchanged from Task 1) still reads `_scrollController.position`.

- [ ] Add the new `_buildMissingItemsSection` method plus the `_MissingItemCard` widget at the end of `_CollectionScreenState`, before the closing brace of the class:

```dart
  Widget _buildMissingItemsSection() {
    final missingVm = _missingItemsVm!;
    if (missingVm.state == MissingItemsState.loading ||
        missingVm.state == MissingItemsState.idle) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (missingVm.state == MissingItemsState.error ||
        missingVm.missingItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.collections,
            style: TextStyle(
              color: AppColorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final item in missingVm.missingItems)
                SizedBox(
                  width: 170,
                  child: _MissingItemCard(
                    item: item,
                    isRequesting: missingVm.isRequesting(item.tmdbId),
                    isRequested: missingVm.requestedTmdbIds.contains(item.tmdbId),
                    requestLabel: l10n.request,
                    onRequest: () => missingVm.requestMissingItem(item),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingItemCard extends StatelessWidget {
  final MissingCollectionItem item;
  final bool isRequesting;
  final bool isRequested;
  final String requestLabel;
  final VoidCallback onRequest;

  const _MissingItemCard({
    required this.item,
    required this.isRequesting,
    required this.isRequested,
    required this.requestLabel,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: AppRadius.circular(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColorScheme.onSurface.withAlpha(20),
                border: Border.fromBorderSide(
                  ThemeRegistry.active.borders.chipBorder,
                ),
              ),
              child: item.posterPath != null
                  ? CachedNetworkImage(
                      imageUrl:
                          'https://image.tmdb.org/t/p/w342${item.posterPath}',
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.movie, size: 30),
                      ),
                    )
                  : const Center(child: Icon(Icons.movie, size: 30)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.title,
          style: TextStyle(color: AppColorScheme.onSurface, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: isRequesting || isRequested ? null : onRequest,
            child: Text(isRequested ? '✓' : requestLabel),
          ),
        ),
      ],
    );
  }
}
```

- [ ] Remove the now-orphaned closing brace duplication: since `_buildMissingItemsSection` was inserted with its own class closing brace (`}`) followed immediately by the new `_MissingItemCard` class, delete the original trailing `}` that used to close `_CollectionScreenState` right after the old `_buildGrid` method and the pre-existing `_CollectionGridCard` class remains unchanged below it (already present from Task 1, no edit needed there).

- [ ] Run: `flutter test test/ui/screens/browse/collection_screen_test.dart`
- [ ] Expect pass: `00:0X +2: All tests passed!`
- [ ] Run the full previously-written suite for this feature to confirm no regressions: `flutter test test/data/viewmodels/collection_view_model_test.dart test/data/viewmodels/collection_missing_items_view_model_test.dart test/data/services/row_data_source_acdb_test.dart test/data/repositories/tmdb_repository_collection_test.dart test/ui/screens/browse/collection_screen_test.dart`
- [ ] Expect: `00:0X +8: All tests passed!` (1 + 2 + 1 + 1 + 2 tests, but count reflects actual number of `test`/`testWidgets` blocks across the five files — verify all show `passed`, none `failed`).
- [ ] Commit: `git add lib/ui/screens/browse/collection_screen.dart && git commit -m "Render missing-items section on CollectionScreen with Seerr request button"`

**Step 6: Wire `Destinations.collection`/route to pass `tmdbCollectionId` when known**

- [ ] The route builder in `E:\Moonfin-Core\lib\ui\navigation\app_router.dart` (lines 319-325) currently only passes `collectionId`. Since the TMDB collection id for a given library BoxSet is not something the route path itself carries (per the spec's open verification item: it must be resolved from the BoxSet's own `ProviderIds` at runtime, not passed through navigation), leave the route builder unchanged for now — `CollectionScreen` resolves `tmdbCollectionId` from the collection's own item data once loaded, which is out of scope for this task's diff/request widget and belongs to the open verification item called out in the spec (confirm whether ACdb-created BoxSets carry a usable TMDB collection provider id before wiring this end-to-end). No code change required here; this is a documented follow-on, not a step in this plan.

---

### Verification

This plan implements spec section 3 ("Collections: normal TMDB box sets + purpose-built ACdb row"), specifically:

- **§3.1 (Real collections screen)**: `CollectionViewModel` + rewritten `CollectionScreen` fetch and render collection contents via `itemsApi.getItems(parentId: collectionId)`, matching the exact call pattern already proven in `add_to_collection_dialog.dart`, and reuse the grid/breadcrumb/infinite-scroll structural patterns from `folder_browse_screen.dart`. Verified by `test/data/viewmodels/collection_view_model_test.dart` and `test/ui/screens/browse/collection_screen_test.dart`.
- **§3.2 (Purpose-built ACdb row)**: `RowDataSource.loadAcdbCollections` queries `/Items` with `IncludeItemTypes=BoxSet` and `Tags=<tag>`, reusing the existing `_getItemsWithFallback`/`_buildRow` machinery that `loadCollections` already uses, giving the row its own `id` (`acdbCollections`) and title so it stays structurally distinct from the generic collections row. Verified by `test/data/services/row_data_source_acdb_test.dart`. Full home-layout-builder surfacing (new `HomeSectionType` case across five files plus the admin HTML page) is flagged as necessary follow-on work, not fabricated into this plan.
- **§3.3 (Missing-items + Seerr request)**: the new `GET /Moonfin/Tmdb/Collection/{tmdbCollectionId}` proxy on `TmdbController` (Task 3) follows the identical structure, caching, auth, and error-handling conventions of the existing `EpisodeRating`/`SeasonRatings` actions; `TmdbRepository.getCollection()` (Task 4) proxies it client-side using the existing `_get` helper; `CollectionMissingItemsViewModel` (Task 5) diffs canonical TMDB parts against library items by `tmdbId` (via `AggregatedItem.tmdbId`, which already parses `ProviderIds.Tmdb`) and wires each missing item's Request button directly to the existing `SeerrRepository.createRequest(mediaId: tmdbId, mediaType: 'movie')` with no new Seerr plumbing. Verified by `test/data/viewmodels/collection_missing_items_view_model_test.dart` and the widget-level assertion in `test/ui/screens/browse/collection_screen_test.dart`.
- Server-side changes (Task 3) have no automated test harness in `E:\Moonfin_Plugin` today; verification is the manual `curl` sequence in Task 3 Step 3 against a running Jellyfin server with a configured TMDB API key, confirming success, caching, invalid-id (400), and unauthenticated (401) behavior.
- Per the spec's explicit open item, before treating §3.3 as fully done against the user's real server: confirm whether the user's actual ACdb-managed BoxSets carry a usable TMDB collection id via `ProviderIds` (feed `tmdbCollectionId` into `CollectionScreen` only when present); if not, the spec calls for a TMDB search-by-name-and-year fallback, which is explicitly out of scope for this plan and should be scoped separately once that verification is done.