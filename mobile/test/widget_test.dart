import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/main.dart';
import 'package:mobile/providers/providers.dart';

void main() {
  testWidgets('App smoke test — renders without crashing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          recentGamesProvider.overrideWith((ref) async => []),
        ],
        child: const ArbiterApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Arbiter AI'), findsWidgets);
  });
}
