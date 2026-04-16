import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

/// Scrollable list of moves with per-move status badges.
///
/// Status badge logic:
///   is_legal && !needs_manual_review → green ✓  (auto-resolved)
///   is_legal &&  needs_manual_review → amber ⚠  (needs arbiter check)
///   !is_legal                        → red ✗    (illegal / OCR failure)
class MoveList extends StatelessWidget {
  final List<MoveAnalysis> moves;
  final int selectedIndex;
  final ValueChanged<int> onMoveTap;

  const MoveList({
    super.key,
    required this.moves,
    required this.selectedIndex,
    required this.onMoveTap,
  });

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) {
      return Center(
        child: Text(
          'No moves yet.',
          style: AppTextStyles.bodyDim,
        ),
      );
    }

    return ListView.builder(
      itemCount: moves.length,
      itemBuilder: (context, index) {
        final move = moves[index];
        final isSelected = index == selectedIndex;
        final isEven = index.isEven;

        return _MoveListTile(
          move: move,
          isSelected: isSelected,
          isEven: isEven,
          onTap: () => onMoveTap(index),
        );
      },
    );
  }
}

// ── Move tile ─────────────────────────────────────────────────────────────────

class _MoveListTile extends StatelessWidget {
  final MoveAnalysis move;
  final bool isSelected;
  final bool isEven;
  final VoidCallback onTap;

  const _MoveListTile({
    required this.move,
    required this.isSelected,
    required this.isEven,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(move);
    final statusIcon = _statusIcon(move);
    final reasonCode = _primaryReasonCode(move);

    final moveLabel = move.selected_san ?? move.ocr_raw_text;
    final moveNumber = move.color == 'white'
        ? '${move.move_number}.'
        : '${move.move_number}…';

    // Alternating row backgrounds
    Color rowBg;
    if (isSelected) {
      rowBg = AppColors.primaryLight.withAlpha(50);
    } else {
      rowBg = isEven ? AppColors.surface : AppColors.background;
    }

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: rowBg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // ── Fixed-width move number ──────────────────────────────────
            SizedBox(
              width: 44,
              child: Text(
                moveNumber,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.onSurfaceDim,
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),

            // ── SAN text ─────────────────────────────────────────────────
            Expanded(
              child: Text(
                moveLabel,
                style: AppTextStyles.mono.copyWith(
                  fontSize: 15,
                  color: move.is_legal
                      ? AppColors.onBackground
                      : AppColors.illegal,
                ),
              ),
            ),

            // ── OCR confidence (only when uncertain) ──────────────────────
            if (move.needs_manual_review || !move.is_legal)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(move.confidence * 100).toStringAsFixed(0)}%',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: _reasonTooltip(reasonCode),
                      child: _ReasonPill(
                        label: _reasonLabel(reasonCode),
                        color: reasonCode == 'illegal_move'
                            ? AppColors.illegal
                            : AppColors.review,
                      ),
                    ),
                  ],
                ),
              ),

            // ── FIDE alerts count badge ───────────────────────────────────
            if (move.fide_alerts.isNotEmpty) ...[
              _AlertBadge(count: move.fide_alerts.length),
              const SizedBox(width: 6),
            ],

            // ── Status icon (right-aligned) ───────────────────────────────
            Icon(statusIcon, size: 16, color: statusColor),
          ],
        ),
      ),
    );
  }

  Color _statusColor(MoveAnalysis m) {
    if (!m.is_legal) return AppColors.illegal;
    if (m.needs_manual_review) return AppColors.review;
    return AppColors.legal;
  }

  IconData _statusIcon(MoveAnalysis m) {
    if (!m.is_legal) return Icons.close;
    if (m.needs_manual_review) return Icons.warning_amber_rounded;
    return Icons.check;
  }

  String _primaryReasonCode(MoveAnalysis m) {
    if (!m.is_legal) return 'illegal_move';
    if (m.review_reasons.isNotEmpty) return m.review_reasons.first;
    if (m.confidence < 0.85) return 'below_threshold';
    return 'legacy_needs_review';
  }

  String _reasonLabel(String code) {
    return switch (code) {
      'illegal_move' => 'Illegal / Gecersiz',
      'manual_parse_fallback' => 'Manual fallback / Manuel fallback',
      'below_threshold' => 'Low score / Dusuk skor',
      'low_ocr_confidence' => 'Low OCR / Dusuk OCR',
      'ambiguous_top_two' => 'Ambiguous / Belirsiz',
      _ => 'Needs review / Inceleme',
    };
  }

  String _reasonTooltip(String code) {
    return switch (code) {
      'illegal_move' =>
        'Illegal move detected. Arbiter must correct this move.\nGecersiz hamle algilandi. Hakem hamleyi duzeltmeli.',
      'manual_parse_fallback' =>
        'Manual SAN could not be parsed directly; fuzzy fallback was used.\nManuel SAN dogrudan parse edilemedi; fuzzy fallback kullanildi.',
      'below_threshold' =>
        'Match score is below threshold and needs arbiter confirmation.\nEslesme skoru esik altinda, hakem onayi gerekiyor.',
      'low_ocr_confidence' =>
        'OCR confidence is low; verify this move manually.\nOCR guveni dusuk; hamleyi manuel dogrulayin.',
      'ambiguous_top_two' =>
        'Two legal candidates are too close; arbiter should choose.\nIki yasal aday birbirine cok yakin; hakem secmeli.',
      _ =>
        'Manual review required for this move.\nBu hamle icin manuel inceleme gerekiyor.',
    };
  }
}

// ── Alert badge ───────────────────────────────────────────────────────────────

class _AlertBadge extends StatelessWidget {
  final int count;
  const _AlertBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.review.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          fontSize: 10,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ReasonPill extends StatelessWidget {
  final String label;
  final Color color;

  const _ReasonPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
