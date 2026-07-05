import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/collection_missing_items_view_model.dart';

class MockTmdbRepository extends Mock implements TmdbRepository {}
class MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  late MockTmdbRepository tmdbRepo;
  late MockSeerrRepository seerrRepo;

  setUp(() {
    tmdbRepo = MockTmdbRepository();
    seerrRepo = MockSeerrRepository();
  });

  AggregatedItem libraryItem(String tmdbId) => AggregatedItem(
        id: 'lib-$tmdbId',
        serverId: 'server-1',
        rawData: {
          'Id': 'lib-$tmdbId',
          'Name': 'Owned $tmdbId',
          'Type': 'Movie',
          'ProviderIds': {'Tmdb': tmdbId},
        },
      );

  test('diffs canonical TMDB parts against library items by tmdbId', () async {
    when(() => tmdbRepo.getCollection(10)).thenAnswer((_) async => {
          'success': true,
          'id': 10,
          'name': 'Star Wars Collection',
          'parts': [
            {'id': 1891, 'title': 'The Empire Strikes Back', 'releaseDate': '1980-05-20', 'posterPath': '/a.jpg', 'overview': ''},
            {'id': 1892, 'title': 'Return of the Jedi', 'releaseDate': '1983-05-25', 'posterPath': '/b.jpg', 'overview': ''},
          ],
        });

    final vm = CollectionMissingItemsViewModel(
      tmdbRepository: tmdbRepo,
      seerrRepository: seerrRepo,
    );
    await vm.loadMissingItems(
      tmdbCollectionId: 10,
      libraryItems: [libraryItem('1891')],
    );

    expect(vm.missingItems.length, 1);
    expect(vm.missingItems.first.tmdbId, 1892);
    expect(vm.missingItems.first.title, 'Return of the Jedi');
  });

  test('requestMissingItem calls SeerrRepository.createRequest for movie media type', () async {
    when(() => tmdbRepo.getCollection(10)).thenAnswer((_) async => {
          'success': true,
          'id': 10,
          'name': 'Star Wars Collection',
          'parts': [
            {'id': 1892, 'title': 'Return of the Jedi', 'releaseDate': '1983-05-25', 'posterPath': '/b.jpg', 'overview': ''},
          ],
        });
    when(() => seerrRepo.createRequest(
          mediaId: 1892,
          mediaType: 'movie',
        )).thenAnswer((_) async => SeerrRequest.fromJson({
          'id': 1,
          'status': 1,
          'type': 'movie',
          'media': {'id': 1, 'tmdbId': 1892, 'status': 3, 'mediaType': 'movie'},
        }));

    final vm = CollectionMissingItemsViewModel(
      tmdbRepository: tmdbRepo,
      seerrRepository: seerrRepo,
    );
    await vm.loadMissingItems(tmdbCollectionId: 10, libraryItems: const []);
    await vm.requestMissingItem(vm.missingItems.first);

    verify(() => seerrRepo.createRequest(mediaId: 1892, mediaType: 'movie')).called(1);
    expect(vm.requestedTmdbIds.contains(1892), true);
  });
}
