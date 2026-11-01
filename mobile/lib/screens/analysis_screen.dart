import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/report.dart';
import '../core/chess/notation.dart';
import '../core/chess/position.dart';
import '../core/chess/types.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../services/share_service.dart';
import '../theme/arbiter_theme.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/analysis_panels.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';
import 'game_info_sheet.dart';
import 'move_edit_sheet.dart';
import 'tool_sheets.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, required this.gameId});
  final String gameId;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  int? _cursor; // ply index; -1 = start position
  bool _flipped = false;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int _defaultCursor(GameAnalysis a) =>
      a.stopPly ?? (a.end?.ply ?? a.plies.length - 1);

  void _select(int ply) => setState(() => _cursor = ply);

  void _selectPosition(GameAnalysis a, int positionIndex) =>
      _select(positionIndex - 1);

  /// Position index used by the arbiter tools for the current cursor.
  int _toolPosition(GameAnalysis a, int cursor) {
    if (cursor < 0) return 0;
    final p = a.plies[cursor];
    return p.state.isResolved ? cursor + 1 : a.resolvedCount;
  }

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(gameRecordProvider(widget.gameId));
    final analysis = ref.watch(analysisProvider(widget.gameId));
    final games = ref.watch(gamesProvider);
    if (record == null || analysis == null) {
      return Scaffold(
        appBar: AppBar(),
        body: games.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyHint(icon: Icons.search_off, title: 'Oyun bulunamadı'),
      );
    }
    final cursor = (_cursor ?? _defaultCursor(analysis))
        .clamp(-1, analysis.plies.length - 1);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.title, overflow: TextOverflow.ellipsis),
            Text(
              [
                if (record.event.isNotEmpty) record.event,
                if (record.round.isNotEmpty) 'Tur ${record.round}',
                if (record.board.isNotEmpty) 'Masa ${record.board}',
                record.timeControl.label,
              ].join(' · '),
              style: TextStyle(
                  fontSize: ArbiterFontSize.labelSm,
                  color: context.arbiterColors.contentTertiary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Oyun bilgileri',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGameInfoSheet(context, record),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(v, record, analysis),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pgn', child: Text('PGN paylaş')),
              const PopupMenuItem(value: 'text', child: Text('Raporu metin olarak paylaş')),
              const PopupMenuItem(value: 'pdf', child: Text('PDF hakem raporu')),
              if (analysis.stopPly == null && analysis.end == null)
                const PopupMenuItem(value: 'continue', child: Text('Tahtada devam et')),
              const PopupMenuItem(value: 'delete', child: Text('Oyunu sil')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final board = _BoardArea(
          analysis: analysis,
          locale: record.locale,
          cursor: cursor,
          flipped: _flipped,
          onFlip: () => setState(() => _flipped = !_flipped),
          onSelect: _select,
        );
        final tools = _ToolBar(
          onTool: (t) => _openTool(t, record, analysis, cursor),
        );
        final tabs = _Tabs(
          controller: _tabs,
          record: record,
          analysis: analysis,
          cursor: cursor,
          onSelect: _select,
          onSelectPosition: (i) => _selectPosition(analysis, i),
          onEdit: (ply) =>
              showMoveEditSheet(context, record: record, analysis: analysis, ply: ply),
        );
        final banner = _StatusBanner(
          analysis: analysis,
          onFix: (ply) {
            _select(ply);
            showMoveEditSheet(context, record: record, analysis: analysis, ply: ply);
          },
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: (box.maxWidth * 0.48).clamp(360, 560),
                child: ListView(
                  padding: const EdgeInsets.all(ArbiterSpacing.s3),
                  children: [banner, board, const SizedBox(height: 8), tools],
                ),
              ),
              Expanded(child: tabs),
            ],
          );
        }
        return NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    ArbiterSpacing.s3, ArbiterSpacing.s2, ArbiterSpacing.s3, 0),
                child: Column(children: [banner, board, tools]),
              ),
            ),
          ],
          body: tabs,
        );
      }),
    );
  }

  Future<void> _menu(String v, GameRecord rec, GameAnalysis a) async {
    switch (v) {
      case 'pgn':
        await sharePgn(context, rec, a);
      case 'text':
        if (await ensureProAccess(context, ref, ProFeature.report) && mounted) {
          await shareReportText(context, ref, rec, a);
        }
      case 'pdf':
        if (await ensureProAccess(context, ref, ProFeature.report) && mounted) {
          await shareReportPdf(context, ref, rec, a);
        }
      case 'continue':
        context.push('/board?game=${rec.id}');
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Oyun silinsin mi?'),
            content: const Text('Bu işlem geri alınamaz.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Sil')),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(gamesProvider.notifier).delete(rec.id);
          if (mounted) context.go('/');
        }
    }
  }

  void _openTool(ArbiterTool t, GameRecord rec, GameAnalysis a, int cursor) {
    var pos = _toolPosition(a, cursor);
    final claimable = a.events.where((e) => e.nature == RuleNature.claimable);
    final here = claimable.where((e) => e.ply == cursor);
    if (t == ArbiterTool.claim && claimable.isNotEmpty && (_cursor == null || here.isNotEmpty)) {
      // Untouched cursor: jump to the latest moment a draw could be claimed.
      pos = (here.isNotEmpty ? here.first : claimable.last).ply + 1;
    }
    switch (t) {
      case ArbiterTool.claim:
        context.push('/game/${rec.id}/claim?pos=$pos');
      case ArbiterTool.illegal:
        final ply = a.plies.isEmpty
            ? 0
            : (a.stopPly != null && a.plies[a.stopPly!].state == PlyState.illegal
                ? a.stopPly!
                : cursor.clamp(0, a.plies.length - 1));
        context.push('/game/${rec.id}/illegal?ply=$ply');
      case ArbiterTool.flag:
        showFlagFallSheet(context, record: rec, analysis: a, positionIndex: pos);
      case ArbiterTool.compare:
        context.push('/compare?game=${rec.id}');
    }
  }
}

