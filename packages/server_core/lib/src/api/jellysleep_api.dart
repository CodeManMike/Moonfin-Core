/// Abstract interface for the third-party Jellysleep plugin's sleep-timer
/// REST API, implemented per-backend in `server_jellyfin`.
abstract class JellysleepApi {
  /// Starts a sleep timer. [type] is `'duration'` (minutes) or `'episode'`
  /// (episode count); [duration] is the corresponding numeric value.
  Future<void> startTimer({required String type, required int duration});

  /// Cancels any active sleep timer for the current user/session.
  Future<void> cancelTimer();
}
