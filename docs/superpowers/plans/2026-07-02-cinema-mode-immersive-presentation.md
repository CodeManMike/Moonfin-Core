# Cinema Mode Immersive Presentation Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

**Goal**: While Cinema Mode is enabled and either a preroll or the movie's main feature is playing, suppress every reachable UI chrome element (nav/back bar, clock/"ends at" label, lock overlay, accidental focus-triggered controls) and cover the exact frame where the last preroll ends and the main feature begins with an opaque black layer so there is no flash or jarring cut.

**Architecture**: `VideoPlayerScreen` (`lib/ui/screens/playback/video_player_screen.dart`) already hides its OSD chrome for preroll items via `_isCurrentPreroll` / `_syncPrerollOsdState` / the `hideOsdForPreroll` flag read in `build()`. This plan generalizes that existing preroll-only suppression into a single pure helper, `_shouldSuppressCinemaChrome`, that also suppresses chrome for the *main feature* when Cinema Mode is on and the queue shows the feature immediately followed (in playback history) a preroll. A second pure helper, `_shouldShowCinemaBlackout`, detects the exact queue transition from a preroll item to a non-preroll item and drives a one-shot full-black `Positioned.fill(ColoredBox)` layer (the same idiom already used for `_isRestoringPosition`) that is cleared on the next video frame, giving a seamless cut instead of a flash. Both helpers are top-level pure functions taking plain data (`bool cinemaModeEnabled`, `List<dynamic> queueItems`, `int currentIndex`, a `bool Function(dynamic) isPreroll` predicate) so they can be unit-tested without instantiating `VideoPlayerScreen`'s heavy GetIt-backed widget tree — matching this repository's existing pattern of testing extracted pure logic for this file rather than pumping the full screen (see `test/preference/user_preferences_passthrough_test.dart` for the `UserPreferences` construction convention this plan reuses).

**Tech Stack**: Flutter/Dart, `flutter_test` + `mocktail` (declared in `pubspec.yaml`, `mocktail: ^1.0.5`), `jellyfin_preference` package (`packages/preference`) for `Preference<bool>`/`PreferenceStore`, tests run via `flutter test <path>` from `E:\Moonfin-Core`.

---

### Task 1: Extract and test the cinema-chrome-suppression decision logic

Files:
- Create: `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart`
- Create: `E:\Moonfin-Core\lib\ui\screens\playback\cinema_mode_chrome.dart`
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (imports at lines 19-67; `_syncPrerollOsdState` at lines 363-371; `_isCurrentPreroll` at line 310; `_showControls`/`_toggleControls` at lines 2553-2580; `build()` at lines 3278-3449)

- [ ] Step 1: Write the failing test for the new pure helper `shouldSuppressCinemaChrome`

  Create `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin/ui/screens/playback/cinema_mode_chrome.dart';

  void main() {
    group('shouldSuppressCinemaChrome', () {
      test('does not suppress chrome when Cinema Mode is disabled', () {
        expect(
          shouldSuppressCinemaChrome(
            cinemaModeEnabled: false,
            isCurrentItemPreroll: true,
          ),
          isFalse,
        );
      });

      test('suppresses chrome for a preroll item when Cinema Mode is enabled', () {
        expect(
          shouldSuppressCinemaChrome(
            cinemaModeEnabled: true,
            isCurrentItemPreroll: true,
          ),
          isTrue,
        );
      });

      test('suppresses chrome for the main feature when Cinema Mode is enabled', () {
        expect(
          shouldSuppressCinemaChrome(
            cinemaModeEnabled: true,
            isCurrentItemPreroll: false,
          ),
          isTrue,
        );
      });

      test('does not suppress chrome for a non-preroll item when Cinema Mode is disabled', () {
        expect(
          shouldSuppressCinemaChrome(
            cinemaModeEnabled: false,
            isCurrentItemPreroll: false,
          ),
          isFalse,
        );
      });
    });
  }
  ```

- [ ] Step 2: Run the test, expecting it to fail because `cinema_mode_chrome.dart` does not exist yet

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output contains:
  ```
  Error: Error when reading 'lib/ui/screens/playback/cinema_mode_chrome.dart': No such file or directory
  ```

