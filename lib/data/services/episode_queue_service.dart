import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';

/// Shared season/episode fetch helper. Both `ItemDetailViewModel` and the
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
