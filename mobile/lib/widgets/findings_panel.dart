import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

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

// ── Color helpers ─────────────────────────────────────────────────────────────

/// Returns the tier color: red for AUTOMATIC/ILLEGAL, amber for CLAIMABLE.
Color _tierColor(bool isAutomatic) =>
    isAutomatic ? AppColors.illegal : AppColors.review;

// ── Public widget ─────────────────────────────────────────────────────────────

/// Lists all FIDE rule findings for a game, grouped and colour-coded by tier.
///
/// 🔴 RED  — AUTOMATIC findings: game-ending events enforced unconditionally
///           (illegal move, fivefold repetition, 75-move rule, checkmate,
///           stalemate, insufficient material).
///
/// 🟡 YELLOW — CLAIMABLE findings: player opportunities that require a claim
///           (threefold repetition, 50-move rule).  The arbiter is notified
///           but the game does NOT end automatically.
///
/// Each card:
///   • Displays the FIDE article number as a tappable chip.
///   • Expands to show the full official rule text (accordion).
///   • Can be dismissed (swipe left) to hide it for the session.
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
    if (widget.findings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.legal,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'No FIDE findings.',
                style: AppTextStyles.body.copyWith(color: AppColors.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'All moves validated without issues.',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      );
    }

    // Separate visible findings into the two tiers.
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
            const Icon(Icons.done_all, color: AppColors.legal, size: 40),
            const SizedBox(height: 12),
            Text('All findings dismissed.', style: AppTextStyles.bodyDim),
          ],
        ),
      );
    }

    final automatic = visibleIndexed
        .where((e) => e.value.is_automatic)
        .toList();
    final claimable = visibleIndexed
        .where((e) => !e.value.is_automatic)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (automatic.isNotEmpty) ...[
          _SectionHeader(
            color: AppColors.illegal,
            icon: Icons.error_outline,
            label: 'Stop Play / Oyunu Durdur',
            sublabel: 'Automatic result: arbiter must end game',
          ),
          const SizedBox(height: 8),
          ...automatic.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DismissibleCard(
                listIndex: e.key,
                finding: e.value,
                onDismiss: () => setState(() => _dismissed.add(e.key)),
              ),
            ),
          ),
        ],
        if (automatic.isNotEmpty && claimable.isNotEmpty)
          const SizedBox(height: 8),
        if (claimable.isNotEmpty) ...[
          _SectionHeader(
            color: AppColors.review,
            icon: Icons.info_outline,
            label: 'Claimable Draw / Talep Edilebilir',
            sublabel: 'Game continues until a player claim is made',
          ),
          const SizedBox(height: 8),
          ...claimable.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
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

// ── Section header ────────────────────────────────────────────────────────────

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
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(sublabel, style: AppTextStyles.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dismissible wrapper ───────────────────────────────────────────────────────

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
    return Dismissible(
      key: ValueKey(listIndex),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(180),
          borderRadius: AppRadius.cardAll,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: _FindingCard(finding: finding),
    );
  }
}

// ── Finding card (accordion) ──────────────────────────────────────────────────

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
    final finding = widget.finding;
    final tierColor = _tierColor(finding.is_automatic);
    final ruleRef = _kFideRules[finding.type];
    final moveLabel =
        'Ply ${finding.ply_index} · Move ${(finding.ply_index ~/ 2) + 1}';
    final (icon, _) = _iconFor(finding.type);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      // Border must be uniform when borderRadius is set — Flutter's paint engine
      // cannot anti-alias corners when side colors or widths differ.
      // The thick left accent is drawn as a Positioned child instead.
      // clipBehavior clips the Positioned bar to the card's rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: tierColor.withAlpha(40)),
      ),
      child: Stack(
        children: [
          // ── Content column ───────────────────────────────────────────────
          // Padded left by 3 px to leave room for the accent bar below.
          // This child drives the Stack (and therefore the card) height.
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon in coloured circle
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tierColor.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tierColor, size: 17),
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row + badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _titleFor(finding.type),
                              style: AppTextStyles.titleSmall
                                  .copyWith(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TierBadge(
                            isAutomatic: finding.is_automatic,
                            color: tierColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Short description
                      Text(
                        finding.description,
                        style:
                            AppTextStyles.bodyDim.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 6),

                      // Move location + FIDE article chip on same row
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 11,
                            color: AppColors.onSurfaceDim,
                          ),
                          const SizedBox(width: 3),
                          Text(moveLabel, style: AppTextStyles.caption),
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

          // ── Expandable rule text (accordion) ─────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _ruleExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 12),
            secondChild: ruleRef != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          color: tierColor.withAlpha(60),
                          height: 16,
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 13,
                              color: tierColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              ruleRef.article,
                              style: TextStyle(
                                color: tierColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ruleRef.fullText,
                          style: AppTextStyles.bodyDim.copyWith(
                            fontSize: 12,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(height: 12),
          ),
        ],
      ),
          ),

          // ── Left accent bar ──────────────────────────────────────────────
          // Positioned fills the full height of the Stack (= card height).
          // clipBehavior on the AnimatedContainer rounds its top/bottom corners.
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

  static (IconData, Color) _iconFor(String type) {
    return switch (type) {
      'checkmate' => (Icons.emoji_events, AppColors.accent),
      'stalemate' => (Icons.balance, Colors.lightBlue),
      'insufficient_material' =>
        (Icons.remove_circle_outline, Colors.lightBlue),
      'fivefold_automatic' => (Icons.repeat, AppColors.illegal),
      'seventy_five_automatic' => (Icons.timer_off, AppColors.illegal),
      'threefold_claim_available' => (Icons.repeat, AppColors.review),
      'fifty_claim_available' => (Icons.timer, AppColors.review),
      'illegal_move' => (Icons.block, AppColors.illegal),
      'ocr_uncertain' => (Icons.help_outline, AppColors.review),
      _ => (Icons.info_outline, AppColors.onSurfaceDim),
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

// ── Tier badge ────────────────────────────────────────────────────────────────

class _TierBadge extends StatelessWidget {
  final bool isAutomatic;
  final Color color;

  const _TierBadge({required this.isAutomatic, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isAutomatic ? 'AUTO / OTOMATIK' : 'CLAIM / TALEP',
        style: TextStyle(
          color: isAutomatic ? Colors.white : Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── FIDE article chip ─────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              article,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 12,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
