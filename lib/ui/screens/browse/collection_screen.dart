import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/viewmodels/collection_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';

class CollectionScreen extends StatefulWidget {
  final String collectionId;
  final String? serverId;

  const CollectionScreen({
    super.key,
    required this.collectionId,
    this.serverId,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late final CollectionViewModel _vm;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final serverId = widget.serverId;
    final client = serverId != null && serverId.isNotEmpty
        ? GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                serverId,
              ) ??
              GetIt.instance<MediaServerClient>()
        : GetIt.instance<MediaServerClient>();
    _vm = CollectionViewModel(client);
    _vm.addListener(_onChanged);
    _scrollController.addListener(_onScroll);
    _vm.loadCollection(widget.collectionId);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _vm.loadMore();
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _imageUrl(AggregatedItem item, {int? maxWidth}) {
    final api = _vm.imageApi;
    final primaryTag = item.primaryImageTag;
    if (primaryTag != null) {
      return api.getPrimaryImageUrl(item.id, maxWidth: maxWidth, tag: primaryTag);
    }
    if (item.backdropImageTags.isNotEmpty) {
      return api.getBackdropImageUrl(
        item.id,
        maxWidth: maxWidth,
        tag: item.backdropImageTags.first,
      );
    }
    return null;
  }

  void _onItemTap(AggregatedItem item) {
    context.push(
      Destinations.itemOrPhoto(
        item.id,
        serverId: item.serverId,
        type: item.type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        showBackButton: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_vm.state) {
      case CollectionState.loading:
        return const Center(child: CircularProgressIndicator());
      case CollectionState.error:
        return Center(
          child: Text(
            AppLocalizations.of(context).failedToLoad,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready when _vm.items.isEmpty:
        return Center(
          child: Text(
            AppLocalizations.of(context).collectionPlaceholder,
            style: TextStyle(color: AppColorScheme.onSurface.withAlpha(179)),
          ),
        );
      case CollectionState.ready:
        return _buildGrid();
    }
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const spacing = 12.0;
        const targetCardWidth = 170.0;

        final crossAxisCount =
            ((constraints.maxWidth - horizontalPadding * 2 + spacing) /
                    (targetCardWidth + spacing))
                .floor()
                .clamp(2, 10);

        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                (crossAxisCount - 1) * spacing) /
            crossAxisCount;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            32,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: 16,
            children: [
              for (final item in _vm.items)
                SizedBox(
                  width: cardWidth,
                  child: _CollectionGridCard(
                    item: item,
                    imageUrl: _imageUrl(item, maxWidth: cardWidth.toInt()),
                    icon: MediaCard.iconForType(item.type),
                    onTap: () => _onItemTap(item),
                  ),
                ),
              if (_vm.hasMore)
                SizedBox(
                  width: cardWidth,
                  child: const AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CollectionGridCard extends StatelessWidget {
  final AggregatedItem item;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  const _CollectionGridCard({
    required this.item,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ar = MediaCard.aspectRatioForType(item.type);

    return InkWell(
      borderRadius: AppRadius.circular(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: ar,
            child: ClipRRect(
              borderRadius: AppRadius.circular(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColorScheme.onSurface.withAlpha(20),
                  border: Border.fromBorderSide(
                    ThemeRegistry.active.borders.chipBorder,
                  ),
                ),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Center(
                          child: Icon(
                            icon,
                            color: AppColorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            size: 30,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          icon,
                          color: AppColorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          size: 30,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            style: TextStyle(color: AppColorScheme.onSurface, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
