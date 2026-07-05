import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';

void main() {
  group('gridCrossAxisCountFor', () {
    test('comfortable density matches the existing unscaled column count', () {
      final count = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.comfortable,
      );
      // (1200 - 120 + 12) / (150 + 12) floored = 6
      expect(count, 6);
    });

    test('compact density increases column count for the same width', () {
      final comfortable = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.comfortable,
      );
      final compact = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.compact,
      );
      expect(compact, greaterThan(comfortable));
    });

    test('result is clamped between 2 and 20 regardless of density', () {
      final tiny = gridCrossAxisCountFor(
        availableWidth: 50,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.compact,
      );
      expect(tiny, 2);

      final huge = gridCrossAxisCountFor(
        availableWidth: 20000,
        gridPadding: 60,
        cardWidth: 40,
        spacing: 4,
        density: GridDensity.compact,
      );
      expect(huge, 20);
    });
  });
}
