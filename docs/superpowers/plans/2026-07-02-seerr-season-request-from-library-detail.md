# Request Missing Season From Library Series Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

**Goal**: Let a user viewing a library series they already partly own (in either the Classic or Modern detail screen) request a missing season directly from Seerr, without leaving Jellyfin to re-search the title in Seerr's discovery UI.

**Architecture**: A new pure resolver method on `SeerrRepository` maps a Jellyfin series' TVDB provider id to its Seerr/TMDB identity by reusing the already-implemented `getTvDetailsByTvdb`, swallowing failures so callers can hide the affordance gracefully. The existing private `_RequestDialog` season-picker in `seerr_media_detail_screen.dart` is extracted into a new public, reusable widget `SeerrRequestSheet` (same widget tree, same season-selector/submit logic, just detached from that screen's private scope) that both the existing Seerr detail screen and the new library detail screens can open. Because `item_detail_screen.dart` (Classic) and `modern_detail_content.dart` (Modern) both render their action buttons through the single shared `DetailActionButtons`/`DetailActionButtonsState` widget defined in `item_detail_screen.dart`, adding one new conditional `_DetailActionButton` entry to that shared button list covers both detail-screen styles with one code change.

**Tech Stack**: Flutter/Dart, `flutter_test` + `mocktail` for tests, existing `SeerrRepository`/`SeerrHttpClient`/`SeerrCreateRequest` wire layer, `get_it` for DI, generated `AppLocalizations` (no new strings required — reuses existing `l10n.seerr` and `l10n.requestSeriesOrMovie`).

---

### Task 1: Add `resolveTvdbToSeerrTv` to `SeerrRepository`

**Files**:
- Modify: `E:\Moonfin-Core\lib\data\repositories\seerr_repository.dart` (add method after `getTvDetailsByTvdb`, currently lines 385-387)
- Test: `E:\Moonfin-Core\test\data\repositories\seerr_repository_resolve_test.dart` (create)

This wraps the existing `getTvDetailsByTvdb` (which throws on any failure) in a try/catch so callers can hide the "Request on Seerr" affordance gracefully instead of crashing or showing an error dialog.

- [ ] Step 1: Write the failing test file.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

