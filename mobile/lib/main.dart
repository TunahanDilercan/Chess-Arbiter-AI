import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/game_repository.dart';
import 'monetization/subscription.dart';
import 'providers/providers.dart';
import 'router.dart';
import 'theme/arbiter_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final repo = (kIsWeb ? null : await createFileRepository()) ??
      PrefsGameRepository(prefs);
  final rcKey = revenueCatKeyForPlatform();
  final SubscriptionService subs = rcKey != null
      ? RevenueCatSubscriptionService(rcKey)
      : PreviewSubscriptionService(prefs);
  await subs.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        gameRepositoryProvider.overrideWithValue(repo),
        subscriptionServiceProvider.overrideWithValue(subs),
      ],
      child: ArbiterApp(router: buildRouter()),
    ),
  );
}

class ArbiterApp extends ConsumerWidget {
  const ArbiterApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Hakem Masası',
      debugShowCheckedModeBanner: false,
      theme: ArbiterTheme.light(),
      darkTheme: ArbiterTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
