import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/data/game_repository.dart';
import 'package:mobile/main.dart';
import 'package:mobile/monetization/plans.dart';
import 'package:mobile/monetization/quota.dart';
import 'package:mobile/monetization/subscription.dart';
import 'package:mobile/providers/providers.dart';
import 'package:mobile/router.dart';
import 'package:mobile/theme/arbiter_tokens.dart';
import 'package:mobile/widgets/piece_image.dart';

Future<(SharedPreferences, PreviewSubscriptionService)> _pumpApp(
    WidgetTester tester, {bool firstRun = false, bool quotaUsed = false}) async {
  SharedPreferences.setMockInitialValues({
    'onboarded_v1': !firstRun,
    if (quotaUsed) 'quota_week': UsageQuota.weekKey(DateTime.now()),
    if (quotaUsed) 'quota_used': kFreeWeeklyToolUses,
  });
  final prefs = await SharedPreferences.getInstance();
  final subs = PreviewSubscriptionService(prefs, allowPurchases: true);
  await subs.init();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      gameRepositoryProvider.overrideWithValue(MemoryGameRepository()),
      subscriptionServiceProvider.overrideWithValue(subs),
    ],
    child: ArbiterApp(router: buildRouter()),
  ));
  await tester.pumpAndSettle();
  return (prefs, subs);
}

void main() {
  testWidgets('home renders the offline desk and welcome card', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Hakem Masası'), findsOneWidget);
    expect(find.text('Tahtada oyna'), findsOneWidget);
    expect(find.text('Örneği aç'), findsOneWidget);
  });

  testWidgets('first run shows the disclaimer once', (tester) async {
    final (prefs, _) = await _pumpApp(tester, firstRun: true);
    expect(find.text('Başlamadan önce'), findsOneWidget);
    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();
    expect(find.text('Başlamadan önce'), findsNothing);
    expect(prefs.getBool('onboarded_v1'), isTrue);
  });

  testWidgets('sample game shows the illegal move and claim opportunity',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Örneği aç'));
    await tester.pumpAndSettle();
    expect(find.textContaining('İnceleme gerekli'), findsWidgets);
    expect(find.textContaining('talep fırsatı'), findsOneWidget);
    expect(find.text('Talep kontrolü'), findsOneWidget);
  });

  testWidgets('no paywall mid-dispute: verdict headline shown when quota is used up',
      (tester) async {
    await _pumpApp(tester, quotaUsed: true);
    await tester.tap(find.text('Örneği aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Talep kontrolü'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Talebi doğrula'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Talebi doğrula'));
    await tester.pumpAndSettle();
    expect(find.text('Hakem Masası Pro'), findsNothing); // no paywall pushed
    expect(find.textContaining('talep DOĞRU', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Gerekçe, madde dayanakları', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Hakem kaydına ekle', skipOffstage: false), findsNothing);
  });

  testWidgets('moves can be played on the board', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Tahtada oyna'));
    await tester.pumpAndSettle();
    final board = find.byType(AspectRatio).first;
    final rect = tester.getRect(board);
    final sq = rect.width / 8;
    Offset at(int file, int rank) =>
        rect.topLeft + Offset((file + 0.5) * sq, (7 - rank + 0.5) * sq);
    await tester.tapAt(at(4, 1)); // e2
    await tester.pump();
    await tester.tapAt(at(4, 3)); // e4
    await tester.pumpAndSettle();
    expect(find.text('1.e4'), findsOneWidget);
    expect(find.textContaining('Sıra: Siyah'), findsOneWidget);
  });

  testWidgets('preview purchase unlocks Pro', (tester) async {
    final (_, subs) = await _pumpApp(tester);
    await tester.tap(find.textContaining('Turnuvada mısın?'));
    await tester.pumpAndSettle();
    expect(find.text('Hakem Masası Pro'), findsOneWidget);
    // The purchase bar is pinned to the bottom: no scrolling needed.
    expect(find.textContaining('her hafta tahsil edilir'), findsOneWidget);
    await tester.tap(find.textContaining('Turnuva haftasını başlat'));
    await tester.pumpAndSettle();
    expect(subs.current.isPro, isTrue);
    expect(subs.current.productId, kPlans.first.productId);
    expect(find.text('Pro etkin'), findsOneWidget);
    await tester.tap(find.text('Masaya dön'));
    await tester.pumpAndSettle();
    expect(find.text('Hakem Masası Pro'), findsNothing);
  });

  testWidgets('piece set choice is applied and remembered', (tester) async {
    final (prefs, _) = await _pumpApp(tester);
    await tester.tap(find.byTooltip('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Modern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modern'));
    await tester.pumpAndSettle();
    expect(prefs.getString('piece_set'), 'spatial');
    final scope = tester.widget<PieceSetScope>(find.byType(PieceSetScope));
    expect(scope.pieceSet, PieceSet.spatial);
  });

  testWidgets('settings can erase every game on the device', (tester) async {
    final (prefs, _) = await _pumpApp(tester);
    await tester.tap(find.text('Örneği aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    List<Object> games() => ProviderScope.containerOf(tester.element(find.byType(ArbiterApp)))
        .read(gamesProvider)
        .requireValue;
    expect(games(), isNotEmpty);
    await tester.tap(find.byTooltip('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tüm verileri sil'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Tüm verileri sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(games(), isEmpty);
    expect(prefs.getBool('onboarded_v1'), isTrue);
  });

  testWidgets('position setup flags a dead position', (tester) async {
    await _pumpApp(tester);
    await tester.ensureVisible(find.text('Tahtadaki konum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tahtadaki konum'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Konum değerlendirmesi'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Konum değerlendirmesi'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tahtayı boşalt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ölü konum'), findsOneWidget);
  });

  test('weekly quota allows three free tool uses and resets on Monday', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 4); // Wednesday
    final q = UsageQuota(prefs, clock: () => now);
    for (var i = 0; i < kFreeWeeklyToolUses; i++) {
      expect(await q.tryConsume(), isTrue);
    }
    expect(await q.tryConsume(), isFalse);
    expect(q.remaining, 0);
    now = DateTime(2026, 11, 8, 23); // Sunday, same week
    expect(q.remaining, 0);
    now = DateTime(2026, 11, 9); // Monday
    expect(q.remaining, kFreeWeeklyToolUses);
  });
}