- [ ] Step 3: Create the minimal pure helper file

  Create `E:\Moonfin-Core\lib\ui\screens\playback\cinema_mode_chrome.dart`:

  ```dart
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
  ```

  Note: when Cinema Mode is disabled, chrome suppression still follows the pre-existing preroll-only behavior (`isCurrentItemPreroll`), so this helper is a strict superset of today's logic, never a regression for users with Cinema Mode off.

- [ ] Step 4: Run the test, expecting it to pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 5: Commit

  ```
  git add lib/ui/screens/playback/cinema_mode_chrome.dart test/ui/screens/playback/cinema_mode_chrome_test.dart
  git commit -m "Add pure Cinema Mode chrome-suppression decision helper"
  ```

- [ ] Step 6: Write the failing test for the second pure helper, `shouldShowCinemaBlackout`, in the same test file

  Read the current end of `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart` (the closing of the `shouldSuppressCinemaChrome` group and `main()`):

  ```dart
        test('does not suppress chrome for a non-preroll item when Cinema Mode is disabled', () {
          expect(
            shouldSuppressCinemaChrome(
              cinemaModeEnabled: false,
              isCurrentItemPreroll: false,
            ),
            isFalse,
          );
        });
      });
    }
  ```

  Change it to:

  ```dart
        test('does not suppress chrome for a non-preroll item when Cinema Mode is disabled', () {
          expect(
            shouldSuppressCinemaChrome(
              cinemaModeEnabled: false,
              isCurrentItemPreroll: false,
            ),
            isFalse,
          );
        });
      });

      group('shouldShowCinemaBlackout', () {
        test('shows a blackout when the previous queue item was a preroll and the current one is not', () {
          expect(
            shouldShowCinemaBlackout(
              cinemaModeEnabled: true,
              previousItemWasPreroll: true,
              isCurrentItemPreroll: false,
            ),
            isTrue,
          );
        });

        test('does not show a blackout between two preroll items', () {
          expect(
            shouldShowCinemaBlackout(
              cinemaModeEnabled: true,
              previousItemWasPreroll: true,
              isCurrentItemPreroll: true,
            ),
            isFalse,
          );
        });

        test('does not show a blackout when there was no previous preroll', () {
          expect(
            shouldShowCinemaBlackout(
              cinemaModeEnabled: true,
              previousItemWasPreroll: false,
              isCurrentItemPreroll: false,
            ),
            isFalse,
          );
        });

        test('does not show a blackout when Cinema Mode is disabled', () {
          expect(
            shouldShowCinemaBlackout(
              cinemaModeEnabled: false,
              previousItemWasPreroll: true,
              isCurrentItemPreroll: false,
            ),
            isFalse,
          );
        });
      });
    }
  ```

- [ ] Step 7: Run the test, expecting it to fail because `shouldShowCinemaBlackout` is not defined

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output contains:
  ```
  Error: The function 'shouldShowCinemaBlackout' isn't defined.
  ```

- [ ] Step 8: Add the second helper to the implementation file

  Read the current full content of `E:\Moonfin-Core\lib\ui\screens\playback\cinema_mode_chrome.dart`:

  ```dart
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
  ```

  Change it to:

  ```dart
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
  ```

- [ ] Step 9: Run the test, expecting it to pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 10: Commit

  ```
  git add lib/ui/screens/playback/cinema_mode_chrome.dart test/ui/screens/playback/cinema_mode_chrome_test.dart
  git commit -m "Add pure Cinema Mode preroll-to-feature blackout decision helper"
  ```

---

### Task 2: Wire chrome suppression into `VideoPlayerScreen` for the main feature, not just preroll

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (imports at lines 56-60; `_isCurrentPreroll` getter at line 310; `_syncPrerollOsdState` at lines 363-371; `build()` at lines 3278-3283, 3316-3398)
- Test: `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart` (already covers the pure logic being wired in; this task has no new pure-logic branches, only call-site wiring, so it is verified by `flutter analyze` plus the existing Task 1 tests continuing to pass)

