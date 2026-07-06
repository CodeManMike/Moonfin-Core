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

  group('isForwardEpisodeAdvance', () {
    test('is true for a normal forward step (next episode)', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 0,
        newIndex: 1,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isTrue);
    });

    test('is false for going back to the previous episode', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 2,
        newIndex: 1,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });

    test('is false for jumping ahead multiple episodes via the switcher', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 0,
        newIndex: 3,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });

    test('is false for jumping backward via the episode switcher', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 3,
        newIndex: 0,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });

    test('is false when the index is unchanged (e.g. queue mutation)', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 1,
        newIndex: 1,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });

    test('is true for repeat-all wrap-around from the last item to the first', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 4,
        newIndex: 0,
        queueLength: 5,
        isRepeatAll: true,
      );
      expect(result, isTrue);
    });

    test('is false for a same wrap-around shape when repeat-all is off', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: 4,
        newIndex: 0,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });

    test('is false when either index is negative (empty/uninitialized queue)', () {
      final result = isForwardEpisodeAdvance(
        previousIndex: -1,
        newIndex: 0,
        queueLength: 5,
        isRepeatAll: false,
      );
      expect(result, isFalse);
    });
  });
}
