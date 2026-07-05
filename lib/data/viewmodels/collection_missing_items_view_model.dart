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
