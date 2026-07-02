All confirmed. Now writing the complete plan.

# Genres Browsable List With Live Preview Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

Goal: Replace the image-collage genre grid on both `AllGenresScreen` and `LibraryGenresScreen` with a two-pane layout — a scrollable, image-free text list of genre names on the left and a live item panel on the right that loads immediately on focus/selection — while deleting all per-genre artwork enrichment code.

Architecture: `GenreListItem` (id + name only) replaces `GenreCardData`; a new stateless `GenreNameListTile` (D-pad focusable, text-only) replaces `GenreGridCard` and fully retires `lib/ui/widgets/genre_grid_card.dart`. A new shared `GenreItemsPanel` widget owns the right-hand pane: given a `genreId` (and, for the library variant, a `parentId`/`includeItemTypes`), it calls `RowDataSource.loadGenreRow` (already used elsewhere for genre item queries) and renders the results with the existing `MediaCard` widget in a `GridView`. Both screens keep their existing top-level `Scaffold`/backdrop/header chrome and swap only the body: a `Row` of `Expanded(GenreNameListTile list)` + `Expanded(GenreItemsPanel)`. Selection state is a simple `_selectedGenre` field updated both `onFocusChange` (TV/keyboard/remote D-pad traversal) and `onTap` (mouse/touch), so the right panel updates the moment focus moves down the list, satisfying the D-pad "focus moves down the left list and the right panel updates on focus or selection" requirement.

Tech Stack: Flutter/Dart, `flutter_test` + `mocktail` for unit/widget tests, existing `server_core` `MediaServerClient`/`ItemsApi`/`ImageApi` abstract interfaces, `go_router`, `get_it`, `moonfin_design` theming.

---

### Task 1: `GenreListItem` model (replaces `GenreCardData`)

Files:
- Create: `E:\Moonfin-Core\lib\ui\widgets\genre_name_list_tile.dart`
- Test: `E:\Moonfin-Core\test\ui\widgets\genre_name_list_tile_test.dart`
- Modify: none yet (old `genre_grid_card.dart` is deleted in Task 5 once nothing references it)

