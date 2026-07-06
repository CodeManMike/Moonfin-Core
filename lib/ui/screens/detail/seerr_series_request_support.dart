import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';

/// Resolves a Jellyfin library series to its Seerr/TMDB identity via its
/// TVDB provider id, so a "Request on Seerr" affordance can be shown on the
/// series' own Jellyfin detail screen. Returns null (never throws) when
/// Seerr is unavailable, the series has no TVDB id, or the lookup fails, so
/// callers can hide the affordance instead of surfacing an error.
Future<SeerrTvDetails?> resolveSeriesForSeerrRequest({
  required AggregatedItem item,
  required bool seerrAvailable,
  required SeerrRepository repository,
}) async {
  if (item.type != 'Series') return null;
  if (!seerrAvailable) return null;

  final tvdbRaw = item.providerIds['Tvdb'];
  final tvdbId = tvdbRaw != null ? int.tryParse(tvdbRaw) : null;
  if (tvdbId == null) return null;

  return repository.resolveTvdbToSeerrTv(tvdbId);
}
