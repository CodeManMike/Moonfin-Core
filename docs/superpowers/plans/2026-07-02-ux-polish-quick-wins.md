That's fine, no CI reference needed — `flutter test <path>` per the user's instructions is the standard invocation. Now writing the final plan.

# Vertical Navigation, Focus Treatment & Playback Polish Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

Goal: Ship the six small/small-medium UX-polish backlog items from spec section 10 (snappier D-pad timing, non-shifting row focus treatment, cross-library quick-filter chips, an independent grid-density control, trickplay tile prefetch on mount, and consistent D-pad/hardware-remote seek stepping) without touching the two large-scope items, the season/episode route-push rework, the Classic/Modern detail-screen unification, chapter tick marks, or bringup-sequence collapse.

Architecture: All six tasks are surgical edits inside three existing files — `lib/ui/screens/home/home_screen.dart`, `lib/ui/screens/browse/library_browse_screen.dart`, and `lib/ui/screens/playback/video_player_screen.dart` — plus one new preference declaration in `lib/preference/user_preferences.dart` and `lib/preference/preference_constants.dart`. Where the surrounding class is a heavily GetIt-wired `State` (home screen, player screen) that cannot be practically unit-instantiated, pure logic is extracted into standalone top-level functions so it stays unit-testable, and the remaining UI wiring is verified manually on-device per this repo's stated testing conventions.

Tech Stack: Flutter/Dart, `flutter_test`, `mocktail` (declared but not required for these tasks — all six tasks use plain constructible types), local `jellyfin_preference` package (`EnumPreference`/`Preference`), GetIt service locator.

---

### Task 1: Reduce vertical-nav debounce and focus-handoff duration

**Files:**
- Modify: `lib/ui/screens/home/home_screen.dart` (lines 658-660, 2357-2366)
- Test: manual verification procedure (documented below) — no automated test, per explicit instruction for pure timing-constant tuning

This is a pure timing-constant change. `_allowVerticalNavNow()` (lines 2357-2366) gates repeated up/down D-pad presses using a hardcoded `Duration(milliseconds: 140)` literal inline in the comparison (not a named constant), and `_focusHandoffDuration` (line 658) is a named `Duration(milliseconds: 220)` used by `Scrollable.ensureVisible(..., duration: _focusHandoffDuration, curve: _focusHandoffCurve)` at lines 2326-2330. Because both are compile-time constants consumed only by Flutter's internal animation/timer scheduling, there is no observable Dart-level output to assert against in a widget test — the only true signal is perceived input latency on a real remote, which `flutter_test`'s fake clock cannot represent meaningfully. Per this plan's instructions, the verification step is a documented manual procedure, not a fabricated unit test.

- [ ] Step 1: Read the current values to confirm the exact text to replace.

Current code at lines 656-660:
```dart
  static const _previewStartDelay = Duration(milliseconds: 1200);
  static const _focusHandoffDuration = Duration(milliseconds: 220);
  static const _focusHandoffCurve = Curves.easeInOutCubic;
  static const _mediaBarFadeDuration = Duration(milliseconds: 220);
```

Current code at lines 2357-2366:
```dart
  bool _allowVerticalNavNow() {
    final now = DateTime.now();
    if (_lastVerticalNavAt != null &&
        now.difference(_lastVerticalNavAt!) <
            const Duration(milliseconds: 140)) {
      return false;
    }
    _lastVerticalNavAt = now;
    return true;
  }
```

- [ ] Step 2: Extract the inline `140` literal into a named constant next to `_focusHandoffDuration`, and reduce both values. Edit lines 656-660 to:

```dart
  static const _previewStartDelay = Duration(milliseconds: 1200);
  static const _verticalNavDebounceDuration = Duration(milliseconds: 90);
  static const _focusHandoffDuration = Duration(milliseconds: 140);
  static const _focusHandoffCurve = Curves.easeInOutCubic;
  static const _mediaBarFadeDuration = Duration(milliseconds: 220);
```

- [ ] Step 3: Update `_allowVerticalNavNow()` (lines 2357-2366) to reference the new named constant instead of the inline literal:

```dart
  bool _allowVerticalNavNow() {
    final now = DateTime.now();
    if (_lastVerticalNavAt != null &&
        now.difference(_lastVerticalNavAt!) <
            _verticalNavDebounceDuration) {
      return false;
    }
    _lastVerticalNavAt = now;
    return true;
  }
```

- [ ] Step 4: Confirm the file still analyzes cleanly (this catches typos/syntax errors — it is not a behavioral test). Run:
```
flutter analyze lib/ui/screens/home/home_screen.dart
```
Expect output: `No issues found!` (or only pre-existing issues unrelated to these two edits — compare against a pre-edit `flutter analyze` run if any issues appear).

