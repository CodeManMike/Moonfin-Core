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
            serverId: _client.deviceInfo.id,
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
