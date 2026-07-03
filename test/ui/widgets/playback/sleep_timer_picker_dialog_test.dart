import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/playback/sleep_timer_picker_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

// TrackSelectorDialog's row widget resolves the user's focus-color
// preference via GetIt<UserPreferences>; register a real instance backed by
// mock SharedPreferences so the dialog can build, mirroring the pattern in
// test/ui/screens/browse/folder_browse_sort_dialog_test.dart.
Future<UserPreferences> _registerPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  final store = PreferenceStore();
  await store.init();
  final prefs = UserPreferences(store);
  GetIt.instance.registerSingleton<UserPreferences>(prefs);
  return prefs;
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required bool isEpisodicContent,
}) async {
  await _registerPrefs();
  addTearDown(() => GetIt.instance.unregister<UserPreferences>());

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            SleepTimerPickerDialog.show(
              context,
              isEpisodicContent: isEpisodicContent,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows fixed duration options',
    (tester) async {
      await _pumpDialog(tester, isEpisodicContent: false);

      expect(find.text('In 15 minutes'), findsOneWidget);
      expect(find.text('In 30 minutes'), findsOneWidget);
      expect(find.text('In 45 minutes'), findsOneWidget);
      expect(find.text('In 60 minutes'), findsOneWidget);
    },
  );

  testWidgets(
    'returns a duration-type result when a duration option is tapped',
    (tester) async {
      await _registerPrefs();
      addTearDown(() => GetIt.instance.unregister<UserPreferences>());

      SleepTimerResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SleepTimerPickerDialog.show(
                  context,
                  isEpisodicContent: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('In 30 minutes'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, SleepTimerType.duration);
      expect(result!.value, 30);
    },
  );

  testWidgets(
    'shows episode-count options only for episodic content',
    (tester) async {
      await _pumpDialog(tester, isEpisodicContent: true);

      expect(find.text('After this episode'), findsOneWidget);
      expect(find.text('After 2 more episodes'), findsOneWidget);
    },
  );

  testWidgets(
    'hides episode-count options for non-episodic content',
    (tester) async {
      await _pumpDialog(tester, isEpisodicContent: false);

      expect(find.text('After this episode'), findsNothing);
    },
  );
}