- [ ] Step 5: Manual verification procedure (documented, not automated — timing/feel constants are not meaningfully assertable via `flutter_test`'s fake clock). On a real Android TV device or a physical remote-driven TV build:
  1. Launch Moonfin, land on the Home screen with at least 4 content rows loaded.
  2. Hold the D-pad down button and press it repeatedly at a natural fast cadence (roughly 4-5 presses/second).
  3. Confirm every press moves focus down exactly one row with no dropped presses and no double-jumps — this validates the 90ms debounce is short enough to feel responsive but still suppresses accidental double-fires from remote button bounce.
  4. Confirm the on-screen focus highlight/scroll settles into its new row position quickly and without a noticeable "catch-up" lag, compared to the pre-change build side-by-side — this validates the 140ms focus-handoff duration.
  5. Repeat with D-pad up.
  6. Record pass/fail in the PR description; if presses are dropped or double-fire, increase `_verticalNavDebounceDuration` in 10ms increments and repeat from step 2.

- [ ] Step 6: Commit.
```
git add lib/ui/screens/home/home_screen.dart
git commit -m "$(cat <<'EOF'
Reduce vertical-nav debounce and focus-handoff duration for snappier D-pad response

Extracts the inline 140ms debounce literal into a named constant and drops it to
90ms; reduces focus-handoff animation from 220ms to 140ms to match Plex's
"predictable, fast" D-pad feel called out in the UX polish backlog audit.
EOF
)"
```

---

### Task 2: Stop shifting row layout on focus change

**Files:**
- Modify: `lib/ui/screens/home/home_screen.dart` (lines 3143-3151, 3361-3383)
- Create: `test/ui/screens/home/home_row_focus_treatment_test.dart`

`_focusedRowExtraSpacing` (20.0, line 575) is currently injected two places: (a) the offset-computation loop at lines 3143-3151 adds `focusedRowSpacing` (`_focusedRowExtraSpacing * 2` = 40.0 on TV, non-fullscreen) to `currentTop` after the focused row's extent, which shifts every subsequent row's top offset downward; and (b) the actual `AnimatedPadding` at lines 3361-3383 inserts that same spacing as vertical padding around the focused row's content. Both must be removed together (the offset loop reserves space that the padding then consumes) and replaced with a non-shifting `AnimatedScale` focus treatment applied at the same wrapping site, so no other row's position changes when focus moves.

Because `_ContentRowsState` is a private, deeply GetIt-wired State class, it cannot be practically instantiated in a widget test. Per this repo's convention of extracting pure logic for testability, this task extracts the row-spacing math into a top-level pure function that the test drives directly.

- [ ] Step 1: Read the current spacing computation to confirm exact text.

Current code at lines 3137-3152:
```dart
    final rowExtents = _computeRowExtents(rows, posterSize, prefs);
    final rowTopOffsets = <double>[];
    var currentTop = listTopPadding + infoPlaceholderHeight;
    if (includeMediaBar) {
      currentTop += mediaBarHeight;
    }
    final focusedRowSpacing = PlatformDetection.isTV && !fullScreenRows
        ? _focusedRowExtraSpacing * 2
        : 0.0;
    for (var i = 0; i < rowExtents.length; i++) {
      rowTopOffsets.add(currentTop);
      currentTop += rowExtents[i];
      if (i == _activeFocusedRowIndex) {
        currentTop += focusedRowSpacing;
      }
    }
```

- [ ] Step 2: Write the failing test first. This test exercises the pure helper function `homeRowFocusScale` that Step 4 will add — it does not exist yet, so the test fails to compile, which is the expected "red" state for this extraction.

Create `test/ui/screens/home/home_row_focus_treatment_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/home_screen.dart';

void main() {
  group('homeRowFocusScale', () {
    test('unfocused row is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: false, isTV: true, fullScreenRows: false),
        1.0,
      );
    });

    test('focused row on TV in non-fullscreen mode is scaled up', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: true, fullScreenRows: false),
        greaterThan(1.0),
      );
    });

    test('focused row on TV in fullscreen mode is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: true, fullScreenRows: true),
        1.0,
      );
    });

    test('focused row off TV is not scaled', () {
      expect(
        homeRowFocusScale(isFocused: true, isTV: false, fullScreenRows: false),
        1.0,
      );
    });
  });

  group('homeRowFocusExtraSpacing', () {
    test('always returns zero regardless of focus state', () {
      expect(
        homeRowFocusExtraSpacing(isFocused: true, isTV: true, fullScreenRows: false),
        0.0,
      );
      expect(
        homeRowFocusExtraSpacing(isFocused: false, isTV: true, fullScreenRows: false),
        0.0,
      );
    });
  });
}
```

- [ ] Step 3: Run the test and confirm it fails because `homeRowFocusScale`/`homeRowFocusExtraSpacing` do not exist yet.
```
flutter test test/ui/screens/home/home_row_focus_treatment_test.dart
```
Expected output includes: `Error: Method not found: 'homeRowFocusScale'.` (compile error, since the functions do not exist in `home_screen.dart` yet).

- [ ] Step 4: Add the two pure top-level functions to `home_screen.dart`, directly above the `_ContentRows` class declaration (which starts at line 548). Insert before line 548:

```dart
/// Scale factor applied to a home row's content when it holds D-pad focus.
///
/// Returns `1.0` (no scaling) unless running on a TV platform in the
/// non-fullscreen row layout, so the focused-row visual treatment never
/// shifts sibling rows — see [homeRowFocusExtraSpacing], which is always
/// zero for the same reason.
double homeRowFocusScale({
  required bool isFocused,
  required bool isTV,
  required bool fullScreenRows,
}) {
  if (!isFocused || !isTV || fullScreenRows) return 1.0;
  return 1.04;
}

/// Extra vertical spacing reserved after a focused home row.
///
/// Always zero: the focused-row treatment is a non-shifting scale
/// ([homeRowFocusScale]) rather than inserted padding, so sibling row
/// positions never move when focus changes.
double homeRowFocusExtraSpacing({
  required bool isFocused,
  required bool isTV,
  required bool fullScreenRows,
}) {
  return 0.0;
}

class _ContentRows extends StatefulWidget {
```

- [ ] Step 5: Run the test again and confirm it passes.
```
flutter test test/ui/screens/home/home_row_focus_treatment_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 6: Wire the offset-computation loop (lines 3143-3151) to use the new always-zero helper instead of `_focusedRowExtraSpacing * 2`, removing the row-shifting behavior. Replace:
```dart
    final focusedRowSpacing = PlatformDetection.isTV && !fullScreenRows
        ? _focusedRowExtraSpacing * 2
        : 0.0;
    for (var i = 0; i < rowExtents.length; i++) {
      rowTopOffsets.add(currentTop);
      currentTop += rowExtents[i];
      if (i == _activeFocusedRowIndex) {
        currentTop += focusedRowSpacing;
      }
    }
```
with:
```dart
    for (var i = 0; i < rowExtents.length; i++) {
      rowTopOffsets.add(currentTop);
      currentTop += rowExtents[i];
      currentTop += homeRowFocusExtraSpacing(
        isFocused: i == _activeFocusedRowIndex,
        isTV: PlatformDetection.isTV,
        fullScreenRows: fullScreenRows,
      );
    }
```

- [ ] Step 7: Replace the `AnimatedPadding` at lines 3361-3383 with an `AnimatedScale` that does not reserve extra layout space. Replace:
```dart
              final itemWidget = Padding(
                padding: EdgeInsets.only(left: rowLeftInset),
                child: AnimatedPadding(
                  duration: _focusedRowSpacingDuration,
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                    vertical:
                        (PlatformDetection.isTV &&
                            !fullScreenRows &&
                            rowIndex == _activeFocusedRowIndex)
                        ? _focusedRowExtraSpacing
                        : 0,
                  ),
                  child: _buildShiftedRow(
                    child: paddedRowChild,
                    rowIndex: rowIndex,
                    rowTopOffsets: rowTopOffsets,
                    rowExtents: rowExtents,
                    showInfoOverlay: showInfoOverlay,
                    overlayBottom: overlayBottom,
                  ),
                ),
              );
```
with:
```dart
              final itemWidget = Padding(
                padding: EdgeInsets.only(left: rowLeftInset),
                child: AnimatedScale(
                  duration: _focusedRowSpacingDuration,
                  curve: Curves.easeOut,
                  alignment: Alignment.centerLeft,
                  scale: homeRowFocusScale(
                    isFocused: rowIndex == _activeFocusedRowIndex,
                    isTV: PlatformDetection.isTV,
                    fullScreenRows: fullScreenRows,
                  ),
                  child: _buildShiftedRow(
                    child: paddedRowChild,
                    rowIndex: rowIndex,
                    rowTopOffsets: rowTopOffsets,
                    rowExtents: rowExtents,
                    showInfoOverlay: showInfoOverlay,
                    overlayBottom: overlayBottom,
                  ),
                ),
              );
```

- [ ] Step 8: `_focusedRowExtraSpacing` (line 575) is now unused — remove it to keep `flutter analyze` clean. Read the field declaration once more to confirm no other usage remains.
```
flutter analyze lib/ui/screens/home/home_screen.dart 2>&1 | grep -i "_focusedRowExtraSpacing\|unused"
```
Confirm the only remaining reference is the declaration itself at line 575, then remove that line. Replace:
```dart
  static const double _kHomeRowLabelInset = 16.0;
  static const double _focusedRowExtraSpacing = 20.0;
  static const Duration _focusedRowSpacingDuration = Duration(
    milliseconds: 200,
  );
```
with:
```dart
  static const double _kHomeRowLabelInset = 16.0;
  static const Duration _focusedRowSpacingDuration = Duration(
    milliseconds: 200,
  );
```

- [ ] Step 9: Run `flutter analyze` on the file and the full test file again to confirm everything is still green.
```
flutter analyze lib/ui/screens/home/home_screen.dart && flutter test test/ui/screens/home/home_row_focus_treatment_test.dart
```
Expected: `No issues found!` followed by `All tests passed!`

- [ ] Step 10: Manual verification procedure (documented, not automated — the scroll-position/visual-jitter behavior this fixes is only meaningfully observable in a real running app). On a TV build or emulator with D-pad input:
  1. Load Home with 5+ rows, none in fullscreen-rows mode.
  2. Move focus down through the rows one at a time.
  3. Confirm rows below the focused row do not visibly shift/jump vertically as focus moves — only the focused row's own card content should subtly scale up.
  4. Confirm scrolling to keep the focused row visible still works correctly (no items clipped or misaligned).

- [ ] Step 11: Commit.
```
git add lib/ui/screens/home/home_screen.dart test/ui/screens/home/home_row_focus_treatment_test.dart
git commit -m "$(cat <<'EOF'
Replace row-shifting focus spacing with a non-shifting scale treatment

