import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';

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
List<String> _parseMoves(String text) {
  final castlingLong = RegExp(
    r'[Oo0]\s*[-‐-―−]\s*[Oo0]\s*[-‐-―−]\s*[Oo0]',
  );
  final castlingShort = RegExp(
    r'[Oo0]\s*[-‐-―−]\s*[Oo0]',
  );
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
    final c = context.arbiterColors;
    ref.listen(manualAnalysisProvider, _listenAndNavigate);
    final analysisState = ref.watch(manualAnalysisProvider);
    final isLoading = analysisState.isLoading;

    final apiError =
        analysisState.hasError ? _friendlyError(analysisState.error) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Moves Manually'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ArbiterSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionLabel(
                icon: Icons.info_outline,
                text: 'Enter moves separated by spaces or newlines. '
                    'Move numbers (1. 2.) are stripped automatically.',
              ),
              const SizedBox(height: ArbiterSpacing.s4),
              Container(
                decoration: BoxDecoration(
                  color: c.surfaceInset,
                  borderRadius: BorderRadius.circular(ArbiterRadii.md),
                  border: Border.all(
                    color: _validationError != null
                        ? c.feedbackDanger
                        : Colors.transparent,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 8,
                  minLines: 5,
                  enabled: !isLoading,
                  // Disable autocorrect so the mobile keyboard cannot mutate
                  // chess notation (e.g. spaces around hyphens in O-O / O-O-O).
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                      fontFamily: ArbiterFontFamily.mono,
                      fontSize: ArbiterFontSize.notationMd,
                      color: c.contentPrimary),
                  decoration: InputDecoration(
                    hintText: 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O\n'
                        '— or one move per line —\n'
                        '1. e4 e5\n2. Nf3 Nc6',
                    hintStyle: TextStyle(
                        fontFamily: ArbiterFontFamily.mono,
                        fontSize: ArbiterFontSize.notationSm,
                        color: c.contentTertiary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(ArbiterSpacing.s4),
                  ),
                  onChanged: (_) {
                    if (_validationError != null) {
                      setState(() => _validationError = null);
                    }
                  },
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: ArbiterSpacing.s1),
                Text(_validationError!,
                    style: TextStyle(
                        color: c.feedbackDanger,
                        fontSize: ArbiterFontSize.bodySm)),
              ],
              const SizedBox(height: ArbiterSpacing.s5),
              Text('Piece notation language',
                  style: TextStyle(
                      color: c.contentSecondary,
                      fontSize: ArbiterFontSize.bodySm)),
              const SizedBox(height: ArbiterSpacing.s1),
              _LocaleSelector(
                selected: _locale,
                enabled: !isLoading,
                onChanged: (v) => setState(() => _locale = v),
              ),
              const SizedBox(height: ArbiterSpacing.s6),
              if (apiError != null) ...[
                _ErrorBanner(message: apiError),
                const SizedBox(height: ArbiterSpacing.s4),
              ],
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _submit,
                  icon: isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.contentInverse),
                        )
                      : const Icon(Icons.analytics_outlined, size: 20),
                  label: Text(isLoading ? 'Analysing…' : 'Analyse'),
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
    if (raw.contains('DioException')) {
      final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
      if (match != null) return match.group(1)!;
      return 'Server error — check that the backend is reachable.';
    }
    return raw;
  }
}

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
    final c = context.arbiterColors;
    return SegmentedButton<String>(
      segments: _localeOptions
          .map((o) =>
              ButtonSegment<String>(value: o.code, label: Text(o.label)))
          .toList(),
      selected: {selected},
      onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
      style: SegmentedButton.styleFrom(
        backgroundColor: c.surfaceInset,
        foregroundColor: c.contentSecondary,
        selectedBackgroundColor: c.accentPrimaryMuted,
        selectedForegroundColor: c.accentPrimary,
        side: BorderSide(color: c.surfaceElevated),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.contentTertiary),
        const SizedBox(width: ArbiterSpacing.s1),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm)),
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
    final c = context.arbiterColors;
    return Container(
      padding: const EdgeInsets.all(ArbiterSpacing.s2),
      decoration: BoxDecoration(
        color: c.feedbackDanger.withAlpha(30),
        borderRadius: BorderRadius.circular(ArbiterRadii.md),
        border: Border.all(color: c.feedbackDanger.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: c.feedbackDanger, size: 18),
          const SizedBox(width: ArbiterSpacing.s2),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: c.feedbackDanger, fontSize: ArbiterFontSize.bodySm)),
          ),
        ],
      ),
    );
  }
}
