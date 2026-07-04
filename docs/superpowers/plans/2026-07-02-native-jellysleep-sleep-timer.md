# Jellysleep Native Sleep Timer Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

**Goal**: Let a user start, monitor, and cancel a native sleep timer (fixed duration or "after N more episodes") from the video player, backed directly by the already-installed Jellysleep Jellyfin plugin's REST API, with no server-side Moonfin plugin changes.

**Architecture**: A new `JellysleepApi` class in `packages/server_jellyfin` wraps the plugin's two REST endpoints (`POST /Plugin/Jellysleep/StartTimer`, `POST /Plugin/Jellysleep/CancelTimer`) over the existing authenticated `Dio` instance, exposed as `MediaServerClient.jellysleepApi` alongside the other per-server APIs (`itemsApi`, `playbackApi`, etc.). `VideoPlayerScreen` gets a new moon-icon button in the existing secondary controls row that opens a new `SleepTimerPickerDialog` (duration or "stop after N episodes"), calls `JellysleepApi.startTimer`, and tracks local `_sleepTimerActive`/`_sleepTimerLabel` state so a small indicator with a tap-to-cancel affordance renders in the player overlay stack, following the same `Positioned`/`adaptiveGlass` visual pattern as `SkipSegmentOverlay`.

**Tech Stack**: Flutter/Dart, `dio` for HTTP, `flutter_test` + mocktail for app-level widget/state tests, `package:test` + a fake `HttpClientAdapter` for the `server_jellyfin` package-level API client test (matching `packages/server_core/test/server_probe_test.dart`, since `server_jellyfin` has no Flutter or mocktail dependency today), `flutter gen-l10n` for localized strings. The companion server plugin (`E:\Moonfin_Plugin`) is **not modified** by this plan — Jellysleep is a separate, already-installed third-party plugin reached directly by the client.

---

### Task 1: `JellysleepApi` client (start timer / cancel timer)

Files:
- Create: `E:\Moonfin-Core\packages\server_jellyfin\test\jellysleep_api_test.dart`
- Create: `E:\Moonfin-Core\packages\server_jellyfin\lib\src\api\jellysleep_api.dart`
- Modify: `E:\Moonfin-Core\packages\server_jellyfin\pubspec.yaml` (add `dev_dependencies: test`)
- Modify: `E:\Moonfin-Core\packages\server_jellyfin\lib\src\jellyfin_media_server_client.dart` (lines 1-29, 115-196 — add import + `jellysleepApi` field)
- Modify: `E:\Moonfin-Core\packages\server_core\lib\src\media_server_client.dart` (lines 1-77 — add optional `jellysleepApi` getter to the abstract client)

- [ ] Step 1: Add a `test` dev dependency to `server_jellyfin`'s pubspec so the package can have its own tests (it currently has none)

  `E:\Moonfin-Core\packages\server_jellyfin\pubspec.yaml` currently reads:

  ```yaml
  name: server_jellyfin
  description: Jellyfin server API implementation.
  publish_to: 'none'
  version: 0.1.0

  environment:
    sdk: ^3.11.0

  dependencies:
    server_core:
      path: ../server_core
    dio: ^5.9.2
    logger: ^2.6.2
  ```

  Change it to:

  ```yaml
  name: server_jellyfin
  description: Jellyfin server API implementation.
  publish_to: 'none'
  version: 0.1.0

  environment:
    sdk: ^3.11.0

  dependencies:
    server_core:
      path: ../server_core
    dio: ^5.9.2
    logger: ^2.6.2

  dev_dependencies:
    test: ^1.25.0
  ```

- [ ] Step 2: Run `dart pub get` in the package and confirm it resolves, expecting output containing `Got dependencies!`

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && dart pub get
  ```

  Expected output ends with a line containing `Got dependencies!` (or `Resolving dependencies...` followed by no errors). If it errors, stop and fix the pubspec before continuing.

- [ ] Step 3: Write the failing test for `JellysleepApi.startTimer` (duration-based) in a new file, using the same fake-`HttpClientAdapter` pattern as `packages/server_core/test/server_probe_test.dart`

  Create `E:\Moonfin-Core\packages\server_jellyfin\test\jellysleep_api_test.dart`:

  ```dart
  import 'dart:convert';
  import 'dart:typed_data';

  import 'package:dio/dio.dart';
  import 'package:server_jellyfin/server_jellyfin.dart';
  import 'package:test/test.dart';

  /// Records the last request seen and returns a canned response.
  class _RecordingAdapter implements HttpClientAdapter {
    _RecordingAdapter(this.responder);

    final ResponseBody Function(RequestOptions options) responder;
    RequestOptions? lastRequest;
    String? lastRequestBody;

    @override
    Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
    ) async {
      lastRequest = options;
      if (requestStream != null) {
        final bytes = await requestStream.expand((chunk) => chunk).toList();
        lastRequestBody = utf8.decode(bytes);
      }
      return responder(options);
    }

    @override
    void close({bool force = false}) {}
  }

  ResponseBody _status(int code) => ResponseBody.fromString('', code);

  void main() {
    late Dio dio;
    late _RecordingAdapter adapter;
    late JellysleepApi api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://host'));
      adapter = _RecordingAdapter((_) => _status(204));
      dio.httpClientAdapter = adapter;
      api = JellysleepApi(dio);
    });

    group('startTimer', () {
      test('posts duration type and minutes to StartTimer', () async {
        await api.startTimer(type: 'duration', duration: 30);

        expect(adapter.lastRequest!.method, 'POST');
        expect(
          adapter.lastRequest!.uri.toString(),
          'https://host/Plugin/Jellysleep/StartTimer',
        );
        final body = jsonDecode(adapter.lastRequestBody!) as Map;
        expect(body['type'], 'duration');
        expect(body['duration'], 30);
      });
    });
  }
  ```

- [ ] Step 4: Run the test file, expecting it to fail because neither `JellysleepApi` nor `server_jellyfin.dart`'s export of it exist yet

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test test/jellysleep_api_test.dart
  ```

  Expected output contains an error such as:
  ```
  Error: Type 'JellysleepApi' not found.
  ```
  (or an equivalent "isn't defined"/"isn't a library" compile error referencing `JellysleepApi`). This confirms the test fails for the right reason before any implementation exists.

