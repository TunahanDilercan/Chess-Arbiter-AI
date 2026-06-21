import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/arbiter_theme.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/findings_panel.dart';
import '../widgets/move_list.dart';

class GameScreen extends ConsumerWidget {
  final String gameId;

  /// When non-null the game data is used directly and no API fetch is made.
  /// Used by the manual-entry flow where the analysis result is already in hand.
  final GameAnalysisResponse? preloadedGame;

  const GameScreen({super.key, required this.gameId, this.preloadedGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameAsync = preloadedGame != null
        ? AsyncValue.data(preloadedGame!)
        : ref.watch(gameProvider(gameId));
    final selectedIdx = ref.watch(selectedMoveIndexProvider);

    MoveAnalysis? selectedMove;
    gameAsync.whenData((game) {
      if (game.moves.isNotEmpty) {
        selectedMove = game.moves[selectedIdx.clamp(0, game.moves.length - 1)];
      }
    });
    // Correction needs a crop image; manual-entry moves have none.
    final hasCrop = selectedMove?.crop_image_url != null;
    final needsCorrection = selectedMove != null &&
        hasCrop &&
        (selectedMove!.needs_manual_review || !selectedMove!.is_legal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Analysis'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/'),
        ),
        actions: [
          gameAsync.whenOrNull(
                data: (game) => _DrawDecisionChip(
                  drawDecision: game.draw_decision,
                  drawReason: game.draw_reason,
                  arbiterMustEnd: game.arbiter_must_end,
                  requiresPlayerClaim: game.requires_player_claim,
                ),
              ) ??
              const SizedBox.shrink(),
          gameAsync.whenOrNull(
                data: (game) => _StatusChip(status: game.status),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: gameAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(gameProvider(gameId)),
        ),
        data: (game) => _GameBody(game: game, gameId: gameId),
      ),
      floatingActionButton: needsCorrection
          ? FloatingActionButton.extended(
              onPressed: () => context
                  .push('/game/$gameId/correct/${selectedMove!.ply_index}'),
              icon: const Icon(Icons.edit),
              label: const Text('Correct Move'),
            )
          : null,
    );
  }
}

class _GameBody extends ConsumerWidget {
  final GameAnalysisResponse game;
  final String gameId;

  const _GameBody({required this.game, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (game.status == 'processing' || game.status == 'queued') {
      return const _StillProcessingView();
    }
    if (game.moves.isEmpty) {
      return _EmptyMovesView(status: game.status);
    }

    final selectedIdx = ref.watch(selectedMoveIndexProvider);
    final moves = game.moves;
    final currentMove = moves[selectedIdx.clamp(0, moves.length - 1)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        return isWide
            ? _WideLayout(
                game: game,
                currentMove: currentMove,
                selectedIdx: selectedIdx,
                moves: moves,
                ref: ref)
            : _NarrowLayout(
                game: game,
                currentMove: currentMove,
                selectedIdx: selectedIdx,
                moves: moves,
                ref: ref);
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  final GameAnalysisResponse game;
  final MoveAnalysis currentMove;
  final int selectedIdx;
  final List<MoveAnalysis> moves;
  final WidgetRef ref;

  const _WideLayout({
    required this.game,
    required this.currentMove,
    required this.selectedIdx,
    required this.moves,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(ArbiterSpacing.s2),
                  child: _SwipeableBoard(
                    currentMove: currentMove,
                    selectedIdx: selectedIdx,
                    total: moves.length,
                    ref: ref,
                  ),
                ),
              ),
              _MoveNavigator(
                  selectedIdx: selectedIdx, total: moves.length, ref: ref),
              _StatsBar(stats: game.stats),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: _TabsSection(
              game: game, selectedIdx: selectedIdx, moves: moves, ref: ref),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final GameAnalysisResponse game;
  final MoveAnalysis currentMove;
  final int selectedIdx;
  final List<MoveAnalysis> moves;
  final WidgetRef ref;

  const _NarrowLayout({
    required this.game,
    required this.currentMove,
    required this.selectedIdx,
    required this.moves,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(ArbiterSpacing.s2),
          child: _SwipeableBoard(
            currentMove: currentMove,
            selectedIdx: selectedIdx,
            total: moves.length,
            ref: ref,
          ),
        ),
        _MoveNavigator(selectedIdx: selectedIdx, total: moves.length, ref: ref),
        Expanded(
          child: _TabsSection(
              game: game, selectedIdx: selectedIdx, moves: moves, ref: ref),
        ),
        _StatsBar(stats: game.stats),
      ],
    );
  }
}

/// Board wrapper: swipe left → next move, swipe right → previous move.
class _SwipeableBoard extends StatelessWidget {
  final MoveAnalysis currentMove;
  final int selectedIdx;
  final int total;
  final WidgetRef ref;

