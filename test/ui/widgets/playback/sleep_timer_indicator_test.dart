import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/playback/sleep_timer_indicator.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String label,
  required VoidCallback onCancel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            SleepTimerIndicator(label: label, onCancel: onCancel),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the provided label', (tester) async {
    await _pump(tester, label: 'Sleeping in 30 min', onCancel: () {});

    expect(find.text('Sleeping in 30 min'), findsOneWidget);
  });

  testWidgets('invokes onCancel when tapped', (tester) async {
    var cancelled = false;
    await _pump(
      tester,
      label: 'Sleeping in 30 min',
      onCancel: () => cancelled = true,
    );

    await tester.tap(find.byType(SleepTimerIndicator));
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('shows a moon icon', (tester) async {
    await _pump(tester, label: 'Sleeping in 30 min', onCancel: () {});

    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });
}
