import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

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
/// [suggestions] — tappable SAN pills shown above the keyboard.
/// Tapping a pill whose text matches [currentInput] marks it selected (gold).
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
    return Material(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Input display ─────────────────────────────────────────────
              _InputDisplay(input: currentInput),
              const SizedBox(height: 6),

              // ── Suggestion pills ──────────────────────────────────────────
              if (suggestions.isNotEmpty) ...[
                _SuggestionRow(
                  suggestions: suggestions,
                  currentInput: currentInput,
                  onTap: onChar,
                ),
                const SizedBox(height: 4),
              ],

              // ── Key rows ──────────────────────────────────────────────────
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

              // ── Utility row ───────────────────────────────────────────────
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

// ── Input display ─────────────────────────────────────────────────────────────

class _InputDisplay extends StatelessWidget {
  final String input;
  const _InputDisplay({required this.input});

  @override
  Widget build(BuildContext context) {
    final hasInput = input.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: hasInput ? AppColors.accent : AppColors.surfaceHigh,
          width: hasInput ? 1.5 : 1,
        ),
      ),
      child: Text(
        hasInput ? input : 'Type a move…',
        style: AppTextStyles.mono.copyWith(
          color: hasInput ? AppColors.onBackground : AppColors.onSurfaceFaint,
          fontSize: 22,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ── Suggestion pills ──────────────────────────────────────────────────────────

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
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.surfaceVar,
                borderRadius: AppRadius.chipAll,
                border: isSelected
                    ? null
                    : Border.all(color: AppColors.surfaceHigh),
              ),
              child: Text(
                sug,
                style: AppTextStyles.mono.copyWith(
                  fontSize: 14,
                  color: isSelected ? Colors.black : AppColors.onBackground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Key row ───────────────────────────────────────────────────────────────────

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: AppTextStyles.label,
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

// ── Individual key ────────────────────────────────────────────────────────────

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
    final isLong = label.length > 3;
    final width = isLong ? 62.0 : (compact ? 34.0 : 42.0);
    // Minimum 44px height for tap targets; compact keys get 40px (within
    // acceptable range for closely-packed keyboard rows).
    final height = compact ? 40.0 : 44.0;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: AppColors.surfaceVar,
        borderRadius: BorderRadius.circular(AppRadius.button + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button + 2),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: isLong ? 12 : (compact ? 14 : 16),
                fontWeight: FontWeight.w600,
                color: AppColors.onBackground,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Utility row ───────────────────────────────────────────────────────────────

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
    return Row(
      children: [
        Expanded(
          child: _ActionKey(
            icon: Icons.backspace_outlined,
            label: '⌫',
            bgColor: const Color(0xFF3C2A2A),
            fgColor: AppColors.error,
            onTap: onBackspace,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ActionKey(
            icon: Icons.clear,
            label: 'Clear',
            bgColor: AppColors.surfaceVar,
            fgColor: AppColors.onSurface,
            onTap: onClear,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: _ActionKey(
            icon: Icons.check_circle_outline,
            label: 'Confirm',
            bgColor: AppColors.primary,
            fgColor: Colors.white,
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
        borderRadius: AppRadius.cardAll,
        child: InkWell(
          borderRadius: AppRadius.cardAll,
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
