import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

// ── Locale option ─────────────────────────────────────────────────────────────

class _LocaleOption {
  final String code;
  final String label;
  const _LocaleOption(this.code, this.label);
}

const _localeOptions = [
  _LocaleOption('en', 'English'),
  _LocaleOption('tr', 'Turkish'),
  _LocaleOption('de', 'German'),
];

// ── Move parser ───────────────────────────────────────────────────────────────

/// Split raw text into SAN tokens, dropping move-number prefixes
/// ("1.", "2...", "10.") and blank entries.
///
/// Pre-normalises castling notation before splitting so that mobile keyboards
/// which insert spaces around hyphens ("O - O", "O - O - O") are handled
/// correctly.  Without this step the three tokens would be sent individually
/// and "-" would fuzzy-match to a random legal move, corrupting the game.
List<String> _parseMoves(String text) {
  // Merge "O - O - O" and "O - O" variants that mobile autocorrect may produce.
  // Handles any mix of O/0/o with optional spaces around hyphens or em-dashes.
  final castlingLong = RegExp(
    r'[Oo0]\s*[-\u2010-\u2015\u2212]\s*[Oo0]\s*[-\u2010-\u2015\u2212]\s*[Oo0]',
  );
  final castlingShort = RegExp(
    r'[Oo0]\s*[-\u2010-\u2015\u2212]\s*[Oo0]',
  );
  // Replace long castling first to avoid partial match by the short pattern.
  var normalised = text.replaceAll(castlingLong, 'O-O-O');
  normalised = normalised.replaceAll(castlingShort, 'O-O');

  final moveNumber = RegExp(r'^\d+\.+$');
  return normalised
      .trim()
      .split(RegExp(r'[\s\n\r]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty && !moveNumber.hasMatch(t))
      .toList();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _controller = TextEditingController();
  String _locale = 'en';
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Navigate when analysis succeeds.
  void _listenAndNavigate(
    AsyncValue<dynamic>? previous,
    AsyncValue<dynamic> next,
  ) {
    next.whenData((game) {
      if (game == null) return;
      if (!mounted) return;
      context.push('/manual/result', extra: game);
    });
  }

  String? _validate(List<String> moves) {
    if (moves.isEmpty) return 'Enter at least one move.';
    if (moves.length > 200) {
      return 'Maximum 200 moves allowed (got ${moves.length}).';
    }
    return null;
  }

  void _submit() {
    final moves = _parseMoves(_controller.text);
    final error = _validate(moves);
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    setState(() => _validationError = null);
    ref.read(manualAnalysisProvider.notifier).analyze(moves, locale: _locale);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(manualAnalysisProvider, _listenAndNavigate);
    final analysisState = ref.watch(manualAnalysisProvider);
    final isLoading = analysisState.isLoading;

    // API error (distinct from local validation error)
    final apiError = analysisState.hasError
        ? _friendlyError(analysisState.error)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Moves Manually'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        // Dismiss keyboard on tap outside
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Instruction ──────────────────────────────────────────────
              _SectionLabel(
                icon: Icons.info_outline,
                text: 'Enter moves separated by spaces or newlines. '
                    'Move numbers (1. 2.) are stripped automatically.',
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Text input ───────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.cardAll,
                  border: Border.all(
                    color: _validationError != null
                        ? AppColors.error
                        : AppColors.surfaceVar,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 8,
                  minLines: 5,
                  enabled: !isLoading,
                  // Disable autocorrect and suggestions so the mobile keyboard
                  // cannot silently mutate chess notation — in particular it
                  // must not add spaces around hyphens in "O-O" / "O-O-O".
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppTextStyles.mono.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O\n'
                        '— or one move per line —\n'
                        '1. e4 e5\n2. Nf3 Nc6',
                    hintStyle: AppTextStyles.mono.copyWith(
                      fontSize: 13,
                      color: AppColors.onSurfaceFaint,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                  ),
                  onChanged: (_) {
                    if (_validationError != null) {
                      setState(() => _validationError = null);
                    }
                  },
                ),
              ),

              // ── Validation error ─────────────────────────────────────────
              if (_validationError != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _validationError!,
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // ── Locale selector ───────────────────────────────────────────
              Text('Piece notation language', style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.xs),
              _LocaleSelector(
                selected: _locale,
                enabled: !isLoading,
                onChanged: (v) => setState(() => _locale = v),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── API error ────────────────────────────────────────────────
              if (apiError != null) ...[
                _ErrorBanner(message: apiError),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── Analyze button ────────────────────────────────────────────
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _submit,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.analytics_outlined, size: 20),
                  label: Text(isLoading ? 'Analysing…' : 'Analyse'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _friendlyError(Object? error) {
    final raw = error?.toString() ?? 'Unknown error';
    // Trim DioException noise
    if (raw.contains('DioException')) {
      final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
      if (match != null) return match.group(1)!;
      return 'Server error — check that the backend is reachable.';
    }
    return raw;
  }
}

// ── Locale selector ───────────────────────────────────────────────────────────

class _LocaleSelector extends StatelessWidget {
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _LocaleSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: _localeOptions
          .map(
            (o) => ButtonSegment<String>(
              value: o.code,
              label: Text(o.label),
            ),
          )
          .toList(),
      selected: {selected},
      onSelectionChanged:
          enabled ? (s) => onChanged(s.first) : null,
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        selectedBackgroundColor: AppColors.primaryLight,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.surfaceVar),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: AppTextStyles.bodyDim.copyWith(fontSize: 13)),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(30),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.error.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
