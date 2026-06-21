import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/arbiter_theme.dart';
import '../theme/arbiter_tokens.dart';

/// Scrollable list of moves with per-move confidence dots and status badges.
///
/// Status logic (the backend is the authority; this only renders it):
///   is_legal && !needs_manual_review → success ✓  (auto-resolved)
///   is_legal &&  needs_manual_review → warning ⚠  (needs arbiter check)
///   !is_legal                        → danger  ✗  (illegal / OCR failure)
class MoveList extends StatefulWidget {
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
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  // Fixed row height keeps scroll-position math exact for auto-follow.
  static const double _rowExtent = 52;

  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(MoveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToSelected();
    }
  }

  /// Keep the selected move centred while navigating with the arrows.
  void _scrollToSelected() {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target =
        (widget.selectedIndex * _rowExtent) - (viewport - _rowExtent) / 2;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: ArbiterMotionDuration.standard,
      curve: ArbiterMotionEasing.expressive,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    if (widget.moves.isEmpty) {
      return Center(
        child: Text('No moves yet.',
            style: TextStyle(color: c.contentSecondary)),
      );
    }

    return ListView.builder(
      controller: _controller,
      itemExtent: _rowExtent,
      itemCount: widget.moves.length,
      padding: const EdgeInsets.symmetric(vertical: ArbiterSpacing.s2),
      itemBuilder: (context, index) {
        final move = widget.moves[index];
        return _MoveListTile(
          move: move,
          isSelected: index == widget.selectedIndex,
          onTap: () => widget.onMoveTap(index),
        );
      },
    );
  }
}

class _MoveListTile extends StatelessWidget {
  final MoveAnalysis move;
  final bool isSelected;
  final VoidCallback onTap;

  const _MoveListTile({
    required this.move,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final statusColor = _statusColor(c, move);
    final dotColor = _confidenceColor(c, move);
    final reasonCode = _primaryReasonCode(move);

    final moveLabel = move.selected_san ?? move.ocr_raw_text;
    final moveNumber =
        move.color == 'white' ? '${move.move_number}.' : '${move.move_number}…';

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ArbiterMotionDuration.fast,
        decoration: BoxDecoration(
          color: isSelected ? c.accentPrimaryMuted : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? c.accentPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: ArbiterSpacing.s3, vertical: ArbiterSpacing.s2),
        child: Row(
          children: [
            // Confidence dot at the leading edge (only when uncertain).
            SizedBox(
              width: 12,
              child: dotColor == null
                  ? null
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: dotColor, shape: BoxShape.circle),
                    ),
            ),

            // Fixed-width move number.
            SizedBox(
              width: 40,
              child: Text(
                moveNumber,
                style: ArbiterNotationStyles.small(context).copyWith(
                  color: isSelected ? c.accentPrimary : c.contentTertiary,
                ),
              ),
            ),

            // SAN text.
            Expanded(
              child: Text(
                moveLabel,
                style: ArbiterNotationStyles.medium(context).copyWith(
                  color: move.is_legal ? c.contentPrimary : c.feedbackDanger,
                  decoration: move.is_legal && move.needs_manual_review
                      ? TextDecoration.underline
                      : null,
                  decorationColor: c.confidenceHigh,
                ),
              ),
            ),

            // OCR confidence + reason pill (only when uncertain).
            if (move.needs_manual_review || !move.is_legal)
              Padding(
                padding: const EdgeInsets.only(right: ArbiterSpacing.s2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${(move.confidence * 100).toStringAsFixed(0)}%',
                        style: ArbiterNotationStyles.small(context)),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: _reasonTooltip(reasonCode),
                      child: _ReasonPill(
                        label: _reasonLabel(reasonCode),
                        color: reasonCode == 'illegal_move'
                            ? c.feedbackDanger
                            : c.feedbackWarning,
                      ),
                    ),
                  ],
                ),
              ),

            // FIDE alerts count badge.
            if (move.fide_alerts.isNotEmpty) ...[
              _AlertBadge(count: move.fide_alerts.length, color: c.feedbackWarning),
              const SizedBox(width: ArbiterSpacing.s2),
            ],

            Icon(_statusIcon(move), size: 16, color: statusColor),
          ],
        ),
      ),
    );
  }

  Color _statusColor(ArbiterColors c, MoveAnalysis m) {
    if (!m.is_legal) return c.feedbackDanger;
    if (m.needs_manual_review) return c.feedbackWarning;
    return c.feedbackSuccess;
  }

  Color? _confidenceColor(ArbiterColors c, MoveAnalysis m) {
    if (!m.is_legal) return c.feedbackDanger;
    if (!m.needs_manual_review && m.confidence >= 0.95) return null;
    if (m.confidence < 0.5) return c.confidenceLow;
    if (m.confidence < 0.8) return c.confidenceMedium;
    return c.confidenceHigh;
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

class _AlertBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _AlertBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(220),
        borderRadius: BorderRadius.circular(ArbiterRadii.full),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF0B0C10),
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
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
