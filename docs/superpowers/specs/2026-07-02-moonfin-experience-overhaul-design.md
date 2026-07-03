# Moonfin Experience Overhaul — Design Spec

## Context

Moonfin-Core (Flutter client, forked from `Moonfin-Client/Moonfin-Core`) and its companion server plugin Moonfin/"Moonbase" (forked as `E:\Moonfin_Plugin`, from `Moonfin-Client/Plugin`) already implement a surprisingly mature settings-sync, theming, and home-layout system. This work started from a much broader ask ("give the Android TV app full Jellyfin-web-style CSS/JS plugin support") that turned out to rest on a mistaken premise: Moonfin-Core is a **native Flutter app**, not a WebView around jellyfin-web, so literal CSS/JS from web-only plugins (KefinTweaks, Jellysleep, JS Injector) cannot run in it — confirmed even by Jellysleep's own README ("❌ Android TV App — uses native interface, cannot be modified"). A prior contributor tried a JS-scraping integration for KefinTweaks in April; it was reverted in June for being "unstable and caused more issues than it solved." Repeating that approach was explicitly rejected in favor of **native reimplementation using real REST APIs only** — no embedded JS/CSS runtime.

What followed was a deep audit of the actual codebase (not assumptions from screenshots) plus a comparative UX audit against Plex, Findroid, Streamyfin, and the official Jellyfin Android TV client. The upshot: most of the "push settings/theme/layout from server" infrastructure the user wanted **already exists and works well** (a full drag-and-drop home-layout builder, theme upload/sync, `PushDefaults` that correctly overwrites existing users' settings). The real remaining work is a specific list of confirmed bugs, three genuinely new features, and a prioritized UX-polish backlog — this document scopes all of it as one release.

This is for a personal fork running on the user's own Jellyfin server (not an upstream contribution), so pragmatism beats strict upstream-style conventions, but code should still be clean and maintainable since the user will live with it.

## Architecture principle

Every item below is native Flutter UI backed by a real, documented REST API (the app's own base Jellyfin API, a third-party plugin's genuine API, or a new small proxy endpoint on the Moonfin server plugin). Nothing executes third-party JavaScript or parses third-party CSS. Where a feature plugs into existing extension points (`HomeSectionPluginSource` / `MoonfinHomeSectionConfig` / `RowDataSource.loadDynamicSection` / `MoonfinSettingsProfile` + `PushDefaults` / `ThemeSpec`), it must reuse them rather than build parallel plumbing.

---

## 1. Bug fixes

### 1.1 Seerr not enabled by default for users
**Problem**: Admins can fully configure Seerr server-side (URL, SSO proxy), but there's no admin-settable "default enabled" for new/existing users — `MoonfinController.GetSeerrConfig` falls back to a hardcoded `true` with no admin override lever, and nothing in `DefaultUserSettings`/`PushDefaults` can push a `SeerrEnabled` default.

**Fix** (server plugin, `E:\Moonfin_Plugin`):
- Add `SeerrEnabled` (nullable bool) to the `DefaultUserSettings`-backing model.
- Add a `DefaultSeerrEnabled` select control in `backend\Pages\configPage.html`, next to the existing `DefaultSeerrBlockNsfw` field (~line 648), wired into the save handler (~line 2579) and the `setNullableBoolSelect` population (~line 2366).
- Update `MoonfinController.GetSeerrConfig`'s fallback chain (~line 1464) to check the new admin default before falling back to `true`.
- Confirm it flows through the existing `PushDefaults`/merge path (`MoonfinSettingsService.MergeProfile`, already proven to overwrite non-null admin fields onto existing users' global profile) — should work automatically once the field exists on the shared model.

### 1.2 Duplicate home screen sections
**Problem**: `home_view_model.dart:317-340`'s dedup filter only computes collision keys for *builtin* row configs (`_duplicateKeysForBuiltin`); plugin-dynamic configs always produce an empty key set, so two dynamic `HomeSectionConfig` entries with identical `pluginSource`/`pluginSection`/`serverId`/`additionalData` (e.g. left over from a repeated sync round-trip) both render with the same `stableId`.

**Fix** (client, `E:\Moonfin-Core`): extend the dedup key computation to also key plugin-dynamic configs on `(pluginSource, pluginSection, serverId, additionalData)`, so a second identical entry is dropped the same way builtin collisions already are. Touches `lib\ui\screens\home\home_view_model.dart` (the `_duplicateKeysForConfig` family, ~lines 721-846).

### 1.3 Sorting broken in folder browsing
**Problem**: reported as "sorting broken everywhere," but library-root sorting is already correct and re-queries properly (`library_browse_view_model.dart`). The real gap: `folder_browse_view_model.dart` hardcodes `sortBy: 'IsFolder,SortName'`/`'SortName'` with no `setSortBy` at all — nested folder navigation silently ignores the user's sort preference, which reads as "sort doesn't work" depending on where you're browsing.

**Fix** (client): add real sort-option plumbing to `folder_browse_view_model.dart` mirroring the pattern already proven in `library_browse_view_model.dart` (persist preference, re-query via `itemsApi.getItems` with the chosen `sortBy`/`sortOrder`). Verify against music/book browse view-models too in case they share the same gap.

### 1.4 Android TV UI oversized / low information density
**Problem**: a global TV-downscale widget (`_TvUiScale`, `lib\app.dart:1069-1111`) exists and is proven to work — but it's gated to `PlatformDetection.isAppleTV` only (`app.dart:229`), so Android TV never gets it. A separate ad-hoc 0.8x `platformScale` multiplier is applied inconsistently: home and detail screens use it, but `library_browse_screen.dart`, `library_genres_screen.dart`, `favorites_screen.dart`, `library_view_screen.dart`, `search_screen.dart`, and `all_genres_screen.dart` compute poster/card sizes with no TV scale factor at all — full desktop-sized cards on a 10-foot display.

**Fix** (client, decided approach): flip the gate at `lib\app.dart:229` from `isAppleTV` to `isTV` so Android TV gets the same global downscale. Follow-up pass required after: audit every screen currently applying the separate 0.8x `platformScale` band-aid (home, detail) to make sure the two scale factors don't stack into overly-cramped cards once the global downscale also applies — reconcile to one consistent scale source.

### Status: all four §1 items implemented and reviewed (2026-07-02)

See `docs/superpowers/plans/2026-07-02-bug-fixes-and-tv-scaling.md` for the full task-by-task record. Summary: §1.1 and §1.2 shipped clean; §1.3 required a follow-up commit after code review found the original fix only added persistence plumbing with no UI ever able to trigger it (closed in `aab77d47`); §1.4 shipped clean with an audit confirming no further code change needed. Final whole-plan review: 138/138 tests passing (`E:\Moonfin-Core`), 0 warnings/errors (`E:\Moonfin_Plugin`).

**New follow-up discovered during §1.3's sibling-file audit, not yet scheduled**: the same "hardcoded sort literal, no way for a user to change it" bug exists in `lib\data\viewmodels\book_browse_view_model.dart:101`, `item_detail_view_model.dart:769`, `library_view_view_model.dart:132,136`, and `live_tv_guide_view_model.dart:301`. These were confirmed out of scope for §1.3 (only `folder_browse_view_model.dart` was named in this spec), but the same class of bug likely applies to at least the browsable ones (`book_browse_view_model.dart`, `live_tv_guide_view_model.dart` — the other two are fixed-purpose row builders/internal lookups, not user-facing sortable screens). Worth its own small plan later so it isn't rediscovered as a "new" bug report.

---

## 2. Home Screen Sections (HSS) real API integration

Unifies three separate asks: "mirror the order set in [the Home Screen Sections plugin]," "none of the HSS sections currently display anything," and (per the UX audit) closing Moonfin's biggest content-variety gap versus Plex/Findroid (Because You Watched, Watch Again, Discover-style rows).

**Confirmed feasible**: HSS's `GET /HomeScreen/Section/{sectionType}?userId=&additionalData=` returns a standard Jellyfin `QueryResult<BaseItemDto>` — the same shape Moonfin already parses everywhere via `AggregatedItem`/`_parseItems`. It's a plugin route on the same Jellyfin server, callable directly with the existing auth token — **no Moonbase proxy needed**. `GET /HomeScreen/Sections?userId=` discovers available sections with `displayText`/`route`/`additionalData`.

**Design**:
- Add a new `HomeSectionPluginSource` value (e.g. `homeScreenSections`) in `home_section_config.dart`.
- New API client method(s) in `packages/server_jellyfin` calling the two HSS endpoints above.
- New case in `RowDataSource.loadDynamicSection` (`row_data_source.dart`) dispatching to it, parsing the response with the existing `_parseItems` path (no new parsing logic needed).
- Surface discovered HSS sections in the admin "Default Home Layout" builder (`configPage.html` already has a `dynamic` badge style ready for exactly this) and in the client's own home-section picker, so admin-configured order genuinely mirrors what's on the actual Jellyfin server.
- **Scope exclusion**: HSS's "Discover" section type proxies Jellyseerr itself and can return non-library items outside the standard `BaseItemDto` shape. Exclude it from this integration — Moonfin already has its own native Seerr discover screens covering that use case. Only wire the library-backed section types (Because You Watched, Watch Again, Genre, Latest Movies/Shows, etc.).
- **Error handling**: if HSS isn't installed on a given server, `GET /HomeScreen/Sections` 404s — treat as "no dynamic HSS sections available" and degrade gracefully (same pattern the old KefinTweaks prober used, just against a real documented API this time).

---

## 3. Collections: normal TMDB box sets + purpose-built ACdb row

Two distinct things, per the correction: (a) a normal collections experience for standard TMDB-tagged box sets, and (b) a separate, purpose-built row specifically for the user's curated ACdb.tv collections.

### 3.1 Real collections screen
Replace the `collection_screen.dart` stub (currently ~25 lines, placeholder text only) with a real screen fetching contents via `itemsApi.getItems(parentId: collectionId)` — already proven to work (`add_to_collection_dialog.dart` uses this exact call). Reuse the grid/card, breadcrumb, and infinite-scroll patterns already built in `folder_browse_screen.dart` rather than reinventing them.

### 3.2 Purpose-built ACdb row
**Confirmed from reading the actual ACdb plugin source** (`jonjonsson/Jellyfin.Plugin.ACdb`): it creates ordinary Jellyfin BoxSets via the standard `ICollectionManager` — no `ProviderIds` entry, no custom `CollectionType`, no naming convention, nothing visible via the generic `/Items` payload that distinguishes an ACdb-managed collection from a user-made or TMDB-tagged one. The only ACdb↔BoxSet linkage lives inside the plugin's own private config JSON. It does have an optional tagging feature (assigns an admin-chosen string tag to member items during sync) and its own `Plugins/ACdb` controller — but that controller is admin-telemetry only (sync status, login state), not a client-facing collections API.

**Design**: do **not** build a bespoke ACdb API client (there's nothing useful for a client to call). Instead:
1. User enables ACdb.tv's optional tag feature and assigns a consistent tag (e.g. `acdb`) to ACdb-managed items during setup (one-time, on acdb.tv's own admin UI).
2. Moonfin adds a new purpose-built home row that queries the existing Jellyfin Items API with `?Tags=acdb&IncludeItemTypes=BoxSet` — reusing whatever existing repository wraps `/Items` (e.g. the same layer `loadCollections` in `row_data_source.dart` already uses, just tag-filtered) rather than a new integration surface.
3. This row is visually/structurally distinct from the generic "Collections" row (own title, own section in the layout builder) even though both ultimately query BoxSets.

### 3.3 Missing-items + Seerr request
For a given collection (ACdb row or general collections screen), show items already in the library alongside items missing from it, with a "Request via Seerr" action on the missing ones.

**Confirmed feasible, one new piece needed**:
- Provider-ID parsing already exists (`AggregatedItem.tmdbId` reads `ProviderIds.Tmdb` generically) — works on BoxSets and their members already, just needs `ProviderIds` included in the `fields` query param (already a free-text passthrough, no server_core change).
- **Missing**: a canonical "what should be in this collection" source. `tmdb_repository.dart` only proxies two narrow endpoints (`/Moonfin/Tmdb/EpisodeRating`, `/Moonfin/Tmdb/SeasonRatings`) through the Moonbase plugin — no `/collection/{id}` support. Add one new Moonbase proxy route, `GET /Moonfin/Tmdb/Collection/{tmdbCollectionId}`, following the existing `/Moonfin/Tmdb/*` pattern (keeps the TMDB key server-side), plus a matching `TmdbRepository.getCollection(collectionTmdbId)` client method.
- Seerr's request-media call already exists end-to-end (`SeerrRepository.createRequest(mediaId, mediaType: 'movie')`, already used elsewhere) — reuse directly, no new plumbing.
- Flow: read a BoxSet/member's `tmdbId` → fetch canonical parts via the new proxy → diff against library items by `tmdbId` → render missing items with a "Request" button wired to the existing Seerr repository call.
- **Open verification item**: confirm at implementation time that the user's actual ACdb-created BoxSets carry a usable TMDB collection ID via `ProviderIds` (the plugin *can* set this depending on how it matched items, per the research, but wasn't confirmed against a live example). If not, fall back to a TMDB search-by-name-and-year lookup instead of a direct collection-ID fetch.

---

## 4. Jellysleep native sleep timer

Jellysleep's own docs confirm it cannot run in Moonfin via its normal mechanism (JS injected into jellyfin-web) — but it does expose a genuine REST API (`Plugin/Jellysleep` route: `POST StartTimer`, `POST CancelTimer`), same-server, same auth token as everything else.

**Design**: new `jellysleep_api.dart` in `server_jellyfin` calling those two endpoints directly. Native button in the player control bar (moon icon, matching Jellysleep's own convention) opening a duration/episode-count picker, following the existing overlay-widget patterns already established (`skip_segment_overlay.dart`, `next_up_overlay.dart`) for how playback-adjacent UI is built in this codebase.

---

## 5. Cinema Mode — immersive presentation

Cinema Mode already exists (`pref_enable_cinema_mode`) but only covers playing trailers/prerolls before a movie starts from the beginning (`item_detail_screen.dart:6804-6818`). Decided enhancement: **immersive presentation only** (no curtain/countdown animation).

**Design**: when Cinema Mode is active and a preroll/feature is playing, suppress all UI chrome and overlays that would normally be reachable/visible during playback (navbar, clock, any accidental-focus-triggered overlay) for a clean "lights down" presentation, with a clean full-black transition between the preroll sequence and the main feature (no jarring cut/flash). This is additive to the existing preroll logic — same preference, expanded behavior while it's active.

---

## 6. Theme presets

No new engineering — the existing `ThemeSpec` token system already supports full color palettes, border radius/shadows, text glow, `isGlass` (real frosted-glass rendering), and `isPixel` (retro chrome), and the admin "Uploaded Themes" panel already handles upload/validation/sync to all clients. This item is pure content authoring: draft a handful of new presets via the existing web theme editor (e.g. a GlassFin-style glass preset, a retro pixel preset) and upload them through the existing admin panel. Can happen independently of any other item here, any time.

---

## 7. Genres — browsable list with live preview

Replace `all_genres_screen.dart`'s current image-collage grid (`GenreGridCard`, one enriched representative-item image fetched per genre) with a two-pane layout: a scrollable, text-first list of genre names on one side (no per-genre image enrichment needed — removes `_loadGenreItems`, should also load faster), and selecting a genre immediately loads its items into the main panel using the existing `itemsApi.getGenres`/items-by-genre calls already in `row_data_source.dart`. On Android TV this is a D-pad-navigable list on the left with focus-driven preview on the right, closer to Jellyfin web's genre browsing feel. Apply the same pattern to `library_genres_screen.dart` (the per-library variant).

---

## 8. In-player episode & season switcher

Let a user jump to any episode or season while still in the player, not just advance sequentially to the next one.

**Confirmed from reading the actual queue/playback architecture**: `QueueService` already supports arbitrary jumps within the loaded queue (`jumpTo`, `PlaybackManager.playFromQueue`) — but the queue is built once, from one season's episode siblings only (`item_detail_screen.dart:7515`), and there's no "load more"/splice API to extend it with another season. The player itself (`video_player_screen.dart`) has no knowledge of series/season structure today — that data only lives in `ItemDetailViewModel` (`_loadSeasons`/`_loadEpisodes`/`loadAllSeriesEpisodes`), which isn't passed into or retained by the player.

**Design**:
- New overlay widget, `episode_switcher_overlay.dart`, modeled on the existing `next_up_overlay.dart` pattern: season tabs + episode grid.
- Player fetches season/episode data on demand via `_clientForItem(currentItem)` + `item.seriesId`, replicating the same `getSeasons`/`getEpisodes` calls `ItemDetailViewModel` already makes. Worth considering extracting that fetch logic into a small shared service both the ViewModel and the player call, rather than duplicating it — cleaner, modest extra scope.
- Selecting an episode in a different season needs a queue-mutation path. Simplest option: rebuild the queue via `playItems(newEpisodeList, startIndex: tappedIndex)` (loses continuity back to the previous season if the user backs out). Better option: add a `replaceFrom`/splice method to `QueueService` that swaps the remainder of the queue while preserving playback history — worth doing given how central the queue already is to this codebase's playback model.

**Scope**: medium.

---

## 9. Deeper Seerr integration

Two distinct pieces, since research showed one is nearly free and the other is a genuine reach.

### 9.1 Request a missing season directly from the library series you already own (small — do this)

**Key finding**: the wire protocol, request models, and repository method already fully support per-season requests end-to-end — `SeerrHttpClient.createRequest` already accepts a `seasons` list or `allSeasons`, `SeerrCreateRequest` already has `specificSeasons(...)`/`allSeasons(...)` factories, and a complete season-picker UI (`_SeasonSelector`, checkboxes, already-requested seasons grayed out) already exists in `seerr_media_detail_screen.dart`. **The only gap is that this flow is never reachable from a real library series' own detail screen** — today a user can only get to it by re-searching the show through Seerr's separate discovery/search UI, even for a show they already partly own.

**Design**: add a "Request on Seerr" affordance to the real library series detail screen (`item_detail_screen.dart` / `modern_detail_content.dart`), resolving the Jellyfin series to its Seerr/TMDB identity via the already-implemented `getTvDetailsByTvdb` lookup, and reusing the existing `_SeasonSelector` sheet/widget rather than rebuilding it. This directly answers "ask for the next season, or a specific season of an already-existing series" — that's exactly what Jellyseerr's per-season request already models; Moonfin just needs to link to it from the right place.

**Note on granularity**: Jellyseerr's API only reports whole-season status (`PARTIALLY_AVAILABLE`/`AVAILABLE`/etc.), not per-episode gaps within a season — "episodes 5-10 of season 2 are missing" isn't data Seerr exposes at all (that level of detail only lives in Sonarr directly). Season-level requesting (what the user actually asked for) is fully supported; individual-missing-episode detection is a separate, larger undertaking (see below) and out of scope for this pass.

### 9.2 Unify search results with Seerr, and surface "missing content" affordances more broadly (medium — optional follow-on)

Search already shows Seerr results inline on the same screen as library results (not a fully separate tab, contrary to how it reads today) — but as a segregated trailing row, not deduplicated or merged with library hits for the same title. True unification (suppressing a Seerr entry for a title you already own, adding an inline request affordance directly on search result cards) requires: matching Seerr results against library results by TMDB/IMDB id, extracting the request-submission logic out of `seerr_media_detail_view_model.dart` into something shareable, a Seerr-item variant of the long-press context menu, and care around the search screen's D-pad focus/row-index logic (real regression risk on TV). Worth doing, but genuinely separate, larger work from 9.1 — can be sequenced after or dropped if 9.1 alone satisfies the itch.

**Scope**: 9.1 small; 9.2 medium.

---

## 10. UX polish backlog (from comparative audit vs. Plex/Findroid/Streamyfin/official Jellyfin)

Moonfin already beats the official Jellyfin Android TV client in several respects worth preserving as-is: working skip-intro/credits + next-up overlays with countdown rings, per-row focus memory that correctly survives detail-screen pop-back, trickplay scrub preview, and voice search with a custom TV keyboard. The gap versus Plex/Findroid/Streamyfin is mostly **timing/consistency polish**, not missing features, with one genuine architectural gap (season/episode navigation). Prioritized:

**Navigation & Focus**
- Consolidate the three independent focus-acquisition retry loops (`_requestMediaBarFocus`, `_ensureInitialHomeFocus` in `home_screen.dart`, and `FocusRouteObserver`) into one deterministic routine — likely root cause of intermittent "focus didn't land" issues. *(medium)*
- Reduce vertical-nav debounce (currently 140ms) and handoff-animation duration (220ms) for snappier D-pad response, matching Plex's praised "predictable, fast" feel. *(small)*
- Stop shifting row layout on focus change (the 40px `_focusedRowExtraSpacing` inserted after the focused row) — apply focus visual treatment (scale/elevate) without moving other rows, simplifying the two separate scroll-alignment code paths that currently exist because of it. *(medium)*
- Centralize back-key handling into one policy instead of splitting it between `LockedFocusRow.onBack` and `HomeScreen`'s top-level `PopScope`. *(medium)*

**Browse & Search**
- Extend the book-library inline quick-filter-chip pattern (already built: `_BookStatusCategories`/`_BookOrganizeChips`) to movies/shows/music, replacing the current full-modal round-trip for every favorites/unwatched toggle. *(medium)*
- Merge (or at least adjacently place with single-keypress-cycle) the separate sort dialog and density/image-type settings dialog — currently three toolbar icons for what feels like one mental action. *(small-medium)*
- Improve the alphabet scrubber: show it for more sort modes (currently name-sort only), add coarse jump bands (A-E/F-J) so reaching distant letters doesn't take ~20 presses, and add a scrubber to `folder_browse_screen.dart` (currently has none). *(medium)*
- Add a direct list/grid density control independent of poster-size preference. *(small)*

**Detail Screens**
- Replace season/episode selection's full route-push-and-reload (`Destinations.item(id)`) with in-place panel swaps — the single biggest architectural gap versus Findroid/Streamyfin's "smooth, in-place" feel. *(large)*
- Add an integrated, always-visible episode picker (combined season selector + episode list, no drill-down) for the Classic detail variant too. *(large)*
- Longer-term: consider whether maintaining two full detail-screen styles (Classic/Modern) is worth the doubled surface area for every future fix, or whether to converge on one. *(large, strategic — not urgent)*

**Playback Controls**
- Add visual chapter tick marks directly on the scrub bar instead of only a modal list. *(medium)*
- Prefetch trickplay tiles on player mount rather than fetching on-demand during scrub drag, matching Streamyfin's approach to eliminating scrub-lag. *(small-medium)*
- Collapse the multi-phase playback bringup sequence (`stoppingPrevious → resolving → opening → waitingForReady → seekingResume`, each swapping its own label/overlay) into one continuous progress indicator. *(medium-large)*
- Verify D-pad seek step duration matches any hardware FF/RW remote button handling — this exact inconsistency is the most-cited official-Jellyfin-app complaint. *(small)*

**Performance & Feel**
- Audit thumbnail/artwork load speed on home screen entry — "thumbnails populated immediately" is specifically called out as a marker of a fast-feeling client. *(medium)*
- Reduce the breadth of `_onGlobalFocusChanged` (recomputes several chrome-visibility booleans on every focus event) — likely jank source on lower-powered Android TV boxes. *(medium)*

**Polish / Delight**
- Confirm Recently Added rows stack multi-episode additions into a single season card (Plex-style) rather than flooding the row with individual episodes, if not already the case.

---

## Verification

- **Bug fixes (§1)**: manual repro-then-fix-then-reverify for each — a fresh test user for Seerr defaults, a server with an actual HSS-configured layout for the duplicate-section fix, nested folder navigation for the sort fix, and a side-by-side before/after screenshot comparison on an Android TV device/emulator for the scaling fix.
- **HSS integration (§2)**: verify against the user's real server (HSS is installed per the plugin list) — confirm section discovery, content rendering, and graceful degradation if a section type is unavailable.
- **Collections/ACdb (§3)**: verify against the user's real ACdb-managed collections after they enable tagging; confirm the TMDB collection-ID caveat one way or the other before finalizing the missing-items flow.
- **Jellysleep (§4)**: verify against the live Jellysleep plugin already installed on the user's server.
- **Cinema Mode (§5)** and **Genres (§7)**: visual/manual verification on an Android TV build.
- **Episode/season switcher (§8)**: verify mid-playback season switching preserves (or intentionally resets) playback queue continuity as designed; test on a series with multiple seasons on real Android TV remote input.
- **Deeper Seerr integration (§9)**: verify §9.1 against a real partially-available series on the user's Jellyseerr instance (request a specific missing season and confirm it reaches Jellyseerr correctly); §9.2, if pursued, needs explicit TV focus-navigation regression testing on the search screen given the real risk of D-pad regressions noted in research.
- **UX polish backlog (§10)**: no single test covers this — treat as an ongoing backlog to work through, verifying each item individually against a real remote (or remote-emulation) on Android TV hardware, not just desktop/mouse testing.
