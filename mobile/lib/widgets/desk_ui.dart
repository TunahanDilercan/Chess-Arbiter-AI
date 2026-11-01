import 'package:flutter/material.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/fide.dart';
import '../core/arbiter/report.dart' show trUpper;
import '../theme/arbiter_tokens.dart';

TextStyle displayStyle(BuildContext context, double size) => TextStyle(
      fontFamily: ArbiterFontFamily.display,
      fontSize: size,
      fontWeight: ArbiterFontWeights.semibold,
      color: context.arbiterColors.contentPrimary,
    );

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              trUpper(text),
              style: TextStyle(
                color: c.contentTertiary,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight: ArbiterFontWeights.semibold,
                letterSpacing: 0.9,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class DeskCard extends StatelessWidget {
  const DeskCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(ArbiterSpacing.s4),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Material(
      color: color ?? c.surfaceRaised,
      borderRadius: BorderRadius.circular(ArbiterRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ArbiterRadii.lg),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ArbiterRadii.lg),
            border: Border.all(color: borderColor ?? c.surfaceElevated),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color, this.icon, this.filled = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withAlpha(28),
        borderRadius: BorderRadius.circular(ArbiterRadii.full),
        border: Border.all(color: color.withAlpha(filled ? 255 : 110)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : color,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight: ArbiterFontWeights.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable article references; a tap shows the Turkish summary.
class ArticleChips extends StatelessWidget {
  const ArticleChips(this.articles, {super.key});
  final List<FideArticle> articles;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final unique = <String, FideArticle>{for (final a in articles) a.number: a};
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in unique.values)
          InkWell(
            borderRadius: BorderRadius.circular(ArbiterRadii.full),
            onTap: () => showArticle(context, a),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.surfaceInset,
                borderRadius: BorderRadius.circular(ArbiterRadii.full),
                border: Border.all(color: c.surfaceElevated),
              ),
              child: Text(
                a.label,
                style: TextStyle(
                  fontFamily: ArbiterFontFamily.mono,
                  color: c.contentSecondary,
                  fontSize: ArbiterFontSize.labelSm,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showArticle(BuildContext context, FideArticle a) {
  final c = context.arbiterColors;
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('${a.label} — ${a.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.summary),
          const SizedBox(height: ArbiterSpacing.s3),
          Text(
            'Özettir; resmî metin: ${Fide.lawsVersion}.',
            style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
      ],
    ),
  );
}

(Color, IconData, String) natureStyle(BuildContext context, RuleNature n) {
  final c = context.arbiterColors;
  return switch (n) {
    RuleNature.automaticEnd => (c.feedbackDanger, Icons.flag, 'OTOMATİK BİTİŞ'),
    RuleNature.claimable => (c.feedbackWarning, Icons.pan_tool_alt, 'TALEP EDİLEBİLİR'),
    RuleNature.error => (c.feedbackDanger, Icons.error_outline, 'HAKEM KARARI'),
    RuleNature.info => (c.contentTertiary, Icons.info_outline, 'BİLGİ'),
  };
}

/// Big pass/fail card used by the arbiter tools.
class VerdictCard extends StatelessWidget {
  const VerdictCard({
    super.key,
    required this.ok,
    required this.headline,
    this.neutral = false,
    this.subtitle,
    this.children = const [],
  });

  final bool ok;
  final bool neutral;
  final String headline;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final color = neutral
        ? c.feedbackWarning
        : ok
            ? c.feedbackSuccess
            : c.feedbackDanger;
    return DeskCard(
      color: color.withAlpha(18),
      borderColor: color.withAlpha(120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                neutral
                    ? Icons.help_outline
                    : ok
                        ? Icons.check_circle
                        : Icons.cancel,
                color: color,
                size: 28,
              ),
              const SizedBox(width: ArbiterSpacing.s3),
              Expanded(child: Text(headline, style: displayStyle(context, 18))),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: ArbiterSpacing.s2),
            Text(subtitle!, style: TextStyle(color: c.contentSecondary)),
          ],
          if (children.isNotEmpty) const SizedBox(height: ArbiterSpacing.s3),
          ...children,
        ],
      ),
    );
  }
}

class Bullet extends StatelessWidget {
  const Bullet(this.text, {super.key, this.icon = Icons.circle, this.color});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: icon == Icons.circle ? 7 : 2, right: 8),
            child: Icon(icon,
                size: icon == Icons.circle ? 6 : 16, color: color ?? c.contentTertiary),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(color: c.contentPrimary, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.title, this.body});
  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.all(ArbiterSpacing.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: c.contentTertiary),
          const SizedBox(height: ArbiterSpacing.s3),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
          if (body != null) ...[
            const SizedBox(height: ArbiterSpacing.s1),
            Text(body!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.contentSecondary)),
          ],
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// Lays out content in a centred column no wider than [maxWidth].
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Scrolls the widget holding [key] into view after the next frame.
void revealAfterFrame(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: ArbiterMotionDuration.expressive,
          curve: Curves.easeOutCubic,
          alignment: 0.05);
    }
  });
}
