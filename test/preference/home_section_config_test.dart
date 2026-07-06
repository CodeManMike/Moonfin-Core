import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/home_section_config.dart';
import 'package:moonfin/preference/preference_constants.dart';

void main() {
  group('HomeSectionType.acdbCollections', () {
    test('serializes to "acdbcollections" and back', () {
      const type = HomeSectionType.acdbCollections;
      expect(type.serializedName, 'acdbcollections');
      expect(
        HomeSectionType.fromSerialized('acdbcollections'),
        HomeSectionType.acdbCollections,
      );
    });

    test('is present in HomeSectionConfig.defaults(), disabled by default', () {
      final defaults = HomeSectionConfig.defaults();
      final acdbEntry = defaults.where(
        (c) => c.type == HomeSectionType.acdbCollections,
      );

      expect(acdbEntry, hasLength(1));
      expect(acdbEntry.single.enabled, isFalse);
      expect(acdbEntry.single.isBuiltin, isTrue);
    });

    test('round-trips through JSON distinctly from the plain collections type', () {
      const config = HomeSectionConfig(
        type: HomeSectionType.acdbCollections,
        enabled: true,
        order: 5,
      );

      final json = config.toJson();
      expect(json['type'], 'acdbcollections');

      final decoded = HomeSectionConfig.fromJson(json);
      expect(decoded.type, HomeSectionType.acdbCollections);
      expect(decoded.type, isNot(equals(HomeSectionType.collections)));
    });
  });

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
