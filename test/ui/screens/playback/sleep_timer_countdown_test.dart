import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/playback/sleep_timer_countdown.dart';

void main() {
  group('decrementSleepTimerEpisodes', () {
    test('reduces the remaining count by one', () {
      expect(decrementSleepTimerEpisodes(3), 2);
    });
  });

  group('sleepTimerEpisodesElapsed', () {
    test('is false while episodes remain', () {
      expect(sleepTimerEpisodesElapsed(1), isFalse);
    });

    test('is true once the count reaches zero', () {
      expect(sleepTimerEpisodesElapsed(0), isTrue);
    });

    test('is true if the count goes negative', () {
      expect(sleepTimerEpisodesElapsed(-1), isTrue);
    });
  });
}
