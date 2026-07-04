import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_request_sheet.dart';

class _MockPreferenceStore extends Mock implements PreferenceStore {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

void main() {
  testWidgets('SeerrRequestSheet shows a season chip per season', (
    WidgetTester tester,
  ) async {
    final session = _MockSessionRepository();
    when(() => session.activeUserId).thenReturn(null);
    final repo = SeerrRepository(
      _MockPreferenceStore(),
      session,
      _MockMediaServerClient(),
    );
    final vm = SeerrMediaDetailViewModel(
      repo,
      SeerrPreferences(_MockPreferenceStore(), session),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SeerrRequestSheet(
            vm: vm,
            isTv: true,
            numberOfSeasons: 3,
            requestedSeasons: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SeerrRequestSheet), findsOneWidget);
  });
}
