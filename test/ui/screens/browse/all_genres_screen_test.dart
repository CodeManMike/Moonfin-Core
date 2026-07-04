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
import 'package:moonfin/ui/screens/browse/all_genres_screen.dart';

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

    when(
      () => itemsApi.getGenres(
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'g1', 'Name': 'Comedy', 'MovieCount': 3},
          {'Id': 'g2', 'Name': 'Drama', 'MovieCount': 2},
        ],
        'TotalRecordCount': 2,
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

  testWidgets('renders genre names without requesting per-genre artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AllGenresScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comedy'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);

    // The old per-genre artwork enrichment loop called getItems once for
    // *every* genre in the list to fetch preview images. The new right-hand
    // GenreItemsPanel calls getItems at most once, only for the single
    // genre that is currently selected/focused - never once per genre in
    // the list.
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
