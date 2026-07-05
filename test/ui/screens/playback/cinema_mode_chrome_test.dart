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
}
