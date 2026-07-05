/// Pure decision logic for Cinema Mode's immersive presentation.
///
/// Kept free of Flutter widget/state dependencies so it can be unit
/// tested without standing up the full [VideoPlayerScreen] widget tree.
library;

/// Whether all reachable UI chrome (nav bar, clock/"ends at" label, lock
/// affordance, and any accidental focus-triggered overlay) should be
/// suppressed right now.
///
/// Cinema Mode suppresses chrome for both the preroll sequence and the
/// main feature — this is additive to the pre-existing preroll-only OSD
/// hiding, not a replacement for it.
bool shouldSuppressCinemaChrome({
  required bool cinemaModeEnabled,
  required bool isCurrentItemPreroll,
}) {
  if (!cinemaModeEnabled) {
    return isCurrentItemPreroll;
  }
  return true;
}

/// Whether a one-shot, full-black cover should be shown right now to hide
/// the cut between the last preroll frame and the first main-feature
/// frame.
///
/// True exactly at the instant the queue has advanced off a preroll item
/// onto a non-preroll item while Cinema Mode is enabled. The caller is
/// responsible for clearing this state again once the next frame has been
/// presented (see [VideoPlayerScreenState]'s use in the `queueChangedStream`
/// listener and `build()`).
bool shouldShowCinemaBlackout({
  required bool cinemaModeEnabled,
  required bool previousItemWasPreroll,
  required bool isCurrentItemPreroll,
}) {
  if (!cinemaModeEnabled) {
    return false;
  }
  return previousItemWasPreroll && !isCurrentItemPreroll;
}
