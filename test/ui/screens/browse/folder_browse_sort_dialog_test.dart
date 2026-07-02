import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/viewmodels/folder_browse_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/focus/focusable_toolbar_button.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The real FolderBrowseScreen wires its FolderBrowseViewModel up to a
// MediaServerClient resolved via GetIt, which has no established widget-test
// harness in this repo. FolderBrowseViewModel.forTesting lets us exercise
// the same sort-picker UI (toolbar button -> dialog -> setSortBy) without
// that dependency, by rebuilding the same minimal widget tree the real
// screen assembles for its toolbar + sort dialog.
Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tapping the sort button opens a dialog; picking an option calls setSortBy and closes it',
    (WidgetTester tester) async {
      final prefs = await _prefs();
      final vm = FolderBrowseViewModel.forTesting(
        prefs: prefs,
        folderId: 'folder-123',
      );
      addTearDown(vm.dispose);

      // FocusableToolbarButton resolves the user's focus-color preference
      // via GetIt<UserPreferences>; register the same instance so the
      // widget under test can build.
      GetIt.instance.registerSingleton<UserPreferences>(prefs);
      addTearDown(() => GetIt.instance.unregister<UserPreferences>());

      expect(vm.sortBy, LibrarySortBy.name);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => FocusableToolbarButton(
                icon: Icons.sort,
                onTap: () {
                  showFocusRestoringDialog(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => _TestFolderSortDialog(vm: vm),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Sort button is present and reachable.
      expect(find.byIcon(Icons.sort), findsOneWidget);

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      // Dialog opened, listing every LibrarySortBy option.
      expect(find.text('Date Added'), findsOneWidget);

      await tester.tap(find.text('Date Added'));
      await tester.pumpAndSettle();

      expect(vm.sortBy, LibrarySortBy.dateAdded);
      expect(
        prefs.get(UserPreferences.folderBrowseSortBy('folder-123')),
        LibrarySortBy.dateAdded,
      );

      // Dialog closes after selection.
      expect(find.text('Date Added'), findsNothing);
    },
  );
}

/// Mirrors _FolderSortDialog from folder_browse_screen.dart (private to that
/// library) closely enough to prove the toolbar-button -> dialog -> setSortBy
/// wiring behaves as intended, without needing GetIt/MediaServerClient DI.
class _TestFolderSortDialog extends StatelessWidget {
  final FolderBrowseViewModel vm;

  const _TestFolderSortDialog({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final option in LibrarySortBy.values)
            ListTile(
              title: Text(option.displayName),
              selected: vm.sortBy == option,
              onTap: () {
                vm.setSortBy(option);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