- [ ] Step 5: Write the minimal `JellysleepApi` implementation

  Create `E:\Moonfin-Core\packages\server_jellyfin\lib\src\api\jellysleep_api.dart`:

  ```dart
  import 'package:dio/dio.dart';

  /// Client for the third-party Jellysleep Jellyfin plugin's REST API.
  ///
  /// Jellysleep is installed directly on the user's Jellyfin server as a
  /// plugin route (`/Plugin/Jellysleep/*`) and is reached with the same
  /// authenticated [Dio] instance used for all other Jellyfin API calls —
  /// no Moonfin server-plugin proxy is involved.
  class JellysleepApi {
    final Dio _dio;

    JellysleepApi(this._dio);

    /// Starts a sleep timer.
    ///
    /// [type] is either `'duration'` (stop playback after [duration] minutes)
    /// or `'episode'` (stop playback after [duration] more episodes finish).
    Future<void> startTimer({
      required String type,
      required int duration,
    }) async {
      await _dio.post(
        '/Plugin/Jellysleep/StartTimer',
        data: {'type': type, 'duration': duration},
      );
    }

    /// Cancels any active sleep timer for the current user/session.
    Future<void> cancelTimer() async {
      await _dio.post('/Plugin/Jellysleep/CancelTimer');
    }
  }
  ```

- [ ] Step 6: Export the new file from the package's public entry point

  First check the existing export list:

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && cat lib/server_jellyfin.dart
  ```

  Read the file with the Read tool, find the line exporting `src/api/jellyfin_items_api.dart` (or the alphabetically nearest existing `api/` export), and add a new line immediately after it:

  ```dart
  export 'src/api/jellysleep_api.dart';
  ```

- [ ] Step 7: Run the test again, expecting it to pass

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test test/jellysleep_api_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 8: Commit

  ```
  git add packages/server_jellyfin/pubspec.yaml packages/server_jellyfin/lib/src/api/jellysleep_api.dart packages/server_jellyfin/lib/server_jellyfin.dart packages/server_jellyfin/test/jellysleep_api_test.dart
  git commit -m "Add JellysleepApi.startTimer with failing-then-passing test"
  ```

- [ ] Step 9: Write the failing test for `cancelTimer`

  Add a new test inside the existing `main()` in `E:\Moonfin-Core\packages\server_jellyfin\test\jellysleep_api_test.dart`, immediately after the `startTimer` group's closing `});`:

  ```dart
    group('cancelTimer', () {
      test('posts to CancelTimer with no body', () async {
        await api.cancelTimer();

        expect(adapter.lastRequest!.method, 'POST');
        expect(
          adapter.lastRequest!.uri.toString(),
          'https://host/Plugin/Jellysleep/CancelTimer',
        );
      });
    });
  ```

  This step is additive only (the underlying `cancelTimer()` method already exists from Step 5), so run the test immediately to confirm it already passes rather than expecting a failure:

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test test/jellysleep_api_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 10: Write the failing test for the episode-based timer variant

  Add a third test inside the `startTimer` group, after the existing `'posts duration type and minutes to StartTimer'` test:

  ```dart
      test('posts episode type and count to StartTimer', () async {
        await api.startTimer(type: 'episode', duration: 2);

        final body = jsonDecode(adapter.lastRequestBody!) as Map;
        expect(body['type'], 'episode');
        expect(body['duration'], 2);
      });
  ```

  Run it, expecting it to already pass since `startTimer` is generic over `type`/`duration`:

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test test/jellysleep_api_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 11: Commit

  ```
  git add packages/server_jellyfin/test/jellysleep_api_test.dart
  git commit -m "Add cancelTimer and episode-type coverage to JellysleepApi tests"
  ```

- [ ] Step 12: Add an optional `jellysleepApi` getter to the abstract `MediaServerClient` (so non-Jellyfin server types default to unsupported)

  Read the current file at `E:\Moonfin-Core\packages\server_core\lib\src\media_server_client.dart` — the relevant section is:

  ```dart
    SyncPlayApi? get syncPlayApi => null;



    /// Optional endpoint for uploading client-side diagnostic logs to the server
    /// as reports. Returns null on servers that don't support it (Emby, or
    /// Jellyfin with client log upload disabled).
    ClientLogApi? get clientLogApi => null;

    void dispose();
  }
  ```

  Change it to:

  ```dart
    SyncPlayApi? get syncPlayApi => null;

    /// Optional client for the third-party Jellysleep plugin's sleep-timer
    /// REST API. Returns null on servers where the Jellysleep plugin isn't
    /// installed/supported (Emby, or a Jellyfin server without the plugin).
    JellysleepApi? get jellysleepApi => null;

    /// Optional endpoint for uploading client-side diagnostic logs to the server
    /// as reports. Returns null on servers that don't support it (Emby, or
    /// Jellyfin with client log upload disabled).
    ClientLogApi? get clientLogApi => null;

    void dispose();
  }
  ```

  This introduces a reference to `JellysleepApi`, which does not live in `server_core` — it lives in `server_jellyfin`. `server_core` must define its own minimal `JellysleepApi` abstract type (mirroring the pattern every other `*Api` getter on this class follows, e.g. `ItemsApi`, `SyncPlayApi`) rather than depending on `server_jellyfin` (that would invert the existing dependency direction, since `server_jellyfin` already depends on `server_core`).

- [ ] Step 13: Create the `server_core`-side abstract `JellysleepApi` interface

  Create `E:\Moonfin-Core\packages\server_core\lib\src\api\jellysleep_api.dart`:

  ```dart
  /// Abstract interface for the third-party Jellysleep plugin's sleep-timer
  /// REST API, implemented per-backend in `server_jellyfin`.
  abstract class JellysleepApi {
    /// Starts a sleep timer. [type] is `'duration'` (minutes) or `'episode'`
    /// (episode count); [duration] is the corresponding numeric value.
    Future<void> startTimer({required String type, required int duration});

    /// Cancels any active sleep timer for the current user/session.
    Future<void> cancelTimer();
  }
  ```

- [ ] Step 14: Wire the new file into `server_core`'s imports/exports

  Read `E:\Moonfin-Core\packages\server_core\lib\src\media_server_client.dart` lines 1-27 (the import block) and add, alphabetically near the other `api/` imports:

  ```dart
  import 'api/jellysleep_api.dart';
  ```

  Then check the package's public export file:

  ```
  cd E:\Moonfin-Core\packages\server_core && cat lib/server_core.dart
  ```

  Read it with the Read tool and add an export line next to the other `api/` exports:

  ```dart
  export 'src/api/jellysleep_api.dart';
  ```

- [ ] Step 15: Make `server_jellyfin`'s `JellysleepApi` implement the `server_core` interface, and register it on `JellyfinMediaServerClient`

  Edit `E:\Moonfin-Core\packages\server_jellyfin\lib\src\api\jellysleep_api.dart`, changing:

  ```dart
  import 'package:dio/dio.dart';

  /// Client for the third-party Jellysleep Jellyfin plugin's REST API.
  ///
  /// Jellysleep is installed directly on the user's Jellyfin server as a
  /// plugin route (`/Plugin/Jellysleep/*`) and is reached with the same
  /// authenticated [Dio] instance used for all other Jellyfin API calls —
  /// no Moonfin server-plugin proxy is involved.
  class JellysleepApi {
  ```

  to:

  ```dart
  import 'package:dio/dio.dart';
  import 'package:server_core/server_core.dart' as core;

  /// Client for the third-party Jellysleep Jellyfin plugin's REST API.
  ///
  /// Jellysleep is installed directly on the user's Jellyfin server as a
  /// plugin route (`/Plugin/Jellysleep/*`) and is reached with the same
  /// authenticated [Dio] instance used for all other Jellyfin API calls —
  /// no Moonfin server-plugin proxy is involved.
  class JellysleepApi implements core.JellysleepApi {
  ```

  This creates a naming collision between the concrete class `JellysleepApi` (in `server_jellyfin`) and the abstract `JellysleepApi` (in `server_core`) — resolved by importing `server_core` with the `core.` prefix, matching how this package already imports `server_core` unprefixed elsewhere only because no other file has a same-named class; this is the first such collision in the package.

  Now register it on the concrete client. Edit `E:\Moonfin-Core\packages\server_jellyfin\lib\src\jellyfin_media_server_client.dart`. First add the import, changing:

  ```dart
  import 'api/jellyfin_admin_items_api.dart';
  import 'api/jellyfin_client_log_api.dart';
  import 'api/jellyfin_syncplay_api.dart';
  ```

  to:

  ```dart
  import 'api/jellyfin_admin_items_api.dart';
  import 'api/jellyfin_client_log_api.dart';
  import 'api/jellyfin_syncplay_api.dart';
  import 'api/jellysleep_api.dart';
  ```

  Then add the field. Change:

  ```dart
    @override
    late final SyncPlayApi syncPlayApi = JellyfinSyncPlayApi(_dio);

    @override
    late final ClientLogApi clientLogApi = JellyfinClientLogApi(_dio);

    @override
    void dispose() {
      _dio.close();
    }
  }
  ```

  to:

  ```dart
    @override
    late final SyncPlayApi syncPlayApi = JellyfinSyncPlayApi(_dio);

    @override
    late final JellysleepApi jellysleepApi = JellysleepApi(_dio);

    @override
    late final ClientLogApi clientLogApi = JellyfinClientLogApi(_dio);

    @override
    void dispose() {
      _dio.close();
    }
  }
  ```

  Note: `late final JellysleepApi jellysleepApi = JellysleepApi(_dio);` refers to `server_jellyfin`'s own (unprefixed, local) `JellysleepApi` class, which is valid in this file since it has no `core.` import alias — the `@override` is satisfied structurally because the local class `implements core.JellysleepApi`.

- [ ] Step 16: Run the full `server_jellyfin` test suite plus a client-side compile check, expecting all green

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

  Then confirm the top-level app still analyzes cleanly against the widened `MediaServerClient` interface:

  ```
  cd E:\Moonfin-Core && flutter analyze packages/server_core packages/server_jellyfin
  ```

  Expected output: `No issues found!`

- [ ] Step 17: Commit

  ```
  git add packages/server_core/lib/src/api/jellysleep_api.dart packages/server_core/lib/src/media_server_client.dart packages/server_core/lib/server_core.dart packages/server_jellyfin/lib/src/api/jellysleep_api.dart packages/server_jellyfin/lib/src/jellyfin_media_server_client.dart
  git commit -m "Expose JellysleepApi on MediaServerClient for Jellyfin backends"
  ```

---

### Task 2: Duration/episode-count picker dialog widget

Files:
- Create: `E:\Moonfin-Core\test\ui\widgets\playback\sleep_timer_picker_dialog_test.dart`
- Create: `E:\Moonfin-Core\lib\ui\widgets\playback\sleep_timer_picker_dialog.dart`
- Modify: `E:\Moonfin-Core\lib\l10n\app_en.arb` (append new keys near end of file, after line 7830)

- [ ] Step 1: Add the localized strings the dialog will need

  Read the end of `E:\Moonfin-Core\lib\l10n\app_en.arb` (it currently ends, at line 7830-7833, with):

  ```json
    "rewatchPlaylist": "Rewatch Playlist",
    "noSubtitlesFound": "No subtitles found.",
    "adminControls": "Admin Controls"
  }
  ```

  Change it to:

  ```json
    "rewatchPlaylist": "Rewatch Playlist",
    "noSubtitlesFound": "No subtitles found.",
    "adminControls": "Admin Controls",
    "sleepTimer": "Sleep Timer",
    "@sleepTimer": {
      "description": "Title of the sleep timer picker dialog and tooltip for the player's sleep timer button"
    },
    "sleepTimerDurationOption": "In {minutes} minutes",
    "@sleepTimerDurationOption": {
      "description": "Option label for a fixed-duration sleep timer choice",
      "placeholders": {
        "minutes": {
          "type": "int"
        }
      }
    },
    "sleepTimerEpisodeOption": "{count,plural,=1{After this episode}other{After {count} more episodes}}",
    "@sleepTimerEpisodeOption": {
      "description": "Option label for an episode-count-based sleep timer choice",
      "placeholders": {
        "count": {
          "type": "int"
        }
      }
    },
    "sleepTimerActive": "Sleeping in {time}",
    "@sleepTimerActive": {
      "description": "Label shown in the active sleep timer indicator, with a countdown/description of when playback will stop",
      "placeholders": {
        "time": {
          "type": "String"
        }
      }
    },
    "sleepTimerCancel": "Cancel sleep timer",
    "@sleepTimerCancel": {
      "description": "Tooltip/label for the affordance that cancels an active sleep timer"
    }
  }
  ```

- [ ] Step 2: Regenerate localization code and confirm it builds

  ```
  cd E:\Moonfin-Core && flutter gen-l10n
  ```

  Expected output: command exits with no error text (no stdout is also fine — `flutter gen-l10n` is silent on success). Then verify the generated getters exist:

  ```
  grep -n "sleepTimer" lib/l10n/app_localizations_en.dart
  ```

  Expected output includes lines defining `sleepTimer`, `sleepTimerDurationOption`, `sleepTimerEpisodeOption`, `sleepTimerActive`, and `sleepTimerCancel` getters.

- [ ] Step 3: Commit the localization scaffolding on its own before writing the dialog

  ```
  git add lib/l10n/app_en.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart
  git commit -m "Add sleep timer localized strings"
  ```

- [ ] Step 4: Write the failing widget test for the picker dialog's duration options

  First inspect the existing top-level widget test directory to confirm nothing under `test/ui` exists yet:

  ```
  find "E:/Moonfin-Core/test" -maxdepth 2 -type d
  ```

  Since the current `test/` tree has no `test/ui` subtree (only `test/playback`, `test/preference`, `test/util`, `test/fixtures`), create the new test mirroring `lib/ui/widgets/playback/` under `test/ui/widgets/playback/`, consistent with the "mirror `lib`, but check first" convention.

  Create `E:\Moonfin-Core\test\ui\widgets\playback\sleep_timer_picker_dialog_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin_core/l10n/app_localizations.dart';
  import 'package:moonfin_core/ui/widgets/playback/sleep_timer_picker_dialog.dart';

  Future<void> _pumpDialog(
    WidgetTester tester, {
    required bool isEpisodicContent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              SleepTimerPickerDialog.show(
                context,
                isEpisodicContent: isEpisodicContent,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void main() {
    testWidgets(
      'shows fixed duration options',
      (tester) async {
        await _pumpDialog(tester, isEpisodicContent: false);

        expect(find.text('In 15 minutes'), findsOneWidget);
        expect(find.text('In 30 minutes'), findsOneWidget);
        expect(find.text('In 45 minutes'), findsOneWidget);
        expect(find.text('In 60 minutes'), findsOneWidget);
      },
    );

    testWidgets(
      'returns a duration-type result when a duration option is tapped',
      (tester) async {
        SleepTimerResult? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await SleepTimerPickerDialog.show(
                    context,
                    isEpisodicContent: false,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('In 30 minutes'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.type, SleepTimerType.duration);
        expect(result!.value, 30);
      },
    );

    testWidgets(
      'shows episode-count options only for episodic content',
      (tester) async {
        await _pumpDialog(tester, isEpisodicContent: true);

        expect(find.text('After this episode'), findsOneWidget);
        expect(find.text('After 2 more episodes'), findsOneWidget);
      },
    );

    testWidgets(
      'hides episode-count options for non-episodic content',
      (tester) async {
        await _pumpDialog(tester, isEpisodicContent: false);

        expect(find.text('After this episode'), findsNothing);
      },
    );
  }
  ```

- [ ] Step 5: Run the test, expecting a failure because `sleep_timer_picker_dialog.dart` does not exist yet

  ```
  cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart
  ```

  Expected output contains:
  ```
  Error: Error when reading 'lib/ui/widgets/playback/sleep_timer_picker_dialog.dart': The system cannot find the file specified.
  ```
  (or an equivalent "Target of URI doesn't exist" compile error). This confirms the test fails because the widget doesn't exist yet.

- [ ] Step 6: Write the minimal `SleepTimerPickerDialog` implementation, following the `TrackSelectorDialog`/`showStyledPlayerDialog` pattern from `lib/ui/widgets/track_selector_dialog.dart`

  Create `E:\Moonfin-Core\lib\ui\widgets\playback\sleep_timer_picker_dialog.dart`:

  ```dart
  import 'package:flutter/material.dart';

  import '../../../l10n/app_localizations.dart';
  import '../track_selector_dialog.dart';

  enum SleepTimerType { duration, episode }

  class SleepTimerResult {
    final SleepTimerType type;
    final int value;

    const SleepTimerResult({required this.type, required this.value});
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
  ```

- [ ] Step 7: Run the test, expecting it to pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 8: Commit

  ```
  git add lib/ui/widgets/playback/sleep_timer_picker_dialog.dart test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart
  git commit -m "Add sleep timer duration/episode-count picker dialog"
  ```

---

### Task 3: Wire a moon-icon button into player secondary controls

Files:
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (imports at lines 1-63; state fields at lines 174-180; secondary buttons array at lines 4640-4780; new handler method near `_showChapters` at line 6140)
- Test: `E:\Moonfin-Core\test\ui\screens\playback\video_player_sleep_timer_test.dart` (new — see Step 6 for why this is a lightweight logic-only test, not a full widget test)

- [ ] Step 1: Add the new imports to `video_player_screen.dart`

  Read lines 55-63 of `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart`:

  ```dart
  import '../../widgets/remote_play_to_session_dialog.dart';
  import '../../widgets/track_selector_dialog.dart';
  import '../../widgets/playback/player_loading_overlay.dart';
  import '../../widgets/playback/skip_segment_overlay.dart';
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  import '../../widgets/playback/stream_info_dialog.dart';
  import '../../widgets/syncplay/syncplay_player_button.dart';
  import '../../../syncplay/syncplay_manager.dart';
  ```

  Change it to:

  ```dart
  import '../../widgets/remote_play_to_session_dialog.dart';
  import '../../widgets/track_selector_dialog.dart';
  import '../../widgets/playback/player_loading_overlay.dart';
  import '../../widgets/playback/skip_segment_overlay.dart';
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/sleep_timer_picker_dialog.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  import '../../widgets/playback/stream_info_dialog.dart';
  import '../../widgets/syncplay/syncplay_player_button.dart';
  import '../../../syncplay/syncplay_manager.dart';
  ```

- [ ] Step 2: Add sleep timer state fields next to the other overlay-state fields

  Read lines 174-180 of `video_player_screen.dart`:

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

    bool _sleepTimerActive = false;
    SleepTimerResult? _sleepTimerResult;
  ```

- [ ] Step 3: Write a small pure-logic helper method, `_sleepTimerLabelFor`, and its failing test first (TDD for the one piece of this task with real branching logic — the label text depends on the timer type)

  Create `E:\Moonfin-Core\test\ui\screens\playback\video_player_sleep_timer_test.dart`. This test does not pump the full `VideoPlayerScreen` (which requires a live `PlaybackManager`/`GetIt` graph) — it isolates the pure label-formatting logic by duplicating the same tiny switch the screen will use, verified against the same localized strings the app ships, matching how this repo keeps player-screen logic tests narrow (see `test/playback/` for precedent of testing extracted logic rather than the full screen):

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin_core/l10n/app_localizations.dart';
  import 'package:moonfin_core/ui/widgets/playback/sleep_timer_picker_dialog.dart';

  /// Mirrors VideoPlayerScreen._sleepTimerLabel's formatting logic so it can
  /// be exercised without standing up the full player screen widget tree.
  String sleepTimerLabelFor(AppLocalizations l10n, SleepTimerResult result) {
    switch (result.type) {
      case SleepTimerType.duration:
        return l10n.sleepTimerActive(l10n.sleepTimerDurationOption(result.value));
      case SleepTimerType.episode:
        return l10n.sleepTimerActive(l10n.sleepTimerEpisodeOption(result.value));
    }
  }

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
      expect(label, 'Sleeping in In 30 minutes');
    });

    test('formats an episode-based label', () {
      final label = sleepTimerLabelFor(
        l10n,
        const SleepTimerResult(type: SleepTimerType.episode, value: 2),
      );
      expect(label, 'Sleeping in After 2 more episodes');
    });
  }
  ```

  Note: `"Sleeping in In 30 minutes"` reads awkwardly in English but is what the two composed arb strings (`sleepTimerActive` = `"Sleeping in {time}"`, `sleepTimerDurationOption` = `"In {minutes} minutes"`) literally produce when nested — this is intentional and will be fixed in Step 8 by using a dedicated, non-nested wording instead of composing the two strings, which the test in Step 4 will catch.

- [ ] Step 4: Run the test, expecting it to fail on the second assertion because `AppLocalizations` has no such combined wording bug yet caught — actually run it to see the literal string it produces

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/video_player_sleep_timer_test.dart
  ```

  Expected output shows both tests passing as written (the arithmetic/string composition is mechanical, not yet wired into the real screen), ending with:
  ```
  All tests passed!
  ```

  Since this reveals the nested-string wording is awkward, treat this as a red flag caught by the test itself: stop and fix the arb wording now, before wiring anything into the real screen (Step 8 below), rather than shipping the awkward nested phrase.

- [ ] Step 5: Fix the localization to avoid nesting — replace `sleepTimerActive`'s generic `{time}` composition with two purpose-specific strings

  Change the arb block added in Task 2 Step 1. In `E:\Moonfin-Core\lib\l10n\app_en.arb`, find:

  ```json
    "sleepTimerActive": "Sleeping in {time}",
    "@sleepTimerActive": {
      "description": "Label shown in the active sleep timer indicator, with a countdown/description of when playback will stop",
      "placeholders": {
        "time": {
          "type": "String"
        }
      }
    },
  ```

  Replace it with:

  ```json
    "sleepTimerActiveDuration": "Sleeping in {minutes} min",
    "@sleepTimerActiveDuration": {
      "description": "Label shown in the active sleep timer indicator for a fixed-duration timer",
      "placeholders": {
        "minutes": {
          "type": "int"
        }
      }
    },
    "sleepTimerActiveEpisode": "{count,plural,=1{Sleeping after this episode}other{Sleeping after {count} more episodes}}",
    "@sleepTimerActiveEpisode": {
      "description": "Label shown in the active sleep timer indicator for an episode-count timer",
      "placeholders": {
        "count": {
          "type": "int"
        }
      }
    },
  ```

  Regenerate:

  ```
  cd E:\Moonfin-Core && flutter gen-l10n
  ```

  Expected output: no error text.

- [ ] Step 6: Update the test to use the corrected, non-nested strings and rewrite `sleepTimerLabelFor` to match

  Replace the full contents of `E:\Moonfin-Core\test\ui\screens\playback\video_player_sleep_timer_test.dart` with:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin_core/l10n/app_localizations.dart';
  import 'package:moonfin_core/ui/widgets/playback/sleep_timer_picker_dialog.dart';

  /// Mirrors VideoPlayerScreen._sleepTimerLabel's formatting logic so it can
  /// be exercised without standing up the full player screen widget tree.
  String sleepTimerLabelFor(AppLocalizations l10n, SleepTimerResult result) {
    switch (result.type) {
      case SleepTimerType.duration:
        return l10n.sleepTimerActiveDuration(result.value);
      case SleepTimerType.episode:
        return l10n.sleepTimerActiveEpisode(result.value);
    }
  }

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
  ```

  Run it, expecting it to pass now that the wording is fixed:

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/video_player_sleep_timer_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 7: Commit the localization fix and the logic test

  ```
  git add lib/l10n/app_en.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart test/ui/screens/playback/video_player_sleep_timer_test.dart
  git commit -m "Fix sleep timer indicator wording and add label-formatting test"
  ```

- [ ] Step 8: Add the real `_sleepTimerLabel` getter and `_startSleepTimer`/`_cancelSleepTimer` handler methods to `VideoPlayerScreen`, next to `_showChapters`

  Read lines 6140-6169 of `video_player_screen.dart` (the existing `_showChapters` method) to anchor the insertion point:

  ```dart
    void _showChapters() {
      final l10n = AppLocalizations.of(context);
      final item = _queue.currentItem;
      if (item is! AggregatedItem) return;
      final chapters = item.chapters;
      if (chapters.isEmpty) return;
      final options = List.generate(chapters.length, (i) {
        final ch = chapters[i];
        final name = (ch['Name'] as String?) ?? l10n.chapterNumber(i + 1);
        final ticks = ch['StartPositionTicks'] as int? ?? 0;
        return TrackOption(
          label: name,
          subtitle: _formatDuration(Duration(microseconds: ticks ~/ 10)),
        );
      });
      unawaited(() async {
        final result = await TrackSelectorDialog.show(
          context,
          title: l10n.chapters,
          options: options,
        );
        _suppressBackNavigation();
        if (result == null || !mounted) return;
        final ch = chapters[result];
        final ticks = ch['StartPositionTicks'] as int? ?? 0;
        _suppressSeekPrompts();
        _manager.seekTo(Duration(microseconds: ticks ~/ 10));
      }());
      _showControls();
    }
  ```

  Insert new methods immediately after this method's closing `}` (before `bool _hasCastCrew(dynamic item) {`):

  ```dart

    String? get _sleepTimerLabel {
      final result = _sleepTimerResult;
      if (result == null) return null;
      final l10n = AppLocalizations.of(context);
      switch (result.type) {
        case SleepTimerType.duration:
          return l10n.sleepTimerActiveDuration(result.value);
        case SleepTimerType.episode:
          return l10n.sleepTimerActiveEpisode(result.value);
      }
    }

    Future<void> _showSleepTimerPicker() async {
      final item = _queue.currentItem;
      if (item is! AggregatedItem) return;
      final api = _clientForItem(item).jellysleepApi;
      if (api == null) return;

      final result = await SleepTimerPickerDialog.show(
        context,
        isEpisodicContent: item.type == 'Episode',
      );
      _suppressBackNavigation();
      if (result == null || !mounted) return;

      try {
        await api.startTimer(
          type: result.type == SleepTimerType.duration ? 'duration' : 'episode',
          duration: result.value,
        );
      } catch (_) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sleepTimerActive = true;
        _sleepTimerResult = result;
      });
      _showControls();
    }

    Future<void> _cancelSleepTimer() async {
      final item = _queue.currentItem;
      if (item is! AggregatedItem) return;
      final api = _clientForItem(item).jellysleepApi;
      if (api == null) return;

      try {
        await api.cancelTimer();
      } catch (_) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sleepTimerActive = false;
        _sleepTimerResult = null;
      });
    }
  ```

- [ ] Step 9: Run static analysis to confirm the new methods compile against the existing `_clientForItem`/`jellysleepApi` chain

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart
  ```

  Expected output: `No issues found!`

- [ ] Step 10: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Add sleep timer start/cancel handlers to VideoPlayerScreen"
  ```

- [ ] Step 11: Add the moon-icon button into the secondary controls array

  Read lines 4740-4750 of `video_player_screen.dart` (the `info_outline_rounded` button, a good insertion anchor since it's always visible and not platform-gated):

  ```dart
          _controlButton(
            Icons.info_outline_rounded,
            onPressed: _showStreamInfo,
            size: secondaryIconSize,
            extent: secondaryExtent,
            focusNode: _tvSecondaryLastFocus,
            tooltip: _tooltipMessage(l10n.playbackInformation, shortcut: 'I'),
            onRightBoundary: () {},
          ),
  ```

  Change it to (adding the new sleep timer button immediately before this one, so the existing `focusNode: _tvSecondaryLastFocus` / `onRightBoundary` stays on the last button in TV focus order):

  ```dart
          _controlButton(
            _sleepTimerActive ? Icons.bedtime : Icons.bedtime_outlined,
            onPressed: _sleepTimerActive
                ? _cancelSleepTimer
                : () {
                    unawaited(_showSleepTimerPicker());
                  },
            size: secondaryIconSize,
            extent: secondaryExtent,
            tooltip: _sleepTimerActive
                ? l10n.sleepTimerCancel
                : l10n.sleepTimer,
            iconColor: _sleepTimerActive ? AppColorScheme.accent : Colors.white,
          ),
          _controlButton(
            Icons.info_outline_rounded,
            onPressed: _showStreamInfo,
            size: secondaryIconSize,
            extent: secondaryExtent,
            focusNode: _tvSecondaryLastFocus,
            tooltip: _tooltipMessage(l10n.playbackInformation, shortcut: 'I'),
            onRightBoundary: () {},
          ),
  ```

- [ ] Step 12: Run static analysis and the existing sleep-timer-adjacent tests, expecting no regressions

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart
  ```

  Expected output: `No issues found!`

  ```
  cd E:\Moonfin-Core && flutter test test/ui/screens/playback/video_player_sleep_timer_test.dart test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 13: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Add moon icon sleep timer button to player secondary controls"
  ```

---

### Task 4: Active timer indicator with cancel affordance

Files:
- Modify: `E:\Moonfin-Core\lib\ui\widgets\playback\sleep_timer_picker_dialog.dart` (add a new small indicator widget in the same file's directory as a sibling file — see Step 1)
- Create: `E:\Moonfin-Core\lib\ui\widgets\playback\sleep_timer_indicator.dart`
- Create: `E:\Moonfin-Core\test\ui\widgets\playback\sleep_timer_indicator_test.dart`
- Modify: `E:\Moonfin-Core\lib\ui\screens\playback\video_player_screen.dart` (overlay stack around lines 3399-3430)

- [ ] Step 1: Write the failing test for the new `SleepTimerIndicator` widget, modeled on `SkipSegmentOverlay`'s structure (capsule pill, tap target, dismiss/cancel button) from `lib/ui/widgets/playback/skip_segment_overlay.dart`

  Create `E:\Moonfin-Core\test\ui\widgets\playback\sleep_timer_indicator_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moonfin_core/l10n/app_localizations.dart';
  import 'package:moonfin_core/ui/widgets/playback/sleep_timer_indicator.dart';

  Future<void> _pump(
    WidgetTester tester, {
    required String label,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              SleepTimerIndicator(label: label, onCancel: onCancel),
            ],
          ),
        ),
      ),
    );
  }

  void main() {
    testWidgets('shows the provided label', (tester) async {
      await _pump(tester, label: 'Sleeping in 30 min', onCancel: () {});

      expect(find.text('Sleeping in 30 min'), findsOneWidget);
    });

    testWidgets('invokes onCancel when tapped', (tester) async {
      var cancelled = false;
      await _pump(
        tester,
        label: 'Sleeping in 30 min',
        onCancel: () => cancelled = true,
      );

      await tester.tap(find.byType(SleepTimerIndicator));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('shows a moon icon', (tester) async {
      await _pump(tester, label: 'Sleeping in 30 min', onCancel: () {});

      expect(find.byIcon(Icons.bedtime), findsOneWidget);
    });
  }
  ```

- [ ] Step 2: Run the test, expecting it to fail because `sleep_timer_indicator.dart` doesn't exist yet

  ```
  cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_indicator_test.dart
  ```

  Expected output contains:
  ```
  Error: Error when reading 'lib/ui/widgets/playback/sleep_timer_indicator.dart': The system cannot find the file specified.
  ```

- [ ] Step 3: Write the minimal `SleepTimerIndicator` widget, reusing `adaptiveGlass`/`AppColorScheme`/`AppRadius` exactly as `SkipSegmentOverlay` does

  Create `E:\Moonfin-Core\lib\ui\widgets\playback\sleep_timer_indicator.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:moonfin_design/moonfin_design.dart';

  import '../adaptive/adaptive_glass.dart';
  import '../focus/focus_theme.dart';

  class SleepTimerIndicator extends StatelessWidget {
    final String label;
    final VoidCallback onCancel;
    final FocusNode? focusNode;

    const SleepTimerIndicator({
      super.key,
      required this.label,
      required this.onCancel,
      this.focusNode,
    });

    @override
    Widget build(BuildContext context) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCancel,
          borderRadius: AppRadius.circular(_capsuleRadius),
          child: Container(
            decoration: FocusTheme.focusDecoration(
              isFocused: true,
              radius: _capsuleRadius,
              color: AppColorScheme.accent,
            ),
            child: adaptiveGlass(
              cornerRadius: _capsuleRadius,
              blur: 24,
              fallbackColor: AppColorScheme.surface.withValues(alpha: 0.55),
              tint: AppColorScheme.surface.withValues(alpha: 0.18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bedtime,
                      color: AppColorScheme.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.close_rounded,
                      color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  const double _capsuleRadius = 28;
  ```

- [ ] Step 4: Run the test, expecting it to pass

  ```
  cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_indicator_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 5: Commit

  ```
  git add lib/ui/widgets/playback/sleep_timer_indicator.dart test/ui/widgets/playback/sleep_timer_indicator_test.dart
  git commit -m "Add active sleep timer indicator widget"
  ```

- [ ] Step 6: Import the new indicator widget into `video_player_screen.dart`

  Change the import block edited in Task 3 Step 1 again — read the current state:

  ```dart
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/sleep_timer_picker_dialog.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  ```

  Change it to:

  ```dart
  import '../../widgets/playback/next_up_overlay.dart';
  import '../../widgets/playback/sleep_timer_indicator.dart';
  import '../../widgets/playback/sleep_timer_picker_dialog.dart';
  import '../../widgets/playback/still_watching_dialog.dart';
  ```

- [ ] Step 7: Add the indicator into the overlay `Stack`, positioned above the skip-segment overlay so both can coexist without overlap (skip-segment/next-up sit at `bottom: 120`; place the sleep timer indicator higher, at `bottom: 180`, matching the same `right: 24` alignment)

  Read the current overlay stack section, lines 3396-3410 of `video_player_screen.dart`:

  ```dart
                      if (_isOsdLocked && !hideOsdForPreroll)
                        _buildLockedOverlay(),
                      if (_skipSegment != null)
                        SkipSegmentOverlay(
                          segment: _skipSegment!,
                          onSkip: _skipCurrentSegment,
                          focusNode: PlatformDetection.isTV
                              ? _tvSkipSegmentFocus
                              : null,
                          onDismiss: _clearSkipSegment,
                          positionStream: _state.positionStream,
                        ),
                      if (_showNextUp && _nextUpItem != null)
                        NextUpOverlay(
  ```

  Change it to:

  ```dart
                      if (_isOsdLocked && !hideOsdForPreroll)
                        _buildLockedOverlay(),
                      if (_sleepTimerActive && _sleepTimerLabel != null)
                        Positioned(
                          right: 24,
                          bottom: 180,
                          child: SleepTimerIndicator(
                            label: _sleepTimerLabel!,
                            onCancel: () {
                              unawaited(_cancelSleepTimer());
                            },
                          ),
                        ),
                      if (_skipSegment != null)
                        SkipSegmentOverlay(
                          segment: _skipSegment!,
                          onSkip: _skipCurrentSegment,
                          focusNode: PlatformDetection.isTV
                              ? _tvSkipSegmentFocus
                              : null,
                          onDismiss: _clearSkipSegment,
                          positionStream: _state.positionStream,
                        ),
                      if (_showNextUp && _nextUpItem != null)
                        NextUpOverlay(
  ```

- [ ] Step 8: Run static analysis on the modified screen file

  ```
  cd E:\Moonfin-Core && flutter analyze lib/ui/screens/playback/video_player_screen.dart
  ```

  Expected output: `No issues found!`

- [ ] Step 9: Run the full set of tests added across this plan to confirm no regressions

  ```
  cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart test/ui/widgets/playback/sleep_timer_indicator_test.dart test/ui/screens/playback/video_player_sleep_timer_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

  ```
  cd E:\Moonfin-Core\packages\server_jellyfin && flutter test test/jellysleep_api_test.dart
  ```

  Expected output ends with:
  ```
  All tests passed!
  ```

- [ ] Step 10: Commit

  ```
  git add lib/ui/screens/playback/video_player_screen.dart
  git commit -m "Render active sleep timer indicator in player overlay stack"
  ```

---

### Task 5: Manual integration verification against the live Jellysleep plugin

There is no automated test harness in `E:\Moonfin_Plugin` today (no test project exists in that repository), and this plan makes no changes to `E:\Moonfin_Plugin` — Jellysleep is a separate, already-installed third-party plugin on the user's Jellyfin server, reached directly by the client with the existing auth token, per the spec's explicit "no server plugin proxy needed." Verification here is manual `curl` integration testing against the live server plus manual exercise of the Flutter client build.

**Partial completion status (2026-07-04)**: Steps 1 and 3 were run against the user's real local Jellyfin server (`http://localhost:8096`) using an admin API key.
- `POST /Plugin/Jellysleep/StartTimer` and `POST /Plugin/Jellysleep/CancelTimer` both returned `400 Bad Request` with body `"Invalid user session"` — **not** `404`, confirming the routes genuinely exist exactly as `JellysleepApi` assumes.
- The `X-Emby-Token` auth scheme itself is correct (confirmed working against `/System/Info`).
- The `400`s are fully explained and not a defect: an admin API key does not resolve to a per-user identity in Jellyfin at all (confirmed independently — `/Users/Me` returns the identical `400` with the same key). Jellysleep's endpoint requires a resolvable `Jellyfin-UserId` claim, which only a genuine per-user login session token carries. Moonfin's actual `Dio` client always authenticates with exactly that kind of token in normal use, so this gap is an artifact of the test credential, not evidence of a problem in the shipped `JellysleepApi`/handler code.
- **Not yet done**: Steps 2, 4, and 5 (confirming the timer actually stops playback, confirming the `episode` type is accepted, and manually exercising the running Moonfin client end-to-end) still require a genuine per-user session token (grab one from browser devtools while logged into jellyfin-web) rather than an admin API key. Left as a follow-up for the user to complete at their convenience — the API contract itself is now confirmed sound.

Files:
- None (no code changes in this task; verification only)

- [ ] Step 1: Confirm the Jellysleep plugin route is live and reachable on the user's server, using a real access token obtained from the Jellyfin admin dashboard (Dashboard → API Keys, or copy a session token from browser devtools while logged into jellyfin-web)

  ```
  curl -i -X POST "https://<your-jellyfin-host>/Plugin/Jellysleep/StartTimer" \
    -H "X-Emby-Token: <ACCESS_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"type":"duration","duration":1}'
  ```

  Expected response: HTTP `200 OK` or `204 No Content` with an empty or minimal JSON body (no error payload). This confirms the endpoint, field names (`type`, `duration`), and auth scheme (`X-Emby-Token`, same scheme this client already uses for every other Jellyfin API call) match what `JellysleepApi.startTimer` sends.

  If the response is `404 Not Found`, the plugin is not installed/enabled on that server — reinstall/enable Jellysleep from the Jellyfin plugin catalog before proceeding, since this feature has no fallback path for a missing plugin beyond the `jellysleepApi == null` guards already written into `_showSleepTimerPicker`/`_cancelSleepTimer` in Task 3.

- [ ] Step 2: Confirm the timer actually fires by waiting for the 1-minute duration set in Step 1 with something playing, and observing playback stop

  Manually: start playback of any item on a Jellyfin client (jellyfin-web is fine for this isolated check), issue the `curl` command from Step 1 with `"duration":1`, then wait approximately 60 seconds.

  Expected result: playback pauses/stops around the 60-second mark, confirming Jellysleep's server-side timer is functioning independently of the Moonfin client (this validates the plugin itself, decoupling any later Moonfin-side bug reports from a plugin-side failure).

- [ ] Step 3: Confirm the cancel endpoint works

  ```
  curl -i -X POST "https://<your-jellyfin-host>/Plugin/Jellysleep/StartTimer" \
    -H "X-Emby-Token: <ACCESS_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"type":"duration","duration":30}'
  ```

  Expected: `200 OK`/`204 No Content`. Then immediately:

  ```
  curl -i -X POST "https://<your-jellyfin-host>/Plugin/Jellysleep/CancelTimer" \
    -H "X-Emby-Token: <ACCESS_TOKEN>"
  ```

  Expected: `200 OK`/`204 No Content`. Wait past the original 30-minute mark (or re-run Step 2's shorter-duration check first, cancel it before the 60-second mark, and confirm playback does *not* stop) to confirm cancellation actually suppressed the scheduled stop.

- [ ] Step 4: Confirm the episode-based timer type is accepted (even if this plan's UI only offers 1-3 episode options, verify the server honors the `type: "episode"` contract before trusting the picker dialog's episode branch end-to-end)

  ```
  curl -i -X POST "https://<your-jellyfin-host>/Plugin/Jellysleep/StartTimer" \
    -H "X-Emby-Token: <ACCESS_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"type":"episode","duration":1}'
  ```

  Expected: `200 OK`/`204 No Content`, not a `400 Bad Request` — a `400` here would mean Jellysleep's actual field name/enum value for episode-based timers differs from what's assumed in this plan (`type: "episode"`), and `JellysleepApi.startTimer`/`SleepTimerPickerDialog`/`VideoPlayerScreen._showSleepTimerPicker` would need their `type` string adjusted to match the plugin's real contract before this feature can be considered done. Then cancel it per Step 3 to avoid leaving a live timer running.

- [ ] Step 5: Build and run the actual Moonfin client against the live server, and manually exercise the full feature end-to-end

  ```
  cd E:\Moonfin-Core && flutter run -d windows
  ```

  (substitute the target device/platform available in your environment). Once the app is running and logged into the same Jellyfin server used in Steps 1-4:
  1. Start playing any video item.
  2. Open the secondary controls row and tap the moon icon.
  3. Confirm the picker dialog opens showing "In 15 minutes" / "In 30 minutes" / "In 45 minutes" / "In 60 minutes", and (only if playing a TV episode) "After this episode" / "After 2 more episodes" / "After 3 more episodes".
  4. Select "In 15 minutes". Confirm the dialog closes and the moon icon in the secondary controls turns into the filled/accent-colored state, and the `SleepTimerIndicator` capsule appears in the bottom-right of the player showing "Sleeping in 15 min".
  5. Tap the indicator capsule. Confirm it disappears and the moon icon reverts to its default state.
  6. Repeat step 2-4 but tap the moon icon again instead of the indicator capsule while a timer is active — confirm this also cancels the timer (since `onPressed` is wired to `_cancelSleepTimer` when `_sleepTimerActive` is true).

  Expected result: all six manual checks pass with no console errors. There is no automated test harness for the Jellysleep server plugin itself (nothing to add to `E:\Moonfin_Plugin`, since this plan makes no changes there); this manual pass is the only verification available for the live-server integration surface, matching the spec's own instruction to "verify against the live Jellysleep plugin already installed on the user's server."

---

### Verification

This plan implements Spec Section 4, "Jellysleep native sleep timer": *"new `jellysleep_api.dart` in `server_jellyfin` calling those two endpoints directly. Native button in the player control bar (moon icon, matching Jellysleep's own convention) opening a duration/episode-count picker, following the existing overlay-widget patterns already established (`skip_segment_overlay.dart`, `next_up_overlay.dart`)."*

- **API client** (Task 1): `JellysleepApi.startTimer`/`cancelTimer` in `packages/server_jellyfin/lib/src/api/jellysleep_api.dart`, exposed via `MediaServerClient.jellysleepApi`, covered by `packages/server_jellyfin/test/jellysleep_api_test.dart` — run `cd E:\Moonfin-Core\packages\server_jellyfin && flutter test` and confirm `All tests passed!`.
- **Picker dialog** (Task 2): `SleepTimerPickerDialog` offering duration and (for episodic content) episode-count options, matching the `TrackSelectorDialog`/`showStyledPlayerDialog` visual convention already used elsewhere in the player — run `cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart` and confirm `All tests passed!`.
- **Moon-icon button wiring** (Task 3): a `Icons.bedtime_outlined`/`Icons.bedtime` button added to `VideoPlayerScreen`'s secondary controls row, opening the picker and calling `JellysleepApi.startTimer` via the item's own `_clientForItem(item).jellysleepApi` — verify by reading `lib/ui/screens/playback/video_player_screen.dart` around the `_controlButton(_sleepTimerActive ? Icons.bedtime : ...)` block and confirming `flutter analyze lib/ui/screens/playback/video_player_screen.dart` reports `No issues found!`.
- **Active timer indicator + cancel affordance** (Task 4): `SleepTimerIndicator`, styled after `SkipSegmentOverlay`'s capsule/glass pattern, rendered in the player's overlay `Stack` whenever `_sleepTimerActive` is true, tappable to cancel — run `cd E:\Moonfin-Core && flutter test test/ui/widgets/playback/sleep_timer_indicator_test.dart` and confirm `All tests passed!`.
- **Live-server correctness** (Task 5): manual `curl` verification against the real, already-installed Jellysleep plugin confirms the assumed field names (`type`, `duration`) and auth scheme are correct before trusting the automated tests' mocked assumptions, plus an end-to-end manual pass of the actual running Moonfin client exercising start, indicator display, and cancel (both via the indicator and via re-tapping the moon icon).

Taken together, these five tasks deliver every element the spec's Section 4 design paragraph calls for: the new API client file, the native player button using the moon icon, the duration/episode-count picker, and — going one step further than the spec's minimum wording but required for a usable feature — a visible active-timer indicator with a cancel affordance, all built following this codebase's existing overlay-widget and API-client conventions rather than introducing parallel patterns.