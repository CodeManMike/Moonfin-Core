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

  group('shouldAllowHoverPreview', () {
    test('allows hover preview when no row currently has D-pad focus', () {
      expect(
        shouldAllowHoverPreview(
          hoverRowIndex: 2,
          activeFocusedRowIndex: null,
        ),
        isTrue,
      );
    });

    test(
      'allows hover preview in a different row than the one with D-pad focus',
      () {
        expect(
          shouldAllowHoverPreview(
            hoverRowIndex: 5,
            activeFocusedRowIndex: 2,
          ),
          isTrue,
        );
      },
    );

    test(
      'blocks hover preview in the same row that currently has D-pad focus',
      () {
        // This is the stale-hover race: a row's own auto-scroll-on-focus-
        // change animation can shift a different card under a stationary
        // mouse cursor, firing onHoverStart for the wrong item and stealing
        // the preview slot from the item the user actually D-pad-navigated
        // to. Only the keyboard-driven schedule should win here.
        expect(
          shouldAllowHoverPreview(
            hoverRowIndex: 2,
            activeFocusedRowIndex: 2,
          ),
          isFalse,
        );
      },
    );
  });
}
