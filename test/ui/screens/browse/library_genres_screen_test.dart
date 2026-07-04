import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart' hide ImageType;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/services/background_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/browse/library_genres_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;
  late MockImageApi imageApi;

  setUp(() async {
    await GetIt.instance.reset();
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    imageApi = MockImageApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(imageApi);
    when(() => client.userId).thenReturn('user1');
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'device1',
        name: 'Test Device',
        appName: 'Moonfin',
        appVersion: '1.0.0',
      ),
    );

    when(() => itemsApi.getItem(any())).thenAnswer(
      (_) async => {
        'Id': 'lib1',
        'Name': 'Movies',
        'CollectionType': 'movies',
      },
    );

    when(
      () => itemsApi.getGenres(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'g1', 'Name': 'Action', 'MovieCount': 5},
        ],
        'TotalRecordCount': 1,
      },
    );

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
    ).thenAnswer((_) async => {'Items': [], 'TotalRecordCount': 0});

    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<RowDataSource>(RowDataSource(client));
    GetIt.instance.registerSingleton<BackgroundService>(BackgroundService());
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('renders library genre names without requesting per-genre artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryGenresScreen(libraryId: 'lib1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action'), findsOneWidget);

    // The old per-genre artwork enrichment loop called getItems once for
    // *every* genre in the list to fetch preview images. The new right-hand
    // GenreItemsPanel calls getItems at most once, only for the single
    // genre that is currently selected/focused - never once per genre.
    verify(
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
    ).called(lessThanOrEqualTo(1));
  });
}
