# Bug Fixes (Spec §1) Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

Goal: Fix the four confirmed §1 bugs from `docs/superpowers/specs/2026-07-02-moonfin-experience-overhaul-design.md` — missing admin default for Seerr enablement, duplicate plugin-dynamic home sections, ignored folder-browse sort, and the Apple-TV-only UI downscale gate — without touching any other spec section.

Architecture: Each fix is scoped to the single file the spec identifies as the root cause and reuses an existing, proven pattern already in the codebase (the `setNullableBoolSelect`/save-handler pattern for admin defaults, the `_duplicateKeysForBuiltin` key-set pattern for dedup, the `LibraryBrowseViewModel.setSortBy` pattern for sort persistence, and the existing `PlatformDetection.isTV` getter for the TV gate). No new abstractions, services, or parallel plumbing are introduced.

Tech Stack: Flutter/Dart client (`E:\Moonfin-Core`, package `moonfin`) with `flutter_test` + `mocktail`; ASP.NET Core / .NET 8 Jellyfin server plugin (`E:\Moonfin_Plugin`, `Moonfin.Server.csproj`) with no automated test project — verified via manual `curl` against a running Jellyfin server.

---

### Task 1: Admin-settable `DefaultSeerrEnabled` flowing through `PushDefaults`

Files:
- Modify: `E:\Moonfin_Plugin\backend\Pages\configPage.html` (new select control near line 648, load-population near line 2366, save handler near line 2579)
- Modify: `E:\Moonfin_Plugin\backend\Api\MoonfinController.cs` (`GetSeerrConfig` fallback chain, lines 1446-1476)
- No change needed: `E:\Moonfin_Plugin\backend\Models\MoonfinSettingsProfile.cs` — `SeerrEnabled` (nullable bool) already exists at line 16 and is already merged by `MoonfinSettingsService.MergeProfile` (reflection-based, copies any non-null incoming property onto `existing`, lines 473-489), so `PushDefaults` already carries it once the admin UI writes it.
- Test: none — this repository has no automated test project for the C#/.NET server plugin. Verification is manual `curl` against a running Jellyfin server (see steps below).

This repository has **no existing test project** for the `.NET` server plugin (`Moonfin.Server.csproj` has zero test references and there is no sibling `*.Tests.csproj`). Do not invent one — every "test" step below is a manual `curl`-based integration check against a running Jellyfin instance with the plugin installed, exactly as the task instructions require.

- [ ] Step 1: Confirm current (buggy) fallback behavior with a manual repro. With the Jellyfin server running and Moonfin plugin installed, and with `DefaultUserSettings` having no `seerrEnabled` key set (fresh install), run:
  ```bash
  curl -s -H "X-Emby-Token: <ADMIN_API_KEY>" "http://<server>:8096/Moonfin/Seerr/Config"
  ```
  Expected current (buggy) output — `userEnabled` is hardcoded `true` regardless of any admin preference because there is no admin default lever yet:
  ```json
  {"enabled":false,"url":null,"displayName":"Seerr","variant":"seerr","userEnabled":true}
  ```
  Record this as the "before" baseline — there is no way today to make `userEnabled` default to `false` for new users short of every user manually disabling it.

- [ ] Step 2: Add the `DefaultSeerrEnabled` select control to `configPage.html` next to the existing `DefaultSeerrBlockNsfw` field. Read the current block first (already read above, lines 647-654):
  ```html
                        <div class="inputContainer">
                            <label class="inputLabel inputLabelUnfocused" for="DefaultSeerrBlockNsfw">Block NSFW In Seerr</label>
                            <select id="DefaultSeerrBlockNsfw" is="emby-select">
                                <option value="">Not set (user decides)</option>
                                <option value="true">Yes</option>
                                <option value="false">No</option>
                            </select>
                        </div>
                    </div>
  ```
  Replace with (adds a new `DefaultSeerrEnabled` control before the closing `</div>`):
  ```html
                        <div class="inputContainer">
                            <label class="inputLabel inputLabelUnfocused" for="DefaultSeerrBlockNsfw">Block NSFW In Seerr</label>
                            <select id="DefaultSeerrBlockNsfw" is="emby-select">
                                <option value="">Not set (user decides)</option>
                                <option value="true">Yes</option>
                                <option value="false">No</option>
                            </select>
                        </div>
                        <div class="inputContainer">
                            <label class="inputLabel inputLabelUnfocused" for="DefaultSeerrEnabled">Enable Seerr By Default</label>
                            <select id="DefaultSeerrEnabled" is="emby-select">
                                <option value="">Not set (defaults to enabled)</option>
                                <option value="true">Yes</option>
                                <option value="false">No</option>
                            </select>
                        </div>
                    </div>
  ```

- [ ] Step 3: Wire the new control into the load/population code path (the `setNullableBoolSelect` calls that run when the config page loads). Read the current line (already read above, line 2366):
  ```javascript
                    setNullableBoolSelect('#DefaultSeerrBlockNsfw', defaults.seerrBlockNsfw);
  ```
  Replace with:
  ```javascript
                    setNullableBoolSelect('#DefaultSeerrBlockNsfw', defaults.seerrBlockNsfw);
                    setNullableBoolSelect('#DefaultSeerrEnabled', defaults.seerrEnabled);
  ```

- [ ] Step 4: Wire the new control into the save handler. Read the current line (already read above, line 2579):
  ```javascript
                        config.DefaultUserSettings.seerrBlockNsfw = getNullableBoolSelect('#DefaultSeerrBlockNsfw');
  ```
  Replace with:
  ```javascript
                        config.DefaultUserSettings.seerrBlockNsfw = getNullableBoolSelect('#DefaultSeerrBlockNsfw');
                        config.DefaultUserSettings.seerrEnabled = getNullableBoolSelect('#DefaultSeerrEnabled');
  ```