  const _SwipeableBoard({
    required this.currentMove,
    required this.selectedIdx,
    required this.total,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final notifier = ref.read(selectedMoveIndexProvider.notifier);
        if (velocity < -200 && selectedIdx < total - 1) {
          notifier.state = selectedIdx + 1;
        } else if (velocity > 200 && selectedIdx > 0) {
          notifier.state = selectedIdx - 1;
        }
      },
      child: ChessBoard(
        fen: currentMove.fen_after,
        lastMoveFrom: _from(currentMove),
        lastMoveTo: _to(currentMove),
        errorSquare: !currentMove.is_legal ? _to(currentMove) : null,
        checkSquare: currentMove.check_square,
        palette: ref.watch(settingsProvider).palette,
      ),
    );
  }

  String? _from(MoveAnalysis m) {
    final uci = m.selected_uci;
    if (uci == null || uci.length < 4) return null;
    return uci.substring(0, 2);
  }

  String? _to(MoveAnalysis m) {
    final uci = m.selected_uci;
    if (uci == null || uci.length < 4) return null;
    return uci.substring(2, 4);
  }
}

class _TabsSection extends StatelessWidget {
  final GameAnalysisResponse game;
  final int selectedIdx;
  final List<MoveAnalysis> moves;
  final WidgetRef ref;

  const _TabsSection({
    required this.game,
    required this.selectedIdx,
    required this.moves,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            dividerColor: c.surfaceElevated,
            labelColor: c.accentPrimary,
            unselectedLabelColor: c.contentTertiary,
            indicatorColor: c.accentPrimary,
            tabs: [
              Tab(text: 'Moves (${moves.length})'),
              Tab(text: 'Findings (${game.findings.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                MoveList(
                  moves: moves,
                  selectedIndex: selectedIdx,
                  onMoveTap: (i) =>
                      ref.read(selectedMoveIndexProvider.notifier).state = i,
                ),
                FindingsPanel(findings: game.findings),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveNavigator extends StatelessWidget {
  final int selectedIdx;
  final int total;
  final WidgetRef ref;

  const _MoveNavigator({
    required this.selectedIdx,
    required this.total,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final canPrev = selectedIdx > 0;
    final canNext = selectedIdx < total - 1;

    void setIdx(int i) =>
        ref.read(selectedMoveIndexProvider.notifier).state = i;

    return Container(
      color: c.surfaceRaised,
      padding: const EdgeInsets.symmetric(
          horizontal: ArbiterSpacing.s2, vertical: ArbiterSpacing.s1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: canPrev ? () => setIdx(0) : null,
            icon: const Icon(Icons.first_page),
            iconSize: 28,
            color: c.contentPrimary,
            disabledColor: c.contentTertiary,
          ),
          IconButton(
            onPressed: canPrev ? () => setIdx(selectedIdx - 1) : null,
            icon: const Icon(Icons.chevron_left),
            iconSize: 32,
            color: c.contentPrimary,
            disabledColor: c.contentTertiary,
          ),
          Text('${selectedIdx + 1} / $total',
              style: ArbiterNotationStyles.medium(context)),
          IconButton(
            onPressed: canNext ? () => setIdx(selectedIdx + 1) : null,
            icon: const Icon(Icons.chevron_right),
            iconSize: 32,
            color: c.contentPrimary,
            disabledColor: c.contentTertiary,
          ),
          IconButton(
            onPressed: canNext ? () => setIdx(total - 1) : null,
            icon: const Icon(Icons.last_page),
            iconSize: 28,
            color: c.contentPrimary,
            disabledColor: c.contentTertiary,
          ),
        ],
      ),
    );
  }
}

class _StillProcessingView extends StatelessWidget {
  const _StillProcessingView();

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: c.accentPrimary),
            const SizedBox(height: ArbiterSpacing.s5),
            Text('Game is still processing…',
                style: TextStyle(
                    color: c.contentPrimary,
                    fontSize: ArbiterFontSize.headingSm,
                    fontWeight: ArbiterFontWeights.semibold)),
            const SizedBox(height: ArbiterSpacing.s2),
            Text(
              'Check the processing screen for progress.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.contentSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMovesView extends StatelessWidget {
  final String status;
  const _EmptyMovesView({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: c.contentTertiary, size: 56),
            const SizedBox(height: ArbiterSpacing.s4),
            Text('No moves found',
                style: TextStyle(
                    fontFamily: ArbiterFontFamily.display,
                    color: c.contentPrimary,
                    fontSize: ArbiterFontSize.headingMd,
                    fontWeight: ArbiterFontWeights.semibold)),
            const SizedBox(height: ArbiterSpacing.s2),
            Text(
              status == 'failed'
                  ? 'Processing failed — the scoresheet could not be read.'
                  : 'The scoresheet was processed but no moves were extracted.\n'
                      'The image may be too faint or at an unsupported angle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.contentSecondary),
            ),
            const SizedBox(height: ArbiterSpacing.s6),
            ElevatedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload Another'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final GameStats stats;
  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Container(
      color: c.surfaceRaised,
      padding: const EdgeInsets.symmetric(
          horizontal: ArbiterSpacing.s4, vertical: ArbiterSpacing.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
              label: 'Total',
              value: stats.total_moves.toString(),
              color: c.contentPrimary),
          _StatItem(
              label: 'Auto',
              value: stats.auto_resolved.toString(),
              color: c.feedbackSuccess),
          _StatItem(
              label: 'Review',
              value: stats.manual_review_required.toString(),
              color: c.feedbackWarning),
          _StatItem(
              label: 'Illegal',
              value: stats.illegal_moves.toString(),
              color: c.feedbackDanger),
          _StatItem(
              label: 'Avg OCR',
              value: '${(stats.ocr_avg_confidence * 100).toStringAsFixed(0)}%',
              color: c.contentSecondary),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontFamily: ArbiterFontFamily.mono,
                color: color,
                fontWeight: ArbiterFontWeights.semibold,
                fontSize: ArbiterFontSize.headingSm)),
        Text(label,
            style: TextStyle(
                color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final (color, label) = switch (status) {
      'completed' => (c.feedbackSuccess, 'Done'),
      'needs_review' => (c.feedbackWarning, 'Review'),
      'failed' => (c.feedbackDanger, 'Failed'),
      _ => (c.accentPrimary, status),
    };

    return Padding(
      padding: const EdgeInsets.only(right: ArbiterSpacing.s3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ArbiterRadii.sm),
            border: Border.all(color: color),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
                color: color,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight: ArbiterFontWeights.semibold,
                letterSpacing: 0.6),
          ),
        ),
      ),
    );
  }
}

