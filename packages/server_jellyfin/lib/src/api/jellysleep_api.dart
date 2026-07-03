import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart' as core;

/// Client for the third-party Jellysleep Jellyfin plugin's REST API.
///
/// Jellysleep is installed directly on the user's Jellyfin server as a
/// plugin route (`/Plugin/Jellysleep/*`) and is reached with the same
/// authenticated [Dio] instance used for all other Jellyfin API calls —
/// no Moonfin server-plugin proxy is involved.
class JellysleepApi implements core.JellysleepApi {
  final Dio _dio;

  JellysleepApi(this._dio);

  /// Starts a sleep timer.
  ///
  /// [type] is either `'duration'` (stop playback after [duration] minutes)
  /// or `'episode'` (stop playback after [duration] more episodes finish).
  @override
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
  @override
  Future<void> cancelTimer() async {
    await _dio.post('/Plugin/Jellysleep/CancelTimer');
  }
}
