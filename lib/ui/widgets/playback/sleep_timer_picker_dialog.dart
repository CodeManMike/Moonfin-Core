import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../track_selector_dialog.dart';

enum SleepTimerType { duration, episode }

class SleepTimerResult {
  final SleepTimerType type;
  final int value;

  const SleepTimerResult({required this.type, required this.value});
}

/// Formats the label shown in the active sleep timer indicator for [result].
///
/// Extracted as a standalone function (rather than inlined where it's used)
/// so it can be unit-tested directly without needing a live [BuildContext]
/// or the full player screen widget tree.
String sleepTimerLabelFor(AppLocalizations l10n, SleepTimerResult result) {
  switch (result.type) {
    case SleepTimerType.duration:
      return l10n.sleepTimerActiveDuration(result.value);
    case SleepTimerType.episode:
      return l10n.sleepTimerActiveEpisode(result.value);
  }
}

class SleepTimerPickerDialog {
  SleepTimerPickerDialog._();

  static const List<int> _durationOptionsMinutes = [15, 30, 45, 60];
  static const List<int> _episodeOptionsCount = [1, 2, 3];

  static Future<SleepTimerResult?> show(
    BuildContext context, {
    required bool isEpisodicContent,
  }) {
    final l10n = AppLocalizations.of(context);

    final options = <TrackOption>[
      for (final minutes in _durationOptionsMinutes)
        TrackOption(label: l10n.sleepTimerDurationOption(minutes)),
      if (isEpisodicContent)
        for (final count in _episodeOptionsCount)
          TrackOption(label: l10n.sleepTimerEpisodeOption(count)),
    ];

    return TrackSelectorDialog.show(
      context,
      title: l10n.sleepTimer,
      options: options,
    ).then((index) {
      if (index == null) return null;
      if (index < _durationOptionsMinutes.length) {
        return SleepTimerResult(
          type: SleepTimerType.duration,
          value: _durationOptionsMinutes[index],
        );
      }
      final episodeIndex = index - _durationOptionsMinutes.length;
      return SleepTimerResult(
        type: SleepTimerType.episode,
        value: _episodeOptionsCount[episodeIndex],
      );
    });
  }
}
