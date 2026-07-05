import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/trickplay_info.dart';

void main() {
  group('trickplayImageCountFor', () {
    const info = TrickplayInfo(
      width: 320,
      height: 180,
      tileWidth: 10,
      tileHeight: 10,
      interval: 10000,
    );

    test('computes image count from duration and tiles-per-image', () {
      // 100 tiles/image * 10000ms interval = 1,000,000ms covered per image.
      // A 45-minute (2,700,000ms) item needs ceil(2700000/1000000)+1 = 4 images.
      final count = trickplayImageCountFor(
        durationMs: 2700000,
        info: info,
      );
      expect(count, 4);
    });

    test('falls back to 16 when duration is unknown (zero or negative)', () {
      expect(trickplayImageCountFor(durationMs: 0, info: info), 16);
      expect(trickplayImageCountFor(durationMs: -1, info: info), 16);
    });

    test('clamps to a maximum of 128 images for very long content', () {
      final count = trickplayImageCountFor(
        durationMs: 999999999,
        info: info,
      );
      expect(count, 128);
    });

    test('never returns fewer than 2 images for a positive duration', () {
      // Even a 1ms duration still needs the ceil(...) + 1 formula's minimum
      // of one image plus the trailing image, matching the proven formula
      // already shipped in appletv_player_host_screen.dart's _trickplayPayload.
      final count = trickplayImageCountFor(durationMs: 1, info: info);
      expect(count, 2);
    });
  });
}
