import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';

void main() {
  group('LibrarySortBy display names', () {
    // "Rating" previously mapped to OfficialRating (the content/parental
    // certification string, e.g. "PG-13"), while the actual numeric quality
    // score lived under the separate "Community Rating" option. A user
    // picking the option simply labelled "Rating" - the intuitive choice for
    // "worst to best rating" - got certification-string sorting instead,
    // which barely reorders a personal library (most items share 2-3
    // certifications) and reads as "direction doesn't do anything".
    test('the option labelled "Rating" sorts by the numeric community score', () {
      expect(LibrarySortBy.communityRating.displayName, 'Rating');
      expect(LibrarySortBy.communityRating.apiValue, 'CommunityRating');
    });

    test('the content-certification option is labelled unambiguously', () {
      expect(LibrarySortBy.rating.displayName, 'Content Rating');
      expect(LibrarySortBy.rating.apiValue, 'OfficialRating');
    });
  });
}