class _DrawDecisionChip extends StatelessWidget {
  final String drawDecision;
  final String? drawReason;
  final bool arbiterMustEnd;
  final bool requiresPlayerClaim;

  const _DrawDecisionChip({
    required this.drawDecision,
    required this.drawReason,
    required this.arbiterMustEnd,
    required this.requiresPlayerClaim,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    if (drawDecision == 'none') return const SizedBox.shrink();

    // FIDE tier colour: automatic → danger, claimable → warning.
    final (color, label) = switch (drawDecision) {
      'automatic_draw' => (c.feedbackDanger, 'Automatic Draw / Otomatik'),
      'claimable_draw' => (c.feedbackWarning, 'Claimable / Talep Edilebilir'),
      _ => (c.contentTertiary, drawDecision),
    };

    final guidance = arbiterMustEnd
        ? 'Arbiter must end game / Hakem oyunu bitirmeli'
        : requiresPlayerClaim
            ? 'Game continues until claim / Talep edilene kadar devam eder'
            : 'No draw action / Berabere aksiyonu yok';

    final tooltip =
        drawReason == null ? guidance : '$guidance\nReason: $drawReason';

    return Padding(
      padding: const EdgeInsets.only(right: ArbiterSpacing.s2),
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ArbiterRadii.sm),
              border: Border.all(color: color),
            ),
            child: Text(
              label,
              style: TextStyle(
                  color: color,
                  fontSize: ArbiterFontSize.labelSm,
                  fontWeight: ArbiterFontWeights.semibold),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.feedbackDanger.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.error_outline, color: c.feedbackDanger, size: 36),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            Text('Failed to Load Game',
                style: TextStyle(
                    fontFamily: ArbiterFontFamily.display,
                    color: c.contentPrimary,
                    fontSize: ArbiterFontSize.headingMd,
                    fontWeight: ArbiterFontWeights.semibold)),
            const SizedBox(height: ArbiterSpacing.s2),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.contentSecondary)),
            const SizedBox(height: ArbiterSpacing.s5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('Home'),
                ),
                const SizedBox(width: ArbiterSpacing.s3),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
