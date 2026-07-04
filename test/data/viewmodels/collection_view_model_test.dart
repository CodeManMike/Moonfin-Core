import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/viewmodels/collection_view_model.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('https://example.test');
  });

  test('loadCollection fetches items with parentId and sets ready state', () async {
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 0,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        });

    final vm = CollectionViewModel(client);
    await vm.loadCollection('col-1');

    expect(vm.state, CollectionState.ready);
    expect(vm.items.length, 1);
    expect(vm.items.first.id, 'item-1');
    expect(vm.hasMore, false);
  });

  test('loadMore appends items and stops when totalCount reached', () async {
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 0,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 2,
        });
    when(() => itemsApi.getItems(
          parentId: 'col-1',
          recursive: false,
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: 1,
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: true,
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-2', 'Name': 'Movie Two', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 2,
        });

    final vm = CollectionViewModel(client);
    await vm.loadCollection('col-1');
    expect(vm.hasMore, true);

    await vm.loadMore();

    expect(vm.items.length, 2);
    expect(vm.items.last.id, 'item-2');
    expect(vm.hasMore, false);
  });
}
