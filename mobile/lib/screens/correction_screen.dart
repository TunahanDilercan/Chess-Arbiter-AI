import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/arbiter_theme.dart';
import '../theme/arbiter_tokens.dart';
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
      final move =
          game.moves.where((m) => m.ply_index == widget.plyIndex).firstOrNull;
      if (move == null) return;

      final suggestions = <String>[];
      if (move.selected_san != null) suggestions.add(move.selected_san!);
      for (final c in move.ocr_candidates) {
        if (!suggestions.contains(c.text)) suggestions.add(c.text);
      }
      ref
          .read(correctionProvider.notifier)
          .setSuggestions(suggestions.take(5).toList());
    });
  }

  // The backend re-validates the submitted SAN and returns the updated game.
  Future<void> _confirm() async {
    final input = ref.read(correctionProvider).input.trim();
    if (input.isEmpty) return;

    final notifier = ref.read(gameProvider(widget.gameId).notifier);
    await notifier.correctMove(widget.plyIndex, input);

    if (!mounted) return;
    final gameAsync = ref.read(gameProvider(widget.gameId));

    if (gameAsync.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Correction rejected: ${gameAsync.error}')),
      );
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final correction = ref.watch(correctionProvider);

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
    final moveColor = widget.plyIndex % 2 == 0 ? 'White' : 'Black';
    final moveNumber = widget.plyIndex ~/ 2 + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Correct Move $moveNumber ($moveColor)'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          if (isLoading)
            LinearProgressIndicator(
              color: c.accentPrimary,
              backgroundColor: c.surfaceElevated,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ArbiterSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ArbiterRadii.sm),
                    child: ChessBoard(
                      fen: fen ??
                          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                      palette: ref.watch(settingsProvider).palette,
                    ),
                  ),
                  const SizedBox(height: ArbiterSpacing.s4),
                  if (ocrRaw != null && ocrRaw.isNotEmpty) ...[
                    Text('OCR READ',
                        style: TextStyle(
                            color: c.contentTertiary,
                            fontSize: ArbiterFontSize.labelSm,
                            fontWeight: ArbiterFontWeights.semibold,
                            letterSpacing: 0.8)),
                    const SizedBox(height: ArbiterSpacing.s1),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.surfaceInset,
                        borderRadius: BorderRadius.circular(ArbiterRadii.md),
                      ),
                      child: Text(
                        ocrRaw,
                        style: ArbiterNotationStyles.medium(context)
                            .copyWith(color: c.feedbackWarning),
                      ),
                    ),
                    const SizedBox(height: ArbiterSpacing.s4),
                  ],
                  Text(
                    isLoading
                        ? 'Submitting correction…'
                        : 'Enter the correct SAN for this position:',
                    style: TextStyle(
                        color: c.contentSecondary,
                        fontSize: ArbiterFontSize.bodySm),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ChessKeyboard(
            currentInput: correction.input,
            suggestions: correction.suggestions,
            onChar: (ch) => ref.read(correctionProvider.notifier).addChar(ch),
            onBackspace: () => ref.read(correctionProvider.notifier).backspace(),
            onClear: () => ref.read(correctionProvider.notifier).clear(),
            onConfirm: isLoading ? () {} : _confirm,
          ),
        ],
      ),
    );
  }
}
