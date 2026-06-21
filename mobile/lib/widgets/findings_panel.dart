import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/arbiter_tokens.dart';

// ── FIDE rule reference dictionary ───────────────────────────────────────────
//
// Keys match FindingType string values from the backend.
// Each entry carries the article label shown on the card and the full
// official FIDE Laws of Chess text shown in the expanded accordion.

typedef _RuleRef = ({String article, String fullText});

const Map<String, _RuleRef> _kFideRules = {
  'illegal_move': (
    article: 'FIDE Art. 3.10',
    fullText:
        'An illegal move is a move that is not permitted by these Laws. '
        'An illegal move which has been completed must be corrected if at all '
        'possible. The move which violates the Laws must be replaced by a legal '
        'move. If the player has touched a piece, that piece must be moved or '
        'captured if possible; otherwise the player shall lose the right to '
        'claim that the opponent touched a piece.',
  ),
  'threefold_claim_available': (
    article: 'FIDE Art. 9.2.1',
    fullText:
        'The game is drawn, upon a correct claim by a player whose turn it is '
        'to move, when the same position, for at least the third time (not '
        'necessarily by a repetition of moves), is about to appear, if the '
        'player first writes the move, which shall result in this position, on '
        'their scoresheet and declares to the arbiter the intention to make '
        'this move, or has just appeared, and the player whose turn it is to '
        'move claims the draw.',
  ),
  'fifty_claim_available': (
    article: 'FIDE Art. 9.3',
    fullText:
        'The game is drawn, upon a correct claim by the player who is to move, '
        'if the last 50 consecutive moves have been made by each player without '
        'the movement of any pawn and without any capture. If the claim is '
        'correct, the game is drawn; if incorrect, the arbiter shall add two '
        'minutes to the opponent\'s remaining thinking time. The position '
        'resulting from the wrongful claim shall then be reinstated.',
  ),
  'fivefold_automatic': (
    article: 'FIDE Art. 9.6.1',
    fullText:
        'The game is drawn when the same position has appeared, as in 9.2.2, '
        'for at least five times. This is determined by the arbiter or through '
        'the chess clock (if it has an appropriate function). The draw is '
        'mandatory and cannot be prevented by either player — no claim is '
        'required.',
  ),
  'seventy_five_automatic': (
    article: 'FIDE Art. 9.6.2',
    fullText:
        'The game is drawn when each player has completed 75 moves without the '
        'movement of any pawn and without any capture. The draw is mandatory '
        'and cannot be prevented by either player — no claim is required. If '
        'the last move resulted in checkmate, that result takes precedence.',
  ),
  'checkmate': (
    article: 'FIDE Art. 1.2',
    fullText:
        'The objective of each player is to place the opponent\'s king "under '
        'attack" in such a way that the opponent has no legal move. The player '
        'who achieves this goal is said to have "checkmated" the opponent\'s '
        'king and wins the game. Leaving one\'s own king under attack, '
        'exposing one\'s own king to attack and "capturing" the opponent\'s '
        'king are not allowed.',
  ),
  'stalemate': (
    article: 'FIDE Art. 5.2.1',
    fullText:
        'The game is drawn when the player to move has no legal move and his '
        'king is not in check. The game is said to end in stalemate. This '
        'immediately ends the game.',
  ),
  'insufficient_material': (
    article: 'FIDE Art. 5.2.2',
    fullText:
        'The game is drawn when a position has arisen in which neither player '
        'can checkmate the opponent\'s king with any series of legal moves. '
        'The game is said to end in a draw due to insufficient mating material.',
  ),
};

// ── Color helper ──────────────────────────────────────────────────────────────
//
// FIDE tier (the single source of truth is the backend's is_automatic flag):
//   AUTOMATIC / ILLEGAL → danger; CLAIMABLE → warning.
Color _tierColor(ArbiterColors c, bool isAutomatic) =>
    isAutomatic ? c.feedbackDanger : c.feedbackWarning;

