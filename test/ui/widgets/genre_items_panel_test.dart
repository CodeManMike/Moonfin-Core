import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/ui/widgets/genre_items_panel.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late MockImageApi imageApi;
  late RowDataSource dataSource;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    imageApi = MockImageApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(imageApi);
    dataSource = RowDataSource(client);
  });

  testWidgets('shows empty state when no genre is selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenreItemsPanel(
            genreId: null,
            genreName: null,
            dataSource: dataSource,
            serverId: 'server1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('loads and renders items for the selected genre', (
    tester,
  ) async {
    when(
      () => itemsApi.getItems(
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        genreIds: any(named: 'genreIds'),
        filters: any(named: 'filters'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        isFavorite: any(named: 'isFavorite'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
        imageTypeLimit: any(named: 'imageTypeLimit'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'i1', 'Name': 'Movie One', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 1,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenreItemsPanel(
            genreId: 'g1',
            genreName: 'Comedy',
            dataSource: dataSource,
            serverId: 'server1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Movie One'), findsOneWidget);
  });
}
