import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/browse/collection_screen.dart';

class MockMediaServerClient extends Mock implements MediaServerClient {}
class MockItemsApi extends Mock implements ItemsApi {}
class MockImageApi extends Mock implements ImageApi {}

void main() {
  late MockMediaServerClient client;
  late MockItemsApi itemsApi;

  setUp(() {
    client = MockMediaServerClient();
    itemsApi = MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(MockImageApi());
    when(() => client.baseUrl).thenReturn('https://example.test');
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
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('renders fetched collection item name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CollectionScreen(collectionId: 'col-1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Movie One'), findsOneWidget);
  });
}
