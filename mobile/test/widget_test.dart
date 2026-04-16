import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';
import 'package:mobile/providers/providers.dart';

void main() {
  testWidgets('App smoke test — renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentGamesProvider.overrideWith((ref) async => []),
        ],
        child: const ArbiterApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Arbiter AI'), findsWidgets);
  });
}