Removes the 40px AnimatedPadding inserted after the focused home row (which
shifted every row below it) and replaces it with an AnimatedScale applied to
the focused row's own content, so focus changes no longer move sibling rows.
EOF
)"
```

---

### Task 3: Extend book-library inline quick-filter chips to movie/show/music libraries

**Files:**
- Modify: `lib/ui/screens/browse/library_browse_screen.dart` (lines 577-624, 1065-1256, 2067-2098, 2100-2146)
- Create: `test/ui/screens/browse/library_status_chips_test.dart`

`_BookStatusCategories` and `_BookOrganizeChips` are fully built but **currently dead code in production** — the only call site (`_LibraryHeader` instantiation at lines 577-624) hardcodes `isBookBrowse: false`, so these chip rows never render regardless of library type. This task (a) fixes that wiring bug so book libraries actually get their chips, and (b) generalizes `_BookStatusCategories` into a library-type-agnostic `_StatusFilterChips` widget rendered for movie/show/music libraries too (replacing the full-modal round-trip through `_showFilterSortDialog` for a plain favorites/unwatched toggle). `_BookOrganizeChips` (author/genre grouping) is book-specific and stays book-only — only the played/favorite status chips generalize, per the spec's explicit target ("replacing the current full-modal round-trip for every favorites/unwatched toggle").

- [ ] Step 1: Read the current dead-wiring call site and the widget being extended, to confirm exact text (already captured above; reproduced here for the diff).

Current code at lines 606-611:
```dart
                isMusicBrowse: _vm.isMusicBrowse,
                isBookBrowse: false,
                activeBookTab: _bookMediaTab,
                bookOrganizeMode: _bookOrganizeMode,
                playedFilter: _vm.playedFilter,
                favoriteFilter: _vm.favoriteFilter,
```

Current code at lines 2100-2146 (`_BookStatusCategories`, to be generalized):
```dart
class _BookStatusCategories extends StatelessWidget {
  final PlayedStatusFilter playedFilter;
  final bool favoriteFilter;
  final ValueChanged<PlayedStatusFilter> onPlayedFilterChanged;
  final ValueChanged<bool> onFavoriteFilterChanged;

  const _BookStatusCategories({
    required this.playedFilter,
    required this.favoriteFilter,
    required this.onPlayedFilterChanged,
    required this.onFavoriteFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BookFilterChip(
          label: l10n.all,
          selected: playedFilter == PlayedStatusFilter.all && !favoriteFilter,
          onTap: () {
            onFavoriteFilterChanged(false);
            onPlayedFilterChanged(PlayedStatusFilter.all);
          },
        ),
        _BookFilterChip(
          label: l10n.unread,
          selected: playedFilter == PlayedStatusFilter.unwatched,
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.unwatched),
        ),
        _BookFilterChip(
          label: l10n.readStatus,
          selected: playedFilter == PlayedStatusFilter.watched,
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.watched),
        ),
        _BookFilterChip(
          label: l10n.favorites,
          selected: favoriteFilter,
          onTap: () => onFavoriteFilterChanged(!favoriteFilter),
        ),
      ],
    );
  }
}
```

- [ ] Step 2: Write the failing test first, against a pure label-selection helper function this task will add (`statusChipLabels`), which decides "Watched"/"Unwatched" vs "Read"/"Unread" wording without needing `BuildContext`/`AppLocalizations` in the test. Because `_LibraryHeader` and its dialog siblings are private widgets inside a screen with GetIt-backed dependencies elsewhere in the file, this test targets the extracted pure decision function rather than pumping the full screen.

Create `test/ui/screens/browse/library_status_chips_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';

void main() {
  group('isStatusChipSelected', () {
    test('All chip is selected only when filter is all and favorite is off', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.all,
          playedFilter: PlayedStatusFilter.all,
          favoriteFilter: false,
        ),
        isTrue,
      );
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.all,
          playedFilter: PlayedStatusFilter.all,
          favoriteFilter: true,
        ),
        isFalse,
      );
    });

    test('Unwatched chip tracks the unwatched played filter', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.unwatched,
          playedFilter: PlayedStatusFilter.unwatched,
          favoriteFilter: false,
        ),
        isTrue,
      );
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.unwatched,
          playedFilter: PlayedStatusFilter.watched,
          favoriteFilter: false,
        ),
        isFalse,
      );
    });

    test('Favorites chip tracks favoriteFilter independent of played filter', () {
      expect(
        isStatusChipSelected(
          chip: StatusChipKind.favorites,
          playedFilter: PlayedStatusFilter.watched,
          favoriteFilter: true,
        ),
        isTrue,
      );
    });
  });
}
```

- [ ] Step 3: Run the test and confirm it fails to compile because `StatusChipKind` and `isStatusChipSelected` do not exist yet.
```
flutter test test/ui/screens/browse/library_status_chips_test.dart
```
Expected output includes: `Error: Type 'StatusChipKind' not found.`

- [ ] Step 4: Add the pure enum and selection function to `library_browse_screen.dart`, directly above the `_BookOrganizeChips` class (line 2067). Insert before line 2067:

```dart
/// The four quick-filter chips shown inline above a library grid.
enum StatusChipKind { all, unwatched, watched, favorites }

/// Whether [chip] should render as selected given the current filter state.
///
/// Mirrors the selection logic already used by the book-library chip row so
/// movie/show/music libraries get identical toggle semantics: the "all" chip
/// is only selected when both the played filter is [PlayedStatusFilter.all]
/// and the favorite filter is off, while the other three chips each track a
/// single independent filter value.
bool isStatusChipSelected({
  required StatusChipKind chip,
  required PlayedStatusFilter playedFilter,
  required bool favoriteFilter,
}) {
  return switch (chip) {
    StatusChipKind.all =>
      playedFilter == PlayedStatusFilter.all && !favoriteFilter,
    StatusChipKind.unwatched => playedFilter == PlayedStatusFilter.unwatched,
    StatusChipKind.watched => playedFilter == PlayedStatusFilter.watched,
    StatusChipKind.favorites => favoriteFilter,
  };
}
```

- [ ] Step 5: Run the test again and confirm it passes.
```
flutter test test/ui/screens/browse/library_status_chips_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 6: Generalize `_BookStatusCategories` into `_StatusFilterChips`, using the new pure helper and swapping the book-specific "Read"/"Unread" labels for a `isBookLibrary` flag so the same widget serves both. Replace the class at lines 2100-2146:
```dart
class _BookStatusCategories extends StatelessWidget {
  final PlayedStatusFilter playedFilter;
  final bool favoriteFilter;
  final ValueChanged<PlayedStatusFilter> onPlayedFilterChanged;
  final ValueChanged<bool> onFavoriteFilterChanged;

  const _BookStatusCategories({
    required this.playedFilter,
    required this.favoriteFilter,
    required this.onPlayedFilterChanged,
    required this.onFavoriteFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BookFilterChip(
          label: l10n.all,
          selected: playedFilter == PlayedStatusFilter.all && !favoriteFilter,
          onTap: () {
            onFavoriteFilterChanged(false);
            onPlayedFilterChanged(PlayedStatusFilter.all);
          },
        ),
        _BookFilterChip(
          label: l10n.unread,
          selected: playedFilter == PlayedStatusFilter.unwatched,
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.unwatched),
        ),
        _BookFilterChip(
          label: l10n.readStatus,
          selected: playedFilter == PlayedStatusFilter.watched,
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.watched),
        ),
        _BookFilterChip(
          label: l10n.favorites,
          selected: favoriteFilter,
          onTap: () => onFavoriteFilterChanged(!favoriteFilter),
        ),
      ],
    );
  }
}
```
with:
```dart
class _StatusFilterChips extends StatelessWidget {
  final PlayedStatusFilter playedFilter;
  final bool favoriteFilter;
  final bool isBookLibrary;
  final ValueChanged<PlayedStatusFilter> onPlayedFilterChanged;
  final ValueChanged<bool> onFavoriteFilterChanged;

  const _StatusFilterChips({
    required this.playedFilter,
    required this.favoriteFilter,
    required this.isBookLibrary,
    required this.onPlayedFilterChanged,
    required this.onFavoriteFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BookFilterChip(
          label: l10n.all,
          selected: isStatusChipSelected(
            chip: StatusChipKind.all,
            playedFilter: playedFilter,
            favoriteFilter: favoriteFilter,
          ),
          onTap: () {
            onFavoriteFilterChanged(false);
            onPlayedFilterChanged(PlayedStatusFilter.all);
          },
        ),
        _BookFilterChip(
          label: isBookLibrary ? l10n.unread : l10n.unwatched,
          selected: isStatusChipSelected(
            chip: StatusChipKind.unwatched,
            playedFilter: playedFilter,
            favoriteFilter: favoriteFilter,
          ),
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.unwatched),
        ),
        _BookFilterChip(
          label: isBookLibrary ? l10n.readStatus : l10n.watched,
          selected: isStatusChipSelected(
            chip: StatusChipKind.watched,
            playedFilter: playedFilter,
            favoriteFilter: favoriteFilter,
          ),
          onTap: () => onPlayedFilterChanged(PlayedStatusFilter.watched),
        ),
        _BookFilterChip(
          label: l10n.favorites,
          selected: isStatusChipSelected(
            chip: StatusChipKind.favorites,
            playedFilter: playedFilter,
            favoriteFilter: favoriteFilter,
          ),
          onTap: () => onFavoriteFilterChanged(!favoriteFilter),
        ),
      ],
    );
  }
}
```

