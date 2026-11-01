import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import 'desk_ui.dart';

/// Lets the action run if the user is Pro, or spends one of the free weekly
/// uses; otherwise opens the paywall. Returns true when the action may run.
Future<bool> ensureProAccess(
    BuildContext context, WidgetRef ref, ProFeature feature) async {
  if (ref.read(entitlementProvider).isPro) return true;
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

enum ToolAccess { full, preview }

/// For the arbiter tools used during a live dispute: never blocks with a
/// paywall. Pro or a free weekly use → [ToolAccess.full]; otherwise the tool
/// still shows its verdict headline ([ToolAccess.preview]) and locks the
/// reasoning, logging and report behind [LockedDetails].
Future<ToolAccess> requestToolAccess(
    BuildContext context, WidgetRef ref, ProFeature feature) async {
  if (ref.read(entitlementProvider).isPro) {
    return ToolAccess.full;
  }
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
    return ToolAccess.full;
  }
  return ToolAccess.preview;
}

/// Shown under a preview verdict: what Pro adds, with a non-blocking CTA.
class LockedDetails extends ConsumerWidget {
  const LockedDetails({super.key, required this.feature, required this.onUnlocked});
  final ProFeature feature;
  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    return Container(
      margin: const EdgeInsets.only(top: ArbiterSpacing.s3),
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      decoration: BoxDecoration(
        color: c.surfaceInset,
        borderRadius: BorderRadius.circular(ArbiterRadii.md),
        border: Border.all(color: c.surfaceElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: c.accentPrimary),
              const SizedBox(width: ArbiterSpacing.s2),
              Expanded(
                child: Text('Gerekçe, madde dayanakları, hakem kaydı ve rapor Pro\'da',
                    style: TextStyle(
                        color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
              ),
            ],
          ),
          const SizedBox(height: ArbiterSpacing.s1),
          Text(
            'Bu haftaki $kFreeWeeklyToolUses ücretsiz kullanım bitti; karar başlığını '
            'her zaman görürsünüz. Haklar Pazartesi yenilenir.',
            style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm),
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          FilledButton.tonal(
            onPressed: () async {
              final bought = await context.push<bool>('/pro?feature=${feature.name}');
              if (bought ?? false) onUnlocked();
            },
            child: const Text('Turnuva Haftası ile aç'),
          ),
        ],
      ),
    );
  }
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
