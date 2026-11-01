import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../monetization/plans.dart';
import '../providers/providers.dart';
import 'desk_ui.dart';

/// Lets the action run if the user is Pro, or spends one of the free weekly
/// uses; otherwise opens the paywall. Returns true when the action may run.
Future<bool> ensureProAccess(
    BuildContext context, WidgetRef ref, ProFeature feature) async {
  if (ref.read(entitlementProvider).valueOrNull?.isPro ?? false) return true;
  if (feature.usesFreeQuota) {
    final quota = ref.read(quotaProvider);
    if (await quota.tryConsume()) {
      ref.read(quotaTickProvider.notifier).state++;
      if (context.mounted) {
        final left = quota.remaining;
        showSnack(
            context,
            left > 0
                ? 'Ücretsiz deneme kullanıldı — bu hafta $left hakkınız kaldı.'
                : 'Bu haftanın son ücretsiz hakkını kullandınız. Pazartesi yenilenir.');
      }
      return true;
    }
  }
  if (!context.mounted) return false;
  final bought = await context.push<bool>('/pro?feature=${feature.name}');
  return bought ?? false;
}

class ProBadge extends ConsumerWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isPro(ref)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFA77F50),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('PRO',
          style: TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}