- [ ] Step 7: Update the two call sites inside `_LibraryHeader.build()` that referenced `_BookStatusCategories`/`isBookBrowse`-gated rendering. First, read the surrounding conditional block again (lines 1237-1255) to confirm exact text:
```dart
          if (isBookBrowse) ...[
            const SizedBox(height: 10),
            _BookMediaTabs(
              activeTab: activeBookTab,
              onChanged: onBookTabChanged,
            ),
            const SizedBox(height: 8),
            _BookStatusCategories(
              playedFilter: playedFilter,
              favoriteFilter: favoriteFilter,
              onPlayedFilterChanged: onPlayedFilterChanged,
              onFavoriteFilterChanged: onFavoriteFilterChanged,
            ),
            const SizedBox(height: 8),
            _BookOrganizeChips(
              mode: bookOrganizeMode,
              onChanged: onBookOrganizeChanged,
            ),
          ],
```
Replace with:
```dart
          if (isBookBrowse) ...[
            const SizedBox(height: 10),
            _BookMediaTabs(
              activeTab: activeBookTab,
              onChanged: onBookTabChanged,
            ),
            const SizedBox(height: 8),
            _StatusFilterChips(
              playedFilter: playedFilter,
              favoriteFilter: favoriteFilter,
              isBookLibrary: true,
              onPlayedFilterChanged: onPlayedFilterChanged,
              onFavoriteFilterChanged: onFavoriteFilterChanged,
            ),
            const SizedBox(height: 8),
            _BookOrganizeChips(
              mode: bookOrganizeMode,
              onChanged: onBookOrganizeChanged,
            ),
          ] else if (!isMusicBrowse) ...[
            const SizedBox(height: 8),
            _StatusFilterChips(
              playedFilter: playedFilter,
              favoriteFilter: favoriteFilter,
              isBookLibrary: false,
              onPlayedFilterChanged: onPlayedFilterChanged,
              onFavoriteFilterChanged: onFavoriteFilterChanged,
            ),
          ],
```
(Music libraries are excluded here because `LibraryBrowseViewModel` does not track per-item played/favorite state the same way for albums/artists — `isMusicBrowse` already gates the settings-dialog image-type section off for the same reason at line 1212, so this follows existing precedent in the same widget.)

- [ ] Step 8: Fix the dead-wiring bug at the only `_LibraryHeader` call site so `isBookBrowse` reflects the real view-model state instead of a hardcoded `false`. Replace line 607:
```dart
                isBookBrowse: false,
```
with:
```dart
                isBookBrowse: _vm.isBookLibrary,
```

- [ ] Step 9: Run `flutter analyze` on the file to confirm the rename from `_BookStatusCategories` to `_StatusFilterChips` left no dangling references.
```
flutter analyze lib/ui/screens/browse/library_browse_screen.dart
```
Expected: `No issues found!`

- [ ] Step 10: Run the unit test file again to reconfirm it still passes after the widget-level edits (the pure function under test is unchanged by Steps 6-8, so this is a regression check).
```
flutter test test/ui/screens/browse/library_status_chips_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 11: Manual verification procedure (documented — the chip row's visual rendering and tap-to-filter round-trip against a real library requires a running app with a real or test Jellyfin server). On a device/emulator connected to a real server:
  1. Open a movie library. Confirm the "All / Unwatched / Watched / Favorites" chip row now renders inline below the toolbar (previously invisible due to the wiring bug).
  2. Tap "Unwatched". Confirm the grid filters immediately without opening the sort/filter modal, and the chip shows selected state.
  3. Tap "Favorites". Confirm the grid filters to favorites and "All" deselects.
  4. Repeat for a TV-show library and confirm identical behavior.
  5. Open a music library and confirm the chip row does NOT render (excluded per Step 7).
  6. Open a book library and confirm "Read/Unread" labels (not "Watched/Unwatched") still render, matching pre-change book behavior, and the chips now actually appear where before they were silently dead.

- [ ] Step 12: Commit.
```
git add lib/ui/screens/browse/library_browse_screen.dart test/ui/screens/browse/library_status_chips_test.dart
git commit -m "$(cat <<'EOF'
Extend book-library quick-filter chips to movie/show libraries

Generalizes _BookStatusCategories into _StatusFilterChips (book-agnostic
labels) and fixes the isBookBrowse: false hardcode that silently prevented
the chip row from ever rendering, so movie/show libraries get the same
inline favorites/unwatched/watched toggle instead of a full-modal round-trip.
EOF
)"
```

---

### Task 4: Add a direct list/grid density control independent of poster size

**Files:**
- Modify: `lib/preference/preference_constants.dart` (after line 99), `lib/preference/user_preferences.dart` (after line 619), `lib/ui/screens/browse/library_browse_screen.dart` (lines 665-689, 1941-1943, 1974-2003), `lib/l10n/app_en.arb` (after line 526)
- Create: `test/ui/screens/browse/library_grid_density_test.dart`

`_buildGrid()`'s `crossAxisCount` (lines 685-689) is currently derived purely from `cardWidth` (which comes from `_vm.posterSize`, line 675/271-283) divided into the available width, clamped `2..20`. There is no separate density concept — poster size and column count are coupled. This task adds a `GridDensity` enum (`comfortable`/`compact`) and a `libraryGridDensity` preference that scales the *effective* column-width divisor independently of the poster-size-driven `cardWidth`, exposed as a new radio group in `_SettingsDialog` alongside the existing poster-size radios.

- [ ] Step 1: Write the failing test first, against a pure top-level function `gridCrossAxisCountFor` that Step 4 will add. This function takes the same inputs `_buildGrid()`'s `LayoutBuilder` already computes locally (`constraints.maxWidth`, `gridPadding`, `cardWidth`, `spacing`) plus the new density enum, so it is testable with plain numbers and no widget pump.

Create `test/ui/screens/browse/library_grid_density_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';

