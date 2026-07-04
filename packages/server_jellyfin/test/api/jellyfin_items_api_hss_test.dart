import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_jellyfin/src/api/jellyfin_items_api.dart';
import 'package:test/test.dart';

class MockDio extends Mock implements Dio {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeRequestOptions());
  });

  group('JellyfinItemsApi.getHomeScreenSections', () {
    late MockDio dio;
    late JellyfinItemsApi api;

    setUp(() {
      dio = MockDio();
      api = JellyfinItemsApi(dio, () => 'user-1');
    });

    test('GETs /HomeScreen/Sections with userId and returns the decoded list', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Sections');
      when(() => dio.get(
            '/HomeScreen/Sections',
            queryParameters: {'userId': 'user-1'},
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: [
              {
                'route': 'BecauseYouWatched',
                'displayText': 'Because You Watched',
                'additionalData': '',
              },
              {
                'route': 'Discover',
                'displayText': 'Discover',
                'additionalData': '',
              },
            ],
          ));

      final result = await api.getHomeScreenSections();

      expect(result, hasLength(2));
      expect(result[0]['route'], 'BecauseYouWatched');
      expect(result[1]['route'], 'Discover');
    });
  });

  group('JellyfinItemsApi.getHomeScreenSectionItems', () {
    late MockDio dio;
    late JellyfinItemsApi api;

    setUp(() {
      dio = MockDio();
      api = JellyfinItemsApi(dio, () => 'user-1');
    });

    test('GETs /HomeScreen/Section/{sectionType} with userId and additionalData', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Section/BecauseYouWatched');
      when(() => dio.get(
            '/HomeScreen/Section/BecauseYouWatched',
            queryParameters: {
              'userId': 'user-1',
              'additionalData': 'seriesId-123',
            },
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: {
              'Items': [
                {'Id': 'abc', 'Name': 'Some Movie', 'Type': 'Movie'},
              ],
              'TotalRecordCount': 1,
            },
          ));

      final result = await api.getHomeScreenSectionItems(
        'BecauseYouWatched',
        additionalData: 'seriesId-123',
      );

      expect(result['TotalRecordCount'], 1);
      expect((result['Items'] as List), hasLength(1));
      expect((result['Items'] as List).first['Name'], 'Some Movie');
    });

    test('wraps a bare List response into an Items/TotalRecordCount map', () async {
      final requestOptions = RequestOptions(path: '/HomeScreen/Section/LatestMovies');
      when(() => dio.get(
            '/HomeScreen/Section/LatestMovies',
            queryParameters: {
              'userId': 'user-1',
            },
          )).thenAnswer((_) async => Response(
            requestOptions: requestOptions,
            statusCode: 200,
            data: [
              {'Id': 'xyz', 'Name': 'Another Movie', 'Type': 'Movie'},
            ],
          ));

      final result = await api.getHomeScreenSectionItems('LatestMovies');

      expect(result['TotalRecordCount'], 1);
      expect((result['Items'] as List).first['Id'], 'xyz');
    });
  });
}