- [ ] Step 5: Update `GetSeerrConfig`'s fallback chain in `MoonfinController.cs` to check the new admin default before falling back to `true`. Read the current code (already read above, lines 1446-1476):
  ```csharp
    public async Task<ActionResult<SeerrConfigResponse>> GetSeerrConfig()
    {
        var config = MoonfinPlugin.Instance?.Configuration;
        
        var userId = this.GetUserIdFromClaims();
        MoonfinUserSettings? userSettings = null;
        
        if (userId != null)
        {
            userSettings = await _settingsService.GetUserSettingsAsync(userId.Value);
        }

        var displayName = config?.SeerrDisplayName;
        if (string.IsNullOrWhiteSpace(displayName))
        {
            displayName = "Seerr";
        }

        var userSeerrEnabled = userSettings?.Global?.SeerrEnabled
            ?? userSettings?.SeerrEnabled  // legacy v1
            ?? true;

        return Ok(new SeerrConfigResponse
        {
            Enabled = config?.SeerrEnabled ?? false,
            Url = config?.SeerrUrl,
            DisplayName = displayName,
            Variant = "seerr",
            UserEnabled = userSeerrEnabled
        });
    }
  ```
  Replace with (inserts `config?.DefaultUserSettings?.SeerrEnabled` into the chain before the hardcoded `true`):
  ```csharp
    public async Task<ActionResult<SeerrConfigResponse>> GetSeerrConfig()
    {
        var config = MoonfinPlugin.Instance?.Configuration;
        
        var userId = this.GetUserIdFromClaims();
        MoonfinUserSettings? userSettings = null;
        
        if (userId != null)
        {
            userSettings = await _settingsService.GetUserSettingsAsync(userId.Value);
        }

        var displayName = config?.SeerrDisplayName;
        if (string.IsNullOrWhiteSpace(displayName))
        {
            displayName = "Seerr";
        }

        var userSeerrEnabled = userSettings?.Global?.SeerrEnabled
            ?? userSettings?.SeerrEnabled  // legacy v1
            ?? config?.DefaultUserSettings?.SeerrEnabled
            ?? true;

        return Ok(new SeerrConfigResponse
        {
            Enabled = config?.SeerrEnabled ?? false,
            Url = config?.SeerrUrl,
            DisplayName = displayName,
            Variant = "seerr",
            UserEnabled = userSeerrEnabled
        });
    }
  ```

- [ ] Step 6: Build the plugin to confirm it compiles (this is the closest thing to a "test run" available in this repository):
  ```powershell
  cd E:\Moonfin_Plugin
  dotnet build backend\Moonfin.Server.csproj -c Release
  ```
  Expected output ends with:
  ```
  Build succeeded.
      0 Warning(s)
      0 Error(s)
  ```

- [ ] Step 7: Deploy the built DLL and `configPage.html` (already embedded as a resource, so a full rebuild picks it up) to the Jellyfin plugin folder and restart Jellyfin, then manually verify via the admin dashboard: open the Moonfin plugin config page, set "Enable Seerr By Default" to **No**, click Save. Confirm no JS console errors and the page reloads with the select still showing "No".

- [ ] Step 8: Verify the new admin default reaches `GetSeerrConfig` for a **new** user (one with no `MoonfinUserSettings` file yet, so both `userSettings?.Global?.SeerrEnabled` and the legacy field are null):
  ```bash
  curl -s -H "X-Emby-Token: <NEW_USER_API_KEY>" "http://<server>:8096/Moonfin/Seerr/Config"
  ```
  Expected output — `userEnabled` now reflects the admin default instead of the hardcoded `true`:
  ```json
  {"enabled":false,"url":null,"displayName":"Seerr","variant":"seerr","userEnabled":false}
  ```

- [ ] Step 9: Verify `PushDefaults` propagates the new default onto an **existing** user's settings (proving the "flows through PushDefaults" requirement). With an existing user whose `Global.SeerrEnabled` is currently `null` (never customized), call:
  ```bash
  curl -s -X POST -H "X-Emby-Token: <ADMIN_API_KEY>" "http://<server>:8096/Moonfin/Admin/PushDefaults?overwrite=false"
  ```
  Expected output:
  ```json
  {"success":true,"overwrite":false,"usersAffected":<N>,"orphansDeleted":0,"liveRefreshDeliveries":<M>}
  ```
  Then re-run the `GET /Moonfin/Seerr/Config` call as that existing user and confirm `userEnabled` is now `false`, matching the admin default merged onto their `Global` profile by `MergeProfile`.

- [ ] Step 10: State explicitly in the PR/commit description that there is no automated test harness for `E:\Moonfin_Plugin` today — verification for this task is the manual `curl` sequence in Steps 1, 7, 8, and 9 only.

- [ ] Step 11: Commit.
  ```bash
  git -C E:\Moonfin_Plugin add backend/Pages/configPage.html backend/Api/MoonfinController.cs
  git -C E:\Moonfin_Plugin commit -m "Add admin-settable DefaultSeerrEnabled flowing through PushDefaults"
  ```

---

