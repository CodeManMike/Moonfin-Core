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

/// Whether [target] belongs to the same season as the live queue's
/// [currentQueueItem]. Used to decide between a cheap `jumpTo` within the
/// existing queue versus a full requeue via `playItems` when the user picks
/// an episode from the switcher overlay.
bool isSameSeasonAsCurrentQueue(AggregatedItem target, dynamic currentQueueItem) {
  if (currentQueueItem is! AggregatedItem) return false;
  final targetSeasonId = target.seasonId;
  final currentSeasonId = currentQueueItem.seasonId;
  if (targetSeasonId == null || currentSeasonId == null) return false;
  return targetSeasonId == currentSeasonId;
}