- [ ] Step 1: Write the failing test for the new data model
Create `E:\Moonfin-Core\test\ui\widgets\genre_name_list_tile_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/genre_name_list_tile.dart';

void main() {
  test('GenreListItem stores id and name with no image fields', () {
    final genre = GenreListItem(id: 'g1', name: 'Comedy');

    expect(genre.id, 'g1');
    expect(genre.name, 'Comedy');
  });
}
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/widgets/genre_name_list_tile_test.dart
```
Expected output (compilation failure, file doesn't exist yet):
```
Error: Error when reading 'lib/ui/widgets/genre_name_list_tile.dart': The system cannot find the file specified.
```

- [ ] Step 3: Write minimal implementation
Create `E:\Moonfin-Core\lib\ui\widgets\genre_name_list_tile.dart`:
```dart
class GenreListItem {
  final String id;
  final String name;

  GenreListItem({required this.id, required this.name});
}
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/widgets/genre_name_list_tile_test.dart
```
Expected output:
```
00:01 +1: All tests passed!
```

- [ ] Step 5: Commit
```
git add lib/ui/widgets/genre_name_list_tile.dart test/ui/widgets/genre_name_list_tile_test.dart
git commit -m "Add GenreListItem model for text-only genre list"
```

---

### Task 2: `GenreNameListTile` widget (D-pad focusable text row)

Files:
- Modify: `E:\Moonfin-Core\lib\ui\widgets\genre_name_list_tile.dart` (append widget below the model added in Task 1)
- Test: `E:\Moonfin-Core\test\ui\widgets\genre_name_list_tile_test.dart` (append widget tests below the model test added in Task 1)

- [ ] Step 1: Write the failing test for tap activation
Append to `E:\Moonfin-Core\test\ui\widgets\genre_name_list_tile_test.dart` (replace the whole file to add the new imports and group):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/genre_name_list_tile.dart';

void main() {
  test('GenreListItem stores id and name with no image fields', () {
    final genre = GenreListItem(id: 'g1', name: 'Comedy');

    expect(genre.id, 'g1');
    expect(genre.name, 'Comedy');
  });

  group('GenreNameListTile', () {
    testWidgets('renders genre name and calls onTap when activated', (
      tester,
    ) async {
      var tapped = false;
      final genre = GenreListItem(id: 'g1', name: 'Comedy');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenreNameListTile(
              genre: genre,
              selected: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Comedy'), findsOneWidget);

      await tester.tap(find.byType(GenreNameListTile));
      await tester.pumpAndSettle();

      expect(tapped, true);
    });
  });
}
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/widgets/genre_name_list_tile_test.dart
```
Expected output:
```
Error: The name 'GenreNameListTile' isn't a type.
```

- [ ] Step 3: Write minimal implementation
Replace `E:\Moonfin-Core\lib\ui\widgets\genre_name_list_tile.dart` in full:
```dart
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../util/focus/dpad_keys.dart';
import '../mixins/focus_state_mixin.dart';

class GenreListItem {
  final String id;
  final String name;

  GenreListItem({required this.id, required this.name});
}

class GenreNameListTile extends StatefulWidget {
  final GenreListItem genre;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;

  const GenreNameListTile({
    super.key,
    required this.genre,
    required this.selected,
    required this.onTap,
    this.onFocusChange,
  });

  @override
  State<GenreNameListTile> createState() => _GenreNameListTileState();
}

class _GenreNameListTileState extends State<GenreNameListTile>
    with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.selected || showFocusBorder;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        onFocusChange: (focused) {
          setFocused(focused);
          widget.onFocusChange?.call(focused);
        },
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isHighlighted
                ? AppColorScheme.accent.withAlpha(40)
                : Colors.transparent,
            child: Text(
              widget.genre.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                color: AppColorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/widgets/genre_name_list_tile_test.dart
```
Expected output:
```
00:01 +2: All tests passed!
```

- [ ] Step 5: Commit
```
git add lib/ui/widgets/genre_name_list_tile.dart test/ui/widgets/genre_name_list_tile_test.dart
git commit -m "Add GenreNameListTile focusable text row widget"
```

---

### Task 3: `GenreItemsPanel` right-hand panel (loads items via `RowDataSource.loadGenreRow`)

This is the panel that satisfies "selecting a genre immediately loads its items into a right hand main panel using the existing genre item query calls." It calls `RowDataSource.loadGenreRow`, which internally calls `_getItemsWithFallback(genreIds: [genreId], ...)` → `_client.itemsApi.getItems(genreIds: ..., ...)`, exactly the query already used by `loadGenreArtwork`/`_loadGenreItems` in the two screens being replaced, and the same query family used by `LibraryBrowseScreen` when a genre card is tapped today.

Files:
- Create: `E:\Moonfin-Core\lib\ui\widgets\genre_items_panel.dart`
- Test: `E:\Moonfin-Core\test\ui\widgets\genre_items_panel_test.dart`

- [ ] Step 1: Write the failing test for empty-selection state
Create `E:\Moonfin-Core\test\ui\widgets\genre_items_panel_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/ui/widgets/genre_items_panel.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late MockImageApi imageApi;
  late RowDataSource dataSource;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    imageApi = MockImageApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(imageApi);
    dataSource = RowDataSource(client);
  });

  testWidgets('shows empty state when no genre is selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenreItemsPanel(
            genreId: null,
            genreName: null,
            dataSource: dataSource,
            serverId: 'server1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GridView), findsNothing);
  });
}
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/widgets/genre_items_panel_test.dart
```
Expected output:
```
Error: Error when reading 'lib/ui/widgets/genre_items_panel.dart': The system cannot find the file specified.
```

- [ ] Step 3: Write minimal implementation (empty-state only)
Create `E:\Moonfin-Core\lib\ui\widgets\genre_items_panel.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/services/row_data_source.dart';

class GenreItemsPanel extends StatelessWidget {
  final String? genreId;
  final String? genreName;
  final RowDataSource dataSource;
  final String serverId;