- [ ] Step 1: Import the new helper into `video_player_screen.dart`

  Read lines 56-60 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
  import '../../widgets/playback/player_loading_overlay.dart';
  import '../../widgets/playback/skip_segment_overlay.dart';
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  import '../../widgets/playback/stream_info_dialog.dart';
  ```

  Change it to:

  ```dart
  import '../../widgets/playback/player_loading_overlay.dart';
  import '../../widgets/playback/skip_segment_overlay.dart';
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  import '../../widgets/playback/stream_info_dialog.dart';
  import 'cinema_mode_chrome.dart';
  ```

- [ ] Step 2: Replace the `hideOsdForPreroll` local in `build()` with a call to `shouldSuppressCinemaChrome`

  Read lines 3278-3286 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
    @override
    Widget build(BuildContext context) {
      final hideOsdForPreroll = _isCurrentPreroll;
      if (_isInPiP) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [_buildVideoSurface()]),
        );
      }
  ```

  Change it to:

  ```dart
    @override
    Widget build(BuildContext context) {
      final hideOsdForPreroll = shouldSuppressCinemaChrome(
        cinemaModeEnabled: _prefs.get(UserPreferences.cinemaModeEnabled),
        isCurrentItemPreroll: _isCurrentPreroll,
      );
      if (_isInPiP) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [_buildVideoSurface()]),
        );
      }
  ```

  This keeps the existing `hideOsdForPreroll` variable name (so the three call sites at lines 3383, 3397 that already gate `_buildTopOverlay(context)`/`_buildBottomOverlay(context)`/`_buildLockedOverlay()` need no further changes) but now evaluates to `true` for the main feature too whenever Cinema Mode is on, not only for preroll items.

- [ ] Step 3: Run static analysis to catch any missed reference, expecting no errors introduced

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart lib/ui/screens/playback/cinema_mode_chrome.dart
  ```

  Expected output ends with:
  ```
  No issues found!
  ```

- [ ] Step 4: Extend `_syncPrerollOsdState` so a Cinema-Mode main feature also collapses any already-visible controls back down, using the same helper

  Read lines 363-371 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
    void _syncPrerollOsdState() {
      if (!_isCurrentPreroll) return;
      _hideTimer?.cancel();
      if (!_controlsVisible && !_isOsdLocked) return;
      setState(() {
        _controlsVisible = false;
        _isOsdLocked = false;
      });
    }
  ```

  Change it to:

  ```dart
    void _syncPrerollOsdState() {
      final suppressChrome = shouldSuppressCinemaChrome(
        cinemaModeEnabled: _prefs.get(UserPreferences.cinemaModeEnabled),
        isCurrentItemPreroll: _isCurrentPreroll,
      );
      if (!suppressChrome) return;
      _hideTimer?.cancel();
      if (!_controlsVisible && !_isOsdLocked) return;
      setState(() {
        _controlsVisible = false;
        _isOsdLocked = false;
      });
    }
  ```

  This is called from `_showControls()` (line 2553-2557) and `_toggleControls()` (line 2565-2569) — both already route through `_syncPrerollOsdState` before doing anything else when `_isCurrentPreroll` is true. Because those two call sites still gate on `_isCurrentPreroll` directly (see Step 5), Step 5 below extends them to use the same shared helper so a tap/click/focus event during the Cinema-Mode main feature is swallowed the same way a preroll tap is swallowed today, instead of flashing the OSD on before `_syncPrerollOsdState` hides it again next frame.

