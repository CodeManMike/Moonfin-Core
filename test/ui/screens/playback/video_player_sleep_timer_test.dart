import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/playback/sleep_timer_picker_dialog.dart';

// This exercises the real `sleepTimerLabelFor` helper that
// VideoPlayerScreen's private `_sleepTimerLabel` getter delegates to, so a
// regression in the production formatting logic (e.g. swapped cases, a
// dropped l10n call, or reading the wrong field) will fail this test.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('formats a duration-based label', () {
    final label = sleepTimerLabelFor(
      l10n,
      const SleepTimerResult(type: SleepTimerType.duration, value: 30),
    );
    expect(label, 'Sleeping in 30 min');
  });

  test('formats an episode-based label (plural)', () {
    final label = sleepTimerLabelFor(
      l10n,
      const SleepTimerResult(type: SleepTimerType.episode, value: 2),
    );
    expect(label, 'Sleeping after 2 more episodes');
  });

  test('formats an episode-based label (singular)', () {
    final label = sleepTimerLabelFor(
      l10n,
      const SleepTimerResult(type: SleepTimerType.episode, value: 1),
    );
    expect(label, 'Sleeping after this episode');
  });
}
