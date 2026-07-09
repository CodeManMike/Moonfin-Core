import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/seerr_browse_view_model.dart';
import 'package:moonfin/preference/preference_constants.dart';

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  late _MockSeerrRepository repo;
  late SeerrBrowseViewModel vm;
  final capturedSortBy = <String>[];

  setUp(() {
    repo = _MockSeerrRepository();
    capturedSortBy.clear();
    when(() => repo.ensureInitialized()).thenAnswer((_) async {});
    when(
      () => repo.discoverMovies(
        page: any(named: 'page'),
        sortBy: any(named: 'sortBy'),
        genre: any(named: 'genre'),
        studio: any(named: 'studio'),
        keywords: any(named: 'keywords'),
      ),
    ).thenAnswer((invocation) async {
      capturedSortBy.add(
        invocation.namedArguments[#sortBy] as String,
      );
      return const SeerrDiscoverPage();
    });
    vm = SeerrBrowseViewModel(repo, mediaType: 'movie');
  });

  test('starts with Popularity descending by default', () {
    expect(vm.state.sortBy.field, 'popularity');
    expect(vm.state.sortDirection, SortDirection.descending);
  });

  test('selecting a new field applies that field\'s default direction', () async {
    vm.setSortBy(const SeerrSortOption('Rating', 'vote_average'));
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.sortBy.field, 'vote_average');
    expect(vm.state.sortDirection, SortDirection.descending);
    expect(capturedSortBy.last, 'vote_average.desc');
  });

  test(
    'tapping the same field a second time reverses direction',
    () async {
      vm.setSortBy(const SeerrSortOption('Rating', 'vote_average'));
      await Future<void>.delayed(Duration.zero);
      expect(capturedSortBy.last, 'vote_average.desc');

      vm.toggleSortDirection();
      await Future<void>.delayed(Duration.zero);
      expect(vm.state.sortDirection, SortDirection.ascending);
      expect(capturedSortBy.last, 'vote_average.asc');

      vm.toggleSortDirection();
      await Future<void>.delayed(Duration.zero);
      expect(vm.state.sortDirection, SortDirection.descending);
      expect(capturedSortBy.last, 'vote_average.desc');
    },
  );

  test('Title defaults to ascending when first selected', () async {
    vm.setSortBy(const SeerrSortOption(
      'Title',
      'original_title',
      defaultDirection: SortDirection.ascending,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.sortDirection, SortDirection.ascending);
    expect(capturedSortBy.last, 'original_title.asc');
  });
}
