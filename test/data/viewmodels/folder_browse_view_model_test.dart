import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/viewmodels/folder_browse_view_model.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setSortBy persists the chosen sort under the folder-scoped preference key', () async {
    final prefs = await _prefs();
    final vm = FolderBrowseViewModel.forTesting(prefs: prefs, folderId: 'folder-123');

    expect(vm.sortBy, LibrarySortBy.name);

    await vm.setSortBy(LibrarySortBy.dateAdded);

    expect(vm.sortBy, LibrarySortBy.dateAdded);
    expect(
      prefs.get(UserPreferences.folderBrowseSortBy('folder-123')),
      LibrarySortBy.dateAdded,
    );
  });

  test('a previously persisted sort choice is read back on construction', () async {
    final prefs = await _prefs();
    await prefs.set(
      UserPreferences.folderBrowseSortBy('folder-456'),
      LibrarySortBy.rating,
    );

    final vm = FolderBrowseViewModel.forTesting(prefs: prefs, folderId: 'folder-456');

    expect(vm.sortBy, LibrarySortBy.rating);
  });
}
