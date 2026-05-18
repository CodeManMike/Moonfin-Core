import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:playback_jellyfin/playback_jellyfin.dart';
import 'package:playback_emby/playback_emby.dart';
import 'package:server_core/server_core.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/repositories/offline_repository.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/services/offline_playback_tracker.dart';
import '../../playback/hdr_stream_capability.dart';
import '../../playback/known_defects.dart';
import '../../playback/media_kit_player_backend.dart';
import '../../playback/media3_player_backend.dart';
import '../../playback/offline_stream_resolver.dart';
import '../../platform/pip_service.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../syncplay/syncplay_manager.dart';
import '../../util/platform_detection.dart';

final _getIt = GetIt.instance;

bool _isDolbyVisionResolution(StreamResolutionResult resolution) {
  for (final stream in resolution.mediaStreams) {
    if (HdrStreamCapability.isDolbyVisionVideoStream(stream)) {
      return true;
    }
  }
  return false;
}

bool _hasUnsupportedDolbyVisionProfile(StreamResolutionResult resolution) {
  final prefs = _getIt<UserPreferences>();
  final allowDolbyVisionProfile7ElDirectPlay =
      KnownDefects.shouldAllowDolbyVisionProfile7ElDirectPlay(
        behavior: prefs.get(
          UserPreferences.dolbyVisionProfile7DirectPlayBehavior,
        ),
      );
  for (final stream in resolution.mediaStreams) {
    if (HdrStreamCapability.streamNeedsDolbyVisionProfileTranscode(
      stream,
      allowDolbyVisionProfile7ElDirectPlay:
          allowDolbyVisionProfile7ElDirectPlay,
    )) {
      return true;
    }
  }
  return false;
}

void registerPlaybackModule() {
  final pipService = PipService();
  _getIt.registerSingleton<PipService>(pipService);

  final backend = MediaKitPlayerBackend(
    _getIt<UserPreferences>(),
    onNativeHandleReady: pipService.initializeIos,
  );
  final media3Backend = Media3PlayerBackend(_getIt<UserPreferences>());
  _getIt.registerSingleton<MediaKitPlayerBackend>(backend);
  _getIt.registerSingleton<Media3PlayerBackend>(media3Backend);

  final prefs = _getIt<UserPreferences>();
  final useMedia3ByDefault =
      PlatformDetection.isAndroid &&
      PlatformDetection.isTV &&
      prefs.get(UserPreferences.playbackEnginePreference) ==
          PlaybackEnginePreference.media3;
  final initialBackend = useMedia3ByDefault ? media3Backend : backend;
  _getIt.registerSingleton<PlayerBackend>(initialBackend);

  final manager = PlaybackManager();
  manager.setBackend(initialBackend);
  manager.setBackendSelector((resolution, currentBackend) {
    if (PlatformDetection.isAndroid && PlatformDetection.isTV) {
      final preferMedia3 =
          prefs.get(UserPreferences.playbackEnginePreference) ==
          PlaybackEnginePreference.media3;
      if (preferMedia3) {
        if (currentBackend is Media3PlayerBackend) return currentBackend;
        return _getIt<Media3PlayerBackend>();
      }
      if (currentBackend is MediaKitPlayerBackend) return currentBackend;
      return _getIt<MediaKitPlayerBackend>();
    }

    if (currentBackend is MediaKitPlayerBackend) return currentBackend;
    return _getIt<MediaKitPlayerBackend>();
  });
  manager.setTranscodeSelector((resolution) {
    if (!(PlatformDetection.isAndroid && PlatformDetection.isTV)) {
      return false;
    }

    if (_hasUnsupportedDolbyVisionProfile(resolution)) {
      return true;
    }

    if (!_isDolbyVisionResolution(resolution)) {
      return false;
    }

    if (PlatformDetection.supportsDolbyVision) {
      return false;
    }

    if (!PlatformDetection.supportsAnyHdr) {
      return true;
    }

    final selected = prefs.get(UserPreferences.dolbyVisionFallbackBehavior);
    if (selected == DolbyVisionFallbackBehavior.transcode) {
      return true;
    }
    if (selected == DolbyVisionFallbackBehavior.hdr10Fallback) {
      return !PlatformDetection.supportsHdr10;
    }

    return false;
  });
  manager.setStartPositionAdjuster((_, startPosition) {
    final prefs = _getIt<UserPreferences>();
    final raw = prefs.get(UserPreferences.resumeSubtractDuration);
    final secs = int.tryParse(raw) ?? 0;
    if (secs <= 0) return startPosition;
    final rewind = Duration(seconds: secs);
    if (startPosition <= rewind) return Duration.zero;
    return startPosition - rewind;
  });
  manager.setResolverConfigurator(_ensureResolverForItem);
  _getIt.registerSingleton<PlaybackManager>(manager);

  _getIt.registerLazySingleton<OfflineStreamResolver>(
    () => OfflineStreamResolver(_getIt<OfflineRepository>()),
  );
  _getIt.registerLazySingleton<OfflinePlaybackTracker>(
    () => OfflinePlaybackTracker(_getIt<OfflineRepository>()),
  );

  _getIt.registerLazySingleton<SyncPlayManager>(
    () => SyncPlayManager(
      _getIt<PlaybackManager>(),
      _getIt<UserPreferences>(),
    ),
  );
}

void setActiveStreamResolver(MediaServerClient client) {
  if (_getIt.isRegistered<MediaStreamResolver>()) {
    _getIt.unregister<MediaStreamResolver>();
  }
  if (_getIt.isRegistered<PlayerService>()) {
    _getIt.unregister<PlayerService>();
  }

  final (MediaStreamResolver resolver, PlayerService service) =
      switch (client.serverType) {
    ServerType.jellyfin => () {
      final p = JellyfinPlugin(client);
      return (p.createStreamResolver(), p.createPlaySessionService());
    }(),
    ServerType.emby => () {
      final p = EmbyPlugin(client);
      return (p.createStreamResolver(), p.createPlaySessionService());
    }(),
  };

  _getIt.registerSingleton<MediaStreamResolver>(resolver);
  _getIt.registerSingleton<PlayerService>(service);

  final manager = _getIt<PlaybackManager>();
  manager.setResolver(resolver);
  manager.setPlayerService(service);
}

Future<void> _ensureResolverForItem(dynamic item) async {
  if (item is! AggregatedItem) return;
  final factory = _getIt<MediaServerClientFactory>();
  final client = factory.getClientIfExists(item.serverId);
  if (client == null || identical(client, _getIt<MediaServerClient>())) return;
  setActiveStreamResolver(client);
}
