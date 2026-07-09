import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/viewmodels/library_view_view_model.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

AggregatedItem _item(String id) =>
    AggregatedItem(id: id, serverId: 'server-1', rawData: const {});

void main() {
  late _MockMediaServerClient client;
  late LibraryViewViewModel vm;

  setUp(() {
    client = _MockMediaServerClient();
    vm = LibraryViewViewModel(
      libraryId: 'library-1',
      dataSource: RowDataSource(client),
      client: client,
    );
  });

  tearDown(() {
    vm.dispose();
  });

  test('setFocusedItem updates focusedItemNotifier', () {
    vm.setFocusedItem(_item('item-1'));
    expect(vm.focusedItemNotifier.value?.id, 'item-1');
  });

  test(
    'setFocusedItem does not notify the ViewModel\'s own listeners - a pure '
    'focus change must not force the whole screen to rebuild',
    () {
      var notifyCount = 0;
      vm.addListener(() => notifyCount++);

      vm.setFocusedItem(_item('item-1'));
      vm.setFocusedItem(_item('item-2'));
      vm.setFocusedItem(_item('item-3'));

      expect(notifyCount, 0);
      expect(vm.focusedItemNotifier.value?.id, 'item-3');
    },
  );

  test('re-focusing the same item is a no-op', () {
    var notifierNotifyCount = 0;
    vm.focusedItemNotifier.addListener(() => notifierNotifyCount++);

    final item = _item('item-1');
    vm.setFocusedItem(item);
    vm.setFocusedItem(item);

    expect(notifierNotifyCount, 1);
  });

  test('focusing null clears the focused item', () {
    vm.setFocusedItem(_item('item-1'));
    vm.setFocusedItem(null);
    expect(vm.focusedItemNotifier.value, isNull);
  });
}
