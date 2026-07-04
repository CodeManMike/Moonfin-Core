import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/preference/home_section_config.dart';

import 'package:dio/dio.dart' as dio_pkg;

class MockMediaServerClient extends Mock implements MediaServerClient {}

class MockItemsApi extends Mock implements ItemsApi {}

void main() {
  group('RowDataSource.loadDynamicSection with homeScreenSections source', () {
    late MockMediaServerClient client;
    late MockItemsApi itemsApi;
    late RowDataSource dataSource;

    setUp(() {
      client = MockMediaServerClient();
      itemsApi = MockItemsApi();
      when(() => client.itemsApi).thenReturn(itemsApi);
      dataSource = RowDataSource(client);
    });

    test('fetches HSS section items and parses them via the standard item pipeline', () async {
      when(() => itemsApi.getHomeScreenSectionItems(
            'BecauseYouWatched',
            additionalData: null,
          )).thenAnswer((_) async => {
            'Items': [
              {'Id': 'item-1', 'Name': 'Movie One', 'Type': 'Movie'},
              {'Id': 'item-2', 'Name': 'Movie Two', 'Type': 'Movie'},
            ],
            'TotalRecordCount': 2,
          });

      final row = await dataSource.loadDynamicSection(
        rowId: 'pluginDynamic:homeScreenSections:server-1:BecauseYouWatched:',
        section: 'BecauseYouWatched',
        title: 'Because You Watched',
        serverId: 'server-1',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      expect(row.rowType, HomeRowType.pluginDynamic);
      expect(row.items, hasLength(2));
      expect(row.items[0].id, 'item-1');
      expect(row.items[0].serverId, 'server-1');
      expect(row.title, 'Because You Watched');
    });

    test('returns an empty row when HSS is not installed (404)', () async {
      final requestOptions = RequestOptionsStub('/HomeScreen/Section/LatestMovies');
      when(() => itemsApi.getHomeScreenSectionItems(
            'LatestMovies',
            additionalData: null,
          )).thenThrow(DioExceptionStub(requestOptions, 404));

      final row = await dataSource.loadDynamicSection(
        rowId: 'pluginDynamic:homeScreenSections:server-1:LatestMovies:',
        section: 'LatestMovies',
        title: 'Latest Movies',
        serverId: 'server-1',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      expect(row.items, isEmpty);
      expect(row.rowType, HomeRowType.pluginDynamic);
    });
  });

  group('RowDataSource.filterDiscoverableHomeScreenSections', () {
    test('excludes the Discover route and keeps library-backed routes', () {
      final raw = [
        {'route': 'BecauseYouWatched', 'displayText': 'Because You Watched', 'additionalData': ''},
        {'route': 'Discover', 'displayText': 'Discover', 'additionalData': ''},
        {'route': 'WatchAgain', 'displayText': 'Watch Again', 'additionalData': ''},
      ];

      final filtered = RowDataSource.filterDiscoverableHomeScreenSections(raw);

      expect(filtered, hasLength(2));
      expect(filtered.map((e) => e['route']), containsAll(['BecauseYouWatched', 'WatchAgain']));
      expect(filtered.any((e) => e['route'] == 'Discover'), isFalse);
    });

    test('is case-insensitive on the route value', () {
      final raw = [
        {'route': 'discover', 'displayText': 'discover lowercase', 'additionalData': ''},
      ];

      final filtered = RowDataSource.filterDiscoverableHomeScreenSections(raw);

      expect(filtered, isEmpty);
    });
  });
}

class RequestOptionsStub extends dio_pkg.RequestOptions {
  RequestOptionsStub(String path) : super(path: path);
}

class DioExceptionStub extends dio_pkg.DioException {
  DioExceptionStub(dio_pkg.RequestOptions requestOptions, int statusCode)
      : super(
          requestOptions: requestOptions,
          response: dio_pkg.Response(
            requestOptions: requestOptions,
            statusCode: statusCode,
          ),
          type: dio_pkg.DioExceptionType.badResponse,
        );
}
