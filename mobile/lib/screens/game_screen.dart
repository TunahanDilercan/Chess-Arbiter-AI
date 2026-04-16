import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chess_board.dart';
import '../widgets/findings_panel.dart';
import '../widgets/move_list.dart';

class GameScreen extends ConsumerWidget {
  final String gameId;

  /// When non-null the game data is used directly and no API fetch is made.
  /// Used by the manual-entry flow where the analysis result is already in hand.
  final GameAnalysisResponse? preloadedGame;

  const GameScreen({
    super.key,
    required this.gameId,
    this.preloadedGame,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use preloaded data when available, otherwise fetch from the server.
    final gameAsync = preloadedGame != null
        ? AsyncValue.data(preloadedGame!)
        : ref.watch(gameProvider(gameId));
    final selectedIdx = ref.watch(selectedMoveIndexProvider);

    // Determine whether the currently selected move needs correction.
    MoveAnalysis? selectedMove;
    gameAsync.whenData((game) {
      if (game.moves.isNotEmpty) {
        selectedMove = game.moves[selectedIdx.clamp(0, game.moves.length - 1)];
      }
    });
    // Correction requires a crop image to display in the correction screen.
    // Manual-entry moves have no crop, so the button is hidden for them.
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
              onPressed: () => context.push(
                '/game/$gameId/correct/${selectedMove!.ply_index}',
              ),
              icon: const Icon(Icons.edit),
              label: const Text('Correct Move'),
            )
          : null,
    );
  }
}

// ── Game body ──────────────────────────────────────────────────────────────────

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
                ref: ref,
              )
            : _NarrowLayout(
                game: game,
                currentMove: currentMove,
                selectedIdx: selectedIdx,
                moves: moves,
                ref: ref,
              );
      },
    );
  }

}

// ── Wide layout (tablet / landscape) ─────────────────────────────────────────

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
        // ── Board + navigator ────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: ChessBoard(
                    fen: currentMove.fen_after,
                    lastMoveFrom: _from(currentMove),
                    lastMoveTo: _to(currentMove),
                    errorSquare:
                        !currentMove.is_legal ? _to(currentMove) : null,
                  ),
                ),
              ),
              _MoveNavigator(
                selectedIdx: selectedIdx,
                total: moves.length,
                ref: ref,
              ),
              _StatsBar(stats: game.stats),
            ],
          ),
        ),

        // ── Tabs ─────────────────────────────────────────────────────────
        Expanded(
          flex: 4,
          child: _TabsSection(game: game, selectedIdx: selectedIdx, moves: moves, ref: ref),
        ),
      ],
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

// ── Narrow layout (phone) ─────────────────────────────────────────────────────

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
        // ── Board ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ChessBoard(
            fen: currentMove.fen_after,
            lastMoveFrom: _from(currentMove),
            lastMoveTo: _to(currentMove),
            errorSquare: !currentMove.is_legal ? _to(currentMove) : null,
          ),
        ),

        // ── Navigation arrows ─────────────────────────────────────────
        _MoveNavigator(
          selectedIdx: selectedIdx,
          total: moves.length,
          ref: ref,
        ),

        // ── Tabs ──────────────────────────────────────────────────────
        Expanded(
          child: _TabsSection(
            game: game,
            selectedIdx: selectedIdx,
            moves: moves,
            ref: ref,
          ),
        ),

        // ── Stats bar ─────────────────────────────────────────────────
        _StatsBar(stats: game.stats),
      ],
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

// ── Tabs section ─────────────────────────────────────────────────────────────

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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            dividerColor: AppColors.surfaceVar,
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
                  onMoveTap: (i) {
                    ref.read(selectedMoveIndexProvider.notifier).state = i;
                  },
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

