import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart' hide ImageType;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/viewmodels/library_browse_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

AggregatedItem _item(String id) =>
    AggregatedItem(id: id, serverId: 'server-1', rawData: const {});

void main() {
  late _MockMediaServerClient client;
  late UserPreferences prefs;
  late LibraryBrowseViewModel vm;

  setUp(() async {
    client = _MockMediaServerClient();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    vm = LibraryBrowseViewModel(
      libraryId: 'library-1',
      client: client,
      prefs: prefs,
      mdbListRepository: MdbListRepository(client),
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