### Task 2: Fix duplicate home sections — extend dedup keys to plugin-dynamic configs

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\home\home_view_model.dart` (lines 721-726, the `_duplicateKeysForConfig` method)
- Create: `E:\Moonfin-Core\test\ui\screens\home\home_view_model_dedup_test.dart`
- Test command: `flutter test test/ui/screens/home/home_view_model_dedup_test.dart`

The dedup keying logic (`_duplicateKeysForConfig` / `_duplicateKeysForBuiltin`) is a private `static` method on `HomeViewModel`, and `HomeViewModel`'s constructor requires heavy dependencies (`RowDataSource`, `MediaServerClient`, `MediaBarViewModel`, `MultiServerRepository`) that have no existing mocks in this repo. To make the logic unit-testable without instantiating the full view model (matching zero existing precedent for mocking those types), this task marks `_duplicateKeysForConfig` `@visibleForTesting` and renames it to a public name so a same-package test file can call it directly, following the `@visibleForTesting` precedent already used in `lib/playback/media_kit_player_backend.dart:606`.

- [ ] Step 1: Read the exact current method to confirm the edit target (already read above, `lib/ui/screens/home/home_view_model.dart` lines 721-726):
  ```dart
  static Set<String> _duplicateKeysForConfig(HomeSectionConfig cfg) {
    if (cfg.isBuiltin) {
      return _duplicateKeysForBuiltin(cfg.type);
    }
    return const <String>{};
  }
  ```

- [ ] Step 2: Create the test directory and failing test file. `test/ui/screens/home/` does not exist yet, mirroring `lib/ui/screens/home/`. Write `E:\Moonfin-Core\test\ui\screens\home\home_view_model_dedup_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin/preference/home_section_config.dart';
  import 'package:moonfin/preference/preference_constants.dart';
  import 'package:moonfin/ui/screens/home/home_view_model.dart';

  void main() {
    group('HomeViewModel.duplicateKeysForConfig', () {
      test('two identical plugin-dynamic configs produce the same non-empty key set', () {
        const configA = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
          pluginAdditionalData: 'genre=action',
        );
        const configB = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
          pluginAdditionalData: 'genre=action',
        );

        final keysA = HomeViewModel.duplicateKeysForConfig(configA);
        final keysB = HomeViewModel.duplicateKeysForConfig(configB);

        expect(keysA, isNotEmpty);
        expect(keysA, equals(keysB));
      });

      test('plugin-dynamic configs differing only by pluginSection produce different keys', () {
        const configA = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
        );
        const configB = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'popular',
        );

        final keysA = HomeViewModel.duplicateKeysForConfig(configA);
        final keysB = HomeViewModel.duplicateKeysForConfig(configB);

        expect(keysA, isNot(equals(keysB)));
      });

      test('plugin-dynamic configs differing only by serverId produce different keys', () {
        const configA = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
        );
        const configB = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-2',
          pluginSection: 'trending',
        );

        final keysA = HomeViewModel.duplicateKeysForConfig(configA);
        final keysB = HomeViewModel.duplicateKeysForConfig(configB);

        expect(keysA, isNot(equals(keysB)));
      });

      test('plugin-dynamic configs differing only by pluginAdditionalData produce different keys', () {
        const configA = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
          pluginAdditionalData: 'genre=action',
        );
        const configB = HomeSectionConfig(
          kind: HomeSectionKind.pluginDynamic,
          pluginSource: HomeSectionPluginSource.collections,
          serverId: 'server-1',
          pluginSection: 'trending',
          pluginAdditionalData: 'genre=comedy',
        );

        final keysA = HomeViewModel.duplicateKeysForConfig(configA);
        final keysB = HomeViewModel.duplicateKeysForConfig(configB);

        expect(keysA, isNot(equals(keysB)));
      });

      test('builtin configs still key off type as before', () {
        const config = HomeSectionConfig(
          kind: HomeSectionKind.builtin,
          type: HomeSectionType.latestMedia,
        );

        expect(
          HomeViewModel.duplicateKeysForConfig(config),
          equals(const {'latestMedia'}),
        );
      });
    });
  }
  ```

- [ ] Step 3: Run the test expecting failure (compile error, since `duplicateKeysForConfig` doesn't exist as a public/visible member yet):
  ```bash
  flutter test test/ui/screens/home/home_view_model_dedup_test.dart
  ```
  Expected output (compile-time failure):
  ```
  Error: Method not found: 'HomeViewModel.duplicateKeysForConfig'.
  ```

- [ ] Step 4: Rename `_duplicateKeysForConfig` to a `@visibleForTesting` public method `duplicateKeysForConfig`, and update its one call site plus the one place it's invoked in the dedup filter. Read the current usages first (already read above, lines 320-340):
  ```dart
      final enabledBuiltinKeys = visibleConfigsRaw
          .where((c) => c.isBuiltin)
          .expand(_duplicateKeysForConfig)
          .toSet();
      final seenPluginKeys = <String>{};
      final visibleConfigs = visibleConfigsRaw
          .where((c) {
            if (!c.isPluginDynamic) return true;
            final duplicateKeys = _duplicateKeysForConfig(c);
            if (duplicateKeys.any(enabledBuiltinKeys.contains)) {
              return false;
            }
            final duplicatesExistingPlugin = duplicateKeys.any(
              seenPluginKeys.contains,
            );
            if (!duplicatesExistingPlugin) {
              seenPluginKeys.addAll(duplicateKeys);
            }
            return !duplicatesExistingPlugin;
          })
          .toList(growable: false);
  ```
  Replace with (renames both call sites to the new public name):
  ```dart
      final enabledBuiltinKeys = visibleConfigsRaw
          .where((c) => c.isBuiltin)
          .expand(duplicateKeysForConfig)
          .toSet();
      final seenPluginKeys = <String>{};
      final visibleConfigs = visibleConfigsRaw
          .where((c) {
            if (!c.isPluginDynamic) return true;
            final duplicateKeys = duplicateKeysForConfig(c);
            if (duplicateKeys.any(enabledBuiltinKeys.contains)) {
              return false;
            }
            final duplicatesExistingPlugin = duplicateKeys.any(
              seenPluginKeys.contains,
            );
            if (!duplicatesExistingPlugin) {
              seenPluginKeys.addAll(duplicateKeys);
            }
            return !duplicatesExistingPlugin;
          })
          .toList(growable: false);
  ```

- [ ] Step 5: Rewrite the `_duplicateKeysForConfig` method definition (lines 721-726) as the public, `@visibleForTesting`, plugin-aware version. This requires adding the `package:flutter/foundation.dart` import's `visibleForTesting` annotation, which is already imported at line 7 (`import 'package:flutter/foundation.dart';`), so no new import is needed. Replace:
  ```dart
  static Set<String> _duplicateKeysForConfig(HomeSectionConfig cfg) {
    if (cfg.isBuiltin) {
      return _duplicateKeysForBuiltin(cfg.type);
    }
    return const <String>{};
  }
  ```
  With:
  ```dart
  @visibleForTesting
  static Set<String> duplicateKeysForConfig(HomeSectionConfig cfg) {
    if (cfg.isBuiltin) {
      return _duplicateKeysForBuiltin(cfg.type);
    }
    return {
      'plugin:${cfg.pluginSource.serializedName}:${cfg.pluginSection ?? ''}:${cfg.serverId ?? ''}:${cfg.pluginAdditionalData ?? ''}',
    };
  }
  ```

- [ ] Step 6: Run the test expecting pass:
  ```bash
  flutter test test/ui/screens/home/home_view_model_dedup_test.dart
  ```
  Expected output:
  ```
  00:0X +5: All tests passed!
  ```

- [ ] Step 7: Run `flutter analyze` on the touched file to confirm the rename didn't leave any stray reference to the old private name:
  ```bash
  flutter analyze lib/ui/screens/home/home_view_model.dart
  ```
  Expected output:
  ```
  No issues found!
  ```

- [ ] Step 8: Commit.
  ```bash
  git add lib/ui/screens/home/home_view_model.dart test/ui/screens/home/home_view_model_dedup_test.dart
  git commit -m "Fix duplicate home sections by keying plugin-dynamic dedup on source/section/server/data"
  ```

---

### Task 3: Fix folder browse sort being hardcoded and ignored

Files:
- Modify: `E:\Moonfin-Core\lib\data\viewmodels\folder_browse_view_model.dart` (constructor, `_fetchItemsWithFallback`, add `sortBy`/`setSortBy`)
- Modify: `E:\Moonfin-Core\lib\preference\user_preferences.dart` (add a `folderBrowseSortBy` preference key, mirroring `librarySortBy` at line 1849)
- Modify: `E:\Moonfin-Core\lib\ui\screens\browse\folder_browse_screen.dart` (pass `prefs` into the constructor call at line 43)
- Create: `E:\Moonfin-Core\test\data\viewmodels\folder_browse_view_model_test.dart`
- Test command: `flutter test test/data/viewmodels/folder_browse_view_model_test.dart`

This mirrors the proven `LibraryBrowseViewModel` pattern exactly: inject `UserPreferences`, read `LibrarySortBy` from a per-scope preference key in the constructor, add a public `sortBy` getter and `setSortBy` method that persists and reloads, and use `_sortBy.apiValue` (instead of the hardcoded `'IsFolder,SortName'` literal) when building the `getItems` call — while preserving the existing `IsFolder,` prefix behavior (folders-first) that today's hardcoded string encodes, plus the 500-error `SortName`-only fallback.

- [ ] Step 1: Add a `folderBrowseSortBy` preference, mirroring the existing `librarySortBy` factory. Read the current code (already read above, `lib/preference/user_preferences.dart` lines 1849-1854):
  ```dart
    static EnumPreference<LibrarySortBy> librarySortBy(String libraryId) =>
        EnumPreference(
          key: 'library_sort_by_$libraryId',
          defaultValue: LibrarySortBy.name,
          values: LibrarySortBy.values,
        );
  ```
  Add immediately after it:
  ```dart
    static EnumPreference<LibrarySortBy> librarySortBy(String libraryId) =>
        EnumPreference(
          key: 'library_sort_by_$libraryId',
          defaultValue: LibrarySortBy.name,
          values: LibrarySortBy.values,
        );

    static EnumPreference<LibrarySortBy> folderBrowseSortBy(String folderId) =>
        EnumPreference(
          key: 'folder_browse_sort_by_$folderId',
          defaultValue: LibrarySortBy.name,
          values: LibrarySortBy.values,
        );
  ```

- [ ] Step 2: Write the failing test first. Create `E:\Moonfin-Core\test\data\viewmodels\folder_browse_view_model_test.dart`, mirroring the `SharedPreferences.setMockInitialValues` + `PreferenceStore` setup already used in `test/preference/user_preferences_passthrough_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:jellyfin_preference/jellyfin_preference.dart';
  import 'package:moonfin/data/viewmodels/folder_browse_view_model.dart';
  import 'package:moonfin/preference/preference_constants.dart';
  import 'package:moonfin/preference/user_preferences.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    final store = PreferenceStore();
    await store.init();
    return UserPreferences(store);
  }

  void main() {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('setSortBy persists the chosen sort under the folder-scoped preference key', () async {
      final prefs = await _prefs();
      final vm = FolderBrowseViewModel.forTesting(prefs: prefs, folderId: 'folder-123');

      expect(vm.sortBy, LibrarySortBy.name);

      await vm.setSortBy(LibrarySortBy.dateAdded);

      expect(vm.sortBy, LibrarySortBy.dateAdded);
      expect(
        prefs.get(UserPreferences.folderBrowseSortBy('folder-123')),
        LibrarySortBy.dateAdded,
      );
    });

    test('a previously persisted sort choice is read back on construction', () async {
      final prefs = await _prefs();
      await prefs.set(
        UserPreferences.folderBrowseSortBy('folder-456'),
        LibrarySortBy.rating,
      );

      final vm = FolderBrowseViewModel.forTesting(prefs: prefs, folderId: 'folder-456');

      expect(vm.sortBy, LibrarySortBy.rating);
    });
  }
  ```
  This references a `FolderBrowseViewModel.forTesting` constructor and `sortBy`/`setSortBy` members that do not exist yet, and a `folderId`-scoped preference — this is intentional; it drives the implementation in the next steps. (`UserPreferences(store)` and `PreferenceStore` match the constructor pattern already used by `_prefs()` in `test/preference/user_preferences_passthrough_test.dart`.)

- [ ] Step 3: Run the test expecting failure:
  ```bash
  flutter test test/data/viewmodels/folder_browse_view_model_test.dart
  ```
  Expected output (compile-time failure):
  ```
  Error: The method 'forTesting' isn't defined for the class 'FolderBrowseViewModel'.
  ```

- [ ] Step 4: Modify `FolderBrowseViewModel` to accept `UserPreferences`, expose `sortBy`/`setSortBy`, and use the persisted value instead of the hardcoded string. Read the current constructor and top-of-class fields (already read above, `lib/data/viewmodels/folder_browse_view_model.dart` lines 1-30):
  ```dart
  import 'package:flutter/foundation.dart';
  import 'package:dio/dio.dart';
  import 'package:server_core/server_core.dart';

  import '../models/aggregated_item.dart';
  import '../utils/playlist_utils.dart';

  class BreadcrumbEntry {
    final String id;
    final String name;

    const BreadcrumbEntry({required this.id, required this.name});
  }

  enum FolderBrowseState { loading, ready, error }

  class FolderBrowseViewModel extends ChangeNotifier {
    final MediaServerClient _client;

    final String? _serverId;

    static const _pageSize = 100;
    static const _fields =
        'Type,ProductionYear,ImageTags,BackdropImageTags,ChildCount,ParentThumbItemId,ParentThumbImageTag,SeriesId,SeriesPrimaryImageTag';
    // Cap image tags to one per type (server returns all by default)
    static const _imageTypes = 'Primary,Backdrop,Thumb';
    static const _imageTypeLimit = 1;

    FolderBrowseViewModel(this._client, {String? serverId})
      : _serverId = serverId;
  ```
  Replace with (adds `UserPreferences` + `LibrarySortBy` state, a `forTesting` named constructor for the unit test, and keeps the primary constructor's call site compatible by resolving prefs via `GetIt` at the call site in Step 7 rather than here):
  ```dart
  import 'package:flutter/foundation.dart';
  import 'package:dio/dio.dart';
  import 'package:server_core/server_core.dart';

  import '../../preference/preference_constants.dart';
  import '../../preference/user_preferences.dart';
  import '../models/aggregated_item.dart';
  import '../utils/playlist_utils.dart';

  class BreadcrumbEntry {
    final String id;
    final String name;

    const BreadcrumbEntry({required this.id, required this.name});
  }

  enum FolderBrowseState { loading, ready, error }

  class FolderBrowseViewModel extends ChangeNotifier {
    final MediaServerClient _client;
    final UserPreferences _prefs;

    final String? _serverId;
    final String _rootFolderId;

    static const _pageSize = 100;
    static const _fields =
        'Type,ProductionYear,ImageTags,BackdropImageTags,ChildCount,ParentThumbItemId,ParentThumbImageTag,SeriesId,SeriesPrimaryImageTag';
    // Cap image tags to one per type (server returns all by default)
    static const _imageTypes = 'Primary,Backdrop,Thumb';
    static const _imageTypeLimit = 1;

    late LibrarySortBy _sortBy;
    LibrarySortBy get sortBy => _sortBy;

    FolderBrowseViewModel(
      this._client, {
      required UserPreferences prefs,
      String? serverId,
      String rootFolderId = '',
    }) : _prefs = prefs,
         _serverId = serverId,
         _rootFolderId = rootFolderId {
      _sortBy = _prefs.get(UserPreferences.folderBrowseSortBy(_rootFolderId));
    }

    @visibleForTesting
    FolderBrowseViewModel.forTesting({
      required UserPreferences prefs,
      required String folderId,
      MediaServerClient? client,
    }) : _client = client ?? MediaServerClient(baseUrl: 'test://test'),
         _prefs = prefs,
         _serverId = null,
         _rootFolderId = folderId {
      _sortBy = _prefs.get(UserPreferences.folderBrowseSortBy(_rootFolderId));
    }

    Future<void> setSortBy(LibrarySortBy value) async {
      if (_sortBy == value) return;
      _sortBy = value;
      await _prefs.set(UserPreferences.folderBrowseSortBy(_rootFolderId), value);
      await loadFolder(currentFolderId.isEmpty ? _rootFolderId : currentFolderId);
    }
  ```

- [ ] Step 5: Run the test expecting failure again (now a real assertion or constructor-signature failure, whichever surfaces first — if `MediaServerClient` has no `baseUrl`-only constructor, this step's failure output documents the exact fix needed):
  ```bash
  flutter test test/data/viewmodels/folder_browse_view_model_test.dart
  ```
  Expected output before Step 6 lands the `_fetchItemsWithFallback` change: the two sort tests should now compile and run, confirming `sortBy`/`setSortBy` work in isolation. If `MediaServerClient(baseUrl: 'test://test')` does not compile because the real constructor requires different named parameters, inspect `MediaServerClient`'s constructor in `package:server_core` and adjust the `forTesting` constructor's client instantiation to match — this is a mechanical fix, not a design change.

- [ ] Step 6: Wire `_sortBy.apiValue` into `_fetchItemsWithFallback`, replacing the hardcoded literals. Read the current method (already read above, lines 176-212):
  ```dart
    Future<Map<String, dynamic>> _fetchItemsWithFallback({
      required String parentId,
      required int startIndex,
    }) async {
      try {
        return await _client.itemsApi.getItems(
          parentId: parentId,
          recursive: false,
          sortBy: 'IsFolder,SortName',
          sortOrder: 'Ascending',
          startIndex: startIndex,
          limit: _pageSize,
          fields: _fields,
          enableImageTypes: _imageTypes,
          imageTypeLimit: _imageTypeLimit,
          enableTotalRecordCount: true,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode ?? 0;
        if (statusCode < 500) {
          rethrow;
        }

        return _client.itemsApi.getItems(
          parentId: parentId,
          recursive: false,
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          startIndex: startIndex,
          limit: _pageSize,
          fields: _fields,
          enableImageTypes: _imageTypes,
          imageTypeLimit: _imageTypeLimit,
          enableTotalRecordCount: false,
        );
      }
    }
  ```
  Replace with (uses `_sortBy.apiValue`, keeping the `IsFolder,` folders-first prefix on the primary request and the plain-sort fallback on 5xx, exactly matching the existing behavior but now driven by the persisted preference instead of a literal):
  ```dart
    Future<Map<String, dynamic>> _fetchItemsWithFallback({
      required String parentId,
      required int startIndex,
    }) async {
      final sortByValue = _sortBy.apiValue;
      try {
        return await _client.itemsApi.getItems(
          parentId: parentId,
          recursive: false,
          sortBy: 'IsFolder,$sortByValue',
          sortOrder: 'Ascending',
          startIndex: startIndex,
          limit: _pageSize,
          fields: _fields,
          enableImageTypes: _imageTypes,
          imageTypeLimit: _imageTypeLimit,
          enableTotalRecordCount: true,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode ?? 0;
        if (statusCode < 500) {
          rethrow;
        }

        return _client.itemsApi.getItems(
          parentId: parentId,
          recursive: false,
          sortBy: sortByValue,
          sortOrder: 'Ascending',
          startIndex: startIndex,
          limit: _pageSize,
          fields: _fields,
          enableImageTypes: _imageTypes,
          imageTypeLimit: _imageTypeLimit,
          enableTotalRecordCount: false,
        );
      }
    }
  ```

- [ ] Step 7: Update the production call site in `folder_browse_screen.dart` to pass `prefs` and the root `folderId`. Read the current code (already read above, `lib/ui/screens/browse/folder_browse_screen.dart` lines 27-47):
  ```dart
  class _FolderBrowseScreenState extends State<FolderBrowseScreen> {
    late final FolderBrowseViewModel _vm;
    final _scrollController = ScrollController();
    DateTime? _lastItemTapAt;
    String? _lastTappedItemId;

    @override
    void initState() {
      super.initState();
      final serverId = widget.serverId;
      final client = serverId != null && serverId.isNotEmpty
          ? GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                  serverId,
                ) ??
                GetIt.instance<MediaServerClient>()
          : GetIt.instance<MediaServerClient>();
      _vm = FolderBrowseViewModel(client, serverId: serverId);
      _vm.addListener(_onChanged);
      _scrollController.addListener(_onScroll);
      _vm.loadFolder(widget.folderId);
    }
  ```
  Replace with (adds the `UserPreferences` import and passes `prefs`/`rootFolderId` through to the constructor):
  ```dart
  class _FolderBrowseScreenState extends State<FolderBrowseScreen> {
    late final FolderBrowseViewModel _vm;
    final _scrollController = ScrollController();
    DateTime? _lastItemTapAt;
    String? _lastTappedItemId;

    @override
    void initState() {
      super.initState();
      final serverId = widget.serverId;
      final client = serverId != null && serverId.isNotEmpty
          ? GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                  serverId,
                ) ??
                GetIt.instance<MediaServerClient>()
          : GetIt.instance<MediaServerClient>();
      _vm = FolderBrowseViewModel(
        client,
        prefs: GetIt.instance<UserPreferences>(),
        serverId: serverId,
        rootFolderId: widget.folderId,
      );
      _vm.addListener(_onChanged);
      _scrollController.addListener(_onScroll);
      _vm.loadFolder(widget.folderId);
    }
  ```
  Also add the import next to the existing ones at the top of the file (already read above, lines 1-16):
  ```dart
  import '../../../data/services/media_server_client_factory.dart';
  import '../../../data/viewmodels/folder_browse_view_model.dart';
  ```
  becomes:
  ```dart
  import '../../../data/services/media_server_client_factory.dart';
  import '../../../data/viewmodels/folder_browse_view_model.dart';
  import '../../../preference/user_preferences.dart';
  ```

- [ ] Step 8: Run the test expecting pass:
  ```bash
  flutter test test/data/viewmodels/folder_browse_view_model_test.dart
  ```
  Expected output:
  ```
  00:0X +2: All tests passed!
  ```

- [ ] Step 9: Run `flutter analyze` on all three touched files to confirm the new constructor parameter and import don't break any other call site:
  ```bash
  flutter analyze lib/data/viewmodels/folder_browse_view_model.dart lib/ui/screens/browse/folder_browse_screen.dart lib/preference/user_preferences.dart
  ```
  Expected output:
  ```
  No issues found!
  ```

- [ ] Step 10: Commit.
  ```bash
  git add lib/data/viewmodels/folder_browse_view_model.dart lib/ui/screens/browse/folder_browse_screen.dart lib/preference/user_preferences.dart test/data/viewmodels/folder_browse_view_model_test.dart
  git commit -m "Fix folder browse sort being hardcoded and ignored"
  ```

- [ ] Step 11: Per the spec's note to "verify against music/book browse view-models too in case they share the same gap," search for other view models with a hardcoded `sortBy` literal that never reads a preference:
  ```bash
  grep -rn "sortBy: 'SortName'\|sortBy: 'IsFolder" lib/data/viewmodels/
  ```
  If this returns any file other than the now-fixed `folder_browse_view_model.dart`, note it as a follow-up (do not fix inline in this task — it is out of scope for §1.3 unless the spec's own audit turns up an in-scope duplicate; the spec text names only `folder_browse_view_model.dart`).

---

### Task 4: Flip Android TV UI scaling gate from Apple-TV-only to all TV platforms, and audit the separate 0.8x `platformScale` multiplier

Files:
- Modify: `E:\Moonfin-Core\lib\app.dart` (line 229 gate, plus a new `@visibleForTesting` extraction for the gate condition)
- Create: `E:\Moonfin-Core\test\app_tv_ui_scale_gate_test.dart`
- Test command: `flutter test test/app_tv_ui_scale_gate_test.dart`
- No code change (audit only, documented in Step 8): `lib/ui/screens/home/home_screen.dart` (lines 2003, 2706-2709, 2737, 3599), `lib/ui/screens/detail/item_detail_screen.dart` (lines 12473-12475, 12584-12586, 12666-12668), `lib/ui/screens/browse/library_browse_screen.dart`, `lib/ui/screens/browse/library_genres_screen.dart`, `lib/ui/screens/browse/favorites_screen.dart`, `lib/ui/screens/browse/library_view_screen.dart`, `lib/ui/screens/search/search_screen.dart`, `lib/ui/screens/browse/all_genres_screen.dart`

`_MoonfinAppState` requires full `GetIt` DI (`UserPreferences`, `AppThemeController`, etc.) that has no existing test setup anywhere in this repo, so a widget-level test that pumps `MoonfinApp` is impractical for a small step. Instead, this task extracts the gate's boolean condition into a small, pure, `@visibleForTesting` top-level function that is unit-testable in isolation, then wires it into the existing `mainChild` expression at line 229.

- [ ] Step 1: Read the current gate and its imports (already read above, `lib/app.dart` lines 42, 229-231):
  ```dart
  import 'util/platform_detection.dart';
  ```
  ```dart
                final mainChild = PlatformDetection.isAppleTV
                    ? _TvUiScale(child: overlay)
                    : overlay;
  ```

- [ ] Step 2: Write the failing test first. Create `E:\Moonfin-Core\test\app_tv_ui_scale_gate_test.dart` (flat, top-level, matching the existing flat convention seen in `test/widget_test.dart`, `test/reader_chrome_test.dart`, `test/pin_entry_dialog_test.dart`):
  ```dart
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
  ```

- [ ] Step 3: Run the test expecting failure:
  ```bash
  flutter test test/app_tv_ui_scale_gate_test.dart
  ```
  Expected output (compile-time failure, function doesn't exist yet):
  ```
  Error: Method not found: 'shouldApplyTvUiScale'.
  ```

- [ ] Step 4: Add the extracted, `@visibleForTesting` top-level function and use it at the gate. Read the current gate site once more for exact surrounding context (already read above, lines 225-231):
  ```dart
                  ],
                );

                final mainChild = PlatformDetection.isAppleTV
                    ? _TvUiScale(child: overlay)
                    : overlay;
  ```
  Replace with:
  ```dart
                  ],
                );

                final mainChild = shouldApplyTvUiScale()
                    ? _TvUiScale(child: overlay)
                    : overlay;
  ```
  Then add the new top-level function right after the imports and before `class MoonfinApp` (already read above, lines 47-49):
  ```dart
  import 'ui/widgets/focus/request_initial_focus.dart';
  import 'package:custom_tv_text_field/custom_tv_text_field.dart';

  class MoonfinApp extends StatefulWidget {
  ```
  becomes:
  ```dart
  import 'ui/widgets/focus/request_initial_focus.dart';
  import 'package:custom_tv_text_field/custom_tv_text_field.dart';

  /// True when the global TV downscale ([_TvUiScale]) should wrap the app
  /// shell. Previously gated to [PlatformDetection.isAppleTV] only, which
  /// meant Android TV (and Tizen) never got the downscale and rendered
  /// oversized, desktop-density cards on a 10-foot display. [isTV] covers
  /// Apple TV, Android TV, and Tizen.
  @visibleForTesting
  bool shouldApplyTvUiScale() => PlatformDetection.isTV;

  class MoonfinApp extends StatefulWidget {
  ```
  This requires `visibleForTesting`, which comes from `package:flutter/foundation.dart` — already imported at line 3 (`import 'package:flutter/foundation.dart' show kIsWeb;`). Since that import uses `show kIsWeb`, it must be widened. Read the current import:
  ```dart
  import 'package:flutter/foundation.dart' show kIsWeb;
  ```
  Replace with:
  ```dart
  import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
  ```

- [ ] Step 5: Run the test expecting pass:
  ```bash
  flutter test test/app_tv_ui_scale_gate_test.dart
  ```
  Expected output:
  ```
  00:0X +2: All tests passed!
  ```

- [ ] Step 6: Run `flutter analyze` on `lib/app.dart` to confirm the widened import and new function don't introduce warnings:
  ```bash
  flutter analyze lib/app.dart
  ```
  Expected output:
  ```
  No issues found!
  ```

- [ ] Step 7: Commit the gate fix separately from the audit findings so the flip is independently revertible.
  ```bash
  git add lib/app.dart test/app_tv_ui_scale_gate_test.dart
  git commit -m "Flip Android TV UI scaling gate from Apple TV only to all TV platforms"
  ```

- [ ] Step 8: Audit every place a separate 0.8x `platformScale` multiplier is applied, now that `_TvUiScale`'s ~1.45x downscale (`_targetScale` at `lib/app.dart:1074`) also applies globally on Android TV, so the two factors don't stack into overly-cramped cards. Enumerate every hit:
  ```bash
  grep -rn "platformScale" lib/ui/
  ```
  Expected output — confirms exactly two files apply the ad-hoc 0.8x band-aid, each in three separate near-identical blocks:
  ```
  lib/ui/screens/detail/item_detail_screen.dart:12473:    final platformScale = PlatformDetection.isTV
  lib/ui/screens/detail/item_detail_screen.dart:12483:        posterSize.portraitHeight.toDouble() * platformScale * rowScale;
  lib/ui/screens/detail/item_detail_screen.dart:12584:    final platformScale = PlatformDetection.isTV
  lib/ui/screens/detail/item_detail_screen.dart:12594:        posterSize.portraitHeight.toDouble() * platformScale * rowScale;
  lib/ui/screens/detail/item_detail_screen.dart:12666:    final platformScale = PlatformDetection.isTV
  lib/ui/screens/detail/item_detail_screen.dart:12676:        posterSize.portraitHeight.toDouble() * platformScale * rowScale;
  lib/ui/screens/home/home_screen.dart:2003:    final platformScale = PlatformDetection.isTV ? 0.8 * desktopScale : desktopScale;
  lib/ui/screens/home/home_screen.dart:2706:    final platformScale = PlatformDetection.isTV
  lib/ui/screens/home/home_screen.dart:2737:      final platformScale = PlatformDetection.isTV
  lib/ui/screens/home/home_screen.dart:3599:    final platformScale = PlatformDetection.isTV
  ```
  Both `home_screen.dart` and `item_detail_screen.dart` gate their local 0.8x multiplier on the same `PlatformDetection.isTV` condition that now also drives `shouldApplyTvUiScale()` globally in `app.dart`. Before this task, Android TV got only the local 0.8x (no global `_TvUiScale` wrap); after this task's Step 4, Android TV gets **both** the global ~1.45x downscale (which shrinks all logical pixels, cards included) **and** the local 0.8x poster multiplier — the two stack multiplicatively to roughly 0.8x on top of the already-scaled layout, which is the over-cramped-cards risk the spec calls out.

- [ ] Step 9: Confirm which of the two mechanisms should own the correction by checking whether Apple TV (which already had the global `_TvUiScale` wrap before this change) also hits the local 0.8x multiplier — if so, Apple TV already has this exact stacking today and its cards are the working reference point:
  ```bash
  grep -n "isAppleTV" lib/ui/screens/home/home_screen.dart lib/ui/screens/detail/item_detail_screen.dart
  ```
  Expected output: no matches — confirming both `platformScale` sites key off `PlatformDetection.isTV` (which already included `isAppleTV` per its definition `static bool get isTV => _isTv || isTizen || isAppleTV;`), so Apple TV has always had both the global `_TvUiScale` wrap and the local 0.8x multiplier stacked together, and that combination is the shipped, presumably-acceptable-density reference for tvOS today.

- [ ] Step 10: Because Apple TV already ships with both factors stacked and is the working reference, and because Android TV was the platform with **no** global scale until Step 4 of this task, conclude the audit: no code change to the 0.8x `platformScale` sites is required by this task — flipping the gate makes Android TV match Apple TV's existing (already-tuned) stacked-scale behavior rather than introducing new stacking. Record this conclusion in the commit message for traceability rather than as a separate doc file.

- [ ] Step 11: Manually verify the visual result on an Android TV emulator/device per the spec's own verification note ("side-by-side before/after screenshot comparison on an Android TV device/emulator for the scaling fix"). Launch the app with `PlatformDetection.setTvMode(true)` active (as it is on a real Android TV build) and visually compare the home screen and item detail screen card density against the same screens on Apple TV. Confirm cards are not visibly smaller/more cramped on Android TV than on Apple TV — if they are, that indicates the 0.8x sites need their own follow-up fix, which is out of scope for this task's audit-only mandate and should be filed as a new backlog item rather than patched ad hoc here.

- [ ] Step 12: Commit the audit conclusion as a no-op marker so the investigation is traceable in history (only if a repo convention exists for recording audit-only findings in a comment; otherwise fold this into the Step 7 commit message and skip a separate commit). Since Step 7 already committed the code change, and Steps 8-11 produced no further code changes, no additional commit is needed for Task 4 — the audit's findings are captured in this plan document and the PR description.

---

### Verification

- **§1.1 (Seerr default)**: Task 1's Steps 1, 8, and 9 directly verify the spec's exact requirement — `MoonfinController.GetSeerrConfig`'s fallback chain now checks `config?.DefaultUserSettings?.SeerrEnabled` before defaulting to `true`, and the admin-set default demonstrably reaches both new users (Step 8) and existing users via `PushDefaults`/`MergeProfile` (Step 9), matching "Confirm it flows through the existing `PushDefaults`/merge path."
- **§1.2 (duplicate home sections)**: Task 2's test suite directly verifies the spec's stated defect — two `HomeSectionConfig` entries with identical `pluginSource`/`pluginSection`/`serverId`/`pluginAdditionalData` now produce identical non-empty dedup keys (collapsed by the existing `seenPluginKeys` logic in `home_view_model.dart`), while configs differing in any one of those four fields remain distinct, exactly matching "extend the dedup key computation to also key plugin-dynamic configs on `(pluginSource, pluginSection, serverId, additionalData)`."
- **§1.3 (folder browse sort)**: Task 3's test suite and manual wiring verify that `FolderBrowseViewModel` now has a real `setSortBy`/`sortBy` pair backed by a persisted preference (mirroring `LibraryBrowseViewModel`), and that `_fetchItemsWithFallback` sends the chosen `LibrarySortBy.apiValue` instead of the hardcoded `'IsFolder,SortName'`/`'SortName'` literals — directly resolving "nested folder navigation silently ignores the user's sort preference." Step 11 covers the spec's follow-up instruction to check sibling view models for the same gap.
- **§1.4 (Android TV scaling)**: Task 4 Step 4 flips the exact line the spec identifies (`lib/app.dart:229`) from `PlatformDetection.isAppleTV` to the `isTV`-backed `shouldApplyTvUiScale()`, verified by a unit test toggling `PlatformDetection.setTvMode`. Steps 8-11 satisfy the spec's required "follow-up pass" auditing every `platformScale` 0.8x site, concluding (with evidence that Apple TV already stacks both factors today) that no additional code change is needed to prevent over-cramped cards, and flagging real-device visual verification as the final check per the spec's own verification note.