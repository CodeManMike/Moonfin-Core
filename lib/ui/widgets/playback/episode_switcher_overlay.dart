import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../l10n/app_localizations.dart';
import '../adaptive/adaptive_glass.dart';

/// Full-player overlay letting the user pick any episode in any season
/// without leaving playback. Modeled on [NextUpOverlay]'s glass-panel
/// pattern (see `next_up_overlay.dart`).
class EpisodeSwitcherOverlay extends StatefulWidget {
  final List<AggregatedItem> seasons;
  final String? initialSeasonId;
  final String? currentEpisodeId;
  final List<AggregatedItem> Function(String seasonId) episodesForSeason;
  final String? Function(AggregatedItem episode) imageUrlForEpisode;
  final void Function(AggregatedItem episode, List<AggregatedItem> seasonEpisodes)
      onEpisodeSelected;
  final VoidCallback onDismiss;

  const EpisodeSwitcherOverlay({
    super.key,
    required this.seasons,
    required this.initialSeasonId,
    required this.currentEpisodeId,
    required this.episodesForSeason,
    required this.imageUrlForEpisode,
    required this.onEpisodeSelected,
    required this.onDismiss,
  });

  @override
  State<EpisodeSwitcherOverlay> createState() => _EpisodeSwitcherOverlayState();
}

class _EpisodeSwitcherOverlayState extends State<EpisodeSwitcherOverlay> {
  late String? _selectedSeasonId = widget.initialSeasonId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedSeasonId = _selectedSeasonId ??
        (widget.seasons.isNotEmpty ? widget.seasons.first.id : null);
    final episodes = selectedSeasonId != null
        ? widget.episodesForSeason(selectedSeasonId)
        : const <AggregatedItem>[];

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          color: Colors.black54,
          child: GestureDetector(
            onTap: () {},
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.circular(18),
                  ),
                  child: adaptiveGlass(
                    cornerRadius: 18,
                    blur: 18,
                    fallbackColor: AppColorScheme.surface.withValues(alpha: 0.9),
                    tint: AppColorScheme.surface.withValues(alpha: 0.3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                          child: Row(
                            children: [
                              Text(
                                l10n.episodes,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: widget.onDismiss,
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                                tooltip: l10n.close,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: widget.seasons.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final season = widget.seasons[index];
                              final isSelected = season.id == selectedSeasonId;
                              return ChoiceChip(
                                label: Text(season.name),
                                selected: isSelected,
                                onSelected: (_) {
                                  setState(() => _selectedSeasonId = season.id);
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 16 / 10,
                            ),
                            itemCount: episodes.length,
                            itemBuilder: (context, index) {
                              final episode = episodes[index];
                              final isCurrent = episode.id == widget.currentEpisodeId;
                              final imageUrl = widget.imageUrlForEpisode(episode);
                              return _EpisodeTile(
                                episode: episode,
                                imageUrl: imageUrl,
                                isCurrent: isCurrent,
                                onTap: () =>
                                    widget.onEpisodeSelected(episode, episodes),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.imageUrl,
    required this.isCurrent,
    required this.onTap,
  });

  final AggregatedItem episode;
  final String? imageUrl;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.circular(10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadius.circular(10),
          border: isCurrent
              ? Border.all(color: AppColorScheme.accent, width: 2)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover)
            else
              Container(color: AppColorScheme.surfaceVariant),
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                    stops: [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                episode.indexNumber != null
                    ? '${episode.indexNumber}. ${episode.name}'
                    : episode.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
