import 'package:flutter/material.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/report.dart';
import '../core/chess/notation.dart';
import '../theme/arbiter_tokens.dart';
import 'desk_ui.dart';

String displayMove(PlyAnalysis p, NotationLocale locale, bool localized) {
  if (p.state.isResolved) {
    return localized ? localizeSan(p.san!, locale) : p.san!;
  }
  return p.raw.isEmpty ? '?' : p.raw;
}

Color plyColor(BuildContext context, PlyState s) {
  final c = context.arbiterColors;
  return switch (s) {
    PlyState.ok => c.contentPrimary,
    PlyState.notationWarning => c.contentPrimary,
    PlyState.ambiguous => c.feedbackWarning,
    PlyState.illegal || PlyState.unparseable => c.feedbackDanger,
    PlyState.empty => c.feedbackWarning,
    PlyState.notReached => c.contentTertiary,
    PlyState.afterGameEnd => c.contentTertiary,
  };
}

String plyStateLabel(PlyState s) => switch (s) {
      PlyState.ok => 'Yasal',
      PlyState.notationWarning => 'Yasal (yazım uyarısı)',
      PlyState.ambiguous => 'Belirsiz',
      PlyState.illegal => 'Kural dışı',
      PlyState.unparseable => 'Okunamadı',
      PlyState.empty => 'Boş hücre',
      PlyState.notReached => 'Değerlendirilemedi',
      PlyState.afterGameEnd => 'Oyun bittikten sonra',
    };

/// Scoresheet-style move table: one row per move number. Keeps the selected
/// ply scrolled into view.
class MoveGrid extends StatefulWidget {
  const MoveGrid({
    super.key,
    required this.analysis,
    required this.locale,
    required this.localized,
    required this.selectedPly,
    required this.onSelect,
    this.onEdit,
  });

  final GameAnalysis analysis;
  final NotationLocale locale;
  final bool localized;
  final int selectedPly;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onEdit;

  @override
  State<MoveGrid> createState() => _MoveGridState();
}

