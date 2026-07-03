import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/app.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  tearDown(() {
    PlatformDetection.setTvMode(false);
  });

  test('shouldApplyTvUiScale is true when running as generic TV mode', () {
    PlatformDetection.setTvMode(true);
    expect(shouldApplyTvUiScale(), isTrue);
  });

  test('shouldApplyTvUiScale is false when not in TV mode and not Apple TV', () {
    PlatformDetection.setTvMode(false);
    expect(shouldApplyTvUiScale(), isFalse);
  });
}
