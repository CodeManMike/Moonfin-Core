import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/playback/cinema_mode_chrome.dart';

void main() {
  group('shouldSuppressCinemaChrome', () {
    test('still suppresses chrome for a preroll item when Cinema Mode is disabled', () {
      expect(
        shouldSuppressCinemaChrome(
          cinemaModeEnabled: false,
          isCurrentItemPreroll: true,
        ),
        isTrue,
      );
    });

    test('suppresses chrome for a preroll item when Cinema Mode is enabled', () {
      expect(
        shouldSuppressCinemaChrome(
          cinemaModeEnabled: true,
          isCurrentItemPreroll: true,
        ),
        isTrue,
      );
    });

    test('suppresses chrome for the main feature when Cinema Mode is enabled', () {
      expect(
        shouldSuppressCinemaChrome(
          cinemaModeEnabled: true,
          isCurrentItemPreroll: false,
        ),
        isTrue,
      );
    });

    test('does not suppress chrome for a non-preroll item when Cinema Mode is disabled', () {
      expect(
        shouldSuppressCinemaChrome(
          cinemaModeEnabled: false,
          isCurrentItemPreroll: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowCinemaBlackout', () {
    test('shows a blackout when the previous queue item was a preroll and the current one is not', () {
      expect(
        shouldShowCinemaBlackout(
          cinemaModeEnabled: true,
          previousItemWasPreroll: true,
          isCurrentItemPreroll: false,
        ),
        isTrue,
      );
    });

    test('does not show a blackout between two preroll items', () {
      expect(
        shouldShowCinemaBlackout(
          cinemaModeEnabled: true,
          previousItemWasPreroll: true,
          isCurrentItemPreroll: true,
        ),
        isFalse,
      );
    });

    test('does not show a blackout when there was no previous preroll', () {
      expect(
        shouldShowCinemaBlackout(
          cinemaModeEnabled: true,
          previousItemWasPreroll: false,
          isCurrentItemPreroll: false,
        ),
        isFalse,
      );
    });

    test('does not show a blackout when Cinema Mode is disabled', () {
      expect(
        shouldShowCinemaBlackout(
          cinemaModeEnabled: false,
          previousItemWasPreroll: true,
          isCurrentItemPreroll: false,
        ),
        isFalse,
      );
    });
  });
}
