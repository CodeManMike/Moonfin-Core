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
