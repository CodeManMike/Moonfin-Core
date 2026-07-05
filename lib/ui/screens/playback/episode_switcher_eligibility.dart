import '../../../data/models/aggregated_item.dart';

/// Whether the in-player episode/season switcher button should be shown
/// for the given queue item (an [AggregatedItem], a raw offline map, or an
/// offline file path string — see `VideoPlayerScreen._queue`).
bool canShowEpisodeSwitcher(dynamic queueItem) {
  if (queueItem is! AggregatedItem) return false;
  if (queueItem.type != 'Episode') return false;
  final seriesId = queueItem.seriesId;
  return seriesId != null && seriesId.isNotEmpty;
}