enum ArbiterTool {
  claim('Talep kontrolü', Icons.balance),
  illegal('Kural dışı hamle', Icons.gpp_maybe_outlined),
  flag('Süre aşımı', Icons.timer_off_outlined),
  compare('Karne karşılaştır', Icons.compare_arrows);

  const ArbiterTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.onTool});
  final ValueChanged<ArbiterTool> onTool;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final t in ArbiterTool.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(t.icon, size: 18, color: c.accentPrimary),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(t.label), const ProBadge()],
                ),
                onPressed: () => onTool(t),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.analysis, required this.onFix});
  final GameAnalysis analysis;
  final ValueChanged<int> onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final a = analysis;
    final (color, icon) = a.hasProblems
        ? (c.feedbackDanger, Icons.report_problem)
        : a.end != null
            ? (c.accentPrimary, Icons.flag)
            : (c.feedbackSuccess, Icons.verified);
    final claimable = a.events.where((e) => e.nature == RuleNature.claimable).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
      child: DeskCard(
        color: color.withAlpha(20),
        borderColor: color.withAlpha(100),
        padding: const EdgeInsets.symmetric(
            horizontal: ArbiterSpacing.s3, vertical: ArbiterSpacing.s2),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: ArbiterSpacing.s2),
            Expanded(
              child: Text(
                analysisStatus(a) +
                    (claimable > 0 ? ' $claimable talep fırsatı var.' : ''),
                style: TextStyle(color: c.contentPrimary, fontSize: ArbiterFontSize.bodySm),
              ),
            ),
            if (a.stopPly != null)
              TextButton(onPressed: () => onFix(a.stopPly!), child: const Text('Düzelt')),
          ],
        ),
      ),
    );
  }
}

class _BoardArea extends ConsumerWidget {
  const _BoardArea({
    required this.analysis,
    required this.locale,
    required this.cursor,
    required this.flipped,
    required this.onFlip,
    required this.onSelect,
  });

