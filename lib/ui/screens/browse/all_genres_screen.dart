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
            serverId: _client.deviceInfo.id,
          ),
        ),
      ],
    );
  }
}