void main() {
  group('gridCrossAxisCountFor', () {
    test('comfortable density matches the existing unscaled column count', () {
      final count = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.comfortable,
      );
      // (1200 - 120 + 12) / (150 + 12) floored = 6
      expect(count, 6);
    });

    test('compact density increases column count for the same width', () {
      final comfortable = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.comfortable,
      );
      final compact = gridCrossAxisCountFor(
        availableWidth: 1200,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.compact,
      );
      expect(compact, greaterThan(comfortable));
    });

    test('result is clamped between 2 and 20 regardless of density', () {
      final tiny = gridCrossAxisCountFor(
        availableWidth: 50,
        gridPadding: 60,
        cardWidth: 150,
        spacing: 12,
        density: GridDensity.compact,
      );
      expect(tiny, 2);

      final huge = gridCrossAxisCountFor(
        availableWidth: 20000,
        gridPadding: 60,
        cardWidth: 40,
        spacing: 4,
        density: GridDensity.compact,
      );
      expect(huge, 20);
    });
  });
}
```

- [ ] Step 2: Run the test and confirm it fails to compile because `GridDensity` and `gridCrossAxisCountFor` do not exist yet.
```
flutter test test/ui/screens/browse/library_grid_density_test.dart
```
Expected output includes: `Error: Type 'GridDensity' not found.`

- [ ] Step 3: Add the `GridDensity` enum to `preference_constants.dart`, directly after the `PosterSize` enum (line 99). Insert after line 99:

```dart

enum GridDensity {
  comfortable(columnScale: 1.0),
  compact(columnScale: 0.8);

  const GridDensity({required this.columnScale});

  /// Multiplier applied to the effective card-width divisor when computing
  /// grid column count: values below 1.0 pack more columns into the same
  /// width without changing the poster-size preference.
  final double columnScale;
}
```

- [ ] Step 4: Add the pure `gridCrossAxisCountFor` function to `library_browse_screen.dart`, directly above the `LibraryBrowseScreen` class declaration (line 48). Insert before line 48:

```dart
/// Computes the grid column count for a library grid, applying [density]'s
/// [GridDensity.columnScale] to the effective card width independently of
/// the poster-size preference that produced [cardWidth].
int gridCrossAxisCountFor({
  required double availableWidth,
  required double gridPadding,
  required double cardWidth,
  required double spacing,
  required GridDensity density,
}) {
  final effectiveCardWidth = cardWidth * density.columnScale;
  return ((availableWidth - gridPadding * 2 + spacing) /
          (effectiveCardWidth + spacing))
      .floor()
      .clamp(2, 20);
}
```

- [ ] Step 5: Run the test again and confirm it passes.
```
flutter test test/ui/screens/browse/library_grid_density_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 6: Add the `libraryGridDensity` preference to `user_preferences.dart`, directly after `libraryPosterSize` (line 619). Insert after line 619:

```dart

  static final libraryGridDensity = EnumPreference(
    key: 'library_grid_density',
    defaultValue: GridDensity.comfortable,
    values: GridDensity.values,
  );
```

- [ ] Step 7: Wire `_buildGrid()`'s `crossAxisCount` computation to use the new function and preference. Read the current code at lines 681-690 once more to confirm exact text:
```dart
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = _isCompact(context);
        final gridPadding = isMobile ? 16.0 : _horizontalPadding;
        final crossAxisCount =
            ((constraints.maxWidth - gridPadding * 2 + spacing) /
                    (cardWidth + spacing))
                .floor()
                .clamp(2, 20);
```
Replace with:
```dart
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = _isCompact(context);
        final gridPadding = isMobile ? 16.0 : _horizontalPadding;
        final crossAxisCount = gridCrossAxisCountFor(
          availableWidth: constraints.maxWidth,
          gridPadding: gridPadding,
          cardWidth: cardWidth,
          spacing: spacing,
          density: _prefs.get(UserPreferences.libraryGridDensity),
        );
```

- [ ] Step 8: Add a density radio section to `_SettingsDialog` (in `library_browse_screen.dart`), reusing the existing `_radioCircle` helper and following the exact structure of the poster-size section immediately above it. Read the current end of `_SettingsDialogState.build()` (lines 1930-1946) to confirm exact text:
```dart
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                l10n.posterSize,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: sectionColor,
                ),
              ),
            ),
            for (final size in PosterSize.values)
              _posterSizeRadioTile(vm, size),
          ],
        ),
      ),
    );
  }
```
Replace with:
```dart
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                l10n.posterSize,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: sectionColor,
                ),
              ),
            ),
            for (final size in PosterSize.values)
              _posterSizeRadioTile(vm, size),
            Divider(color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                l10n.gridDensity,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: sectionColor,
                ),
              ),
            ),
            for (final density in GridDensity.values)
              _gridDensityRadioTile(vm, density),
          ],
        ),
      ),
    );
  }

  Widget _gridDensityRadioTile(LibraryBrowseViewModel vm, GridDensity density) {
    final selected =
        widget.vm.prefs.get(UserPreferences.libraryGridDensity) == density;
    final accent = vm.isBookLibrary ? _bookAccent : _jellyfinBlue;
    final onSurface = AppColorScheme.onSurface;
    final l10n = AppLocalizations.of(context);
    final label = switch (density) {
      GridDensity.comfortable => l10n.gridDensityComfortable,
      GridDensity.compact => l10n.gridDensityCompact,
    };
    return InkWell(
      onTap: () {
        unawaited(
          widget.vm.prefs.set(UserPreferences.libraryGridDensity, density),
        );
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            _radioCircle(selected, accent),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: selected ? onSurface : onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] Step 9: The new radio tile reads `widget.vm.prefs`, but `LibraryBrowseViewModel` does not currently expose its private `_prefs` field publicly. Check and add the getter. Read `lib/data/viewmodels/library_browse_view_model.dart` lines 13-16 to confirm the field:
```dart
class LibraryBrowseViewModel extends ChangeNotifier {
  final MediaServerClient _client;
  final UserPreferences _prefs;
  final MdbListRepository _mdbListRepository;
```
Add a public getter directly after line 16 (`final List<String>? includeItemTypes;` follows at line 20 — insert the getter after the constructor-injected fields block, right before the `static const _pageSize = 48;` line):

Current code at lines 13-23:
```dart
class LibraryBrowseViewModel extends ChangeNotifier {
  final MediaServerClient _client;
  final UserPreferences _prefs;
  final MdbListRepository _mdbListRepository;
  final String libraryId;
  final String? genreId;
  final String? overrideName;
  final List<String>? includeItemTypes;

  static const _pageSize = 48;
  static const _firstPageSize = 75;
```
Replace with:
```dart
class LibraryBrowseViewModel extends ChangeNotifier {
  final MediaServerClient _client;
  final UserPreferences _prefs;
  final MdbListRepository _mdbListRepository;
  final String libraryId;
  final String? genreId;
  final String? overrideName;
  final List<String>? includeItemTypes;

  UserPreferences get prefs => _prefs;

