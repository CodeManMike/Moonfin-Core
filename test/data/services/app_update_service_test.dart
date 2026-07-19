import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/preference/user_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'update notifications default to disabled, so a fresh install never '
    'checks the upstream Moonfin-Client/Moonfin-Core repo for a newer '
    'release and prompts to install over a custom-built app - '
    'AppUpdateService.checkForUpdateIfDue() short-circuits on this before '
    'ever making a network call, per its "respectNotificationPreference" gate',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);

      expect(prefs.get(UserPreferences.updateNotificationsEnabled), isFalse);
    },
  );
}