- [ ] Step 5: Extend `_showControls` and `_toggleControls` to route through the same suppression check for the main feature

  Read lines 2553-2580 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
    void _showControls({bool focusSeekbar = false}) {
      if (_isCurrentPreroll) {
        _syncPrerollOsdState();
        return;
      }
      setState(() => _controlsVisible = true);
      _scheduleHide();
      if (focusSeekbar) {
        _focusPreferredTvOverlayTarget();
      }
    }

    void _toggleControls() {
      if (_isCurrentPreroll) {
        _syncPrerollOsdState();
        return;
      }
      if (_isOsdLocked) {
        _showControls();
        return;
      }
      if (_controlsVisible) {
        _hideTimer?.cancel();
        setState(() => _controlsVisible = false);
      } else {
        _showControls();
      }
    }
  ```

  Change it to:

  ```dart
    void _showControls({bool focusSeekbar = false}) {
      if (shouldSuppressCinemaChrome(
        cinemaModeEnabled: _prefs.get(UserPreferences.cinemaModeEnabled),
        isCurrentItemPreroll: _isCurrentPreroll,
      )) {
        _syncPrerollOsdState();
        return;
      }
      setState(() => _controlsVisible = true);
      _scheduleHide();
      if (focusSeekbar) {
        _focusPreferredTvOverlayTarget();
      }
    }

    void _toggleControls() {
      if (shouldSuppressCinemaChrome(
        cinemaModeEnabled: _prefs.get(UserPreferences.cinemaModeEnabled),
        isCurrentItemPreroll: _isCurrentPreroll,
      )) {
        _syncPrerollOsdState();
        return;
      }
      if (_isOsdLocked) {
        _showControls();
        return;
      }
      if (_controlsVisible) {
        _hideTimer?.cancel();
        setState(() => _controlsVisible = false);
      } else {
        _showControls();
      }
    }
  ```

  This is what suppresses "any accidental focus-triggered overlay": every path that could reveal the OSD (tap-to-toggle at line 3321, `onPanDown`/`onHover` desktop mouse-move at lines 3350-3369, TV D-pad `select`/`enter` at lines 3265-3272, the post-frame `_showControls(focusSeekbar: true)` called from `initState` at line 823) already funnels through `_showControls`/`_toggleControls`, so gating those two entry points is sufficient — no other call site needs to change.

- [ ] Step 6: Run static analysis again to confirm the edits compile cleanly

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart
  ```

  Expected output ends with:
  ```
  No issues found!
  ```

- [ ] Step 7: Re-run the Task 1 pure-logic tests to confirm nothing regressed (the wiring itself has no new branchable logic to unit test — it is straight call-site delegation to already-tested pure functions)

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 8: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Suppress player chrome during the main feature when Cinema Mode is on"
  ```

---

### Task 3: Clean full-black transition between the last preroll and the main feature

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (state fields at lines 174-180; `_queueSub` listener at lines 855-875; `build()` Stack at lines 3371-3391)
- Test: `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart` (already covers `shouldShowCinemaBlackout`'s branching from Task 1; this task adds the queue-transition call-site, verified by `flutter analyze` since the state machine itself has no new pure branches beyond what Task 1 already tests)

- [ ] Step 1: Add the blackout-tracking state field next to the other preroll/OSD fields

  Read lines 174-180 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
    MediaSegment? _skipSegment;
    Duration? _skipTo;
    bool _showNextUp = false;
    AggregatedItem? _nextUpItem;
    bool _nextUpDismissed = false;
    bool _isNextUpAdvancing = false;
    int _consecutiveEpisodes = 0;
  ```

  Change it to:

  ```dart
    MediaSegment? _skipSegment;
    Duration? _skipTo;
    bool _showNextUp = false;
    AggregatedItem? _nextUpItem;
    bool _nextUpDismissed = false;
    bool _isNextUpAdvancing = false;
    int _consecutiveEpisodes = 0;

    bool _showCinemaBlackout = false;
    dynamic _previousQueueItem;
  ```

  `_previousQueueItem` tracks the queue item that was current just before the latest `queueChangedStream` event, so the listener can tell whether the item being left was a preroll — `QueueService` (`packages/playback_core/lib/src/queue_service.dart`) exposes only `currentItem`/`currentIndex`/`items`, with no built-in "previous item" accessor, so this plan tracks it locally.

