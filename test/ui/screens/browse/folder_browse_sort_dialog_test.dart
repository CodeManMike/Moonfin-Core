import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/browse/folder_browse_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}
class MockImageApi extends Mock implements ImageApi {}
class MockUserViewsApi extends Mock implements UserViewsApi {}
class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late UserPreferences prefs;

  setUp(() async {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(MockImageApi());
    when(() => client.baseUrl).thenReturn('https://example.test');

    when(() => itemsApi.getItem(any(), mediaSourceId: any(named: 'mediaSourceId')))
        .thenAnswer((_) async => {'Name': 'Folder', 'Id': 'folder-123'});
    when(() => itemsApi.getItems(
          parentId: any(named: 'parentId'),
          recursive: any(named: 'recursive'),
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: any(named: 'startIndex'),
          limit: any(named: 'limit'),
          fields: any(named: 'fields'),
          enableImageTypes: any(named: 'enableImageTypes'),
          imageTypeLimit: any(named: 'imageTypeLimit'),
          enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        )).thenAnswer((_) async => {
          'Items': [
            {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        });

    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      GetIt.instance.unregister<MediaServerClient>();
    }
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
      GetIt.instance.unregister<MediaServerClientFactory>();
    }
    GetIt.instance.registerSingleton<MediaServerClientFactory>(
      MediaServerClientFactory(
        deviceInfo: const DeviceInfo(
          id: 'test',
          name: 'test',
          appName: 'test',
          appVersion: '1.0',
        ),
      ),
    );

    if (GetIt.instance.isRegistered<UserPreferences>()) {
      GetIt.instance.unregister<UserPreferences>();
    }
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);

    if (GetIt.instance.isRegistered<PlaybackManager>()) {
      GetIt.instance.unregister<PlaybackManager>();
    }
    GetIt.instance.registerSingleton<PlaybackManager>(PlaybackManager());

    if (GetIt.instance.isRegistered<UserRepository>()) {
      GetIt.instance.unregister<UserRepository>();
    }
    GetIt.instance.registerSingleton<UserRepository>(UserRepository());

    final userViewsApi = MockUserViewsApi();
    when(() => userViewsApi.getUserViews())
        .thenAnswer((_) async => {'Items': []});
    when(() => client.userViewsApi).thenReturn(userViewsApi);
    if (GetIt.instance.isRegistered<UserViewsRepository>()) {
      GetIt.instance.unregister<UserViewsRepository>();
    }
    GetIt.instance.registerSingleton<UserViewsRepository>(
      UserViewsRepository(client),
    );

    if (GetIt.instance.isRegistered<PluginSyncService>()) {
      GetIt.instance.unregister<PluginSyncService>();
    }
    GetIt.instance.registerSingleton<PluginSyncService>(
      PluginSyncService(GetIt.instance<UserPreferences>(), store),
    );

    final sessionRepository = MockSessionRepository();
    when(() => sessionRepository.activeUserId).thenReturn('user-1');
    if (GetIt.instance.isRegistered<SeerrPreferences>()) {
      GetIt.instance.unregister<SeerrPreferences>();
    }
    GetIt.instance.registerSingleton<SeerrPreferences>(
      SeerrPreferences(store, sessionRepository),
    );
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets(
    'tapping the sort button opens the real dialog; picking an option calls '
    'setSortBy, persists the preference, and closes the dialog',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FolderBrowseScreen(folderId: 'folder-123'),
        ),
      );
      await tester.pumpAndSettle();

      // Sort button is present and reachable.
      expect(find.byIcon(Icons.sort), findsOneWidget);

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      // The real _FolderSortDialog opened, listing every LibrarySortBy option.
      expect(find.text('Date Added'), findsOneWidget);

      await tester.tap(find.text('Date Added'));
      await tester.pumpAndSettle();

      expect(
        prefs.get(UserPreferences.folderBrowseSortBy('folder-123')),
        LibrarySortBy.dateAdded,
      );

      // The real dialog closes after selection.
      expect(find.text('Date Added'), findsNothing);

      // setSortBy triggered a reload sorted by the new option.
      final verification = verify(() => itemsApi.getItems(
            parentId: any(named: 'parentId'),
            recursive: any(named: 'recursive'),
            sortBy: captureAny(named: 'sortBy'),
            sortOrder: any(named: 'sortOrder'),
            startIndex: any(named: 'startIndex'),
            limit: any(named: 'limit'),
            fields: any(named: 'fields'),
            enableImageTypes: any(named: 'enableImageTypes'),
            imageTypeLimit: any(named: 'imageTypeLimit'),
            enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
          ));
      expect(
        verification.captured.last,
        'IsFolder,${LibrarySortBy.dateAdded.apiValue}',
      );
    },
  );
}
