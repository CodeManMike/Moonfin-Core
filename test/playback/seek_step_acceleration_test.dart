import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/playback/video_player_screen.dart';

void main() {
  group('seekStepMultiplierFor', () {
    test('no acceleration for the first few repeats', () {
      expect(seekStepMultiplierFor(0), 1);
      expect(seekStepMultiplierFor(4), 1);
    });

    test('2x after 4 repeats', () {
      expect(seekStepMultiplierFor(5), 2);
      expect(seekStepMultiplierFor(10), 2);
    });

    test('6x after 10 repeats', () {
      expect(seekStepMultiplierFor(11), 6);
      expect(seekStepMultiplierFor(18), 6);
    });

    test('12x after 18 repeats', () {
      expect(seekStepMultiplierFor(19), 12);
      expect(seekStepMultiplierFor(100), 12);
    });
  });
}
