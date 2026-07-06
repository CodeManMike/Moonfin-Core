/// Decrements the remaining-episode count for an active "sleep after N
/// episodes" timer by one, called each time the playback queue advances.
int decrementSleepTimerEpisodes(int remaining) => remaining - 1;

/// Whether a "sleep after N episodes" timer with [remaining] episodes left
/// should fire now.
bool sleepTimerEpisodesElapsed(int remaining) => remaining <= 0;

/// Whether a `queueChangedStream` event represents the queue moving forward
/// by exactly one episode (i.e. a genuine episode advance), as opposed to
/// going back to the previous episode, jumping to an arbitrary episode (e.g.
/// via the in-player episode switcher), or other non-advancing queue
/// mutations (inserts, removals, shuffle/repeat toggles).
///
/// [previousIndex] and [newIndex] are the queue's `currentIndex` immediately
/// before and after the change. [queueLength] and [isRepeatAll] describe the
/// queue state after the change, needed to recognize the repeat-all
/// wrap-around from the last item back to index 0 as a forward step.
///
/// Only this "advanced by exactly one, forward" shape should count toward a
/// "sleep after N episodes" countdown; anything else (previous(), jumpTo(),
/// or a queue mutation that leaves the index unchanged or moves it backward)
/// must not decrement the countdown.
bool isForwardEpisodeAdvance({
  required int previousIndex,
  required int newIndex,
  required int queueLength,
  required bool isRepeatAll,
}) {
  if (previousIndex < 0 || newIndex < 0) return false;
  if (newIndex == previousIndex + 1) return true;
  if (isRepeatAll && previousIndex == queueLength - 1 && newIndex == 0) {
    return true;
  }
  return false;
}