  final GameAnalysis analysis;
  final NotationLocale locale;
  final int cursor;
  final bool flipped;
  final VoidCallback onFlip;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final a = analysis;
    final p = cursor >= 0 ? a.plies[cursor] : null;
    final Position pos = p == null ? a.positions.first : (p.after ?? p.before);
    final move = p?.move;
    final total = a.plies.length;
    final kingInCheck = pos.isCheck ? Square.name(pos.kingSquare(pos.turn)) : null;
    final caption = p == null
        ? 'Başlangıç konumu'
        : p.state.isResolved
            ? '${p.label} ${displayMove(p, locale, ref.watch(settingsProvider).showLocalized)}'
            : '${p.label} "${p.raw}" — ${plyStateLabel(p.state)} (önceki konum)';

    final screenH = MediaQuery.sizeOf(context).height;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: narrow ? (screenH * 0.42).clamp(260.0, 440.0) : 440),
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200 && cursor < total - 1) onSelect(cursor + 1);
              if (v > 200 && cursor > -1) onSelect(cursor - 1);
            },
            child: ChessBoard(
              fen: pos.fen,
              lastMoveFrom: move == null ? null : Square.name(move.from),
              lastMoveTo: move == null ? null : Square.name(move.to),
              checkSquare: kingInCheck,
              flipped: flipped,
              palette: ref.watch(settingsProvider).palette,
            ),
          ),
        ),
        const SizedBox(height: ArbiterSpacing.s2),
        Text(caption,
            textAlign: TextAlign.center,
            style: ArbiterNotationStyles.medium(context).copyWith(
                color: p != null && p.state.isProblem ? c.feedbackDanger : null)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                tooltip: 'Başa',
                onPressed: cursor > -1 ? () => onSelect(-1) : null,
                icon: const Icon(Icons.first_page)),
            IconButton(
                tooltip: 'Geri',
                onPressed: cursor > -1 ? () => onSelect(cursor - 1) : null,
                icon: const Icon(Icons.chevron_left, size: 30)),
            IconButton(
                tooltip: 'İleri',
                onPressed: cursor < total - 1 ? () => onSelect(cursor + 1) : null,
                icon: const Icon(Icons.chevron_right, size: 30)),
            IconButton(
                tooltip: 'Sona',
                onPressed: cursor < total - 1 ? () => onSelect(total - 1) : null,
                icon: const Icon(Icons.last_page)),
            IconButton(
                tooltip: 'Tahtayı çevir',
                onPressed: onFlip,
                icon: const Icon(Icons.swap_vert)),
          ],
        ),
      ],
    );
  }
}

class _Tabs extends ConsumerWidget {
  const _Tabs({
    required this.controller,
    required this.record,
    required this.analysis,
    required this.cursor,
    required this.onSelect,
    required this.onSelectPosition,
    required this.onEdit,
  });

  final TabController controller;
  final GameRecord record;
  final GameAnalysis analysis;
  final int cursor;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onSelectPosition;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final localized = ref.watch(settingsProvider.select((s) => s.showLocalized));
    final errors = analysis.events.where((e) => e.nature != RuleNature.info).length;
    return Column(
      children: [
        TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.accentPrimary,
          unselectedLabelColor: c.contentTertiary,
          indicatorColor: c.accentPrimary,
          dividerColor: c.surfaceElevated,
          tabs: [
            Tab(text: 'Hamleler (${analysis.plies.length})'),
            Tab(text: 'Kurallar ($errors)'),
            Tab(text: 'Tekrarlar (${analysis.repetitions.where((g) => g.occurrences.length > 1).length})'),
            Tab(text: 'Kayıt (${record.log.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              Column(
                children: [
                  Expanded(
                    child: MoveGrid(
                      analysis: analysis,
                      locale: record.locale,
                      localized: localized,
                      selectedPly: cursor,
                      onSelect: onSelect,
                      onEdit: onEdit,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(ArbiterSpacing.s2),
                    child: Text('Düzeltmek için hamleye uzun basın.',
                        style: TextStyle(
                            color: c.contentTertiary,
                            fontSize: ArbiterFontSize.labelSm)),
                  ),
                ],
              ),
              RuleTimeline(analysis: analysis, onSelectPly: onSelect),
              RepetitionPanel(analysis: analysis, onSelectPosition: onSelectPosition),
              LogPanel(record: record),
            ],
          ),
        ),
      ],
    );
  }
}