  static const _pageSize = 48;
  static const _firstPageSize = 75;
```

- [ ] Step 10: Add the two new l10n strings. Read `lib/l10n/app_en.arb` lines 523-527 to confirm exact insertion point:
```json
  "extraLarge": "Extra Large",
  "@extraLarge": {
    "description": "Poster size option"
  },
  "libraryGenresTitle": "{name} \u2014 Genres",
```
Replace with:
```json
  "extraLarge": "Extra Large",
  "@extraLarge": {
    "description": "Poster size option"
  },
  "gridDensity": "Grid Density",
  "@gridDensity": {
    "description": "Section header for grid density selection, independent of poster size"
  },
  "gridDensityComfortable": "Comfortable",
  "@gridDensityComfortable": {
    "description": "Grid density option showing fewer, larger columns"
  },
  "gridDensityCompact": "Compact",
  "@gridDensityCompact": {
    "description": "Grid density option showing more, smaller columns"
  },
  "libraryGenresTitle": "{name} \u2014 Genres",
```

- [ ] Step 11: Regenerate localizations so `AppLocalizations.gridDensity` etc. exist, then run `flutter analyze` on both changed Dart files.
```
flutter gen-l10n && flutter analyze lib/ui/screens/browse/library_browse_screen.dart lib/data/viewmodels/library_browse_view_model.dart lib/preference/preference_constants.dart lib/preference/user_preferences.dart
```
Expected: `No issues found!`

- [ ] Step 12: Run the unit test file again to reconfirm the pure function still behaves correctly after wiring.
```
flutter test test/ui/screens/browse/library_grid_density_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 13: Manual verification procedure (documented — visual grid re-layout and preference persistence across app restart requires a running app). On a device/emulator:
  1. Open a movie library, open the settings dialog (gear icon), confirm a new "Grid Density" section with "Comfortable"/"Compact" radios appears below "Poster Size".
  2. Note the current column count. Switch to "Compact". Confirm more columns render immediately without changing poster thumbnail size (poster size selection is untouched).
  3. Switch "Poster Size" to "Large" while density is "Compact". Confirm poster size changes independently — density and poster size do not fight each other.
  4. Restart the app and reopen the library. Confirm the density selection persisted.

- [ ] Step 14: Commit.
```
git add lib/preference/preference_constants.dart lib/preference/user_preferences.dart lib/ui/screens/browse/library_browse_screen.dart lib/data/viewmodels/library_browse_view_model.dart lib/l10n/app_en.arb test/ui/screens/browse/library_grid_density_test.dart
git commit -m "$(cat <<'EOF'
Add a grid density control independent of poster size

Introduces GridDensity (comfortable/compact) and a libraryGridDensity
preference that scales the column-count divisor without touching the
poster-size preference, exposed as a new radio section in the library
settings dialog.
EOF
)"
```

---

### Task 5: Prefetch trickplay tiles on player mount

**Files:**
- Modify: `lib/ui/screens/playback/video_player_screen.dart` (lines 2027-2050)
- Create: `test/data/models/trickplay_prefetch_test.dart`

Trickplay *metadata* (`TrickplayInfo`) already loads on mount via `_loadSegmentsForCurrentItem()` → `_loadTrickplayInfo(item)` (called from `initState()` at line 797). The scrub-lag the spec calls out is that the actual sprite-sheet **images** are only requested when `_getTrickplayTile()` builds an `Image.network(...)` widget, which only happens while `_isSeeking` is true (line 4156) — i.e., the first frame of the first scrub drag is always a cold network fetch. `appletv_player_host_screen.dart`'s `_trickplayPayload()` already contains a proven formula for computing every sprite-sheet image URL for the whole timeline (`imageCount = (durationMs / (interval * tilesPerImage)).ceil() + 1`, clamped `1..128`); this task extracts that formula into a shared, testable pure function and uses it to `precacheImage` every sprite-sheet URL immediately after trickplay info loads on mount, so the images are already in Flutter's image cache before the user starts scrubbing.

- [ ] Step 1: Write the failing test first, against a pure function `trickplayImageCountFor` that computes how many sprite-sheet images must be prefetched for a given duration and `TrickplayInfo`.

Create `test/data/models/trickplay_prefetch_test.dart`:
```dart
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

    test('clamps to a minimum of 1 image', () {
      final count = trickplayImageCountFor(durationMs: 1, info: info);
      expect(count, 1);
    });
  });
}
```

- [ ] Step 2: Run the test and confirm it fails to compile because `trickplayImageCountFor` does not exist yet.
```
flutter test test/data/models/trickplay_prefetch_test.dart
```
Expected output includes: `Error: Method not found: 'trickplayImageCountFor'.`

- [ ] Step 3: Add the pure function to `lib/data/models/trickplay_info.dart`, at the end of the file (after the closing brace of `TrickplayInfo`, currently line 53). Read the current file end to confirm exact text:
```dart
    return TrickplayInfo(
      width: (info['Width'] as num?)?.toInt() ?? 0,
      height: (info['Height'] as num?)?.toInt() ?? 0,
      tileWidth: (info['TileWidth'] as num?)?.toInt() ?? 0,
      tileHeight: (info['TileHeight'] as num?)?.toInt() ?? 0,
      interval: (info['Interval'] as num?)?.toInt() ?? 0,
    );
  }
}
```
Replace with:
```dart
    return TrickplayInfo(
      width: (info['Width'] as num?)?.toInt() ?? 0,
      height: (info['Height'] as num?)?.toInt() ?? 0,
      tileWidth: (info['TileWidth'] as num?)?.toInt() ?? 0,
      tileHeight: (info['TileHeight'] as num?)?.toInt() ?? 0,
      interval: (info['Interval'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Number of trickplay sprite-sheet images that cover a media item of
/// [durationMs] milliseconds, given [info]'s tile grid and sampling
/// interval. Falls back to 16 when duration is not yet known (zero or
/// negative), and is always clamped to the 1-128 range the server's
/// trickplay image index accepts.
int trickplayImageCountFor({required int durationMs, required TrickplayInfo info}) {
  final msPerImage = info.interval * info.tilesPerImage;
  final count = durationMs > 0 && msPerImage > 0
      ? (durationMs / msPerImage).ceil() + 1
      : 16;
  return count.clamp(1, 128);
}
```

- [ ] Step 4: Run the test again and confirm it passes.
```
flutter test test/data/models/trickplay_prefetch_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 5: Wire `_loadTrickplayInfo` in `video_player_screen.dart` to precache every computed sprite-sheet URL right after metadata loads. Read the current method (lines 2027-2050) once more to confirm exact text:
```dart
  void _loadTrickplayInfo(dynamic item) {
    final rawData = _rawDataForQueueItem(item);
    if (rawData == null) {
      if (mounted) {
        setState(() {
          _trickplayInfo = null;
          _trickplayMediaSourceId = null;
        });
      }
      return;
    }

    final mediaSourceId = _manager.currentResolution?.mediaSourceId;
    final info = TrickplayInfo.fromItemData(
      rawData,
      mediaSourceId: mediaSourceId,
    );
    if (mounted) {
      setState(() {
        _trickplayInfo = info;
        _trickplayMediaSourceId = mediaSourceId;
      });
    }
  }
```
Replace with:
```dart
  void _loadTrickplayInfo(dynamic item) {
    final rawData = _rawDataForQueueItem(item);
    if (rawData == null) {
      if (mounted) {
        setState(() {
          _trickplayInfo = null;
          _trickplayMediaSourceId = null;
        });
      }
      return;
    }

    final mediaSourceId = _manager.currentResolution?.mediaSourceId;
    final info = TrickplayInfo.fromItemData(
      rawData,
      mediaSourceId: mediaSourceId,
    );
    if (mounted) {
      setState(() {
        _trickplayInfo = info;
        _trickplayMediaSourceId = mediaSourceId;
      });
    }
    if (info != null && info.isValid) {
      _prefetchTrickplayTiles(item, info, mediaSourceId);
    }
  }

