# Theme Presets Implementation Plan

> For agentic workers, REQUIRED SUB-SKILL is superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task, and steps use checkbox dash-bracket syntax for tracking.

Goal: Ship two new built-in-quality theme presets — a glassmorphism preset (`isGlass: true`) and a retro pixel-art preset (`isPixel: true`) — as complete, schema-valid JSON files, uploaded through the existing Moonfin admin "Uploaded Themes" panel and confirmed accepted by the existing server-side validator with zero code changes.

Architecture: This is content authoring, not engineering — `packages/design/lib/src/theme/theme_spec.dart` already defines the full token schema (colors, borders, semantic, book, fontFamily, textGlow, navColorCycle, transparentNavbarSurface, isGlass, isPixel) and `E:\Moonfin_Plugin\backend\Services\MoonfinThemeValidator.cs` already enforces it server-side on `POST /Moonfin/Admin/Themes`. Each task below authors one complete theme JSON file matching that schema and uploads it via the admin panel at `AdminThemeChooseBtn` / `AdminThemeUploadBtn` (`E:\Moonfin_Plugin\backend\Pages\configPage.html`), which POSTs the raw JSON to the running Jellyfin server; the plugin validates and persists it, then broadcasts `themesChanged` to sync clients.

Tech Stack: JSON theme payloads (no Dart/C# code changes), existing Jellyfin/Moonfin plugin admin dashboard, `curl` for manual server verification (no automated test harness exists for the C# plugin repo today).

---

### Task 1: Author and upload the "Moonlit Glass" glassmorphism preset

Files:
- Create (local, for upload only — not committed to either repo's source tree): `moonlit_glass.json`
- Reference (read-only, already exists): `E:\Moonfin-Core\packages\design\lib\src\theme\theme_spec.dart` (schema/parser, lines 1–677)
- Reference (read-only, already exists): `E:\Moonfin-Core\packages\design\lib\src\theme\themes\glass_theme_spec.dart` (JSON-shape template, `isGlass`/`transparentNavbarSurface` example)
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Services\MoonfinThemeValidator.cs` (server-side range/shape rules: hex colors `#RRGGBB`/`#AARRGGBB`, `id` matches `^[a-z0-9_-]{2,40}$`, border `width` 0–16, shadow `blurRadius` 0–64, `spreadRadius` −32–32 when allowed, radius 0–9999, `book.placeholderPalette` 1–16 entries, `navColorCycle` ≤16 entries)
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Pages\configPage.html` (admin upload UI, lines 657–682 markup, lines 2153–2206 upload JS)

Steps:

- [ ] Step 1: Write the theme JSON file to a local scratch location (e.g. your Downloads folder) named `moonlit_glass.json`, using the exact content below. This is a frosted-glass preset: `isGlass: true`, `transparentNavbarSurface: true`, a cool indigo/aqua/lilac palette, moderate `blurRadius` values (18 and 32 — well within the validator's 0–64 range), and `spreadRadius` values of 0 and 2 (within the −32–32 range) on the `focusGlow` shadows.

```json
{
  "schemaVersion": 1,
  "id": "moonlit_glass",
  "displayName": "Moonlit Glass",
  "description": "Frosted-glass preset with a cool indigo-and-aqua palette, moderate blur, and a soft focus glow.",
  "isGlass": true,
  "transparentNavbarSurface": true,
  "navColorCycle": [
    "#FF7DD3FC",
    "#FFA78BFA",
    "#FF67E8F9",
    "#FFF0ABFC"
  ],
  "colors": {
    "background": "#CC0B0F1A",
    "onBackground": "#FFF5F7FF",
    "surface": "#D9121826",
    "onSurface": "#FFF5F7FF",
    "surfaceVariant": "#268BA4FF",
    "scrim": "#990A0D16",
    "accent": "#FF7DD3FC",
    "onAccent": "#FF0B0F1A",
    "buttonNormal": "#1FFFFFFF",
    "buttonFocused": "#F27DD3FC",
    "buttonDisabled": "#14FFFFFF",
    "buttonActive": "#3D7DD3FC",
    "onButtonNormal": "#FFF5F7FF",
    "onButtonFocused": "#FF0B0F1A",
    "onButtonDisabled": "#66F5F7FF",
    "inputBackground": "#1FFFFFFF",
    "inputFocused": "#33A78BFA",
    "inputBorder": "#33FFFFFF",
    "inputBorderFocused": "#FF7DD3FC",
    "rangeTrack": "#33FFFFFF",
    "rangeProgress": "#FF7DD3FC",
    "rangeThumb": "#FFF5F7FF",
    "seekbarBuffered": "#80FFFFFF",
    "badgeBackground": "#CC7DD3FC",
    "onBadge": "#FF0B0F1A",
    "badgeUnplayed": "#FFA78BFA",
    "badgeWatched": "#FF34D399",
    "recordingActive": "#FFFB7185",
    "recordingScheduled": "#FFFBBF24"
  },
  "borders": {
    "cardBorder": { "color": "#29FFFFFF", "width": 1 },
    "chipBorder": { "color": "#3DFFFFFF", "width": 1 },
    "focusBorder": { "color": "#FF7DD3FC", "width": 2 },
    "navBorder": { "color": "#1FFFFFFF", "width": 1 },
    "cardRadius": 18,
    "chipRadius": 999,
    "chipBackground": "#1FA78BFA",
    "focusGlow": [
      { "color": "#59FFFFFF", "blurRadius": 18, "spreadRadius": 0, "offsetX": 0, "offsetY": 0 },
      { "color": "#4D7DD3FC", "blurRadius": 32, "spreadRadius": 2, "offsetX": 0, "offsetY": 0 }
    ]
  },
  "semantic": {
    "statusAvailable": "#FF34D399",
    "statusRequested": "#FFA78BFA",
    "statusPending": "#FFFBBF24",
    "statusDownloading": "#FF7DD3FC",
    "mediaTypeBadgeMovie": "#FF67E8F9",
    "mediaTypeBadgeShow": "#FFA78BFA"
  },
  "book": {
    "background": "#FF0B0F1A",
    "accent": "#FF7DD3FC",
    "mutedText": "#FFA9C7E8",
    "primaryText": "#FFF5F7FF",
    "sectionTitle": "#FFF0ABFC",
    "divider": "#223E5F82",
    "placeholder": "#FF3B6EA5",
    "shadow": "#33000000",
    "gradientTop": "#FF16233A",
    "gradientBottom": "#FF080C15",
    "inactiveChip": "#556388A8",
    "placeholderPalette": [
      "#FF2E6B9E",
      "#FF3D8C7D",
      "#FF7C5CBF",
      "#FF1F8A8C",
      "#FFB0577D",
      "#FF5B6EC7",
      "#FF6FA85E",
      "#FF3C4E9E",
      "#FF8A6A52",
      "#FF1E9CA8"
    ]
  },
  "textGlow": [
    { "color": "#665CE1FF", "blurRadius": 10, "offsetX": 0, "offsetY": 0 }
  ]
}
```

- [ ] Step 2: Confirm the file is syntactically valid JSON before uploading. Run this exact command against the saved file (adjust the path to wherever you saved it):

```
python -c "import json; json.load(open(r'C:\Users\<you>\Downloads\moonlit_glass.json', encoding='utf-8')); print('valid json')"
```

Expected output: `valid json`. If it raises a `json.decoder.JSONDecodeError`, fix the reported line/column and re-run before proceeding — do not upload malformed JSON.

- [ ] Step 3: Start (or confirm running) your Jellyfin server with the Moonfin plugin installed, then sign in to Jellyfin web as an administrator and open the Moonfin plugin's configuration page (Dashboard → Plugins → Moonfin).

- [ ] Step 4: Scroll to the **Uploaded Themes** section (`h3.sectionTitle` "Uploaded Themes", above "Apply Defaults To Users"). Click the **Choose JSON File** button (`#AdminThemeChooseBtn`) and select `moonlit_glass.json` from Step 1. Confirm the filename now shows next to the button in `#AdminThemeChosenFile` and the **Upload Theme** button (`#AdminThemeUploadBtn`) is no longer disabled.

- [ ] Step 5: Click **Upload Theme**. This calls `uploadSelectedThemeFile()` in `configPage.html`, which `POST`s the JSON body to `{serverUrl}/Moonfin/Admin/Themes`. Confirm the result banner (`#AdminThemeUploadResult`) shows green text reading exactly: `Uploaded "Moonlit Glass" successfully.` If it instead shows red text with one or more `field.path: message` entries joined by ` | `, note them — they map directly to `MoonfinThemeValidator.cs` field paths — fix the JSON and re-upload from Step 4.

- [ ] Step 6: Confirm the new preset now appears in the **Uploaded Theme Catalog** list (`#AdminThemesList`) below the upload controls, showing display name "Moonlit Glass" with a delete (✕) button next to it.

### Task 2: Author and upload the "Arcade Cartridge" retro pixel-art preset

Files:
- Create (local, for upload only — not committed to either repo's source tree): `arcade_cartridge.json`
- Reference (read-only, already exists): `E:\Moonfin-Core\packages\design\lib\src\theme\theme_spec.dart` (same schema/parser as Task 1)
- Reference (read-only, already exists): `E:\Moonfin-Core\packages\design\lib\src\theme\themes\eightbit_hero_theme_spec.dart` (JSON-shape template for `isPixel`: zero-radius corners, opaque thick borders, hard offset drop-shadow with `blurRadius: 0`)
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Services\MoonfinThemeValidator.cs` (same validator as Task 1)
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Pages\configPage.html` (same admin upload UI as Task 1)

Steps:

- [ ] Step 1: Write the theme JSON file to a local scratch location named `arcade_cartridge.json`, using the exact content below. This is a retro pixel-art preset: `isPixel: true`, zero corner radii (`cardRadius`/`chipRadius` both `0`, matching `eightbitHeroThemeSpec`'s `BorderRadius.zero`), a blocky magenta/lime/cyan/gold palette, opaque 2–3px borders (within the validator's 0–16 width range), and a single hard `focusGlow` shadow with `blurRadius: 0` and a 4px/4px offset instead of a soft blur (mirroring `eightbit_hero_theme_spec.dart`'s `BoxShadow(color: Color(0x99FFCD75), offset: Offset(4, 4))`).

```json
{
  "schemaVersion": 1,
  "id": "arcade_cartridge",
  "displayName": "Arcade Cartridge",
  "description": "Retro pixel-art preset with a blocky magenta-and-lime palette, zero-radius corners, and a hard offset drop-shadow.",
  "isPixel": true,
  "navColorCycle": [
    "#FFFF6188",
    "#FFA9F14C",
    "#FF3ADCFF",
    "#FFFFD23F"
  ],
  "colors": {
    "background": "#FF14102B",
    "onBackground": "#FFF4F4F4",
    "surface": "#FF241C4E",
    "onSurface": "#FFF4F4F4",
    "surfaceVariant": "#FF3B2E73",
    "scrim": "#CC14102B",
    "accent": "#FFFF6188",
    "onAccent": "#FF14102B",
    "buttonNormal": "#FF2E2260",
    "buttonFocused": "#FFFFD23F",
    "buttonDisabled": "#FF241C4E",
    "buttonActive": "#FF3ADCFF",
    "onButtonNormal": "#FFF4F4F4",
    "onButtonFocused": "#FF14102B",
    "onButtonDisabled": "#FF6C5FA0",
    "inputBackground": "#FF241C4E",
    "inputFocused": "#FF3B2E73",
    "inputBorder": "#FF6C5FA0",
    "inputBorderFocused": "#FFFFD23F",
    "rangeTrack": "#FF241C4E",
    "rangeProgress": "#FFA9F14C",
    "rangeThumb": "#FFFFD23F",
    "seekbarBuffered": "#FF6C5FA0",
    "badgeBackground": "#FFFF6188",
    "onBadge": "#FFF4F4F4",
    "badgeUnplayed": "#FF3ADCFF",
    "badgeWatched": "#FFA9F14C",
    "recordingActive": "#FFFF6188",
    "recordingScheduled": "#FFFFD23F"
  },
  "borders": {
    "cardBorder": { "color": "#FF6C5FA0", "width": 2 },
    "chipBorder": { "color": "#FFF4F4F4", "width": 2 },
    "focusBorder": { "color": "#FFFFD23F", "width": 3 },
    "navBorder": { "color": "#FF6C5FA0", "width": 2 },
    "cardRadius": 0,
    "chipRadius": 0,
    "chipBackground": "#FF2E2260",
    "focusGlow": [
      { "color": "#99FF6188", "blurRadius": 0, "spreadRadius": 0, "offsetX": 4, "offsetY": 4 }
    ]
  },
  "semantic": {
    "statusAvailable": "#FFA9F14C",
    "statusRequested": "#FF9C5FD6",
    "statusPending": "#FFFFD23F",
    "statusDownloading": "#FF3ADCFF",
    "mediaTypeBadgeMovie": "#FF3ADCFF",
    "mediaTypeBadgeShow": "#FFFF6188"
  },
  "book": {
    "background": "#FF14102B",
    "accent": "#FFFF6188",
    "mutedText": "#FFB6ABE8",
    "primaryText": "#FFF4F4F4",
    "sectionTitle": "#FFFFD23F",
    "divider": "#556C5FA0",
    "placeholder": "#FF3B2E73",
    "shadow": "#4D000000",
    "gradientTop": "#FF241C4E",
    "gradientBottom": "#FF14102B",
    "inactiveChip": "#556C5FA0",
    "placeholderPalette": [
      "#FFB13E53",
      "#FF3B5DC9",
      "#FF5D275D",
      "#FF38B764",
      "#FFEF7D57",
      "#FF41A6F6",
      "#FFA9F14C",
      "#FF9C5FD6",
      "#FF29366F",
      "#FFFFD23F"
    ]
  }
}
```

Note: this preset intentionally omits `fontFamily` (unlike `eightbit_hero_theme_spec.dart`, which sets `fontFamily: 'EightBitHero'` to a font bundled specifically for that built-in theme). Custom uploaded themes are not guaranteed a matching bundled pixel font on every client, so leaving `fontFamily` unset is correct here — per `theme_spec.dart` line 375, `null` falls back to the platform default, which keeps the theme legible everywhere it syncs (Mobile-Desktop, tvOS, Smart-TV).

- [ ] Step 2: Confirm the file is syntactically valid JSON before uploading. Run this exact command against the saved file (adjust the path to wherever you saved it):

```
python -c "import json; json.load(open(r'C:\Users\<you>\Downloads\arcade_cartridge.json', encoding='utf-8')); print('valid json')"
```

Expected output: `valid json`. If it raises a `json.decoder.JSONDecodeError`, fix the reported line/column and re-run before proceeding.

- [ ] Step 3: In the same Moonfin admin **Uploaded Themes** section used in Task 1, click **Choose JSON File** (`#AdminThemeChooseBtn`) again and select `arcade_cartridge.json`. Confirm `#AdminThemeChosenFile` updates to the new filename and `#AdminThemeUploadBtn` is enabled.

- [ ] Step 4: Click **Upload Theme**. Confirm `#AdminThemeUploadResult` shows green text reading exactly: `Uploaded "Arcade Cartridge" successfully.` If red text with `field.path: message` entries appears instead, fix the JSON per the reported paths and re-upload from Step 3.

- [ ] Step 5: Confirm both `Moonlit Glass` and `Arcade Cartridge` now appear in the **Uploaded Theme Catalog** (`#AdminThemesList`), each with its own delete (✕) button.

### Task 3: Verify server-side validator acceptance via direct API calls

Files:
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Api\MoonfinThemesController.cs` (`POST /Moonfin/Admin/Themes`, `GET /Moonfin/Admin/Themes`, `GET /Moonfin/Themes`, `GET /Moonfin/Themes/{themeId}`)
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\Services\MoonfinThemeValidator.cs`
- Reference (read-only, already exists): `E:\Moonfin_Plugin\backend\PluginConfiguration.cs` (lines 176–185, `UploadedThemeEntry` shape: `Id`, `DisplayName`, `FileName`, `SizeBytes`, `UploadedAtUtc`, `UploadedByUserId`, `ChecksumSha256`)

There is no automated test harness for the C# plugin repo (`E:\Moonfin_Plugin`) today — no test project exists anywhere in that repo. Verification here is manual integration testing against the running server using `curl`, not an automated suite.

Steps:

- [ ] Step 1: Get an admin API key or access token for your running Jellyfin server (Dashboard → API Keys, or reuse the browser session's `X-Emby-Token` header value from Task 1/2's network requests). Export it for reuse:

```
export MOONFIN_TOKEN="<your-admin-api-key-or-token>"
export MOONFIN_SERVER="http://localhost:8096"
```

- [ ] Step 2: Confirm the sync-facing endpoint now serves `moonlit_glass` to authenticated clients (this is the same payload shape Mobile-Desktop/tvOS/Smart-TV clients fetch). Run:

```
curl -s -o /dev/null -w "%{http_code}\n" -H "X-Emby-Token: $MOONFIN_TOKEN" "$MOONFIN_SERVER/Moonfin/Themes/moonlit_glass"
```

Expected output: `200`. A `404` means the upload in Task 1 did not persist — re-check Task 1 Step 5's result banner for validation errors before continuing.

- [ ] Step 3: Fetch the full theme body and confirm the `isGlass` flag round-tripped correctly through the validator and store:

```
curl -s -H "X-Emby-Token: $MOONFIN_TOKEN" "$MOONFIN_SERVER/Moonfin/Themes/moonlit_glass" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('id'), d.get('displayName'), d.get('isGlass'))"
```

Expected output: `moonlit_glass Moonlit Glass True`.

- [ ] Step 4: Repeat for the pixel preset:

```
curl -s -H "X-Emby-Token: $MOONFIN_TOKEN" "$MOONFIN_SERVER/Moonfin/Themes/arcade_cartridge" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('id'), d.get('displayName'), d.get('isPixel'))"
```

Expected output: `arcade_cartridge Arcade Cartridge True`.

- [ ] Step 5: Confirm the admin index endpoint lists both entries with the `UploadedThemeEntry` metadata fields defined in `PluginConfiguration.cs` lines 176–185:

```
curl -s -H "X-Emby-Token: $MOONFIN_TOKEN" "$MOONFIN_SERVER/Moonfin/Admin/Themes" | python -c "import json,sys; items=json.load(sys.stdin)['items']; print([ (i['id'], i['displayName'], i['sizeBytes']>0, bool(i['checksumSha256'])) for i in items if i['id'] in ('moonlit_glass','arcade_cartridge') ])"
```

Expected output: a list containing two tuples, each shaped `('moonlit_glass', 'Moonlit Glass', True, True)` and `('arcade_cartridge', 'Arcade Cartridge', True, True)` (order may vary — the index sorts by `DisplayName` then `Id` per `MoonfinThemeStore.cs` `GetThemeIndex()`).

- [ ] Step 6: Negative-path check — confirm the validator actually rejects invalid input rather than silently accepting anything, by POSTing a deliberately broken payload (missing required `colors` object):

```
curl -s -X POST -H "X-Emby-Token: $MOONFIN_TOKEN" -H "Content-Type: application/json" -d '{"id":"broken_test","displayName":"Broken Test"}' "$MOONFIN_SERVER/Moonfin/Admin/Themes" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('error'), 'colors is required.' in d.get('errors', []))"
```

Expected output: `Theme validation failed. True`. This confirms `MoonfinThemeValidator.cs`'s required-field checks (line 85, `GetRequiredObject(payload, "colors", ...)`) are actually enforced on this server, not bypassed — giving confidence that the earlier `200`/success responses for the two real presets reflect genuine validation passes, not a validator that rubber-stamps everything.

### Verification

This plan implements spec section 6, "Theme presets": *"draft a handful of new presets via the existing web theme editor (e.g. a GlassFin-style glass preset, a retro pixel preset) and upload them through the existing admin panel."* Verification is complete when all of the following hold:

- [ ] `moolit_glass.json`'s content (Task 1, Step 1) and `arcade_cartridge.json`'s content (Task 2, Step 1) each pass local JSON-syntax validation (Task 1 Step 2, Task 2 Step 2).
- [ ] Both files were uploaded through the existing admin "Uploaded Themes" panel at `E:\Moonfin_Plugin\backend\Pages\configPage.html` (no new UI code written) and both produced a green "Uploaded ... successfully." result banner with no validator errors (Task 1 Step 5, Task 2 Step 4).
- [ ] Both presets appear in the Uploaded Theme Catalog list in the admin panel (Task 1 Step 6, Task 2 Step 5).
- [ ] `GET /Moonfin/Themes/moonlit_glass` and `GET /Moonfin/Themes/arcade_cartridge` both return `200` with `isGlass: true` and `isPixel: true` respectively, confirming the existing sync payload (consumed by Mobile-Desktop, tvOS, and Smart-TV clients per the admin panel's own description text) serves both new presets correctly (Task 3 Steps 2–4).
- [ ] `GET /Moonfin/Admin/Themes` lists both entries with populated `sizeBytes` and `checksumSha256`, confirming `MoonfinThemeStore` persisted them correctly (Task 3 Step 5).
- [ ] A deliberately invalid payload is still rejected with `400` and a populated `errors` array, confirming `MoonfinThemeValidator.cs` is genuinely enforcing the schema on this server rather than passing everything through (Task 3 Step 6).
- [ ] No files under `packages/design/lib/src/theme/` or `E:\Moonfin_Plugin\backend\Services\MoonfinThemeValidator.cs` were modified — this task is pure content authoring against the already-shipped token system and admin upload/validation pipeline, exactly as spec section 6 states ("No new engineering").