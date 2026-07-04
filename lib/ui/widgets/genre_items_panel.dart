import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/services/row_data_source.dart';
import 'media_card.dart';

class GenreItemsPanel extends StatefulWidget {
  final String? genreId;
  final String? genreName;
  final RowDataSource dataSource;
  final String serverId;
  final List<String>? includeItemTypes;

  const GenreItemsPanel({
    super.key,
    required this.genreId,
    required this.genreName,
    required this.dataSource,
    required this.serverId,
    this.includeItemTypes,
  });

  @override
  State<GenreItemsPanel> createState() => _GenreItemsPanelState();
}

class _GenreItemsPanelState extends State<GenreItemsPanel> {
  List<AggregatedItem> _items = [];
  bool _isLoading = false;
  String? _loadedGenreId;

  @override
  void initState() {
    super.initState();
    _loadForCurrentGenre();
  }

  @override
  void didUpdateWidget(GenreItemsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.genreId != widget.genreId) {
      _loadForCurrentGenre();
    }
  }

  Future<void> _loadForCurrentGenre() async {
    final genreId = widget.genreId;
    if (genreId == null) {
      setState(() {
        _items = [];
        _loadedGenreId = null;
      });
      return;
    }

    setState(() => _isLoading = true);
    final row = await widget.dataSource.loadGenreRow(
      widget.serverId,
      genreId: genreId,
      title: widget.genreName ?? '',
      rowId: 'genrePanel_$genreId',
      includeItemTypes: widget.includeItemTypes,
    );
    if (!mounted || widget.genreId != genreId) return;
    setState(() {
      _items = row.items;
      _isLoading = false;
      _loadedGenreId = genreId;
    });
  }

  String? _imageUrl(AggregatedItem item) {
    return item.primaryImageTag != null
        ? widget.dataSource.imageApi.getPrimaryImageUrl(
            item.id,
            tag: item.primaryImageTag,
            maxWidth: 300,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.genreId == null) {
      return const SizedBox.shrink();
    }

    if (_isLoading && _loadedGenreId != widget.genreId) {
      return Center(
        child: CircularProgressIndicator(color: AppColorScheme.accent),
      );
    }

    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }

    const crossAxisCount = 5;
    const spacing = 16.0;
    const padding = 20.0;
    const posterAspectRatio = 2 / 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - padding * 2 - (crossAxisCount - 1) * spacing) /
            crossAxisCount;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final titleHeight = 24.0 * textScale;
        final childAspectRatio =
            cellWidth / (cellWidth / posterAspectRatio + titleHeight);

        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return MediaCard(
              title: item.name,
              imageUrl: _imageUrl(item),
              width: double.infinity,
              aspectRatio: posterAspectRatio,
            );
          },
        );
      },
    );
  }
}
