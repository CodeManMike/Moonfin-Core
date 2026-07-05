import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';

void main() {
  group('isStatusChipSelected', () {
    test('All chip is selected only when filter is all and favorite is off', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.all,
          playedFilter: PlayedStatusFilter.all,
          favoriteFilter: false,
        ),
        isTrue,
      );
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.all,
          playedFilter: PlayedStatusFilter.all,
          favoriteFilter: true,
        ),
        isFalse,
      );
    });

    test('Unwatched chip tracks the unwatched played filter', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.unwatched,
          playedFilter: PlayedStatusFilter.unwatched,
          favoriteFilter: false,
        ),
        isTrue,
      );
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.unwatched,
          playedFilter: PlayedStatusFilter.watched,
          favoriteFilter: false,
        ),
        isFalse,
      );
    });

    test('Favorites chip tracks favoriteFilter independent of played filter', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.favorites,
          playedFilter: PlayedStatusFilter.watched,
          favoriteFilter: true,
        ),
        isTrue,
      );
    });
  });
}
