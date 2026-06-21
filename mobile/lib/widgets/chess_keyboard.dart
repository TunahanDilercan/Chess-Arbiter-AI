import 'package:flutter/material.dart';

import '../theme/arbiter_tokens.dart';

/// Custom chess SAN keyboard — never triggers the system keyboard.
///
/// Key groups:
///   Pieces    K Q R B N
///   Files     a–h
///   Ranks     1–8
///   Symbols   x + # = O-O O-O-O
///   Promotion =Q =R =B =N
///   Utility   ⌫  Clear  ✓ Confirm
///
/// [suggestions] are backend-provided SAN candidate strings shown as tappable
/// pills above the keys. This widget performs NO chess validation — legality
/// is decided by the backend (see CLAUDE.md).
class ChessKeyboard extends StatelessWidget {
  final String currentInput;
  final List<String> suggestions;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onConfirm;

  const ChessKeyboard({
    super.key,
    required this.currentInput,
    required this.suggestions,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Material(
      color: c.surfaceElevated,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InputDisplay(input: currentInput),
              const SizedBox(height: 6),
              if (suggestions.isNotEmpty) ...[
                _SuggestionRow(
                  suggestions: suggestions,
                  currentInput: currentInput,
                  onTap: onChar,
                ),
                const SizedBox(height: 4),
              ],
              _KeyRow(
                label: 'PIECES',
                keys: const ['K', 'Q', 'R', 'B', 'N'],
                onKey: onChar,
              ),
              _KeyRow(
                label: 'FILES',
                keys: const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
                onKey: onChar,
                compact: true,
              ),
              _KeyRow(
                label: 'RANKS',
                keys: const ['1', '2', '3', '4', '5', '6', '7', '8'],
                onKey: onChar,
                compact: true,
              ),
              _KeyRow(
                label: 'SYMBOLS',
                keys: const ['x', '+', '#', '=', 'O-O', 'O-O-O'],
                onKey: onChar,
              ),
              _KeyRow(
                label: 'PROMO',
                keys: const ['=Q', '=R', '=B', '=N'],
                onKey: onChar,
              ),
              const SizedBox(height: 2),
              _UtilityRow(
                onBackspace: onBackspace,
                onClear: onClear,
                onConfirm: onConfirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputDisplay extends StatelessWidget {
  final String input;
  const _InputDisplay({required this.input});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final hasInput = input.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceInset,
        borderRadius: BorderRadius.circular(ArbiterRadii.md),
        border: Border.all(
          color: hasInput ? c.accentPrimary : c.surfaceRaised,
          width: hasInput ? 1.5 : 1,
        ),
      ),
      child: Text(
        hasInput ? input : 'Type a move…',
        style: TextStyle(
          fontFamily: ArbiterFontFamily.mono,
          color: hasInput ? c.contentPrimary : c.contentTertiary,
          fontSize: 22,
          fontWeight: FontWeight.w500,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final List<String> suggestions;
  final String currentInput;
  final ValueChanged<String> onTap;

  const _SuggestionRow({
    required this.suggestions,
    required this.currentInput,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final sug = suggestions[i];
          final isSelected = currentInput == sug;
          return GestureDetector(
            onTap: () => onTap(sug),
            child: AnimatedContainer(
              duration: ArbiterMotionDuration.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? c.accentPrimary : c.surfaceInset,
                borderRadius: BorderRadius.circular(ArbiterRadii.full),
                border: isSelected
                    ? null
                    : Border.all(color: c.contentTertiary),
              ),
              child: Text(
                sug,
                style: TextStyle(
                  fontFamily: ArbiterFontFamily.mono,
                  fontSize: 14,
                  color: isSelected ? c.contentInverse : c.contentPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final String label;
  final List<String> keys;
  final ValueChanged<String> onKey;
  final bool compact;

  const _KeyRow({
    required this.label,
    required this.keys,
    required this.onKey,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: c.contentTertiary,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: keys
                  .map((k) => _ChessKey(
                        label: k,
                        onTap: () => onKey(k),
                        compact: compact,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChessKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _ChessKey({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final isLong = label.length > 3;
    final width = isLong ? 62.0 : (compact ? 34.0 : 42.0);
    final height = compact ? 40.0 : 44.0;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: c.surfaceInset,
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(ArbiterRadii.sm),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: ArbiterFontFamily.mono,
                fontSize: isLong ? 12 : (compact ? 14 : 16),
                fontWeight: FontWeight.w600,
                color: c.contentPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UtilityRow extends StatelessWidget {
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onConfirm;

  const _UtilityRow({
    required this.onBackspace,
    required this.onClear,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Row(
      children: [
        Expanded(
          child: _ActionKey(
            icon: Icons.backspace_outlined,
            label: '⌫',
            bgColor: c.feedbackDanger.withAlpha(36),
            fgColor: c.feedbackDanger,
            onTap: onBackspace,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ActionKey(
            icon: Icons.clear,
            label: 'Clear',
            bgColor: c.surfaceInset,
            fgColor: c.contentSecondary,
            onTap: onClear,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: _ActionKey(
            icon: Icons.check_circle_outline,
            label: 'Confirm',
            bgColor: c.accentPrimary,
            fgColor: c.contentInverse,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}

class _ActionKey extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;
  final VoidCallback onTap;

  const _ActionKey({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(ArbiterRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(ArbiterRadii.md),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fgColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
