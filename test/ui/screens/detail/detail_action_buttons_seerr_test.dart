import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';

class _MockItemDetailViewModel extends Mock implements ItemDetailViewModel {}

class _MockOfflineRepository extends Mock implements OfflineRepository {}

void main() {
  // DetailActionButtonsState.initState and build() unconditionally touch
  // UserRepository, UserPreferences, and OfflineRepository via GetIt (for the
  // user-change subscription, desktop UI scale, and the offline-download
  // check respectively), so all three must be registered even though this
  // test exercises none of those features directly. This mirrors the
  // pattern in test/ui/widgets/playback/sleep_timer_picker_dialog_test.dart.
  setUp(() async {
    if (!GetIt.instance.isRegistered<UserRepository>()) {
      GetIt.instance.registerSingleton<UserRepository>(UserRepository());
    }
    if (!GetIt.instance.isRegistered<UserPreferences>()) {
      SharedPreferences.setMockInitialValues(const {});
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(
        UserPreferences(store),
      );
    }
    if (!GetIt.instance.isRegistered<OfflineRepository>()) {
      final offlineRepo = _MockOfflineRepository();
      when(
        () => offlineRepo.getSeriesEpisodes(any()),
      ).thenAnswer((_) async => []);
      when(
        () => offlineRepo.getSeasonEpisodes(any()),
      ).thenAnswer((_) async => []);
      GetIt.instance.registerSingleton<OfflineRepository>(offlineRepo);
    }
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<UserRepository>()) {
      GetIt.instance.unregister<UserRepository>();
    }
    if (GetIt.instance.isRegistered<UserPreferences>()) {
      GetIt.instance.unregister<UserPreferences>();
    }
    if (GetIt.instance.isRegistered<OfflineRepository>()) {
      GetIt.instance.unregister<OfflineRepository>();
    }
  });

  testWidgets(
    'shows Request on Seerr for a series with a resolved Seerr identity',
    (WidgetTester tester) async {
      final viewModel = _MockItemDetailViewModel();
      final item = AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {'Type': 'Series', 'Name': 'Test Show'},
      );
      when(() => viewModel.item).thenReturn(item);
      when(() => viewModel.seasons).thenReturn(const []);
      when(() => viewModel.nextUp).thenReturn(null);
      when(() => viewModel.episodes).thenReturn(const []);
      when(() => viewModel.collectionItems).thenReturn(const []);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DetailActionButtons(
              viewModel: viewModel,
              onSelectedMediaSourceChanged: (_) {},
              resolvedSeerrTv: const SeerrTvDetails(id: 999, name: 'Test Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.seerr), findsOneWidget);
    },
  );

  testWidgets('hides Request on Seerr when resolution is null', (
    WidgetTester tester,
  ) async {
    final viewModel = _MockItemDetailViewModel();
    final item = AggregatedItem(
      id: 'series-1',
      serverId: 'server-1',
      rawData: const {'Type': 'Series', 'Name': 'Test Show'},
    );
    when(() => viewModel.item).thenReturn(item);
    when(() => viewModel.seasons).thenReturn(const []);
    when(() => viewModel.nextUp).thenReturn(null);
    when(() => viewModel.episodes).thenReturn(const []);
    when(() => viewModel.collectionItems).thenReturn(const []);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DetailActionButtons(
            viewModel: viewModel,
            onSelectedMediaSourceChanged: (_) {},
            resolvedSeerrTv: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.seerr), findsNothing);
  });
}
