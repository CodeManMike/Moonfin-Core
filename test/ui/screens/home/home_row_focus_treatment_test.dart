import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/home_screen.dart';

void main() {
  group('homeRowFocusScale', () {
    test('unfocused row is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: false, isTV: true, fullScreenRows: false),
        1.0,
      );
    });

    // The row itself is never scaled, regardless of focus/platform/layout -
    // scaling the whole row visually compounded with the per-tile focus scale
    // already applied by MediaCard/GridButtonCard, making an adjacent
    // unfocused tile look nearly as "focused" as the real one. Only the tile
    // that actually has D-pad focus should grow.
    test('focused row on TV in non-fullscreen mode is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: true, fullScreenRows: false),
        1.0,
      );
    });

    test('focused row on TV in fullscreen mode is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: true, fullScreenRows: true),
        1.0,
      );
    });

    test('focused row off TV is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: false, fullScreenRows: false),
        1.0,
      );
    });
  });

  group('homeRowFocusExtraSpacing', () {
    test('always returns zero regardless of focus state', () {
      expect(
        homeRowFocusExtraSpacing(isFocused: true, isTV: true, fullScreenRows: false),
        0.0,
      );
      expect(
        homeRowFocusExtraSpacing(isFocused: false, isTV: true, fullScreenRows: false),
        0.0,
      );
    });
  });
}
