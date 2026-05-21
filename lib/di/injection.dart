import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart' as pkg;
import 'package:server_core/server_core.dart';
import 'package:uuid/uuid.dart';

import '../auth/store/authentication_store.dart';
import '../data/database/database_connection.dart';
import '../data/database/offline_database.dart';
import '../data/repositories/offline_repository.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/recent_searches_store.dart';
import '../data/services/storage_path_service.dart';
import '../preference/preference_constants.dart';
import '../preference/user_preferences.dart';
import '../util/platform_detection.dart';
import 'modules/app_module.dart';
import 'modules/auth_module.dart';
import 'modules/server_module.dart';
import 'modules/playback_module.dart';
import 'modules/preference_module.dart';

final getIt = GetIt.instance;

String _clientName() {
  if (PlatformDetection.isAndroid) return 'Moonfin for Android';
  if (PlatformDetection.isIOS) return 'Moonfin for iOS';
  if (PlatformDetection.isMacOS) return 'Moonfin for macOS';
  if (PlatformDetection.isWindows) return 'Moonfin for Windows';
  if (PlatformDetection.isLinux) return 'Moonfin for Linux';
  return 'Moonfin';
}

String _joinNonEmpty(List<String?> parts, String separator) {
  return parts
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(separator);
}

String _fallbackIfEmpty(String value, String fallback) {
  return value.trim().isEmpty ? fallback : value.trim();
}

String _resolveAndroidDeviceName(AndroidDeviceInfo info) {
  final manufacturer = info.manufacturer.trim();
  final model = info.model.trim();
  final brand = info.brand.trim();

  // Prefer the reported model first. On modern phones this is typically
  // the user-friendly marketing name, e.g. "Pixel 9 Pro XL".
  if (model.isNotEmpty && model.toLowerCase() != 'unknown') {
    final lowerModel = model.toLowerCase();
    final lowerManufacturer = manufacturer.toLowerCase();

    // Avoid repeating manufacturer when model already includes it.
    if (manufacturer.isNotEmpty && !lowerModel.startsWith(lowerManufacturer)) {
      return '$manufacturer $model';
    }

    return model;
  }

  // Fallback path for devices that do not expose a useful model string.
  final combined = _joinNonEmpty([
    manufacturer,
    brand,
    info.device,
    info.product,
  ], ' ');
  return _fallbackIfEmpty(combined, 'Android Device');
}

Future<String> _resolveDeviceName() async {
  final deviceInfo = DeviceInfoPlugin();

  try {
    if (PlatformDetection.isAndroid) {
      final info = await deviceInfo.androidInfo;
      final name = _resolveAndroidDeviceName(info);
      if (!info.isPhysicalDevice) {
        return '$name (emulator)';
      }
      return name;
    }

    if (PlatformDetection.isIOS) {
      final info = await deviceInfo.iosInfo;
      final marketingName = _joinNonEmpty([info.name, info.model], ' ');
      return _fallbackIfEmpty(marketingName, 'iPhone');
    }

    if (PlatformDetection.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return _fallbackIfEmpty(
        _joinNonEmpty([info.computerName, info.model], ' '),
        'Mac',
      );
    }

    if (PlatformDetection.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return _fallbackIfEmpty(
        _joinNonEmpty([info.computerName, info.productName], ' '),
        'Windows PC',
      );
    }

    if (PlatformDetection.isLinux) {
      final info = await deviceInfo.linuxInfo;
      return _fallbackIfEmpty(
        _joinNonEmpty([info.name, info.prettyName], ' '),
        'Linux Device',
      );
    }
  } catch (_) {
    // Fall through to app-based fallback below.
  }

  return _clientName();
}

Future<String> _resolveAppVersion() async {
  try {
    final info = await pkg.PackageInfo.fromPlatform();
    return info.version.trim().isNotEmpty ? info.version.trim() : '0.1.0';
  } catch (_) {
    return '0.1.0';
  }
}

({int major, int minor, int patch})? _parseSemverCore(String? rawVersion) {
  if (rawVersion == null) return null;
  final normalized = rawVersion.trim();
  if (normalized.isEmpty) return null;

  final match = RegExp(r'^\D*(\d+)\.(\d+)\.(\d+)').firstMatch(normalized);
  if (match == null) return null;

  final major = int.tryParse(match.group(1) ?? '');
  final minor = int.tryParse(match.group(2) ?? '');
  final patch = int.tryParse(match.group(3) ?? '');
  if (major == null || minor == null || patch == null) {
    return null;
  }

  return (major: major, minor: minor, patch: patch);
}