- [ ] Step 2: Extend the `_queueSub` listener to compute and apply the blackout using `shouldShowCinemaBlackout`

  Read lines 855-875 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
      _queueSub = _queue.queueChangedStream.listen((_) {
        _loadSegmentsForCurrentItem();
        _manager.suppressAutoNext = false;
        _consecutiveEpisodes++;
        unawaited(_pushMedia3UiMetadata());
        _syncMedia3VolumeBoostLevel();
        unawaited(_syncAutoHdrSwitching());
        final isPreroll = _isCurrentPreroll;
        setState(() {
          _nextUpDismissed = false;
          _showNextUp = false;
          _skipSegment = null;
          if (isPreroll) {
            _controlsVisible = false;
            _isOsdLocked = false;
          }
        });
        if (isPreroll) {
          _hideTimer?.cancel();
        }
      });
  ```

  Change it to:

  ```dart
      _queueSub = _queue.queueChangedStream.listen((_) {
        _loadSegmentsForCurrentItem();
        _manager.suppressAutoNext = false;
        _consecutiveEpisodes++;
        unawaited(_pushMedia3UiMetadata());
        _syncMedia3VolumeBoostLevel();
        unawaited(_syncAutoHdrSwitching());
        final isPreroll = _isCurrentPreroll;
        final wasPreroll = _isPrerollQueueItem(_previousQueueItem);
        final showBlackout = shouldShowCinemaBlackout(
          cinemaModeEnabled: _prefs.get(UserPreferences.cinemaModeEnabled),
          previousItemWasPreroll: wasPreroll,
          isCurrentItemPreroll: isPreroll,
        );
        _previousQueueItem = _queue.currentItem;
        setState(() {
          _nextUpDismissed = false;
          _showNextUp = false;
          _skipSegment = null;
          if (isPreroll) {
            _controlsVisible = false;
            _isOsdLocked = false;
          }
          if (showBlackout) {
            _showCinemaBlackout = true;
          }
        });
        if (isPreroll) {
          _hideTimer?.cancel();
        }
        if (showBlackout) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _showCinemaBlackout = false);
          });
        }
      });
  ```

  The blackout is scheduled to clear on the very next frame after it is painted: `setState(() => _showCinemaBlackout = true)` forces one black frame to render immediately (covering the last preroll frame / first feature frame cut), then the `addPostFrameCallback` scheduled in the same listener callback clears it right after that frame is presented, so the black cover is visible for exactly one frame rather than lingering or never appearing.

- [ ] Step 3: Render the blackout layer in `build()`, above the video surface and bringup overlay but below the paused-description overlay, matching where `_isRestoringPosition`'s equivalent black cover already sits

  Read lines 3371-3391 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildVideoSurface(),
                      _buildBringupOverlay(context),
                      if (_isRestoringPosition)
                        const Positioned.fill(
                          child: ColoredBox(color: Colors.black),
                        ),
                      _buildPausedDescriptionOverlay(),
                      if (_controlsVisible &&
                          !_isOsdLocked &&
                          !hideOsdForPreroll) ...[
                        _buildTopOverlay(context),
                        _buildBottomOverlay(context),
                        if (!PlatformDetection.useLeanbackUi)
                          Positioned.fill(
                            child: Center(child: _buildCenterTransportControls()),
                          ),
                      ],
  ```

  Change it to:

  ```dart
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildVideoSurface(),
                      _buildBringupOverlay(context),
                      if (_isRestoringPosition || _showCinemaBlackout)
                        const Positioned.fill(
                          child: ColoredBox(color: Colors.black),
                        ),
                      _buildPausedDescriptionOverlay(),
                      if (_controlsVisible &&
                          !_isOsdLocked &&
                          !hideOsdForPreroll) ...[
                        _buildTopOverlay(context),
                        _buildBottomOverlay(context),
                        if (!PlatformDetection.useLeanbackUi)
                          Positioned.fill(
                            child: Center(child: _buildCenterTransportControls()),
                          ),
                      ],
  ```