/// Lists all FIDE rule findings for a game, grouped and colour-coded by tier.
///
/// 🔴 AUTOMATIC — game-ending events enforced unconditionally (illegal move,
///    fivefold repetition, 75-move rule, checkmate, stalemate, insufficient
///    material). The arbiter must end the game.
///
/// 🟡 CLAIMABLE — player opportunities that require a claim (threefold
///    repetition, 50-move rule). The arbiter is notified but the game does NOT
///    end automatically. This distinction must never be blurred.
class FindingsPanel extends StatefulWidget {
  final List<RuleFinding> findings;

  const FindingsPanel({super.key, required this.findings});

  @override
  State<FindingsPanel> createState() => _FindingsPanelState();
}

class _FindingsPanelState extends State<FindingsPanel> {
  final Set<int> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final textTheme = Theme.of(context).textTheme;

    if (widget.findings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ArbiterSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  color: c.feedbackSuccess, size: 48),
              const SizedBox(height: ArbiterSpacing.s4),
              Text('No FIDE findings.', style: textTheme.bodyLarge),
              const SizedBox(height: ArbiterSpacing.s1),
              Text('All moves validated without issues.',
                  style: textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    final visibleIndexed = widget.findings
        .asMap()
        .entries
        .where((e) => !_dismissed.contains(e.key))
        .toList();

    if (visibleIndexed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, color: c.feedbackSuccess, size: 40),
            const SizedBox(height: ArbiterSpacing.s3),
            Text('All findings dismissed.', style: textTheme.bodySmall),
          ],
        ),
      );
    }

    final automatic = visibleIndexed.where((e) => e.value.is_automatic).toList();
    final claimable =
        visibleIndexed.where((e) => !e.value.is_automatic).toList();

    return ListView(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      children: [
        if (automatic.isNotEmpty) ...[
          _SectionHeader(
            color: c.feedbackDanger,
            icon: Icons.gavel,
            label: 'Stop Play / Oyunu Durdur',
            sublabel: 'Automatic result: arbiter must end game',
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          ...automatic.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
              child: _DismissibleCard(
                listIndex: e.key,
                finding: e.value,
                onDismiss: () => setState(() => _dismissed.add(e.key)),
              ),
            ),
          ),
        ],
        if (automatic.isNotEmpty && claimable.isNotEmpty)
          const SizedBox(height: ArbiterSpacing.s2),
        if (claimable.isNotEmpty) ...[
          _SectionHeader(
            color: c.feedbackWarning,
            icon: Icons.flag_outlined,
            label: 'Claimable Draw / Talep Edilebilir',
            sublabel: 'Game continues until a player claim is made',
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          ...claimable.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
              child: _DismissibleCard(
                listIndex: e.key,
                finding: e.value,
                onDismiss: () => setState(() => _dismissed.add(e.key)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String sublabel;

  const _SectionHeader({
    required this.color,
    required this.icon,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: ArbiterSpacing.s1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: ArbiterFontSize.labelSm,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(sublabel,
                  style: TextStyle(
                      color: c.contentTertiary,
                      fontSize: ArbiterFontSize.labelSm)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DismissibleCard extends StatelessWidget {
  final int listIndex;
  final RuleFinding finding;
  final VoidCallback onDismiss;

  const _DismissibleCard({
    required this.listIndex,
    required this.finding,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Dismissible(
      key: ValueKey(listIndex),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ArbiterSpacing.s5),
        decoration: BoxDecoration(
          color: c.feedbackDanger.withAlpha(180),
          borderRadius: BorderRadius.circular(ArbiterRadii.lg),
        ),
        child: Icon(Icons.delete_outline, color: c.contentInverse),
      ),
      onDismissed: (_) => onDismiss(),
      child: _FindingCard(finding: finding),
    );
  }
}

class _FindingCard extends StatefulWidget {
  final RuleFinding finding;
  const _FindingCard({required this.finding});

  @override
  State<_FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<_FindingCard> {
  bool _ruleExpanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final finding = widget.finding;
    final tierColor = _tierColor(c, finding.is_automatic);
    final ruleRef = _kFideRules[finding.type];
    final moveLabel =
        'Ply ${finding.ply_index} · Move ${(finding.ply_index ~/ 2) + 1}';
    final icon = _iconFor(finding.type);

    return AnimatedContainer(
      duration: ArbiterMotionDuration.standard,
      // The thick left accent is drawn as a Positioned child (Flutter cannot
      // anti-alias rounded corners when side widths differ); clipBehavior
      // rounds the bar to the card's corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(ArbiterRadii.lg),
        border: Border.all(color: tierColor.withAlpha(40)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: tierColor.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: tierColor, size: 17),
                      ),
                      const SizedBox(width: ArbiterSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    _titleFor(finding.type),
                                    style: TextStyle(
                                      color: c.contentPrimary,
                                      fontSize: ArbiterFontSize.headingSm,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: ArbiterSpacing.s1),
                                _TierBadge(
                                  isAutomatic: finding.is_automatic,
                                  color: tierColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: ArbiterSpacing.s1),
                            Text(
                              finding.description,
                              style: TextStyle(
                                color: c.contentSecondary,
                                fontSize: ArbiterFontSize.bodyMd,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: ArbiterSpacing.s1),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 11, color: c.contentTertiary),
                                const SizedBox(width: 3),
                                Text(moveLabel,
                                    style: TextStyle(
                                        color: c.contentTertiary,
                                        fontSize: ArbiterFontSize.labelSm)),
                                if (ruleRef != null) ...[
                                  const Spacer(),
                                  _FideChip(
                                    article: ruleRef.article,
                                    expanded: _ruleExpanded,
                                    color: tierColor,
                                    onTap: () => setState(
                                        () => _ruleExpanded = !_ruleExpanded),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedCrossFade(
                  duration: ArbiterMotionDuration.standard,
                  crossFadeState: _ruleExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(height: ArbiterSpacing.s3),
                  secondChild: ruleRef != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Divider(
                                  color: tierColor.withAlpha(60), height: 16),
                              Row(
                                children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 13, color: tierColor),
                                  const SizedBox(width: 5),
                                  Text(
                                    ruleRef.article,
                                    style: TextStyle(
                                      color: tierColor,
                                      fontSize: ArbiterFontSize.labelSm,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: ArbiterSpacing.s1),
                              Text(
                                ruleRef.fullText,
                                style: TextStyle(
                                  color: c.contentSecondary,
                                  fontSize: ArbiterFontSize.bodyMd,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(height: ArbiterSpacing.s3),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: tierColor),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) {
    return switch (type) {
      'checkmate' => Icons.emoji_events,
      'stalemate' => Icons.balance,
      'insufficient_material' => Icons.remove_circle_outline,
      'fivefold_automatic' => Icons.repeat,
      'seventy_five_automatic' => Icons.timer_off,
      'threefold_claim_available' => Icons.repeat,
      'fifty_claim_available' => Icons.timer,
      'illegal_move' => Icons.block,
      'ocr_uncertain' => Icons.help_outline,
      _ => Icons.info_outline,
    };
  }

  static String _titleFor(String type) {
    return switch (type) {
      'checkmate' => 'Checkmate',
      'stalemate' => 'Stalemate',
      'insufficient_material' => 'Insufficient Material',
      'fivefold_automatic' => 'Fivefold Repetition',
      'seventy_five_automatic' => '75-Move Rule',
      'threefold_claim_available' => 'Threefold Repetition',
      'fifty_claim_available' => '50-Move Rule',
      'illegal_move' => 'Illegal Move',
      'ocr_uncertain' => 'OCR Uncertain',
      _ => type.replaceAll('_', ' '),
    };
  }
}

class _TierBadge extends StatelessWidget {
  final bool isAutomatic;
  final Color color;

  const _TierBadge({required this.isAutomatic, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        border: Border.all(color: color),
      ),
      child: Text(
        isAutomatic ? 'AUTO / OTOMATIK' : 'CLAIM / TALEP',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _FideChip extends StatelessWidget {
  final String article;
  final bool expanded;
  final Color color;
  final VoidCallback onTap;

  const _FideChip({
    required this.article,
    required this.expanded,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(expanded ? 50 : 25),
          borderRadius: BorderRadius.circular(ArbiterRadii.full),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              article,
              style: TextStyle(
                color: color,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 12, color: color),
          ],
        ),
      ),
    );
  }
}
