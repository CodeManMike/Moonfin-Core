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
