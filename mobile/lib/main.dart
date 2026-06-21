import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/providers.dart';
import 'router.dart';
import 'theme/arbiter_theme.dart';
import 'widgets/offline_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ArbiterApp(),
    ),
  );
}

class ArbiterApp extends ConsumerWidget {
  const ArbiterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Arbiter AI',
      debugShowCheckedModeBanner: false,
      theme: ArbiterTheme.light(),
      darkTheme: ArbiterTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      // App-wide offline banner above every routed page.
      builder: (context, child) => Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