// ── Move navigator ────────────────────────────────────────────────────────────

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
    final canPrev = selectedIdx > 0;
    final canNext = selectedIdx < total - 1;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── First ──────────────────────────────────────────────────
          IconButton(
            onPressed: canPrev
                ? () => ref.read(selectedMoveIndexProvider.notifier).state = 0
                : null,
            icon: const Icon(Icons.first_page),
            iconSize: 28,
            color: AppColors.onSurface,
            disabledColor: AppColors.onSurfaceFaint,
          ),

          // ── Previous ───────────────────────────────────────────────
          IconButton(
            onPressed: canPrev
                ? () => ref.read(selectedMoveIndexProvider.notifier).state =
                      selectedIdx - 1
                : null,
            icon: const Icon(Icons.chevron_left),
            iconSize: 32,
            color: AppColors.onSurface,
            disabledColor: AppColors.onSurfaceFaint,
          ),

          // ── Counter ────────────────────────────────────────────────
          Text(
            '${selectedIdx + 1} / $total',
            style: AppTextStyles.mono.copyWith(fontSize: 14),
          ),

          // ── Next ──────────────────────────────────────────────────
          IconButton(
            onPressed: canNext
                ? () => ref.read(selectedMoveIndexProvider.notifier).state =
                      selectedIdx + 1
                : null,
            icon: const Icon(Icons.chevron_right),
            iconSize: 32,
            color: AppColors.onSurface,
            disabledColor: AppColors.onSurfaceFaint,
          ),

          // ── Last ──────────────────────────────────────────────────
          IconButton(
            onPressed: canNext
                ? () => ref.read(selectedMoveIndexProvider.notifier).state =
                      total - 1
                : null,
            icon: const Icon(Icons.last_page),
            iconSize: 28,
            color: AppColors.onSurface,
            disabledColor: AppColors.onSurfaceFaint,
          ),
        ],
      ),
    );
  }
}

// ── Still processing view ─────────────────────────────────────────────────────

class _StillProcessingView extends StatelessWidget {
  const _StillProcessingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Game is still processing…',
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Check the processing screen for progress.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyDim,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty moves view ──────────────────────────────────────────────────────────

class _EmptyMovesView extends StatelessWidget {
  final String status;
  const _EmptyMovesView({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: AppColors.onSurfaceDim, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No moves found',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              status == 'failed'
                  ? 'Processing failed — the scoresheet could not be read.'
                  : 'The scoresheet was processed but no moves were extracted.\n'
                      'The image may be too faint or at an unsupported angle.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyDim,
            ),
            const SizedBox(height: AppSpacing.xl),
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

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final GameStats stats;
  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Total',
            value: stats.total_moves.toString(),
            color: AppColors.onSurface,
          ),
          _StatItem(
            label: 'Auto',
            value: stats.auto_resolved.toString(),
            color: AppColors.legal,
          ),
          _StatItem(
            label: 'Review',
            value: stats.manual_review_required.toString(),
            color: AppColors.review,
          ),
          _StatItem(
            label: 'Illegal',
            value: stats.illegal_moves.toString(),
            color: AppColors.illegal,
          ),
          _StatItem(
            label: 'Avg OCR',
            value: '${(stats.ocr_avg_confidence * 100).toStringAsFixed(0)}%',
            color: AppColors.onSurfaceDim,
          ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

// ── Status chip ────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'completed' => (AppColors.legal, 'Done'),
      'needs_review' => (AppColors.review, 'Review'),
      'failed' => (AppColors.illegal, 'Failed'),
      _ => (Colors.lightBlue, status),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.onBackground,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color.withAlpha(60),
        side: BorderSide(color: color.withAlpha(120)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    if (drawDecision == 'none') return const SizedBox.shrink();

    final (color, label) = switch (drawDecision) {
      'automatic_draw' => (
          AppColors.illegal,
          'Automatic Draw / Otomatik Berabere',
        ),
      'claimable_draw' => (
          AppColors.review,
          'Claimable Draw / Talep Edilebilir',
        ),
      _ => (AppColors.onSurfaceDim, drawDecision),
    };

    final guidance = arbiterMustEnd
        ? 'Arbiter must end game / Hakem oyunu bitirmeli'
        : requiresPlayerClaim
            ? 'Game continues until claim / Talep edilene kadar oyun devam eder'
            : 'No draw action / Berabere aksiyonu yok';

    final tooltip = drawReason == null
        ? guidance
        : '$guidance\nReason: $drawReason';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: Chip(
          label: Text(
            label,
            style: const TextStyle(
              color: AppColors.onBackground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: color.withAlpha(60),
          side: BorderSide(color: color.withAlpha(120)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Failed to Load Game', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyDim,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('Home'),
                ),
                const SizedBox(width: 12),
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