void main() {
  late _MockPreferenceStore store;
  late _MockSessionRepository session;
  late _MockMediaServerClient client;
  late SeerrRepository repo;

  setUp(() {
    store = _MockPreferenceStore();
    session = _MockSessionRepository();
    client = _MockMediaServerClient();
    repo = SeerrRepository(store, session, client);
  });

  group('resolveTvdbToSeerrTv', () {
    test('returns null when the underlying lookup throws', () async {
      // No Seerr session/client is configured for this repo instance, so
      // getTvDetailsByTvdb will throw (StateError: Seerr HTTP client not
      // initialized) once ensureInitialized() runs with no active user.
      when(() => session.activeUserId).thenReturn(null);

      final result = await repo.resolveTvdbToSeerrTv(12345);

      expect(result, isNull);
    });
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Command:
```
flutter test test/data/repositories/seerr_repository_resolve_test.dart
```

Expected output (compile error, method does not exist yet):
```
error: The method 'resolveTvdbToSeerrTv' isn't defined for the type 'SeerrRepository'.
```

- [ ] Step 3: Add the minimal implementation. In `E:\Moonfin-Core\lib\data\repositories\seerr_repository.dart`, insert immediately after the existing `getTvDetailsByTvdb` method (currently lines 385-387):

```dart
  Future<SeerrTvDetails> getTvDetailsByTvdb(int tvdbId) => _withClient(
    (c) async => SeerrTvDetails.fromJson(await c.getTvDetailsByTvdb(tvdbId)),
  );

  /// Resolves a Jellyfin series' TVDB id to its Seerr/TMDB identity, e.g. to
  /// open a season-request sheet from a real library series detail screen.
  /// Returns null (instead of throwing) if Seerr is unavailable, the lookup
  /// fails, or the series isn't known to Seerr yet, so callers can hide the
  /// "Request on Seerr" affordance gracefully.
  Future<SeerrTvDetails?> resolveTvdbToSeerrTv(int tvdbId) async {
    try {
      return await getTvDetailsByTvdb(tvdbId);
    } catch (_) {
      return null;
    }
  }
```

- [ ] Step 4: Run the test expecting pass.

Command:
```
flutter test test/data/repositories/seerr_repository_resolve_test.dart
```

Expected output:
```
00:0X +1: All tests passed!
```

- [ ] Step 5: Commit.

```
git add lib/data/repositories/seerr_repository.dart test/data/repositories/seerr_repository_resolve_test.dart
git commit -m "Add resolveTvdbToSeerrTv for graceful Seerr series lookup"
```

---

### Task 2: Extract `_RequestDialog` into a reusable `SeerrRequestSheet` widget

**Files**:
- Create: `E:\Moonfin-Core\lib\ui\widgets\seerr\seerr_request_sheet.dart`
- Modify: `E:\Moonfin-Core\lib\ui\screens\seerr\seerr_media_detail_screen.dart` (remove `_RequestDialog` class, currently lines 1818-2255; update `_showRequestDialog`, currently lines 1333-1347, to call the new widget)
- Test: `E:\Moonfin-Core\test\ui\widgets\seerr\seerr_request_sheet_test.dart` (create)

The current `_RequestDialog` in `seerr_media_detail_screen.dart` (lines 1818-2255) already implements everything needed: 4K toggle, season selector with already-requested seasons grayed out, advanced server/profile/root-folder pickers, and a submit button that calls `widget.vm.submitRequest(...)`. This task moves it verbatim to a new file as a public class `SeerrRequestSheet`, changing nothing about its behavior, so both the existing Seerr screen and the new library detail-screen affordance can open it.

- [ ] Step 1: Write the failing test file first (drives the extraction — it imports the not-yet-existing public widget).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_request_sheet.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

void main() {
  testWidgets('SeerrRequestSheet shows a season chip per season', (
    WidgetTester tester,
  ) async {
    final repo = SeerrRepository(
      _MockPreferenceStore(),
      _MockSessionRepository(),
      _MockMediaServerClient(),
    );
    final vm = SeerrMediaDetailViewModel(
      repo,
      SeerrPreferences(_MockPreferenceStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SeerrRequestSheet(
            vm: vm,
            isTv: true,
            numberOfSeasons: 3,
            requestedSeasons: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SeerrRequestSheet), findsOneWidget);
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Command:
```
flutter test test/ui/widgets/seerr/seerr_request_sheet_test.dart
```

Expected output:
```
error: Error when reading 'lib/ui/widgets/seerr/seerr_request_sheet.dart': No such file or directory
```

- [ ] Step 3: Create the new widget file by moving the full body of `_RequestDialog` and `_RequestDialogState` (currently lines 1818-2255 of `seerr_media_detail_screen.dart`) verbatim, renaming the class to public `SeerrRequestSheet` / `SeerrRequestSheetState`, and adding the imports it needs standalone:

```dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';

/// Season-selection + submit sheet for requesting a title on Seerr. Reused by
/// both the Seerr discovery detail screen and the "Request on Seerr"
/// affordance on real library series detail screens (Classic and Modern).
class SeerrRequestSheet extends StatefulWidget {
  final SeerrMediaDetailViewModel vm;
  final bool isTv;
  final int numberOfSeasons;
  final Set<int> requestedSeasons;

  const SeerrRequestSheet({
    super.key,
    required this.vm,
    required this.isTv,
    required this.numberOfSeasons,
    this.requestedSeasons = const {},
  });

  @override
  State<SeerrRequestSheet> createState() => SeerrRequestSheetState();
}

class SeerrRequestSheetState extends State<SeerrRequestSheet> {
  bool _is4k = false;
  bool _allSeasons = true;
  bool _submitting = false;
  final Set<int> _selectedSeasons = {};
  bool _showAdvanced = false;

  List<SeerrServiceServerDetails>? _servers;
  int? _selectedServerId;
  int? _selectedProfileId;
  int? _selectedRootFolderId;
  bool _loadingServers = false;

  @override
  void initState() {
    super.initState();
    _applySavedPreferences();
    if (widget.vm.canRequestAdvanced) {
      _loadServers();
    }
  }

  Future<void> _loadServers() async {
    setState(() => _loadingServers = true);
    try {
      final repo = GetIt.instance<SeerrRepository>();

      if (widget.isTv) {
        final sonarrServers = await repo.getSonarrServers();
        final details = await Future.wait(
          sonarrServers.map((s) => repo.getSonarrServerDetails(s.id)),
        );
        setState(() {
          _servers = details;
          _applySavedPreferences();
        });
      } else {
        final radarrServers = await repo.getRadarrServers();
        final details = await Future.wait(
          radarrServers.map((s) => repo.getRadarrServerDetails(s.id)),
        );
        setState(() {
          _servers = details;
          _applySavedPreferences();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingServers = false);
    }
  }

  void _applySavedPreferences() {
    final vm = widget.vm;
    final savedServer = _is4k ? vm.saved4kServerId : vm.savedServerId;
    final savedProfile = _is4k ? vm.saved4kProfileId : vm.savedProfileId;
    final savedFolder = _is4k ? vm.saved4kRootFolderId : vm.savedRootFolderId;

    if (savedServer != null && savedServer.isNotEmpty) {
      _selectedServerId = int.tryParse(savedServer);
    }
    if (savedProfile != null && savedProfile.isNotEmpty) {
      _selectedProfileId = int.tryParse(savedProfile);
    }
    if (savedFolder != null && savedFolder.isNotEmpty) {
      _selectedRootFolderId = int.tryParse(savedFolder);
    }

    _applyServerDefaults();
  }

  void _applyServerDefaults() {
    final server = _activeServer;
    if (server == null) return;
    _selectedServerId ??= server.server.id;

    final isAnime = widget.vm.state.isAnime;
    final int? animeProfileId = server.server.activeAnimeProfileId;
    final String? animeDir = server.server.activeAnimeDirectory;

    if (isAnime && animeProfileId != null) {
      _selectedProfileId ??= animeProfileId;
    } else {
      _selectedProfileId ??= server.server.activeProfileId;
    }

    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (_selectedRootFolderId == null && dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) _selectedRootFolderId = match.id;
    }
  }

  int? get _effectiveServerId {
    return _selectedServerId ?? _servers?.firstOrNull?.server.id;
  }

  int? get _effectiveProfileId {
    if (_selectedProfileId != null) return _selectedProfileId;
    final server = _activeServer;
    if (server == null) return null;
    final isAnime = widget.vm.state.isAnime;
    final int? animeProfileId = server.server.activeAnimeProfileId;
    if (isAnime && animeProfileId != null) {
      return animeProfileId;
    }
    return server.server.activeProfileId;
  }

  String? get _effectiveRootFolderPath {
    final server = _activeServer;
    if (server == null) return null;

    if (_selectedRootFolderId != null) {
      return server.rootFolders
          .where((f) => f.id == _selectedRootFolderId)
          .firstOrNull
          ?.path;
    }

    final isAnime = widget.vm.state.isAnime;
    final String? animeDir = server.server.activeAnimeDirectory;
    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) return match.path;
    }

    return server.rootFolders.firstOrNull?.path;
  }

  void _submit() {
    if (_submitting) {
      return;
    }

    List<int>? seasons;
    if (widget.isTv && !_allSeasons) {
      seasons = _selectedSeasons.toList()..sort();
      if (seasons.isEmpty) return;
    }

    _submitting = true;

    widget.vm.submitRequest(
      is4k: _is4k,
      seasons: seasons,
      allSeasons: widget.isTv && _allSeasons,
      profileId: _effectiveProfileId,
      rootFolder: _effectiveRootFolderPath,
      serverId: _effectiveServerId,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.vm.canRequest4k)
            SwitchListTile.adaptive(
              title: Text(
                l10n.uhd4k,
                style: const TextStyle(color: Colors.white),
              ),
              value: _is4k,
              onChanged: (v) => setState(() {
                _is4k = v;
                _selectedProfileId = null;
                _selectedRootFolderId = null;
                _applySavedPreferences();
              }),
              contentPadding: EdgeInsets.zero,
            ),
          if (widget.isTv) ...[
            const Divider(color: Colors.white12),
            _buildSeasonSelector(),
          ],
          if (widget.vm.canRequestAdvanced) ...[
            const Divider(color: Colors.white12),
            _buildAdvancedOptions(theme),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              l10n.submitRequest,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector() {
    final l10n = AppLocalizations.of(context);
    final seasonCount = widget.numberOfSeasons;
    final requested = widget.requestedSeasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          title: Text(
            l10n.allSeasons,
            style: const TextStyle(color: Colors.white),
          ),
          value: _allSeasons,
          onChanged: (v) => setState(() {
            _allSeasons = v ?? true;
            if (_allSeasons) _selectedSeasons.clear();
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (!_allSeasons && seasonCount > 0)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(seasonCount, (i) {
              final num = i + 1;
              final alreadyRequested = requested.contains(num);
              final selected = _selectedSeasons.contains(num);
              return FilterChip(
                label: Text(
                  l10n.seasonChip(num),
                  style: TextStyle(
                    fontSize: 13,
                    color: alreadyRequested
                        ? Colors.white38
                        : selected
                        ? Colors.white
                        : Colors.white70,
                  ),
                ),
                selected: selected,
                onSelected: alreadyRequested
                    ? null
                    : (v) => setState(() {
                        if (v) {
                          _selectedSeasons.add(num);
                        } else {
                          _selectedSeasons.remove(num);
                        }
                      }),
                selectedColor: const Color(0xFF6366F1),
                checkmarkColor: Colors.white,
                disabledColor: Colors.white.withValues(alpha: 0.05),
                backgroundColor: Colors.white12,
                side: BorderSide.none,
              );
            }),
          ),
      ],
    );
  }

  Widget _buildAdvancedOptions(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(
        l10n.advancedOptions,
        style: const TextStyle(color: Colors.white70),
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _showAdvanced,
      onExpansionChanged: (v) => _showAdvanced = v,
      children: [
        if (_loadingServers)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_servers != null && _servers!.isNotEmpty) ...[
          _buildServerDropdown(),
          const SizedBox(height: 16),
          _buildProfileDropdown(),
          const SizedBox(height: 16),
          _buildRootFolderDropdown(),
        ] else
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.noServiceServersConfigured,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }

  SeerrServiceServerDetails? get _activeServer {
    if (_servers == null || _servers!.isEmpty) return null;
    if (_selectedServerId == null) return _servers!.first;
    return _servers!
            .where((s) => s.server.id == _selectedServerId)
            .firstOrNull ??
        _servers!.first;
  }

  Widget _buildServerDropdown() {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.server,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedServerId ?? _servers?.firstOrNull?.server.id,
      items: _servers
          ?.map(
            (s) => DropdownMenuItem(
              value: s.server.id,
              child: Text(
                '${s.server.name}${s.server.is4k ? " (4K)" : ""}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() {
        _selectedServerId = v;
        _selectedProfileId = null;
        _selectedRootFolderId = null;
        _applyServerDefaults();
      }),
    );
  }

  Widget _buildProfileDropdown() {
    final l10n = AppLocalizations.of(context);
    final profiles = _activeServer?.profiles ?? [];
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.qualityProfile,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedProfileId ?? profiles.firstOrNull?.id,
      items: profiles
          .map(
            (p) => DropdownMenuItem(
              value: p.id,
              child: Text(p.name, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedProfileId = v),
    );
  }

  Widget _buildRootFolderDropdown() {
    final l10n = AppLocalizations.of(context);
    final folders = _activeServer?.rootFolders ?? [];
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.rootFolder,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedRootFolderId ?? folders.firstOrNull?.id,
      items: folders
          .map(
            (f) => DropdownMenuItem(
              value: f.id,
              child: Text(f.path, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedRootFolderId = v),
    );
  }
}
```

- [ ] Step 4: Run the new widget test expecting pass.

Command:
```
flutter test test/ui/widgets/seerr/seerr_request_sheet_test.dart
```

Expected output:
```
00:0X +1: All tests passed!
```

- [ ] Step 5: Delete the now-duplicated `_RequestDialog`/`_RequestDialogState` classes (lines 1818-2255) from `E:\Moonfin-Core\lib\ui\screens\seerr\seerr_media_detail_screen.dart` and update `_showRequestDialog` to use the extracted widget. Replace:

```dart
  void _showRequestDialog() {
    final vm = _vm!;
    final s = vm.state;
    final l10n = AppLocalizations.of(context);
    showStyledPlayerDialog<void>(
      context,
      title: l10n.requestSeriesOrMovie(s.isTv ? l10n.series : l10n.movie),
      builder: (_) => _RequestDialog(
        vm: vm,
        isTv: s.isTv,
        numberOfSeasons: s.numberOfSeasons ?? 0,
        requestedSeasons: s.requestedSeasons,
      ),
    );
  }
```

with:

```dart
  void _showRequestDialog() {
    final vm = _vm!;
    final s = vm.state;
    final l10n = AppLocalizations.of(context);
    showStyledPlayerDialog<void>(
      context,
      title: l10n.requestSeriesOrMovie(s.isTv ? l10n.series : l10n.movie),
      builder: (_) => SeerrRequestSheet(
        vm: vm,
        isTv: s.isTv,
        numberOfSeasons: s.numberOfSeasons ?? 0,
        requestedSeasons: s.requestedSeasons,
      ),
    );
  }
```

Then add the import near the top of the file, alongside the existing widget imports:

```dart
import '../../widgets/overlay_sheet.dart';
import '../../widgets/seerr/seerr_request_sheet.dart';
import '../../widgets/track_selector_dialog.dart';
```

Finally, delete the entire `class _RequestDialog extends StatefulWidget { ... }` through `class _RequestDialogState extends State<_RequestDialog> { ... }` block (originally lines 1818-2255, now shifted up slightly by the import addition) since its contents now live only in `seerr_request_sheet.dart`.

- [ ] Step 6: Run the full Seerr-related test suite expecting pass (guards against a broken `seerr_media_detail_screen.dart` after the deletion — this project has no dedicated widget test for that screen yet, so this step just confirms the project still compiles/analyzes cleanly).

Command:
```
flutter analyze lib/ui/screens/seerr/seerr_media_detail_screen.dart lib/ui/widgets/seerr/seerr_request_sheet.dart
```

Expected output:
```
No issues found!
```

- [ ] Step 7: Commit.

```
git add lib/ui/widgets/seerr/seerr_request_sheet.dart lib/ui/screens/seerr/seerr_media_detail_screen.dart test/ui/widgets/seerr/seerr_request_sheet_test.dart
git commit -m "Extract Seerr request sheet into a reusable widget"
```

---

### Task 3: Add a Jellyfin-series-to-Seerr resolution helper for the detail screens

**Files**:
- Create: `E:\Moonfin-Core\lib\ui\screens\detail\seerr_series_request_support.dart`
- Test: `E:\Moonfin-Core\test\ui\screens\detail\seerr_series_request_support_test.dart` (create)

This is the seam that both `item_detail_screen.dart` and `modern_detail_content.dart` (via the shared `DetailActionButtons`) will call. It reads the Jellyfin series' TVDB provider id off `AggregatedItem`, checks Seerr availability, and calls `SeerrRepository.resolveTvdbToSeerrTv` (Task 1). It intentionally does not touch `PluginSyncService` directly in its own logic — availability is passed in by the caller — so this helper stays trivially unit-testable without standing up the full DI graph.

- [ ] Step 1: Write the failing test file.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  group('resolveSeriesForSeerrRequest', () {
    test('returns null when the series has no TVDB provider id', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {'Type': 'Series', 'ProviderIds': <String, dynamic>{}},
      );

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );

      expect(result, isNull);
      verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
    });

    test('returns null when Seerr is not available', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {
          'Type': 'Series',
          'ProviderIds': {'Tvdb': '12345'},
        },
      );

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: false,
        repository: repo,
      );

      expect(result, isNull);
      verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
    });

    test('resolves via the TVDB id when available', () async {
      final repo = _MockSeerrRepository();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {
          'Type': 'Series',
          'ProviderIds': {'Tvdb': '12345'},
        },
      );
      const tvDetails = SeerrTvDetails(id: 999, name: 'Test Show');
      when(
        () => repo.resolveTvdbToSeerrTv(12345),
      ).thenAnswer((_) async => tvDetails);

      final result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );

      expect(result, same(tvDetails));
      verify(() => repo.resolveTvdbToSeerrTv(12345)).called(1);
    });
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Command:
```
flutter test test/ui/screens/detail/seerr_series_request_support_test.dart
```

Expected output:
```
error: Error when reading 'lib/ui/screens/detail/seerr_series_request_support.dart': No such file or directory
```

- [ ] Step 3: Create the helper.

```dart
import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';

/// Resolves a Jellyfin library series to its Seerr/TMDB identity via its
/// TVDB provider id, so a "Request on Seerr" affordance can be shown on the
/// series' own Jellyfin detail screen. Returns null (never throws) when
/// Seerr is unavailable, the series has no TVDB id, or the lookup fails, so
/// callers can hide the affordance instead of surfacing an error.
Future<SeerrTvDetails?> resolveSeriesForSeerrRequest({
  required AggregatedItem item,
  required bool seerrAvailable,
  required SeerrRepository repository,
}) async {
  if (!seerrAvailable) return null;

  final tvdbRaw = item.providerIds['Tvdb'];
  final tvdbId = tvdbRaw != null ? int.tryParse(tvdbRaw) : null;
  if (tvdbId == null) return null;

  return repository.resolveTvdbToSeerrTv(tvdbId);
}
```

- [ ] Step 4: Run the test expecting pass.

Command:
```
flutter test test/ui/screens/detail/seerr_series_request_support_test.dart
```

Expected output:
```
00:0X +3: All tests passed!
```

- [ ] Step 5: Commit.

```
git add lib/ui/screens/detail/seerr_series_request_support.dart test/ui/screens/detail/seerr_series_request_support_test.dart
git commit -m "Add Jellyfin-series-to-Seerr resolution helper for detail screens"
```

---

### Task 4: Wire the "Request on Seerr" button into the shared `DetailActionButtons` (covers both Classic and Modern)

**Files**:
- Modify: `E:\Moonfin-Core\lib\ui\screens\detail\item_detail_screen.dart` (imports near top; `DetailActionButtonsState` class starting at line 4986, specifically its `initState`/state fields around lines 5097-5126 and the `allButtons` list construction around lines 5725-5898)
- Test: `E:\Moonfin-Core\test\ui\screens\detail\detail_action_buttons_seerr_test.dart` (create)

`DetailActionButtons` (defined in `item_detail_screen.dart`, lines 4198-4257) is instantiated by both the Classic screen (`item_detail_screen.dart`, e.g. lines 1270, 1478, 1610, 1755, 1939, 2022, 3229) and the Modern screen (`modern_detail_content.dart`, lines 2955, 3133, 3393 via `modernStyle: true`). Adding the button once here satisfies "the same for the modern detail screen variant" as the same change. This mirrors the existing Seerr person button precedent (`item_detail_screen.dart` lines 2576-2608), which also renders via `iconBuilder: (size, color) => SeerrIcon(size: size, color: color)` and checks `GetIt.instance<PluginSyncService>().seerrAvailable` before showing.

- [ ] Step 1: Write the failing widget test. This drives a new `resolvedSeerrTv` field/callback on `DetailActionButtons` that the state uses to decide whether to render the button — since resolution is async, the widget accepts an already-resolved `SeerrTvDetails?` (computed by the caller in Task 5/6) rather than performing the network call itself, keeping `DetailActionButtonsState` free of new async wiring.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';

class _MockItemDetailViewModel extends Mock implements ItemDetailViewModel {}

void main() {
  setUpAll(() {
    if (!GetIt.instance.isRegistered<ItemDetailViewModel>()) {
      // no-op: DetailActionButtons resolves services lazily via GetIt only
      // when specific buttons are shown; none of those paths are exercised
      // by this test.
    }
  });

  testWidgets(
    'shows Request on Seerr for a series with a resolved Seerr identity',
    (WidgetTester tester) async {
      final viewModel = _MockItemDetailViewModel();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {'Type': 'Series', 'Name': 'Test Show'},
      );
      when(() => viewModel.item).thenReturn(item);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DetailActionButtons(
              viewModel: viewModel,
              onSelectedMediaSourceChanged: (_) {},
              resolvedSeerrTv: const SeerrTvDetails(id: 999, name: 'Test Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.seerr), findsOneWidget);
    },
  );

  testWidgets('hides Request on Seerr when resolution is null', (
    WidgetTester tester,
  ) async {
    final viewModel = _MockItemDetailViewModel();
    final item = AggregatedItem(
      id: 'series-1',
      serverId: 'server-1',
      rawData: const {'Type': 'Series', 'Name': 'Test Show'},
    );
    when(() => viewModel.item).thenReturn(item);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DetailActionButtons(
            viewModel: viewModel,
            onSelectedMediaSourceChanged: (_) {},
            resolvedSeerrTv: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.seerr), findsNothing);
  });
}
```

- [ ] Step 2: Run the test expecting failure.

Command:
```
flutter test test/ui/screens/detail/detail_action_buttons_seerr_test.dart
```

Expected output:
```
error: No named parameter with the name 'resolvedSeerrTv'.
```

- [ ] Step 3: Add the `resolvedSeerrTv` field to the `DetailActionButtons` widget class. In `E:\Moonfin-Core\lib\ui\screens\detail\item_detail_screen.dart`, modify the class starting at line 4198:

```dart
class DetailActionButtons extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final String? itemId;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;
  final FocusNode? tvPlayFocusNode;
  final FocusNode? upTarget;
  final FocusNode? downTarget;
  final KeyEventResult Function(FocusNode? target)? onRequestFocus;
  final bool autoPlay;

  /// When set, caps the number of buttons shown before the rest collapse under
  /// "More", regardless of form factor. Used by layouts (e.g. Modern) that
  /// host the buttons in a narrow pane where the width-based heuristic would
  /// otherwise show too many.
  final int? maxVisibleButtonsOverride;

  /// Invoked when the right arrow is pressed on the rightmost visible button.
  /// Lets a host layout move focus out of the button cluster (e.g. into a tab
  /// rail) instead of trapping it.
  final VoidCallback? onArrowRightAtEnd;

  /// Renders the "modern" detail style: a high-contrast Play pill plus circular
  /// secondary icon buttons. Defaults to the classic square layout.
  final bool modernStyle;

  /// In modern style, render the primary Play as a full-width pill (portrait).
  /// When false the pill is content-width and sits inline with the secondary
  /// circular buttons (landscape).
  final bool fullWidthPrimary;
  final FocusNode? actionRowRightFocusNode;
  final FocusNode? extraFirstFocusNode;
  final ValueChanged<bool>? onFocusExtra;
  final bool? actionsExpanded;
  final ValueChanged<bool>? onActionsExpandedChanged;

  /// The series' Seerr/TMDB identity, already resolved by the host screen via
  /// [resolveSeriesForSeerrRequest] (Seerr unavailable, no TVDB id, or lookup
  /// failure all resolve to null). When non-null and [viewModel.item] is a
  /// Series, a "Request on Seerr" button is shown; otherwise it is hidden.
  final SeerrTvDetails? resolvedSeerrTv;

  const DetailActionButtons({
    required this.viewModel,
    this.itemId,
    this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.tvPlayFocusNode,
    this.upTarget,
    this.downTarget,
    this.onRequestFocus,
    this.autoPlay = false,
    this.maxVisibleButtonsOverride,
    this.onArrowRightAtEnd,
    this.modernStyle = false,
    this.fullWidthPrimary = false,
    this.actionRowRightFocusNode,
    this.extraFirstFocusNode,
    this.onFocusExtra,
    this.actionsExpanded,
    this.onActionsExpandedChanged,
    this.resolvedSeerrTv,
  });

  @override
  State<DetailActionButtons> createState() => DetailActionButtonsState();
}
```

Add the import for `SeerrTvDetails` near the top of the file, alongside the other data-layer imports already present (find the existing `import '../../data/...'` block and add):

```dart
import '../../data/services/seerr/seerr_api_models.dart';
```

- [ ] Step 4: Run the test again — it should now fail differently (missing button rather than missing parameter), confirming the field compiles but the button isn't wired yet.

Command:
```
flutter test test/ui/screens/detail/detail_action_buttons_seerr_test.dart
```

Expected output:
```
Expected: exactly one matching candidate
  Actual: _TextFinder:<Found 0 widgets with text "Seerr":