  void _prefetchTrickplayTiles(
    dynamic item,
    TrickplayInfo info,
    String? mediaSourceId,
  ) {
    if (!_prefs.get(UserPreferences.trickPlayEnabled)) return;
    final itemId = _itemIdForQueueItem(item);
    if (itemId == null || itemId.isEmpty) return;

    final rawData = _rawDataForQueueItem(item);
    final runtimeTicks = rawData?['RunTimeTicks'] as int?;
    final durationMs = runtimeTicks != null ? runtimeTicks ~/ 10000 : 0;
    final imageCount = trickplayImageCountFor(
      durationMs: durationMs,
      info: info,
    );

    final client = _clientForQueueItem(item);
    final token = client.accessToken;
    final headers = <String, String>{
      if (token != null && token.isNotEmpty)
        'Authorization': 'MediaBrowser Token="$token"',
    };

    for (var i = 0; i < imageCount; i++) {
      final url = client.imageApi.getTrickplayTileImageUrl(
        itemId,
        width: info.width,
        index: i,
        mediaSourceId: mediaSourceId,
      );
      final provider = NetworkImage(url, headers: headers.isEmpty ? null : headers);
      unawaited(
        precacheImage(provider, context).catchError((_) {}),
      );
    }
  }
```

- [ ] Step 6: Confirm `TrickplayInfo` is already imported in `video_player_screen.dart` (it is — line 31 already imports `'../../../data/models/trickplay_info.dart'`), so `trickplayImageCountFor` is available without a new import since it lives in the same file. Run `flutter analyze` on the modified file.
```
flutter analyze lib/ui/screens/playback/video_player_screen.dart
```
Expected: `No issues found!`

- [ ] Step 7: Run both trickplay-related test files together to confirm no regressions.
```
flutter test test/data/models/trickplay_prefetch_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 8: Manual verification procedure (documented — actual network prefetch timing and scrub-drag responsiveness can only be observed against a real server with trickplay-enabled content). On a device/emulator with trickplay enabled and a real Jellyfin server:
  1. Open Network tools (or server access logs) and start playback of an item with trickplay sprite sheets available.
  2. Confirm sprite-sheet image requests (`.../Items/{id}/Trickplay/...`) fire immediately after playback starts, before any scrub interaction occurs.
  3. Begin a scrub drag immediately (within 1-2 seconds of playback start). Confirm the seek-preview thumbnail appears without a visible blank/loading flash on the first frame, compared to the pre-change build side-by-side.
  4. Scrub to a point later in the timeline beyond the first prefetched image. Confirm the corresponding sprite sheet was already requested (visible in the network log) rather than fetched lazily at that exact moment.

- [ ] Step 9: Commit.
```
git add lib/data/models/trickplay_info.dart lib/ui/screens/playback/video_player_screen.dart test/data/models/trickplay_prefetch_test.dart
git commit -m "$(cat <<'EOF'
Prefetch trickplay sprite-sheet images on player mount

Extracts the image-count formula already proven in
appletv_player_host_screen.dart into a shared trickplayImageCountFor
function, and precaches every trickplay sprite-sheet URL right after
metadata loads instead of waiting for the first scrub drag, eliminating the
cold-fetch lag on the first seek-preview frame.
EOF
)"
```

---

### Task 6: Make hardware FF/RW remote seek step match D-pad seek step

**Files:**
- Modify: `lib/ui/screens/playback/video_player_screen.dart` (lines 2777-2797, 3184-3191, 3222-3229)
- Create: `test/playback/seek_step_acceleration_test.dart`

`_accelerateSeekStep(baseMs, event)` (lines 2777-2797) already grows the seek step on repeated presses (2x after 4 repeats, 6x after 10, 12x after 18) and is applied to D-pad `arrowLeft`/`arrowRight` at lines 3116/3130 (TV branch) and 3231-3244 (non-TV branch). The hardware remote `mediaFastForward`/`mediaRewind` handlers in the same non-preroll switch statements (lines 3184-3191 for the TV branch, 3222-3229 for the non-TV branch) call `_seekRelative` with the **flat, unaccelerated** `skipForwardLength`/`skipBackLength` value directly — meaning holding a physical remote's FF/RW button behaves differently from holding D-pad left/right, which is exactly the inconsistency the spec item asks to verify and, since one is found, fix. This task extracts the acceleration decision into a pure function (independently testable, since the existing method mutates instance state) and applies it uniformly to both input paths.

- [ ] Step 1: Read the current acceleration method and its two call sites once more to confirm exact text (already captured above during investigation; reproduced for the diff).

Current code at lines 2777-2797:
```dart
  int _accelerateSeekStep(int baseMs, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _seekDirection = key;
      _seekRepeatCount = 0;
      return baseMs;
    }
    if (event is KeyRepeatEvent) {
      if (_seekDirection != key) {
        _seekDirection = key;
        _seekRepeatCount = 0;
        return baseMs;
      }
      _seekRepeatCount++;
      if (_seekRepeatCount > 18) return baseMs * 12;
      if (_seekRepeatCount > 10) return baseMs * 6;
      if (_seekRepeatCount > 4) return baseMs * 2;
      return baseMs;
    }
    return baseMs;
  }
```

- [ ] Step 2: Write the failing test first, against a pure function `seekStepMultiplierFor(repeatCount)` that this task extracts from the multiplier table embedded in `_accelerateSeekStep` (the direction-tracking/state-reset part stays on the State class since it depends on instance fields, but the multiplier math itself is pure and independently testable).

Create `test/playback/seek_step_acceleration_test.dart`:
```dart
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
```

- [ ] Step 3: Run the test and confirm it fails to compile because `seekStepMultiplierFor` does not exist yet.
```
flutter test test/playback/seek_step_acceleration_test.dart
```
Expected output includes: `Error: Method not found: 'seekStepMultiplierFor'.`

- [ ] Step 4: Add the pure top-level function to `video_player_screen.dart`, directly above the `VideoPlayerScreen` class declaration (line 69). Insert before line 69:

```dart
/// Multiplier applied to a base seek step after [repeatCount] consecutive
/// same-direction key-repeat events, shared by both D-pad arrow-key seeking
/// and hardware fast-forward/rewind remote-button seeking so the two input
/// paths accelerate identically under a held button.
int seekStepMultiplierFor(int repeatCount) {
  if (repeatCount > 18) return 12;
  if (repeatCount > 10) return 6;
  if (repeatCount > 4) return 2;
  return 1;
}

class VideoPlayerScreen extends StatefulWidget {
```

- [ ] Step 5: Run the test again and confirm it passes.
```
flutter test test/playback/seek_step_acceleration_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 6: Rewrite `_accelerateSeekStep` to delegate its multiplier math to the new pure function, keeping only the instance-state direction tracking (this is a pure refactor — behavior for D-pad keys is unchanged). Replace lines 2777-2797:
```dart
  int _accelerateSeekStep(int baseMs, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _seekDirection = key;
      _seekRepeatCount = 0;
      return baseMs;
    }
    if (event is KeyRepeatEvent) {
      if (_seekDirection != key) {
        _seekDirection = key;
        _seekRepeatCount = 0;
        return baseMs;
      }
      _seekRepeatCount++;
      if (_seekRepeatCount > 18) return baseMs * 12;
      if (_seekRepeatCount > 10) return baseMs * 6;
      if (_seekRepeatCount > 4) return baseMs * 2;
      return baseMs;
    }
    return baseMs;
  }
```
with:
```dart
  int _accelerateSeekStep(int baseMs, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _seekDirection = key;
      _seekRepeatCount = 0;
      return baseMs;
    }
    if (event is KeyRepeatEvent) {
      if (_seekDirection != key) {
        _seekDirection = key;
        _seekRepeatCount = 0;
        return baseMs;
      }
      _seekRepeatCount++;
      return baseMs * seekStepMultiplierFor(_seekRepeatCount);
    }
    return baseMs;
  }
```

- [ ] Step 7: Apply the same acceleration to the TV-branch hardware FF/RW handlers (lines 3184-3191), matching the D-pad `arrowLeft`/`arrowRight` cases immediately above them in the same switch. Read the current code once more to confirm exact text:
```dart
        case LogicalKeyboardKey.mediaFastForward:
          _seekRelative(_prefs.get(UserPreferences.skipForwardLength));
          _showControls(focusSeekbar: PlatformDetection.isTV);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaRewind:
          _seekRelative(-_prefs.get(UserPreferences.skipBackLength));
          _showControls(focusSeekbar: PlatformDetection.isTV);
          return KeyEventResult.handled;
```
Replace with:
```dart
        case LogicalKeyboardKey.mediaFastForward:
          _seekRelative(
            _accelerateSeekStep(
              _prefs.get(UserPreferences.skipForwardLength),
              event,
            ),
          );
          _showControls(focusSeekbar: PlatformDetection.isTV);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaRewind:
          _seekRelative(
            -_accelerateSeekStep(
              _prefs.get(UserPreferences.skipBackLength),
              event,
            ),
          );
          _showControls(focusSeekbar: PlatformDetection.isTV);
          return KeyEventResult.handled;
```

- [ ] Step 8: Apply the same change to the non-TV branch hardware FF/RW handlers (lines 3222-3229), matching the `arrowLeft`/`arrowRight` cases immediately below them in the same switch. Read the current code once more to confirm exact text:
```dart
      case LogicalKeyboardKey.mediaFastForward:
        _seekRelative(_prefs.get(UserPreferences.skipForwardLength));
        _showControls(focusSeekbar: PlatformDetection.isTV);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaRewind:
        _seekRelative(-_prefs.get(UserPreferences.skipBackLength));
        _showControls(focusSeekbar: PlatformDetection.isTV);
        return KeyEventResult.handled;
```
Replace with:
```dart
      case LogicalKeyboardKey.mediaFastForward:
        _seekRelative(
          _accelerateSeekStep(
            _prefs.get(UserPreferences.skipForwardLength),
            event,
          ),
        );
        _showControls(focusSeekbar: PlatformDetection.isTV);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaRewind:
        _seekRelative(
          -_accelerateSeekStep(
            _prefs.get(UserPreferences.skipBackLength),
            event,
          ),
        );
        _showControls(focusSeekbar: PlatformDetection.isTV);
        return KeyEventResult.handled;
```

- [ ] Step 9: Run `flutter analyze` on the modified file to confirm the refactor compiles cleanly.
```
flutter analyze lib/ui/screens/playback/video_player_screen.dart
```
Expected: `No issues found!`

- [ ] Step 10: Run the unit test file again to reconfirm the extracted multiplier function still behaves correctly.
```
flutter test test/playback/seek_step_acceleration_test.dart
```
Expected output ends with: `All tests passed!`

- [ ] Step 11: Manual verification procedure (documented — this is the core ask of the backlog item: verifying step duration against real hardware remote FF/RW buttons, which have no software analog in `flutter_test`). On a physical Android TV or Apple TV device with its OEM remote's dedicated fast-forward/rewind buttons:
  1. Start playback of any item. Note the configured `skipForwardLength`/`skipBackLength` values (Settings → Playback → skip lengths).
  2. Press D-pad right once. Confirm the seek jumps forward by exactly the configured skip-forward length.
  3. Release, then press the remote's dedicated hardware fast-forward button once (not D-pad). Confirm the seek jumps forward by the identical amount as step 2.
  4. Hold D-pad right for 2+ seconds (generating repeat events). Confirm the seek step visibly accelerates (larger jumps) the longer it's held.
  5. Release, then hold the hardware fast-forward button for 2+ seconds. Confirm it now also accelerates identically to step 4 — this is the regression this task fixes; prior to this change the hardware button would keep stepping at the flat base amount the entire hold.
  6. Repeat steps 2-5 for rewind (D-pad left vs. hardware rewind button).
  7. Record pass/fail per platform (Android TV remote, Apple TV Siri Remote, any other hardware remote available) since IR/Bluetooth remote repeat-event behavior can vary by platform and driver.

- [ ] Step 12: Commit.
```
git add lib/ui/screens/playback/video_player_screen.dart test/playback/seek_step_acceleration_test.dart
git commit -m "$(cat <<'EOF'
Match hardware FF/RW remote seek acceleration to D-pad seek acceleration

Extracts the seek-step multiplier table from _accelerateSeekStep into a pure
seekStepMultiplierFor function and applies it to the mediaFastForward/
mediaRewind hardware remote key handlers, which previously used a flat
unaccelerated step while D-pad arrow keys already accelerated on hold —
the most-cited official-Jellyfin-app complaint per the UX polish audit.
EOF
)"
```

---

### Verification

- **Task 1** (vertical-nav debounce / focus-handoff duration): implements spec section 10 bullet "Reduce vertical-nav debounce (currently 140ms) and handoff-animation duration (220ms) for snappier D-pad response, matching Plex's praised 'predictable, fast' feel." Verified via the Step 5 manual remote-input procedure, since `flutter_test`'s fake clock cannot represent perceived input latency.
- **Task 2** (non-shifting focus treatment): implements spec section 10 bullet "Stop shifting row layout on focus change ... apply focus visual treatment (scale/elevate) without moving other rows." Verified via `test/ui/screens/home/home_row_focus_treatment_test.dart` (pure scale/spacing logic) plus the Step 10 manual on-device scroll-jitter check.
- **Task 3** (cross-library quick-filter chips): implements spec section 10 bullet "Extend the book-library inline quick-filter-chip pattern ... to movies/shows/music, replacing the current full-modal round-trip for every favorites/unwatched toggle." Verified via `test/ui/screens/browse/library_status_chips_test.dart` (chip-selection logic) plus the Step 11 manual round-trip check against a real server, and additionally fixes the `isBookBrowse: false` dead-wiring bug uncovered during investigation.
- **Task 4** (independent grid density control): implements spec section 10 bullet "Add a direct list/grid density control independent of poster-size preference." Verified via `test/ui/screens/browse/library_grid_density_test.dart` (column-count math) plus the Step 13 manual settings-dialog and persistence check.
- **Task 5** (trickplay prefetch on mount): implements spec section 10 bullet "Prefetch trickplay tiles on player mount rather than fetching on-demand during scrub drag, matching Streamyfin's approach to eliminating scrub-lag." Verified via `test/data/models/trickplay_prefetch_test.dart` (image-count formula) plus the Step 8 manual network-timing check against a live server.
- **Task 6** (D-pad/hardware FF-RW seek-step consistency): implements spec section 10 bullet "Verify D-pad seek step duration matches any hardware FF/RW remote button handling — this exact inconsistency is the most-cited official-Jellyfin-app complaint." Investigation confirmed a genuine divergence (D-pad accelerated on hold, hardware FF/RW did not); fixed and verified via `test/playback/seek_step_acceleration_test.dart` (multiplier table) plus the Step 11 manual hardware-remote procedure, which is the authoritative check since no software harness can simulate a physical remote's native repeat-event cadence.

All six tasks are scoped strictly to small/small-medium items; the two large-scope items (season/episode route-push-to-in-place-swap rework, Classic/Modern detail-screen unification), chapter tick marks, and bringup-sequence collapse are explicitly out of scope and untouched by this plan.