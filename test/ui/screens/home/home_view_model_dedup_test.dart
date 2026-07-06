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

    test('plugin-dynamic configs differing only by pluginSource produce different keys', () {
      const configA = HomeSectionConfig(
        kind: HomeSectionKind.pluginDynamic,
        pluginSource: HomeSectionPluginSource.collections,
        serverId: 'server-1',
        pluginSection: 'trending',
      );
      const configB = HomeSectionConfig(
        kind: HomeSectionKind.pluginDynamic,
        pluginSource: HomeSectionPluginSource.genres,
        serverId: 'server-1',
        pluginSection: 'trending',
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

    test('acdbCollections builtin config has its own distinct dedup key', () {
      const acdbConfig = HomeSectionConfig(
        kind: HomeSectionKind.builtin,
        type: HomeSectionType.acdbCollections,
      );
      const collectionsConfig = HomeSectionConfig(
        kind: HomeSectionKind.builtin,
        type: HomeSectionType.collections,
      );

      final acdbKeys = HomeViewModel.duplicateKeysForConfig(acdbConfig);
      final collectionsKeys = HomeViewModel.duplicateKeysForConfig(
        collectionsConfig,
      );

      expect(acdbKeys, equals(const {'acdbCollections'}));
      expect(acdbKeys, isNot(equals(collectionsKeys)));
    });
  });
}
