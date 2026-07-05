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

    test('focused row on TV in non-fullscreen mode is scaled up', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: true, fullScreenRows: false),
        greaterThan(1.0),
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