bool _isAtMostVersion1_4X(String? rawVersion) {
  final parsed = _parseSemverCore(rawVersion);
  if (parsed == null) return false;

  if (parsed.major != 1) {
    return parsed.major < 1;
  }

  return parsed.minor <= 4;
}

Future<void> _migrateLegacyBitrateCap(PreferenceStore store) async {
  const migrationKey = 'pref_max_bitrate_migrated_v3';
  if (store.getBool(migrationKey) == true) {
    return;
  }

  final current = store.getString(UserPreferences.maxBitrate.key) ?? '';
  if (current == '100') {
    await store.setString(
      UserPreferences.maxBitrate.key,
      UserPreferences.maxBitrate.defaultValue,
    );
  } else {
    final parsed = int.tryParse(current);
    if (parsed != null && parsed >= 1000000) {
      await store.setString(
        UserPreferences.maxBitrate.key,
        '${parsed ~/ 1000000}',
      );
    }
  }

  await store.setBool(migrationKey, true);
}

Future<void> _migrateLegacyMediaBarMode(PreferenceStore store) async {
  const migrationKey = 'pref_media_bar_mode_migrated_v1';
  if (store.getBool(migrationKey) == true) {
    return;
  }

  final existingMode = store.getString(UserPreferences.mediaBarMode.key);
  if (existingMode == null || existingMode.trim().isEmpty) {
    final legacyEnabled = store.getBool(UserPreferences.mediaBarEnabled.key);
    final nextMode = legacyEnabled == false
        ? UserPreferences.mediaBarModeOff
        : UserPreferences.mediaBarModeMoonfin;
    await store.setString(UserPreferences.mediaBarMode.key, nextMode);
  } else {
    final normalized = UserPreferences.normalizeMediaBarMode(existingMode);
    if (normalized != existingMode) {
      await store.setString(UserPreferences.mediaBarMode.key, normalized);
    }
  }

  await store.setBool(migrationKey, true);
}

Future<void> _migrateAndroidMobilePlaybackEngine(
  PreferenceStore store, {
  required String currentAppVersion,
}) async {
  const migrationKey = 'pref_playback_engine_migrated_android_mobile_v1';
  const lastSeenVersionKey = 'pref_last_seen_app_version';
  final previousAppVersion = store.getString(lastSeenVersionKey);

  try {
    if (!PlatformDetection.isAndroid || PlatformDetection.isTV) {
      return;
    }

    if (store.getBool(migrationKey) == true) {
      return;
    }

    final hasStoredEnginePreference = store.containsKey(
      UserPreferences.playbackEnginePreference.key,
    );
    final shouldMigrate =
        _isAtMostVersion1_4X(previousAppVersion) ||
        (previousAppVersion == null && hasStoredEnginePreference);

    if (shouldMigrate) {
      await store.setString(
        UserPreferences.playbackEnginePreference.key,
        PlaybackEnginePreference.media3.name,
      );
    }

    await store.setBool(migrationKey, true);
  } finally {
    if (PlatformDetection.isAndroid &&
        !PlatformDetection.isTV &&
        previousAppVersion != currentAppVersion) {
      await store.setString(lastSeenVersionKey, currentAppVersion);
    }
  }
}

Future<void> configureDependencies() async {
  final preferenceStore = PreferenceStore();
  await preferenceStore.init();
  final appVersion = await _resolveAppVersion();
  await _migrateLegacyBitrateCap(preferenceStore);
  await _migrateLegacyMediaBarMode(preferenceStore);
  await _migrateAndroidMobilePlaybackEngine(
    preferenceStore,
    currentAppVersion: appVersion,
  );

  var deviceId = preferenceStore.getString('device_id');
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await preferenceStore.setString('device_id', deviceId);
  }

  final clientName = _clientName();
  final deviceName = await _resolveDeviceName();
  getIt.registerSingleton<DeviceInfo>(
    DeviceInfo(
      id: deviceId,
      name: deviceName,
      appName: clientName,
      appVersion: appVersion,
    ),
  );

  registerPreferenceModule(preferenceStore);
  getIt.registerLazySingleton<RecentSearchesStore>(
    () => RecentSearchesStore(preferenceStore),
  );

  final storagePath = StoragePathService();
  getIt.registerSingleton<StoragePathService>(storagePath);
  getIt.registerSingleton<OfflineDatabase>(OfflineDatabase(openConnection()));
  getIt.registerSingleton<OfflineRepository>(
    OfflineRepository(getIt<OfflineDatabase>()),
  );

  final connectivityService = ConnectivityService();
  connectivityService.initialize();
  getIt.registerSingleton<ConnectivityService>(connectivityService);

  registerServerModule();
  registerAuthModule();
  await getIt<AuthenticationStore>().init();
  registerPlaybackModule();
  registerAppModule();
}