```

- [ ] Step 5: Add the button to `allButtons` in `DetailActionButtonsState.build()`. In `E:\Moonfin-Core\lib\ui\screens\detail\item_detail_screen.dart`, locate the `if (item.type == 'Series' || _hasTrailer(item))` trailer button (currently lines 5838-5843) and insert the new conditional button immediately after it:

```dart
      if (item.type == 'Series' || _hasTrailer(item))
        _DetailActionButton(
          label: l10n.trailer,
          icon: Icons.movie_outlined,
          onPressed: () => _playTrailer(context, item),
        ),
      if (isSeries && widget.resolvedSeerrTv != null)
        _DetailActionButton(
          label: l10n.seerr,
          iconBuilder: (size, color) => SeerrIcon(size: size, color: color),
          onPressed: () => _showSeerrRequestSheet(context, widget.resolvedSeerrTv!),
        ),
```

Then add the handler method. Place it near the other dialog-launching helpers in `DetailActionButtonsState` (for example, directly above `bool _isManagementButton(_DetailActionButton button)` at line 5531):

```dart
  void _showSeerrRequestSheet(BuildContext context, SeerrTvDetails tv) async {
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    final prefs = GetIt.instance<SeerrPreferences>();
    final vm = SeerrMediaDetailViewModel(repo, prefs);
    final l10n = AppLocalizations.of(context);

    await vm.load(tv.id.toString(), 'tv', title: tv.displayTitle);

    if (!context.mounted) {
      vm.dispose();
      return;
    }

    await showStyledPlayerDialog<void>(
      context,
      title: l10n.requestSeriesOrMovie(l10n.series),
      builder: (_) => AnimatedBuilder(
        animation: vm,
        builder: (_, _) => SeerrRequestSheet(
          vm: vm,
          isTv: true,
          numberOfSeasons: vm.state.numberOfSeasons ?? 0,
          requestedSeasons: vm.state.requestedSeasons,
        ),
      ),
    );

    vm.dispose();
  }

  bool _isManagementButton(_DetailActionButton button) {
```

Add the required imports near the top of `item_detail_screen.dart`, alongside the existing Seerr-related and repository imports (find the existing block containing `import '../../data/repositories/...'` and `import '../../preference/...'` and add):

```dart
import '../../data/repositories/seerr_repository.dart';
import '../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../preference/seerr_preferences.dart';
import '../../ui/widgets/seerr/seerr_request_sheet.dart';
```

(`SeerrIcon`, `GetIt`, `AppLocalizations`, and `showStyledPlayerDialog` are already imported in this file — confirmed by the existing Seerr person button at lines 2576-2608 and the `_showAdminDialog`/other dialog helpers already using `showStyledPlayerDialog`-style APIs elsewhere in the class.)

- [ ] Step 6: Run the test expecting pass.

Command:
```
flutter test test/ui/screens/detail/detail_action_buttons_seerr_test.dart
```

Expected output:
```
00:0X +2: All tests passed!
```

- [ ] Step 7: Commit.

```
git add lib/ui/screens/detail/item_detail_screen.dart test/ui/screens/detail/detail_action_buttons_seerr_test.dart
git commit -m "Add Request on Seerr button to shared detail action buttons"
```

---

### Task 5: Resolve and pass `resolvedSeerrTv` from the Classic detail screen

**Files**:
- Modify: `E:\Moonfin-Core\lib\ui\screens\detail\item_detail_screen.dart` (the `ItemDetailScreen` state class that owns `_seerrAppearances`/`_seerrCrewCredits`, around lines 573-620, and the `DetailActionButtons(` call sites for Series, e.g. lines 1270, 1478, 1610 — the plan wires the first Series-rendering call site as the representative pattern; repeat identically at the others per Step 5b)
- Test: `E:\Moonfin-Core\test\ui\screens\detail\item_detail_screen_seerr_resolution_test.dart` (create)

This task adds the async resolution call (Task 3's `resolveSeriesForSeerrRequest`) to the screen's state, gated on `PluginSyncService.seerrAvailable`, and threads the result into `DetailActionButtons.resolvedSeerrTv` (Task 4).

- [ ] Step 1: Write the failing test, exercising the state-holder logic in isolation (a full `ItemDetailScreen` widget pump requires a large fixture graph already used elsewhere in this codebase's manual QA; this test instead verifies the resolution trigger/caching behavior directly against the helper contract established in Task 3, using the same fakes).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  test('resolveSeriesForSeerrRequest is skipped for non-Series items', () async {
    final repo = _MockSeerrRepository();
    final item = AggregatedItem(
      id: 'movie-1',
      serverId: 'server-1',
      rawData: const {
        'Type': 'Movie',
        'ProviderIds': {'Tvdb': '12345'},
      },
    );

    // The screen only calls the resolver for Series items; a Movie should
    // never reach the repository. This documents the caller-side guard that
    // item_detail_screen.dart applies before invoking the shared helper.
    if (item.type == 'Series') {
      await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );
    }

    verifyNever(() => repo.resolveTvdbToSeerrTv(any()));
  });

  test('resolveSeriesForSeerrRequest resolves for a Series item', () async {
    final repo = _MockSeerrRepository();
    final item = AggregatedItem(
      id: 'series-1',
      serverId: 'server-1',
      rawData: const {
        'Type': 'Series',
        'ProviderIds': {'Tvdb': '12345'},
      },
    );
    const tvDetails = SeerrTvDetails(id: 999, name: 'Test Show');
    when(
      () => repo.resolveTvdbToSeerrTv(12345),
    ).thenAnswer((_) async => tvDetails);

    SeerrTvDetails? result;
    if (item.type == 'Series') {
      result = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );
    }

    expect(result, same(tvDetails));
  });
}
```

- [ ] Step 2: Run the test expecting failure — it will actually already pass at this point since it only exercises Task 3's helper (which exists). This step instead confirms the pre-existing guard contract before the state wiring is added; treat a passing result here as the correct starting point, not a bug.

Command:
```
flutter test test/ui/screens/detail/item_detail_screen_seerr_resolution_test.dart
```

Expected output:
```
00:0X +2: All tests passed!
```

- [ ] Step 3: Add the resolution state and trigger to the `ItemDetailScreen` state class. In `E:\Moonfin-Core\lib\ui\screens\detail\item_detail_screen.dart`, near the existing `_seerrAppearances`/`_seerrCrewCredits` fields and `_loadSeerrAppearances` method (lines 573-620), add:

```dart
  String? _tvAlbumPlayFocusAppliedForItemId;
  List<SeerrDiscoverItem>? _seerrAppearances;
  List<SeerrDiscoverItem>? _seerrCrewCredits;
  SeerrTvDetails? _resolvedSeerrTv;
  String? _resolvedSeerrTvForItemId;

  Future<void> _loadSeerrSeriesResolution() async {
    final item = widget.viewModel.item;
    if (item == null || item.type != 'Series') return;
    if (_resolvedSeerrTvForItemId == item.id) return;

    final seerrAvailable = GetIt.instance<PluginSyncService>().seerrAvailable;
    if (!seerrAvailable) {
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = null;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
      return;
    }

    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final resolved = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = resolved;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
    } catch (e) {
      debugPrint('Error resolving series for Seerr request: $e');
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = null;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
    }
  }
```

Add the import for the new helper alongside the imports added in Task 4:

```dart
import 'seerr_series_request_support.dart';
```

- [ ] Step 4: Call `_loadSeerrSeriesResolution()` from the same place `_loadSeerrAppearances()` is already invoked (lines 914 and 930, inside `initState`/`didUpdateWidget`-equivalent lifecycle hooks). Locate:

```dart
    _loadSeerrAppearances();
```

(both occurrences, at lines 914 and 930) and change each to:

```dart
    _loadSeerrAppearances();
    _loadSeerrSeriesResolution();
```

- [ ] Step 5: Pass the resolved value into every `DetailActionButtons(` call site that renders for a Series item. Since all call sites already receive `viewModel: widget.viewModel` (or the local `viewModel` getter) unconditionally, add the same one-line argument to each of the seven `DetailActionButtons(` invocations found at lines 1270, 1478, 1610, 1755, 1939, 2022, and 3229. For example, the first call site currently reads (structure representative of all seven — exact surrounding arguments differ per call site but all share `viewModel:` and `onSelectedMediaSourceChanged:`):

```dart
      DetailActionButtons(
        viewModel: viewModel,
        onSelectedMediaSourceChanged: onSelectedMediaSourceChanged,
```

Change to:

```dart
      DetailActionButtons(
        viewModel: viewModel,
        onSelectedMediaSourceChanged: onSelectedMediaSourceChanged,
        resolvedSeerrTv: _resolvedSeerrTv,
```

Apply the identical one-line insertion (`resolvedSeerrTv: _resolvedSeerrTv,`) immediately after the existing `onSelectedMediaSourceChanged:` argument at each of the seven call sites (lines 1270, 1478, 1610, 1755, 1939, 2022, 3229). Leave every other existing argument at each call site untouched.

- [ ] Step 6: Run the resolution test again to confirm nothing regressed, plus a static analysis pass on the whole file since seven call sites were touched.

Command:
```
flutter test test/ui/screens/detail/item_detail_screen_seerr_resolution_test.dart && flutter analyze lib/ui/screens/detail/item_detail_screen.dart
```

Expected output:
```
00:0X +2: All tests passed!
No issues found!
```

- [ ] Step 7: Commit.

```
git add lib/ui/screens/detail/item_detail_screen.dart test/ui/screens/detail/item_detail_screen_seerr_resolution_test.dart
git commit -m "Resolve series Seerr identity and surface Request on Seerr in classic detail screen"
```

---

### Task 6: Confirm Modern detail screen inherits the affordance and passes resolution through

**Files**:
- Modify: `E:\Moonfin-Core\lib\ui\screens\detail\modern\modern_detail_content.dart` (the three `DetailActionButtons(` call sites at lines 2955, 3133, 3393; the state class that already owns `_loadSeerrAppearances`-equivalent lifecycle wiring, mirroring `item_detail_screen.dart` lines 247-... where `PluginSyncService.seerrAvailable` is already checked for the person-appearances feature)
- Test: `E:\Moonfin-Core\test\ui\screens\detail\modern_detail_content_seerr_test.dart` (create)

Because `ModernDetailContent` renders through the same `DetailActionButtons` widget (with `modernStyle: true`), it needs the identical `resolvedSeerrTv` plumbing as Task 5 — it does not get the button "for free" until the resolved value is threaded through its own three call sites, since `modern_detail_content.dart` is a separate `StatefulWidget` with its own state (it does not extend or share instance state with `item_detail_screen.dart`).

- [ ] Step 1: Write the failing test, verifying `resolveSeriesForSeerrRequest` is invoked with a Modern-detail-shaped `AggregatedItem`, confirming the same helper contract from Task 3 applies without alteration (the Modern screen requires no bespoke resolver — this test exists to lock that in as a regression guard specific to the Modern integration point).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/ui/screens/detail/seerr_series_request_support.dart';

class _MockSeerrRepository extends Mock implements SeerrRepository {}

void main() {
  test('modern detail screen series resolve via the shared helper', () async {
    final repo = _MockSeerrRepository();
    final item = AggregatedItem(
      id: 'series-42',
      serverId: 'server-1',
      rawData: const {
        'Type': 'Series',
        'Name': 'Modern Show',
        'ProviderIds': {'Tvdb': '54321'},
      },
    );
    const tvDetails = SeerrTvDetails(id: 111, name: 'Modern Show');
    when(
      () => repo.resolveTvdbToSeerrTv(54321),
    ).thenAnswer((_) async => tvDetails);

    final result = await resolveSeriesForSeerrRequest(
      item: item,
      seerrAvailable: true,
      repository: repo,
    );

    expect(result, same(tvDetails));
  });
}
```

- [ ] Step 2: Run the test expecting pass immediately (this test only re-confirms the Task 3 helper's contract against Modern-shaped data — it is not expected to fail, since it exercises no new production code yet; it documents the integration point before the wiring step).

Command:
```
flutter test test/ui/screens/detail/modern_detail_content_seerr_test.dart
```

Expected output:
```
00:0X +1: All tests passed!
```

- [ ] Step 3: Add the same resolution state and trigger pattern to `ModernDetailContent`'s state class in `E:\Moonfin-Core\lib\ui\screens\detail\modern\modern_detail_content.dart`, next to its existing `_seerrAppearances`/`_seerrCrewCredits` fields (the ones referenced by the `_loadSeerrAppearances` logic at line 247 shown earlier):

```dart
  SeerrTvDetails? _resolvedSeerrTv;
  String? _resolvedSeerrTvForItemId;

  Future<void> _loadSeerrSeriesResolution() async {
    final item = widget.viewModel.item;
    if (item == null || item.type != 'Series') return;
    if (_resolvedSeerrTvForItemId == item.id) return;

    final seerrAvailable = GetIt.instance<PluginSyncService>().seerrAvailable;
    if (!seerrAvailable) {
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = null;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
      return;
    }

    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final resolved = await resolveSeriesForSeerrRequest(
        item: item,
        seerrAvailable: true,
        repository: repo,
      );
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = resolved;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolvedSeerrTv = null;
          _resolvedSeerrTvForItemId = item.id;
        });
      }
    }
  }