- [ ] Step 4: Initialize `_previousQueueItem` from the queue's starting item so the very first playback (before any `queueChangedStream` event fires) has a correct baseline

  Read lines 753-756 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
    @override
    void initState() {
      super.initState();
      _screensaverController.setPlaybackActive(true);
  ```

  Change it to:

  ```dart
    @override
    void initState() {
      super.initState();
      _previousQueueItem = _queue.currentItem;
      _screensaverController.setPlaybackActive(true);
  ```

- [ ] Step 5: Run static analysis to confirm the new fields and control flow compile cleanly

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart
  ```

  Expected output ends with:
  ```
  No issues found!
  ```

- [ ] Step 6: Re-run the full Cinema Mode pure-logic test file to confirm the `shouldShowCinemaBlackout` branches this wiring depends on still pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 7: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Add one-frame full-black cover for the preroll-to-feature cut in Cinema Mode"
  ```

---

### Task 4: Full test suite and preroll-flow regression check

Files:
- Test: `E:\Moonfin-Core\test\ui\screens\playback\cinema_mode_chrome_test.dart` (verify final state)
- No production files modified in this task.

- [ ] Step 1: Run the complete Cinema Mode test file one more time end-to-end, expecting all eight cases (four `shouldSuppressCinemaChrome`, four `shouldShowCinemaBlackout`) to pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/cinema_mode_chrome_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 2: Run `flutter analyze` across the two touched files together to catch any cross-file issue missed by per-file runs in earlier tasks

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart lib/ui/screens/playback/cinema_mode_chrome.dart
  ```

  Expected output ends with:
  ```
  No issues found!
  ```

- [ ] Step 3: Confirm the pre-existing preroll-generation logic in `item_detail_screen.dart` is untouched (this plan is additive only) by diffing it against `origin/main`

  ```
  cd E:\Moonfin-Core && git diff origin/main -- lib/ui/screens/detail/item_detail_screen.dart
  ```

  Expected output:
  ```

  ```
  (empty — no output, confirming `_moviePrerollsForStart` at line 6804 and its `UserPreferences.cinemaModeEnabled` gate at line 6814-6818, and the queue-building call site at lines 7527-7540, are byte-for-byte unchanged; this plan only changes how `VideoPlayerScreen` presents whatever queue `item_detail_screen.dart` already built.)

---

### Verification

This plan implements spec section 5 ("Cinema Mode immersive presentation") exactly as scoped — immersive presentation only, no curtain or countdown animation:

- **"Suppress all UI chrome and overlays... reachable or visible such as the navigation bar, the clock, and any accidental focus-triggered overlay"**: Task 2 generalizes the pre-existing preroll-only `hideOsdForPreroll` gate (which already hides `_buildTopOverlay` — the back/nav bar — and `_buildBottomOverlay` — which contains the `_endsAtLabel` "ends at" clock text — and `_buildLockedOverlay`) so it also evaluates `true` for the main feature whenever `UserPreferences.cinemaModeEnabled` is on, via the single source of truth `shouldSuppressCinemaChrome`, tested in Task 1 Steps 1-5. Task 2 Step 5 closes the "accidental focus-triggered overlay" gap by routing both `_showControls` and `_toggleControls` — the two functions every tap, click, hover, and D-pad `select`/`enter` event ultimately calls — through the same suppression check before they can flip `_controlsVisible` to `true`.
- **"Ensure a clean full-black transition between the preroll sequence ending and the main feature starting with no jarring cut or flash"**: Task 3 adds `shouldShowCinemaBlackout` (tested in Task 1 Steps 6-9) and wires it into the `_queueSub` listener so the exact `queueChangedStream` event where the current item flips from a preroll (`__moonfinIsPreroll == true`, set in `item_detail_screen.dart` line 6834 and read via `_isPrerollQueueItem`/`_isCurrentPreroll` in `video_player_screen.dart` lines 305-310) to the main feature forces one fully opaque black frame — reusing the exact `Positioned.fill(child: ColoredBox(color: Colors.black))` idiom this codebase already uses for the analogous `_isRestoringPosition` screen-lock case — before clearing itself on the next frame via `addPostFrameCallback`.
- **"Additive to the existing preroll-before-playback logic, not a replacement"**: Task 4 Step 3 confirms `item_detail_screen.dart`'s `_moviePrerollsForStart` (the `cinemaModeEnabled`-gated preroll queue builder) is untouched; all changes live in `video_player_screen.dart`'s presentation layer plus the new `cinema_mode_chrome.dart` pure-logic module, and `shouldSuppressCinemaChrome` explicitly preserves today's exact preroll-hiding behavior when Cinema Mode is disabled (Task 1 Step 1 test: `cinemaModeEnabled: false` still suppresses chrome for `isCurrentItemPreroll: true`).
