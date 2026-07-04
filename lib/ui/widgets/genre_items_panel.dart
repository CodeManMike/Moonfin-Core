import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/services/row_data_source.dart';

class GenreItemsPanel extends StatelessWidget {
  final String? genreId;
  final String? genreName;
  final RowDataSource dataSource;
  final String serverId;

  const GenreItemsPanel({
    super.key,
    required this.genreId,
    required this.genreName,
    required this.dataSource,
    required this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    if (genreId == null) {
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }
}