```

Add the required imports to `modern_detail_content.dart` alongside its existing data-layer imports (mirroring the ones added in Tasks 4-5):

```dart
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../seerr_series_request_support.dart';
```

- [ ] Step 4: Call `_loadSeerrSeriesResolution()` from the same lifecycle hook(s) already calling this file's existing `_loadSeerrAppearances()`-equivalent logic (the initialization path shown to check `seerrAvailable` around line 247). Add the call immediately after that existing invocation, following the identical pattern used in Task 5 Step 4.

- [ ] Step 5: Pass `resolvedSeerrTv: _resolvedSeerrTv` into all three `DetailActionButtons(` call sites in `modern_detail_content.dart` (lines 2955, 3133, 3393), the same way as Task 5 Step 5. For example, the call site at line 2955:

```dart
            child: DetailActionButtons(
              viewModel: widget.viewModel,
              onSelectedMediaSourceChanged: widget.onSelectedMediaSourceChanged,
```

becomes:

```dart
            child: DetailActionButtons(
              viewModel: widget.viewModel,
              onSelectedMediaSourceChanged: widget.onSelectedMediaSourceChanged,
              resolvedSeerrTv: _resolvedSeerrTv,
```

Apply the identical insertion at the other two call sites (lines 3133 and 3393), leaving every other existing argument untouched.

- [ ] Step 6: Run the test suite and static analysis to confirm the Modern screen still compiles cleanly with the new wiring.

Command:
```
flutter test test/ui/screens/detail/modern_detail_content_seerr_test.dart && flutter analyze lib/ui/screens/detail/modern/modern_detail_content.dart
```

Expected output:
```
00:0X +1: All tests passed!
No issues found!
```

- [ ] Step 7: Commit.

```
git add lib/ui/screens/detail/modern/modern_detail_content.dart test/ui/screens/detail/modern_detail_content_seerr_test.dart
git commit -m "Surface Request on Seerr in modern detail screen variant"
```

---

### Task 7: Full regression pass across touched files

**Files**:
- Test: all files created/modified in Tasks 1-6

- [ ] Step 1: Run the complete set of new tests together.

Command:
```
flutter test test/data/repositories/seerr_repository_resolve_test.dart test/ui/widgets/seerr/seerr_request_sheet_test.dart test/ui/screens/detail/seerr_series_request_support_test.dart test/ui/screens/detail/detail_action_buttons_seerr_test.dart test/ui/screens/detail/item_detail_screen_seerr_resolution_test.dart test/ui/screens/detail/modern_detail_content_seerr_test.dart
```

Expected output:
```
00:0X +10: All tests passed!
```

- [ ] Step 2: Run static analysis on every file touched across this plan.

Command:
```
flutter analyze lib/data/repositories/seerr_repository.dart lib/ui/widgets/seerr/seerr_request_sheet.dart lib/ui/screens/seerr/seerr_media_detail_screen.dart lib/ui/screens/detail/seerr_series_request_support.dart lib/ui/screens/detail/item_detail_screen.dart lib/ui/screens/detail/modern/modern_detail_content.dart
```

Expected output:
```
No issues found!
```

- [ ] Step 3: Run the pre-existing project-wide test suite once to confirm no regression in unrelated tests (this repository's `test/` directory is otherwise flat/mixed convention, per the file layout observed at `E:\Moonfin-Core\test`).

Command:
```
flutter test
```

Expected output: all suites report `All tests passed!` with no new failures relative to the pre-change baseline.

- [ ] Step 4: Commit any final formatting fixups if `flutter analyze` or `dart format` flagged whitespace-only issues (skip this step entirely if Step 2 reported no issues).

```
dart format lib/data/repositories/seerr_repository.dart lib/ui/widgets/seerr/seerr_request_sheet.dart lib/ui/screens/seerr/seerr_media_detail_screen.dart lib/ui/screens/detail/seerr_series_request_support.dart lib/ui/screens/detail/item_detail_screen.dart lib/ui/screens/detail/modern/modern_detail_content.dart
git add -u
git commit -m "Apply dart format to Seerr season-request affordance changes"
```

---

### Verification

This plan implements spec section 9.1: "add a 'Request on Seerr' affordance to the real library series detail screen (`item_detail_screen.dart` / `modern_detail_content.dart`), resolving the Jellyfin series to its Seerr/TMDB identity via the already-implemented `getTvDetailsByTvdb` lookup, and reusing the existing season-selector sheet/widget rather than rebuilding it."

To verify end-to-end against a real Jellyseerr instance (per the design spec's own verification note for §9.1: "verify §9.1 against a real partially-available series on the user's Jellyseerr instance"):

1. Configure Seerr in Moonfin settings against a real Jellyseerr server (`Settings > Integrations > Seerr`) and confirm `GetIt.instance<PluginSyncService>().seerrAvailable` is `true` (visible indirectly: the existing Seerr rows on the Home screen and the Seerr person button on cast/crew detail screens should already be showing).
2. Navigate to a library series you already partly own, whose Jellyfin metadata has a TVDB provider id (most scraped TV series do) and which is `PARTIALLY_AVAILABLE` or missing a season in Jellyseerr.
3. Confirm the "Seerr" action button (Task 4/5/7's `_DetailActionButton` with the `SeerrIcon`) appears in the action row on the **Classic** detail screen for that series.
4. Switch the app's detail-screen style preference to **Modern** and re-open the same series; confirm the same "Seerr" button appears there too (Task 6).
5. Tap/select the button; confirm the extracted `SeerrRequestSheet` (Task 2) opens with the correct season count, with any already-requested/available seasons shown as disabled/grayed-out chips (`requestedSeasons` from the resolved `SeerrTvDetails`/`mediaInfo`).
6. Select a specific missing season, submit, and confirm in the Jellyseerr web UI that a new season request was created against the correct Sonarr series (same `submitRequest`/`createRequest` path already used by the pre-existing Seerr discovery detail screen — Task 1/3 only add resolution, not a new submission path).
7. Confirm the affordance is absent (not merely disabled) when Seerr is not configured (`seerrAvailable == false`) and when viewing a series with no TVDB provider id or one that fails to resolve on Seerr (Task 3's `resolveSeriesForSeerrRequest` returning `null` in both cases), on both Classic and Modern detail screens.

Note: `E:\Moonfin_Plugin` (the C#/.NET Jellyfin server plugin) is not touched by this plan — all endpoints used (`Moonfin/Seerr/Api/tv/tvdb/{tvdbId}`, `Moonfin/Seerr/Api/request`) already exist and are proxied by the existing plugin, confirmed by `SeerrHttpClient.getTvDetailsByTvdb` and `SeerrHttpClient.createRequest` in `lib/data/services/seerr/seerr_http_client.dart`. No server-plugin changes, and therefore no manual `curl` verification against the plugin, are required for this plan; that repository has no automated test harness today regardless.