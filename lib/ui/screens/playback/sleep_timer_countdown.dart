/// Decrements the remaining-episode count for an active "sleep after N
/// episodes" timer by one, called each time the playback queue advances.
int decrementSleepTimerEpisodes(int remaining) => remaining - 1;

/// Whether a "sleep after N episodes" timer with [remaining] episodes left
/// should fire now.
bool sleepTimerEpisodesElapsed(int remaining) => remaining <= 0;
