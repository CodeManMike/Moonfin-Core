import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/home_section_config.dart';

void main() {
  group('HomeSectionPluginSource.homeScreenSections', () {
    test('serializes to "homeScreenSections" and back', () {
      const source = HomeSectionPluginSource.homeScreenSections;
      expect(source.serializedName, 'homeScreenSections');
      expect(
        HomeSectionPluginSource.fromSerialized('homeScreenSections'),
        HomeSectionPluginSource.homeScreenSections,
      );
    });

    test('HomeSectionConfig.pluginDynamic round-trips through JSON with homeScreenSections source', () {
      final config = HomeSectionConfig.pluginDynamic(
        serverId: 'server-1',
        pluginSection: 'BecauseYouWatched',
        pluginAdditionalData: '',
        pluginDisplayText: 'Because You Watched',
        pluginSource: HomeSectionPluginSource.homeScreenSections,
      );

      final json = config.toJson();
      expect(json['pluginSource'], 'homeScreenSections');

      final decoded = HomeSectionConfig.fromJson(json);
      expect(decoded.pluginSource, HomeSectionPluginSource.homeScreenSections);
      expect(decoded.pluginSection, 'BecauseYouWatched');
      expect(decoded.isPluginDynamic, isTrue);
    });
  });
}
