import 'package:flutter_test/flutter_test.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/playback/episode_switcher_eligibility.dart';

AggregatedItem _episode({String? seriesId}) => AggregatedItem(
      id: 'e1',
      serverId: 'server-1',
      rawData: {
        'Id': 'e1',
        'Type': 'Episode',
        'SeriesId': seriesId,
      },
    );

AggregatedItem _movie() => AggregatedItem(
      id: 'm1',
      serverId: 'server-1',
      rawData: {'Id': 'm1', 'Type': 'Movie'},
    );

void main() {
  test('episode with a seriesId is eligible for the switcher', () {
    expect(canShowEpisodeSwitcher(_episode(seriesId: 'series-1')), isTrue);
  });

  test('episode without a seriesId is not eligible', () {
    expect(canShowEpisodeSwitcher(_episode(seriesId: null)), isFalse);
  });

  test('non-episode items are not eligible', () {
    expect(canShowEpisodeSwitcher(_movie()), isFalse);
  });

  test('non-AggregatedItem queue items (offline url/raw map) are not eligible', () {
    expect(canShowEpisodeSwitcher('offline://some/path.mp4'), isFalse);
    expect(canShowEpisodeSwitcher(<String, dynamic>{'Type': 'Episode'}), isFalse);
  });
}
