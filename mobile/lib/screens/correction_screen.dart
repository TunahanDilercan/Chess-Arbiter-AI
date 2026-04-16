import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_keyboard.dart';

class CorrectionScreen extends ConsumerStatefulWidget {
  final String gameId;
  final int plyIndex;

  const CorrectionScreen({
    super.key,
    required this.gameId,
    required this.plyIndex,
  });

  @override
  ConsumerState<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends ConsumerState<CorrectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSuggestions());
  }

  void _initSuggestions() {
    final gameAsync = ref.read(gameProvider(widget.gameId));
    gameAsync.whenData((game) {
      final move = game.moves
          .where((m) => m.ply_index == widget.plyIndex)
          .firstOrNull;
      if (move == null) return;

      final suggestions = <String>[];
      if (move.selected_san != null) {
        suggestions.add(move.selected_san!);
      }
      for (final c in move.ocr_candidates) {
        if (!suggestions.contains(c.text)) suggestions.add(c.text);
      }

      ref
          .read(correctionProvider.notifier)
          .setSuggestions(suggestions.take(5).toList());
    });
  }

  Future<void> _confirm() async {
    final input = ref.read(correctionProvider).input.trim();
    if (input.isEmpty) return;

    final notifier = ref.read(gameProvider(widget.gameId).notifier);
    await notifier.correctMove(widget.plyIndex, input);

    if (!mounted) return;
    final gameAsync = ref.read(gameProvider(widget.gameId));

    if (gameAsync.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Correction rejected: ${gameAsync.error}'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final correction = ref.watch(correctionProvider);

    // FEN of position before this ply (shows what piece is to move).
    final fen = gameAsync.whenOrNull(
      data: (game) {
        try {
          return game.moves
              .firstWhere((m) => m.ply_index == widget.plyIndex)
              .fen_before;
        } catch (_) {
          return null;
        }
      },
    );

    // OCR raw text for this move (shown as context).
    final ocrRaw = gameAsync.whenOrNull(
      data: (game) {
        try {
          return game.moves
              .firstWhere((m) => m.ply_index == widget.plyIndex)
              .ocr_raw_text;
        } catch (_) {
          return null;
        }
      },
    );

    final isLoading = gameAsync.isLoading || gameAsync.isRefreshing;
    final moveColor =
        widget.plyIndex % 2 == 0 ? 'White' : 'Black';
    final moveNumber = widget.plyIndex ~/ 2 + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Correct Move $moveNumber ($moveColor)',
          style: AppTextStyles.titleSmall,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Progress / loading bar ───────────────────────────────────
          if (isLoading)
            const LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceVar,
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Board showing position before move ───────────────
                  ClipRRect(
                    borderRadius: AppRadius.cardAll,
                    child: ChessBoard(
                      fen: fen ??
                          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── OCR raw text ─────────────────────────────────────
                  if (ocrRaw != null && ocrRaw.isNotEmpty) ...[
                    Text('OCR Read', style: AppTextStyles.label),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVar,
                        borderRadius: AppRadius.cardAll,
                        border: Border.all(color: AppColors.surfaceHigh),
                      ),
                      child: Text(
                        ocrRaw,
                        style: AppTextStyles.mono.copyWith(
                          color: AppColors.review,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Instruction ──────────────────────────────────────
                  Text(
                    isLoading
                        ? 'Submitting correction…'
                        : 'Enter the correct SAN for this position:',
                    style: AppTextStyles.bodyDim.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // ── Chess keyboard ───────────────────────────────────────────
          const Divider(height: 1),
          ChessKeyboard(
            currentInput: correction.input,
            suggestions: correction.suggestions,
            onChar: (c) =>
                ref.read(correctionProvider.notifier).addChar(c),
            onBackspace: () =>
                ref.read(correctionProvider.notifier).backspace(),
            onClear: () => ref.read(correctionProvider.notifier).clear(),
            onConfirm: isLoading ? () {} : _confirm,
          ),
        ],
      ),
    );
  }
}
