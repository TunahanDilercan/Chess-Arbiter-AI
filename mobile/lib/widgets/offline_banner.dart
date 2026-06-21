import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';

/// Thin bar shown at the top of the app whenever the device is offline.
/// Mounted app-wide via MaterialApp.router's `builder`. Mirrors the web
/// OfflineBanner; collapses to nothing when online or while the first
/// connectivity result is still loading.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    // Treat "loading" and "error" as online so we never flash a false offline
    // bar; only an explicit `false` shows the banner.
    final online = ref.watch(connectivityProvider).valueOrNull ?? true;
    if (online) return const SizedBox.shrink();

    return Material(
      color: c.feedbackDanger,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ArbiterSpacing.s4, vertical: ArbiterSpacing.s2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 16, color: Colors.white),
              const SizedBox(width: ArbiterSpacing.s2),
              Flexible(
                child: Text(
                  'Çevrimdışısın — yükleme ve analiz bağlantı gelene kadar duraklatıldı.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: ArbiterFontSize.bodySm,
                    fontWeight: ArbiterFontWeights.medium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