  const GenreItemsPanel({
    super.key,
    required this.genreId,
    required this.genreName,
    required this.dataSource,
    required this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    if (genreId == null) {
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }
}
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/widgets/genre_items_panel_test.dart
```
Expected output:
```
00:01 +1: All tests passed!
```

- [ ] Step 5: Commit
```
git add lib/ui/widgets/genre_items_panel.dart test/ui/widgets/genre_items_panel_test.dart
git commit -m "Add GenreItemsPanel skeleton with empty-selection state"
```

- [ ] Step 6: Write the failing test for loading items via `RowDataSource.loadGenreRow`
Append a second test to `E:\Moonfin-Core\test\ui\widgets\genre_items_panel_test.dart` (insert this new `testWidgets` block right after the existing one, inside `main()`, before the closing `}`):
```dart
  testWidgets('loads and renders items for the selected genre', (
    tester,
  ) async {
    when(
      () => itemsApi.getItems(
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        genreIds: any(named: 'genreIds'),
        filters: any(named: 'filters'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        isFavorite: any(named: 'isFavorite'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
        imageTypeLimit: any(named: 'imageTypeLimit'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'i1', 'Name': 'Movie One', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 1,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenreItemsPanel(
            genreId: 'g1',
            genreName: 'Comedy',
            dataSource: dataSource,
            serverId: 'server1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Movie One'), findsOneWidget);
  });
```

- [ ] Step 7: Run test expecting failure
Run:
```
flutter test test/ui/widgets/genre_items_panel_test.dart
```
Expected output:
```
00:01 +1 -1: GenreItemsPanel loads and renders items for the selected genre [E]
  Expected: exactly one matching node in the widget tree
  Actual: _TextFinder:<zero widgets with text "Movie One" (ignoring offstage widgets)>
```

- [ ] Step 8: Write minimal implementation to load and render items
Replace `E:\Moonfin-Core\lib\ui\widgets\genre_items_panel.dart` in full:
```dart
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/services/row_data_source.dart';
import 'media_card.dart';

class GenreItemsPanel extends StatefulWidget {
  final String? genreId;
  final String? genreName;
  final RowDataSource dataSource;
  final String serverId;
  final List<String>? includeItemTypes;

  const GenreItemsPanel({
    super.key,
    required this.genreId,
    required this.genreName,
    required this.dataSource,
    required this.serverId,
    this.includeItemTypes,
  });

  @override
  State<GenreItemsPanel> createState() => _GenreItemsPanelState();
}

class _GenreItemsPanelState extends State<GenreItemsPanel> {
  List<AggregatedItem> _items = [];
  bool _isLoading = false;
  String? _loadedGenreId;

  @override
  void initState() {
    super.initState();
    _loadForCurrentGenre();
  }

  @override
  void didUpdateWidget(GenreItemsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.genreId != widget.genreId) {
      _loadForCurrentGenre();
    }
  }

  Future<void> _loadForCurrentGenre() async {
    final genreId = widget.genreId;
    if (genreId == null) {
      setState(() {
        _items = [];
        _loadedGenreId = null;
      });
      return;
    }

    setState(() => _isLoading = true);
    final row = await widget.dataSource.loadGenreRow(
      widget.serverId,
      genreId: genreId,
      title: widget.genreName ?? '',
      rowId: 'genrePanel_$genreId',
      includeItemTypes: widget.includeItemTypes,
    );
    if (!mounted || widget.genreId != genreId) return;
    setState(() {
      _items = row.items;
      _isLoading = false;
      _loadedGenreId = genreId;
    });
  }

  String? _imageUrl(AggregatedItem item) {
    return item.primaryImageTag != null
        ? widget.dataSource.imageApi.getPrimaryImageUrl(
            item.id,
            tag: item.primaryImageTag,
            maxWidth: 300,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.genreId == null) {
      return const SizedBox.shrink();
    }

    if (_isLoading && _loadedGenreId != widget.genreId) {
      return const Center(
        child: CircularProgressIndicator(color: AppColorScheme.accent),
      );
    }

    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2 / 3,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return MediaCard(
          title: item.name,
          imageUrl: _imageUrl(item),
          width: double.infinity,
        );
      },
    );
  }
}
```

- [ ] Step 9: Run test expecting pass
Run:
```
flutter test test/ui/widgets/genre_items_panel_test.dart
```
Expected output:
```
00:01 +2: All tests passed!
```

- [ ] Step 10: Commit
```
git add lib/ui/widgets/genre_items_panel.dart test/ui/widgets/genre_items_panel_test.dart
git commit -m "Load genre items into right panel via RowDataSource.loadGenreRow"
```

---

### Task 4: Restructure `AllGenresScreen` into two panes, remove artwork enrichment

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\browse\all_genres_screen.dart` (full rewrite of body/state, replacing lines 1-462 entirely)
- Test: `E:\Moonfin-Core\test\ui\screens\browse\all_genres_screen_test.dart`

- [ ] Step 1: Write the failing test for genre list loading without artwork calls
Create `E:\Moonfin-Core\test\ui\screens\browse\all_genres_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import 'package:moonfin/data/services/background_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/browse/all_genres_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late MockImageApi imageApi;

  setUp(() async {
    await GetIt.instance.reset();
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    imageApi = MockImageApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(imageApi);
    when(() => client.userId).thenReturn('user1');

    when(
      () => itemsApi.getGenres(
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'g1', 'Name': 'Comedy', 'MovieCount': 3},
          {'Id': 'g2', 'Name': 'Drama', 'MovieCount': 2},
        ],
        'TotalRecordCount': 2,
      },
    );

    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<RowDataSource>(RowDataSource(client));
    GetIt.instance.registerSingleton<BackgroundService>(BackgroundService());
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('renders genre names without requesting per-genre artwork', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AllGenresScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Comedy'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    verifyNever(
      () => itemsApi.getItems(
        genreIds: any(named: 'genreIds'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
        imageTypeLimit: any(named: 'imageTypeLimit'),
      ),
    );
  });
}
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/screens/browse/all_genres_screen_test.dart
```
Expected output (current screen still calls `getItems` per genre for artwork, and `RowDataSource`/`GetIt` wiring for the current implementation differs from what the test expects):
```
00:01 +0 -1: renders genre names without requesting per-genre artwork [E]
  Bad state: GetIt: Object/factory with type RowDataSource is not registered inside GetIt.
```

- [ ] Step 3: Rewrite `all_genres_screen.dart` to the two-pane layout with no artwork enrichment
Replace `E:\Moonfin-Core\lib\ui\screens\browse\all_genres_screen.dart` in full:
```dart
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../../data/services/background_service.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/utils/genre_browse_utils.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/focusable_toolbar_button.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/fullscreen_backdrop_switcher.dart';
import '../../widgets/genre_items_panel.dart';
import '../../widgets/genre_name_list_tile.dart';
import '../../../l10n/app_localizations.dart';

Color get _navyBackground => AppColorScheme.background;
const _horizontalPadding = 60.0;
const _kCompactBreakpoint = 600.0;
const _genresPageSize = 200;

bool _isCompact(BuildContext context) =>
    PlatformDetection.useMobileUi ||
    MediaQuery.sizeOf(context).width < _kCompactBreakpoint;

class AllGenresScreen extends StatefulWidget {
  const AllGenresScreen({super.key});

  @override
  State<AllGenresScreen> createState() => _AllGenresScreenState();
}

class _AllGenresScreenState extends State<AllGenresScreen> {
  final _client = GetIt.instance<MediaServerClient>();
  final _dataSource = GetIt.instance<RowDataSource>();
  final _backgroundService = GetIt.instance<BackgroundService>();
  StreamSubscription<String?>? _backgroundSub;
  String? _backdropUrl;
  bool _disposed = false;

  List<GenreListItem> _genres = [];
  bool _isLoading = true;
  GenreListItem? _selectedGenre;

  @override
  void initState() {
    super.initState();
    _backgroundSub = _backgroundService.backgroundStream.listen((url) {
      if (mounted) setState(() => _backdropUrl = url);
    });
    _backdropUrl = _backgroundService.currentUrl;
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _backgroundSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = <dynamic>[];
      var startIndex = 0;
      int? total;

      while (true) {
        final response = await _client.itemsApi.getGenres(
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          recursive: true,
          startIndex: startIndex,
          limit: _genresPageSize,
          fields: 'ItemCounts',
          includeItemTypes: kBrowsableGenreItemTypes,
        );

        total ??= response['TotalRecordCount'] as int?;
        final pageItems = (response['Items'] as List?) ?? const [];
        if (pageItems.isEmpty) break;
        items.addAll(pageItems);

        startIndex += pageItems.length;
        if (pageItems.length < _genresPageSize) break;
        if (total != null && startIndex >= total) break;
      }

      _genres = items
          .map((g) {
            final data = g as Map<String, dynamic>;
            final itemCount = browsableGenreCount(
              data,
              normalizedItemTypes: kBrowsableGenreItemTypes,
            );
            return (
              genre: GenreListItem(
                id: data['Id']?.toString() ?? '',
                name: data['Name'] as String? ?? '',
              ),
              itemCount: itemCount,
            );
          })
          .where((entry) => entry.itemCount > 0)
          .map((entry) => entry.genre)
          .toList();
    } catch (_) {}

    _isLoading = false;
    if (_genres.isNotEmpty) {
      _selectedGenre = _genres.first;
    }
    if (!_disposed && mounted) setState(() {});
  }

  void _selectGenre(GenreListItem genre) {
    if (_selectedGenre?.id == genre.id) return;
    setState(() => _selectedGenre = genre);
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final isMobile = _isCompact(context);
    final hasBackdrop = !isMobile && _backdropUrl != null;
    return Scaffold(
      backgroundColor: _navyBackground,
      body: Stack(
        children: [
          if (hasBackdrop)
            Positioned.fill(
              child: FullscreenBackdropSwitcher(
                imageUrl: _backdropUrl!,
                duration: BackgroundService.transitionDuration,
              ),
            ),
          Positioned.fill(
            child: Container(
              color: _navyBackground.withAlpha(hasBackdrop ? 140 : 191),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16.0 : _horizontalPadding,
                  isMobile ? MediaQuery.of(context).padding.top + 8 : 20.0,
                  isMobile ? 16.0 : _horizontalPadding,
                  8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FocusableToolbarButton(
                      icon: Icons.home,
                      size: 42,
                      iconSize: 24,
                      tooltip: AppLocalizations.of(context).home,
                      onTap: () => context.go(Destinations.home),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context).allGenres,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        color: AppColorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColorScheme.accent),
      );
    }

    if (_genres.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noGenresFound,
          style: TextStyle(
            color: AppColorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: _genres.length,
            itemBuilder: (context, index) {
              final genre = _genres[index];
              return GenreNameListTile(
                genre: genre,
                selected: _selectedGenre?.id == genre.id,
                onFocusChange: (focused) {
                  if (focused) _selectGenre(genre);
                },
                onTap: () {
                  _selectGenre(genre);
                  context.push(
                    Destinations.genre(genre.name, genreId: genre.id),
                  );
                },
              );
            },
          ),
        ),
        Expanded(
          child: GenreItemsPanel(
            genreId: _selectedGenre?.id,
            genreName: _selectedGenre?.name,
            dataSource: _dataSource,
            serverId: _client.deviceInfo.id ?? '',
          ),
        ),
      ],
    );
  }
}
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/screens/browse/all_genres_screen_test.dart
```
Expected output:
```
00:01 +1: All tests passed!
```

- [ ] Step 5: Commit
```
git add lib/ui/screens/browse/all_genres_screen.dart test/ui/screens/browse/all_genres_screen_test.dart
git commit -m "Restructure AllGenresScreen into two-pane list and live item panel"
```

---

### Task 5: Restructure `LibraryGenresScreen` into two panes, remove artwork enrichment, delete `genre_grid_card.dart`

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\browse\library_genres_screen.dart` (full rewrite of lines 1-539, keeping `_GenresHeader` unchanged)
- Delete: `E:\Moonfin-Core\lib\ui\widgets\genre_grid_card.dart`
- Test: `E:\Moonfin-Core\test\ui\screens\browse\library_genres_screen_test.dart`

- [ ] Step 1: Write the failing test for library-scoped genre list loading without artwork calls
Create `E:\Moonfin-Core\test\ui\screens\browse\library_genres_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import 'package:moonfin/data/services/background_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/browse/library_genres_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late MockImageApi imageApi;

  setUp(() async {
    await GetIt.instance.reset();
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    imageApi = MockImageApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(imageApi);
    when(() => client.userId).thenReturn('user1');

    when(() => itemsApi.getItem(any())).thenAnswer(
      (_) async => {
        'Id': 'lib1',
        'Name': 'Movies',
        'CollectionType': 'movies',
      },
    );

    when(
      () => itemsApi.getGenres(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'g1', 'Name': 'Action', 'MovieCount': 5},
        ],
        'TotalRecordCount': 1,
      },
    );

    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<RowDataSource>(RowDataSource(client));
    GetIt.instance.registerSingleton<BackgroundService>(BackgroundService());
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('renders library genre names without requesting per-genre artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LibraryGenresScreen(libraryId: 'lib1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action'), findsOneWidget);
    verifyNever(
      () => itemsApi.getItems(
        parentId: any(named: 'parentId'),
        genreIds: any(named: 'genreIds'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
        imageTypeLimit: any(named: 'imageTypeLimit'),
      ),
    );
  });
}
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/screens/browse/library_genres_screen_test.dart
```
Expected output:
```
00:01 +0 -1: renders library genre names without requesting per-genre artwork [E]
  Bad state: GetIt: Object/factory with type RowDataSource is not registered inside GetIt.
```

- [ ] Step 3: Rewrite `library_genres_screen.dart` to the two-pane layout with no artwork enrichment
Replace `E:\Moonfin-Core\lib\ui\screens\browse\library_genres_screen.dart` in full:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../../data/services/background_service.dart';
import '../../../data/services/row_data_source.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/fullscreen_backdrop_switcher.dart';
import '../../widgets/genre_items_panel.dart';
import '../../widgets/genre_name_list_tile.dart';
import '../../../l10n/app_localizations.dart';

Color get _navyBackground => AppColorScheme.background;
const _horizontalPadding = 60.0;
const _mobileHorizontalPadding = 16.0;
const _kCompactBreakpoint = 600.0;

bool _isCompact(BuildContext context) =>
    PlatformDetection.useMobileUi ||
    MediaQuery.sizeOf(context).width < _kCompactBreakpoint;

class LibraryGenresScreen extends StatefulWidget {
  final String libraryId;

  const LibraryGenresScreen({super.key, required this.libraryId});

  @override
  State<LibraryGenresScreen> createState() => _LibraryGenresScreenState();
}

class _LibraryGenresScreenState extends State<LibraryGenresScreen> {
  final _client = GetIt.instance<MediaServerClient>();
  final _dataSource = GetIt.instance<RowDataSource>();
  final _backgroundService = GetIt.instance<BackgroundService>();
  StreamSubscription<String?>? _backgroundSub;
  String? _backdropUrl;

  List<GenreListItem> _genres = [];
  bool _isLoading = true;
  String _libraryName = '';
  String? _collectionType;
  GenreListItem? _selectedGenre;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _backgroundSub = _backgroundService.backgroundStream.listen((url) {
      if (mounted) setState(() => _backdropUrl = url);
    });
    _backdropUrl = _backgroundService.currentUrl;
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _backgroundSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final parentData = await _client.itemsApi.getItem(widget.libraryId);
      _libraryName = parentData['Name'] as String? ?? '';
      _collectionType = (parentData['CollectionType'] as String?)
          ?.toLowerCase();

      final response = await _client.itemsApi.getGenres(
        parentId: widget.libraryId,
        userId: _client.userId,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        recursive: true,
        fields: 'ItemCounts',
      );

      final items = (response['Items'] as List?) ?? [];
      _genres = items
          .map((g) {
            final data = g as Map<String, dynamic>;
            final itemCount =
                data['ChildCount'] as int? ??
                (data['MovieCount'] as int? ?? 0) +
                    (data['SeriesCount'] as int? ?? 0) +
                    (data['AlbumCount'] as int? ?? 0) +
                    (data['SongCount'] as int? ?? 0) +
                    (data['ArtistCount'] as int? ?? 0) +
                    (data['MusicVideoCount'] as int? ?? 0);
            return (
              genre: GenreListItem(
                id: data['Id']?.toString() ?? '',
                name: data['Name'] as String? ?? '',
              ),
              itemCount: itemCount,
            );
          })
          .where((entry) {
            if (_collectionType == 'music') return true;
            return entry.itemCount > 0;
          })
          .map((entry) => entry.genre)
          .toList();
    } catch (_) {}

    _isLoading = false;
    if (_genres.isNotEmpty) {
      _selectedGenre = _genres.first;
    }
    if (!_disposed && mounted) setState(() {});
  }

  void _selectGenre(GenreListItem genre) {
    if (_selectedGenre?.id == genre.id) return;
    setState(() => _selectedGenre = genre);
  }

  String? get _includeType {
    switch (_collectionType) {
      case 'movies':
        return 'Movie';
      case 'tvshows':
        return 'Series';
      case 'music':
        return 'MusicAlbum';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final isMobile = _isCompact(context);
    final hasBackdrop = !isMobile && _backdropUrl != null;
    return Scaffold(
      backgroundColor: _navyBackground,
      body: Stack(
        children: [
          if (hasBackdrop)
            Positioned.fill(
              child: FullscreenBackdropSwitcher(
                imageUrl: _backdropUrl!,
                duration: BackgroundService.transitionDuration,
              ),
            ),
          Positioned.fill(
            child: Container(
              color: _navyBackground.withAlpha(hasBackdrop ? 140 : 191),
            ),
          ),
          Column(
            children: [
              _GenresHeader(
                libraryName: _libraryName,
                isMusic: _collectionType == 'music',
                onBack: () => PlatformDetection.isWeb
                    ? context.popOrHome()
                    : context.pop(),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColorScheme.accent),
      );
    }

    if (_genres.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noGenresFound,
          style: TextStyle(
            color: AppColorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final isMobile = _isCompact(context);
    final horizontalPadding = isMobile
        ? _mobileHorizontalPadding
        : _horizontalPadding;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 20, 0, 20),
            itemCount: _genres.length,
            itemBuilder: (context, index) {
              final genre = _genres[index];
              return GenreNameListTile(
                genre: genre,
                selected: _selectedGenre?.id == genre.id,
                onFocusChange: (focused) {
                  if (focused) _selectGenre(genre);
                },
                onTap: () {
                  _selectGenre(genre);
                  context.push(
                    Destinations.genre(
                      genre.name,
                      genreId: genre.id,
                      parentId: widget.libraryId,
                      includeType: _includeType,
                    ),
                  );
                },
              );
            },
          ),
        ),
        Expanded(
          child: GenreItemsPanel(
            genreId: _selectedGenre?.id,
            genreName: _selectedGenre?.name,
            dataSource: _dataSource,
            serverId: _client.deviceInfo.id ?? '',
            includeItemTypes: _includeType != null ? [_includeType!] : null,
          ),
        ),
      ],
    );
  }
}

class _GenresHeader extends StatelessWidget {
  final String libraryName;
  final bool isMusic;
  final VoidCallback onBack;

  const _GenresHeader({
    required this.libraryName,
    this.isMusic = false,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = _isCompact(context);
    final topPadding = isMobile ? MediaQuery.of(context).padding.top : 8.0;
    final horizontalPadding = isMobile
        ? _mobileHorizontalPadding
        : _horizontalPadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (PlatformDetection.isTV)
            IconButton(
              icon: Icon(
                Icons.home,
                color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                size: 22,
              ),
              onPressed: () => context.go(Destinations.home),
              tooltip: AppLocalizations.of(context).home,
            )
          else
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                size: 22,
              ),
              onPressed: onBack,
              tooltip: AppLocalizations.of(context).back,
            ),
          const SizedBox(width: 12),
          Text(
            isMusic
                ? AppLocalizations.of(context).genres
                : AppLocalizations.of(context).libraryGenresTitle(libraryName),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w300,
              color: AppColorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/screens/browse/library_genres_screen_test.dart
```
Expected output:
```
00:01 +1: All tests passed!
```

- [ ] Step 5: Delete the now-unused `GenreGridCard` widget
Run:
```
git rm lib/ui/widgets/genre_grid_card.dart
```

- [ ] Step 6: Confirm nothing else references the deleted widget
Run:
```
grep -rn "GenreGridCard\|GenreCardData" lib/ test/
```
Expected output:
```
(no output)
```

- [ ] Step 7: Commit
```
git add lib/ui/screens/browse/library_genres_screen.dart test/ui/screens/browse/library_genres_screen_test.dart
git commit -m "Restructure LibraryGenresScreen into two-pane list and delete GenreGridCard"
```

---

### Task 6: D-pad focus-moves-selection integration test

Files:
- Test: `E:\Moonfin-Core\test\ui\screens\browse\all_genres_screen_test.dart` (append a new test to the existing file from Task 4)

- [ ] Step 1: Write the failing test for focus-driven panel updates
Append to `E:\Moonfin-Core\test\ui\screens\browse\all_genres_screen_test.dart`, inside `main()` after the existing `testWidgets` block (add these imports at the top of the file alongside the existing ones: `import 'package:moonfin/ui/widgets/genre_name_list_tile.dart';`):
```dart
  testWidgets('moving dpad focus down the list updates the right panel', (
    tester,
  ) async {
    when(
      () => itemsApi.getItems(
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        genreIds: any(named: 'genreIds'),
        filters: any(named: 'filters'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        isFavorite: any(named: 'isFavorite'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
        imageTypeLimit: any(named: 'imageTypeLimit'),
      ),
    ).thenAnswer((invocation) async {
      final genreIds =
          invocation.namedArguments[#genreIds] as List<String>?;
      if (genreIds?.first == 'g2') {
        return {
          'Items': [
            {'Id': 'd1', 'Name': 'Drama Movie', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        };
      }
      return {
        'Items': [
          {'Id': 'c1', 'Name': 'Comedy Movie', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 1,
      };
    });

    await tester.pumpWidget(const MaterialApp(home: AllGenresScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Comedy Movie'), findsOneWidget);

    final dramaTileFinder = find.ancestor(
      of: find.text('Drama'),
      matching: find.byType(GenreNameListTile),
    );
    final dramaFocus = Focus.of(
      tester.element(find.descendant(
        of: dramaTileFinder,
        matching: find.byType(Focus).first,
      )),
    );
    dramaFocus.requestFocus();
    await tester.pumpAndSettle();

    expect(find.text('Drama Movie'), findsOneWidget);
  });
```

- [ ] Step 2: Run test expecting failure
Run:
```
flutter test test/ui/screens/browse/all_genres_screen_test.dart
```
Expected output (this fails before Task 4/5's `onFocusChange` wiring is exercised correctly against the mocked per-genre responses — since Task 4 already wires `onFocusChange` to `_selectGenre`, this specific failure mode is a stale panel showing "Comedy Movie" still, if focus traversal isn't reaching the tile's inner `Focus` node):
```
00:01 +2 -1: moving dpad focus down the list updates the right panel [E]
  Expected: exactly one matching node in the widget tree
  Actual: _TextFinder:<zero widgets with text "Drama Movie" (ignoring offstage widgets)>
```

- [ ] Step 3: Fix `GenreNameListTile` focus wiring if needed
Re-inspect `E:\Moonfin-Core\lib\ui\widgets\genre_name_list_tile.dart` from Task 2 — the `Focus` widget's `onFocusChange` callback already invokes `widget.onFocusChange?.call(focused)`, and `AllGenresScreen._buildBody` (Task 4) already passes `onFocusChange: (focused) { if (focused) _selectGenre(genre); }`. No production code change is required; if the test still fails, the fix is ensuring the test requests focus on the exact `Focus` node owned by `GenreNameListTile` rather than a `MaterialApp`-level focus scope. Adjust the test to locate the `Focus` widget via its `focusNode` through the `Focus` element directly:
Replace the focus-request portion of the test added in Step 1 with:
```dart
    await tester.pumpWidget(const MaterialApp(home: AllGenresScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Comedy Movie'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(find.text('Drama Movie'), findsOneWidget);
```
Add the required import at the top of the test file:
```dart
import 'package:flutter/services.dart';
```

- [ ] Step 4: Run test expecting pass
Run:
```
flutter test test/ui/screens/browse/all_genres_screen_test.dart
```
Expected output:
```
00:01 +3: All tests passed!
```

- [ ] Step 5: Commit
```
git add test/ui/screens/browse/all_genres_screen_test.dart
git commit -m "Add dpad focus-driven right panel update test for AllGenresScreen"
```

---

### Task 7: Full regression pass

Files:
- Test: all files touched above

- [ ] Step 1: Run the full genres-related test suite
Run:
```
flutter test test/ui/widgets/genre_name_list_tile_test.dart test/ui/widgets/genre_items_panel_test.dart test/ui/screens/browse/all_genres_screen_test.dart test/ui/screens/browse/library_genres_screen_test.dart
```
Expected output:
```
00:03 +9: All tests passed!
```

- [ ] Step 2: Run static analysis to catch unused-import or dead-code fallout from removing artwork enrichment
Run:
```
flutter analyze lib/ui/screens/browse/all_genres_screen.dart lib/ui/screens/browse/library_genres_screen.dart lib/ui/widgets/genre_name_list_tile.dart lib/ui/widgets/genre_items_panel.dart
```
Expected output:
```
No issues found!
```

- [ ] Step 3: Run the full project test suite to confirm no other file depended on the removed `GenreGridCard`/`GenreCardData`
Run:
```
flutter test
```
Expected output: all tests pass, with the same or greater total pass count as before this change (no failures attributable to `genre_grid_card.dart` removal).

- [ ] Step 4: Commit if analyze/test fixes were needed
Only run this if Steps 1-3 required code changes to pass:
```
git add -A
git commit -m "Fix regressions from genre browse two-pane restructuring"
```

---

### Verification

This plan implements spec section 7 ("Genres browsable list with live preview"): the grid-based, per-genre-image-enriched `AllGenresScreen`/`LibraryGenresScreen` are replaced with a two-pane layout (Tasks 4 and 5), the left pane is a scrollable text-only genre list with zero per-genre image fetches (verified by the `verifyNever(() => itemsApi.getItems(...))` assertions in Task 4 Step 1 and Task 5 Step 1, and by the full deletion of `_loadGenreArtwork`/`_loadGenreItems`/`_imageUrlFor`/`_backdropUrlFor` and of `lib/ui/widgets/genre_grid_card.dart` in Task 5), selecting a genre immediately loads its items into a right-hand panel using the existing `RowDataSource.loadGenreRow` → `_getItemsWithFallback(genreIds: ...)` query path already used elsewhere in the codebase (verified by Task 3's item-rendering test and Task 4/5's per-genre item panel wiring), and D-pad navigability is verified by Task 6's focus-traversal test confirming the right panel updates as keyboard/remote focus moves down the left list, not only on tap/select.