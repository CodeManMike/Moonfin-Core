import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/models/home_row.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
  });

  test('loadAcdbCollections queries BoxSet items filtered by the given tag', () async {
    when(() => itemsApi.getItems(
          parentId: null,
          includeItemTypes: const ['BoxSet'],
          excludeItemTypes: null,
          genreIds: null,
          filters: null,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          recursive: true,
          startIndex: null,
          limit: any(named: 'limit'),
          isFavorite: null,
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          tags: const ['acdb'],
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'box-1', 'Name': 'ACdb Curated Set', 'Type': 'BoxSet'},
          ],
          'TotalRecordCount': 1,
        });

    final source = RowDataSource(client);
    final row = await source.loadAcdbCollections('server-1', tag: 'acdb');

    expect(row.id, 'acdbCollections');
    expect(row.rowType, HomeRowType.collections);
    expect(row.items.length, 1);
    expect(row.items.first.id, 'box-1');
  });

  test('acdbCollectionsTag constant matches the documented ACdb.tv tag convention', () {
    expect(RowDataSource.acdbCollectionsTag, 'acdb');
  });
}