class _MoveGridState extends State<MoveGrid> {
  static const _rowHeight = 50.0;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void didUpdateWidget(MoveGrid old) {
    super.didUpdateWidget(old);
    if (old.selectedPly != widget.selectedPly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal({bool animate = true}) {
    if (!_controller.hasClients || widget.selectedPly < 0) return;
    final pos = _controller.position;
    final top = (widget.selectedPly ~/ 2) * _rowHeight;
    if (top >= pos.pixels && top + _rowHeight <= pos.pixels + pos.viewportDimension) {
      return;
    }
    final target = (top - pos.viewportDimension / 2 + _rowHeight / 2)
        .clamp(0.0, pos.maxScrollExtent);
    animate
        ? _controller.animateTo(target,
            duration: ArbiterMotionDuration.standard, curve: Curves.easeOut)
        : _controller.jumpTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final analysis = widget.analysis;
    final locale = widget.locale;
    final localized = widget.localized;
    final selectedPly = widget.selectedPly;
    final onSelect = widget.onSelect;
    final onEdit = widget.onEdit;
    final plies = analysis.plies;
    if (plies.isEmpty) {
      return const EmptyHint(
          icon: Icons.edit_note, title: 'Henüz hamle yok',
          body: 'Tahtada oynayın veya karneden yazın.');
    }
    final rows = (plies.length + 1) ~/ 2;
    return ListView.builder(
      controller: _controller,
      itemExtent: _rowHeight,
      itemCount: rows,
      itemBuilder: (context, r) {
        return Container(
          color: r.isOdd ? c.surfaceInset.withAlpha(90) : null,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text('${r + 1}.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: ArbiterFontFamily.mono,
                        color: c.contentTertiary,
                        fontSize: ArbiterFontSize.notationMd)),
              ),
              const SizedBox(width: ArbiterSpacing.s2),
              for (final i in [r * 2, r * 2 + 1])
                Expanded(
                  child: i < plies.length
                      ? _Cell(
                          ply: plies[i],
                          text: displayMove(plies[i], locale, localized),
                          selected: i == selectedPly,
                          onTap: () => onSelect(i),
                          onLongPress: onEdit == null ? null : () => onEdit(i),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.ply,
    required this.text,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final PlyAnalysis ply;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final color = plyColor(context, ply.state);
    final problem = ply.state.isProblem;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Material(
        color: selected
            ? c.accentPrimaryMuted
            : problem
                ? color.withAlpha(24)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(ArbiterRadii.sm),
          onTap: onTap,
          onLongPress: onLongPress,
          onDoubleTap: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ArbiterRadii.sm),
              border: Border.all(
                color: selected
                    ? c.accentPrimary
                    : problem
                        ? color.withAlpha(140)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: ArbiterFontFamily.mono,
                      fontSize: ArbiterFontSize.notationLg,
                      fontWeight: problem ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                      decoration: ply.state == PlyState.afterGameEnd
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (ply.state == PlyState.notationWarning)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.edit_note, size: 14, color: c.contentTertiary),
                  ),
                if (problem)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.error, size: 14, color: color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RuleTimeline extends StatelessWidget {
  const RuleTimeline({super.key, required this.analysis, required this.onSelectPly});
  final GameAnalysis analysis;
  final ValueChanged<int> onSelectPly;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final events = analysis.events;
    return ListView(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      children: [
        DeskCard(
          padding: const EdgeInsets.all(ArbiterSpacing.s3),
          child: Row(
            children: [
              Icon(
                analysis.hasProblems
                    ? Icons.report_problem
                    : analysis.end != null
                        ? Icons.flag
                        : Icons.verified,
                color: analysis.hasProblems
                    ? c.feedbackDanger
                    : analysis.end != null
                        ? c.accentPrimary
                        : c.feedbackSuccess,
              ),
              const SizedBox(width: ArbiterSpacing.s3),
              Expanded(child: Text(analysisStatus(analysis))),
            ],
          ),
        ),
        const SizedBox(height: ArbiterSpacing.s3),
        if (events.isEmpty)
          const EmptyHint(
            icon: Icons.rule,
            title: 'Kural olayı yok',
            body: 'Mat, pat, tekrar, 50/75 hamle veya hatalı hamle bulunmadı.',
          ),
        for (final e in events) ...[
          _EventTile(event: e, onTap: () => onSelectPly(e.ply)),
          const SizedBox(height: ArbiterSpacing.s2),
        ],
        const SizedBox(height: ArbiterSpacing.s2),
        Text(
          'Üç tekrar ve 50 hamle yalnızca TALEP hakkıdır; oyuncu talep etmezse oyun '
          'devam eder. Beş tekrar, 75 hamle, mat, pat ve ölü konum oyunu '
          'KENDİLİĞİNDEN bitirir.',
          style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
        ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onTap});
  final RuleEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final (color, icon, label) = natureStyle(context, event.nature);
    return DeskCard(
      onTap: onTap,
      borderColor: color.withAlpha(90),
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(label, color: color, icon: icon),
              const Spacer(),
              Icon(Icons.chevron_right, color: c.contentTertiary, size: 18),
            ],
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          Text(event.title,
              style: TextStyle(
                  color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
          const SizedBox(height: ArbiterSpacing.s1),
          Text(event.detail, style: TextStyle(color: c.contentSecondary, height: 1.35)),
          if (event.articles.isNotEmpty) ...[
            const SizedBox(height: ArbiterSpacing.s2),
            ArticleChips(event.articles),
          ],
        ],
      ),
    );
  }
}

class RepetitionPanel extends StatelessWidget {
  const RepetitionPanel({super.key, required this.analysis, required this.onSelectPosition});
  final GameAnalysis analysis;
  final ValueChanged<int> onSelectPosition;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final groups = analysis.repetitions;
    if (groups.isEmpty) {
      return const EmptyHint(
        icon: Icons.repeat,
        title: 'Tekrarlanan konum yok',
        body: 'Aynı konum (9.2.2) iki veya daha fazla kez oluşursa burada listelenir.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      children: [
        for (final g in groups) ...[
          DeskCard(
            padding: const EdgeInsets.all(ArbiterSpacing.s3),
            borderColor: g.occurrences.length >= 3 ? c.feedbackWarning.withAlpha(120) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pill('${g.occurrences.length}×',
                        color: g.occurrences.length >= 5
                            ? c.feedbackDanger
                            : g.occurrences.length >= 3
                                ? c.feedbackWarning
                                : c.contentSecondary),
                    const SizedBox(width: ArbiterSpacing.s2),
                    Expanded(
                      child: Text(
                        g.occurrences.length >= 5
                            ? 'Beş tekrar — otomatik beraberlik'
                            : g.occurrences.length >= 3
                                ? 'Üç tekrar — talep edilebilir'
                                : 'Tekrar eden konum',
                        style: TextStyle(
                            color: c.contentPrimary,
                            fontWeight: ArbiterFontWeights.semibold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ArbiterSpacing.s2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final i in g.occurrences)
                      ActionChip(
                        label: Text(positionLabel(i)),
                        onPressed: () => onSelectPosition(i),
                      ),
                  ],
                ),
                for (final nm in g.nearMisses) ...[
                  const SizedBox(height: ArbiterSpacing.s2),
                  InkWell(
                    onTap: () => onSelectPosition(nm.positionIndex),
                    child: Bullet('${positionLabel(nm.positionIndex)}: ${nm.reason}',
                        icon: Icons.warning_amber, color: c.feedbackWarning),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: ArbiterSpacing.s2),
        ],
      ],
    );
  }
}

class LogPanel extends StatelessWidget {
  const LogPanel({super.key, required this.record});
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    if (record.log.isEmpty) {
      return const EmptyHint(
        icon: Icons.history_edu,
        title: 'Hakem kaydı boş',
        body: 'Talep kontrolleri, kural dışı hamleler ve düzeltmeler burada '
            'zaman damgasıyla saklanır ve rapora eklenir.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      children: [
        for (final e in record.log.reversed) ...[
          DeskCard(
            padding: const EdgeInsets.all(ArbiterSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pill(e.kind.label, color: c.accentPrimary),
                    const Spacer(),
                    Text(formatDateTime(e.at),
                        style: TextStyle(
                            color: c.contentTertiary,
                            fontSize: ArbiterFontSize.labelSm)),
                  ],
                ),
                const SizedBox(height: ArbiterSpacing.s2),
                Text(e.title,
                    style: TextStyle(
                        color: c.contentPrimary,
                        fontWeight: ArbiterFontWeights.semibold)),
                if (e.detail.isNotEmpty) ...[
                  const SizedBox(height: ArbiterSpacing.s1),
                  Text(e.detail, style: TextStyle(color: c.contentSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: ArbiterSpacing.s2),
        ],
      ],
    );
  }
}
