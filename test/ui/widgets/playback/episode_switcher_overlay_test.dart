import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/playback/episode_switcher_overlay.dart';

AggregatedItem _season(String id, String name) => AggregatedItem(
      id: id,
      serverId: 'server-1',
      rawData: {'Id': id, 'Name': name, 'Type': 'Season'},
    );

AggregatedItem _episode(
  String id, {
  required int season,
  required int episode,
  required String name,
}) =>
    AggregatedItem(
      id: id,
      serverId: 'server-1',
      rawData: {
        'Id': id,
        'Name': name,
        'Type': 'Episode',
        'ParentIndexNumber': season,
        'IndexNumber': episode,
      },
    );

Future<void> _registerPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  final store = PreferenceStore();
  await store.init();
  final prefs = UserPreferences(store);
  GetIt.instance.registerSingleton<UserPreferences>(prefs);
}

void main() {
  setUp(() async {
    if (!GetIt.instance.isRegistered<UserPreferences>()) {
      await _registerPrefs();
    }
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<UserPreferences>()) {
      GetIt.instance.unregister<UserPreferences>();
    }
  });

  testWidgets('renders a tab per season and an episode tile per episode',
      (tester) async {
    final seasons = [_season('s1', 'Season 1'), _season('s2', 'Season 2')];
    final episodesBySeasonId = {
      's1': [
        _episode('e1', season: 1, episode: 1, name: 'Pilot'),
        _episode('e2', season: 1, episode: 2, name: 'Second'),
      ],
      's2': [
        _episode('e3', season: 2, episode: 1, name: 'Return'),
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              EpisodeSwitcherOverlay(
                seasons: seasons,
                initialSeasonId: 's1',
                currentEpisodeId: 'e1',
                episodesForSeason: (seasonId) =>
                    episodesBySeasonId[seasonId] ?? const [],
                imageUrlForEpisode: (_) => null,
                onEpisodeSelected: (_, _) {},
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    // Episode tiles render as "<index>. <name>" (see _EpisodeTile), so match
    // on the full rendered label rather than the bare episode name.
    expect(find.text('1. Pilot'), findsOneWidget);
    expect(find.text('2. Second'), findsOneWidget);
    expect(find.text('1. Return'), findsNothing);
  });

  testWidgets(
      'tapping an episode tile invokes onEpisodeSelected with the season list',
      (tester) async {
    final seasons = [_season('s1', 'Season 1')];
    final seasonEpisodes = [
      _episode('e1', season: 1, episode: 1, name: 'Pilot'),
      _episode('e2', season: 1, episode: 2, name: 'Second'),
    ];
    AggregatedItem? selected;
    List<AggregatedItem>? selectedSeasonEpisodes;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              EpisodeSwitcherOverlay(
                seasons: seasons,
                initialSeasonId: 's1',
                currentEpisodeId: 'e1',
                episodesForSeason: (_) => seasonEpisodes,
                imageUrlForEpisode: (_) => null,
                onEpisodeSelected: (episode, episodesInSeason) {
                  selected = episode;
                  selectedSeasonEpisodes = episodesInSeason;
                },
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2. Second'));
    await tester.pumpAndSettle();

    expect(selected?.id, 'e2');
    expect(selectedSeasonEpisodes, hasLength(2));
  });
}
