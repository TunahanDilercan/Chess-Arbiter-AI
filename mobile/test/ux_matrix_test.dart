import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/arbiter/game_record.dart';
import 'package:mobile/core/arbiter/sample.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/data/game_repository.dart';
import 'package:mobile/main.dart';
import 'package:mobile/monetization/subscription.dart';
import 'package:mobile/providers/providers.dart';
import 'package:mobile/router.dart';

/// Every main screen on small/large phones and iPad, at normal and enlarged
/// text sizes, in light and dark theme. Layout overflows fail the test.
const _devices = <String, (Size, double)>{
  'iPhone SE': (Size(375, 667), 2),
  'Android 360': (Size(360, 640), 3),
  'iPhone 15 Pro': (Size(393, 852), 3),
  'iPad': (Size(1024, 1366), 2),
  'iPhone landscape': (Size(852, 393), 3),
};
const _scales = [1.0, 1.35, 2.0];

const _routes = [
  '/',
  '/game/demo',
  '/game/demo/claim?pos=48',
  '/game/demo/illegal?ply=49',
  '/pro',
  '/pro?feature=claimCheck',
  '/board',
  '/board?mode=keyboard',
  '/import',
  '/compare?game=demo',
  '/position',
];

Future<void> _scrollThrough(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    await tester.drag(scrollables.first, const Offset(0, -600), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final dark in [false, true]) {
    for (final device in _devices.entries) {
      for (final scale in _scales) {
        if (dark && scale != 1.35) continue; // dark theme: one scale is enough
        final name = '${device.key} x$scale${dark ? ' dark' : ''}';
        testWidgets('no layout overflow: $name', (tester) async {
          final (size, dpr) = device.value;
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          SharedPreferences.setMockInitialValues({
            'onboarded_v1': true,
            'theme_mode': dark ? 'dark' : 'light',
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = MemoryGameRepository();
          await repo.save(GameRecord(
            id: 'demo',
            createdAt: DateTime(2026, 10, 31),
            updatedAt: DateTime(2026, 10, 31),
            headers: sampleHeaders,
            tokens: sampleTokensTr,
            locale: NotationLocale.tr,
          ));
          final subs = PreviewSubscriptionService(prefs, allowPurchases: true);
          await subs.init();
          final GoRouter router = buildRouter();

          final problems = <String>[];
          var where = '/';
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final text = details.exceptionAsString();
            final loc = RegExp(r'lib/[a-z_/]+\.dart:\d+').firstMatch(details.toString())?.group(0);
            problems.add('$where: ${text.split('\n').first} @ $loc');
          };

          await tester.pumpWidget(ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              gameRepositoryProvider.overrideWithValue(repo),
              subscriptionServiceProvider.overrideWithValue(subs),
            ],
            child: ArbiterApp(router: router),
          ));
          await tester.pumpAndSettle();

          for (final route in _routes) {
            where = route;
            router.go(route);
            await tester.pumpAndSettle();
            await _scrollThrough(tester);
            if (route.contains('claim')) {
              final verify = find.text('Talebi doğrula');
              if (verify.evaluate().isNotEmpty) {
                await tester.ensureVisible(verify);
                await tester.tap(verify);
                await tester.pumpAndSettle();
                await _scrollThrough(tester);
              }
            }
            if (route.contains('illegal')) {
              final advise = find.text('Ne yapmalıyım?');
              if (advise.evaluate().isNotEmpty) {
                await tester.ensureVisible(advise);
                await tester.tap(advise);
                await tester.pumpAndSettle();
                await _scrollThrough(tester);
              }
            }
          }

          where = 'settings sheet';
          router.go('/');
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Ayarlar'));
          await tester.pumpAndSettle();
          await _scrollThrough(tester);
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();

          where = 'game info sheet';
          router.go('/game/demo');
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Oyun bilgileri'));
          await tester.pumpAndSettle();
          await _scrollThrough(tester);
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();

          where = 'move edit sheet';
          router.go('/game/demo');
          await tester.pumpAndSettle();
          final cell = find.text('gxh6');
          if (cell.evaluate().isNotEmpty) {
            await tester.longPress(cell.first, warnIfMissed: false);
            await tester.pumpAndSettle();
            await _scrollThrough(tester);
          }

          FlutterError.onError = previous;
          expect(problems.toSet().toList(), isEmpty);
        });
      }
    }
  }
}
