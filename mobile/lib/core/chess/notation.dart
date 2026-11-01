/// Scoresheet notation normalisation: locale piece letters, castling variants,
/// Unicode glyphs, promotion forms and common OCR/handwriting confusions.
/// Output uses English SAN letters (K Q R B N) for [parseMove].
library;

enum NotationLocale {
  en('EN', 'İngilizce (K Q R B N)'),
  tr('TR', 'Türkçe (Ş V K F A)'),
  de('DE', 'Almanca (K D T L S)'),
  fr('FR', 'Fransızca (R D T F C)'),
  es('ES', 'İspanyolca (R D T A C)');

  const NotationLocale(this.code, this.label);
  final String code;
  final String label;

  static NotationLocale parse(String? s) {
    for (final l in values) {
      if (l.name == s?.toLowerCase()) return l;
    }
    return NotationLocale.en;
  }
}

const Map<NotationLocale, Map<String, String>> localePieceMaps = {
  NotationLocale.en: {},
  NotationLocale.tr: {
    'Ş': 'K', 'S': 'K', // Şah (S without cedilla is a common keyboard slip)
    'V': 'Q', // Vezir
    'K': 'R', // Kale — Turkish K is NOT the English king
    'F': 'B', // Fil
    'A': 'N', // At
  },
  NotationLocale.de: {'D': 'Q', 'T': 'R', 'L': 'B', 'S': 'N'},
  NotationLocale.fr: {'R': 'K', 'D': 'Q', 'T': 'R', 'F': 'B', 'C': 'N'},
  NotationLocale.es: {'R': 'K', 'D': 'Q', 'T': 'R', 'A': 'B', 'C': 'N'},
};

/// Reverse maps for display in a locale (English → local).
Map<String, String> displayPieceMap(NotationLocale l) => switch (l) {
      NotationLocale.en => const {},
      NotationLocale.tr => const {'K': 'Ş', 'Q': 'V', 'R': 'K', 'B': 'F', 'N': 'A'},
      NotationLocale.de => const {'Q': 'D', 'R': 'T', 'B': 'L', 'N': 'S'},
      NotationLocale.fr => const {'K': 'R', 'Q': 'D', 'R': 'T', 'B': 'F', 'N': 'C'},
      NotationLocale.es => const {'K': 'R', 'Q': 'D', 'R': 'T', 'B': 'A', 'N': 'C'},
    };

/// Renders English SAN in the given locale's piece letters.
String localizeSan(String san, NotationLocale l) {
  if (san.startsWith('O-O')) return san;
  final map = displayPieceMap(l);
  if (map.isEmpty) return san;
  return san.split('').map((c) => map[c] ?? c).join();
}

const Map<String, String> _unicodeSubs = {
  '×': 'x', '✕': 'x', '✗': 'x', '✖': 'x', 'х': 'x',
  ':': 'x',
  '‐': '-', '‑': '-', '‒': '-', '–': '-', '—': '-',
  '―': '-', '−': '-',
  '·': '', '​': '', ' ': '',
  '♔': 'K', '♚': 'K', '♕': 'Q', '♛': 'Q',
  '♖': 'R', '♜': 'R', '♗': 'B', '♝': 'B',
  '♘': 'N', '♞': 'N', '♙': '', '♟': '',
};

final _reMoveNumber = RegExp(r'^\d+\s*\.+\s*');
final _reCastleLong = RegExp(r'^[0Oo]-?[0Oo]-?[0Oo]([+#]?)$');
final _reCastleShort = RegExp(r'^[0Oo]-?[0Oo]([+#]?)$');
final _rePromotion =
    RegExp(r'^([a-h](?:x[a-h])?[18])[\(=/]?([QRBNqrbn])\)?([+#]?)$');

String normalizeMove(String text, NotationLocale locale) {
  var s = text.trim();
  if (s.isEmpty) return s;
  s = s.replaceFirst(_reMoveNumber, '').trim();
  for (final e in _unicodeSubs.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  s = s.replaceAll(RegExp(r'[!?]+$'), '');
  if (s.isEmpty) return s;

  final long = _reCastleLong.firstMatch(s);
  if (long != null) return 'O-O-O${long.group(1)}';
  final short = _reCastleShort.firstMatch(s);
  if (short != null) return 'O-O${short.group(1)}';

  final map = localePieceMaps[locale]!;
  if (map.isNotEmpty) {
    // Uppercase-only remap: lowercase files (a-h) are never touched. Applied to
    // the piece letter and the promotion piece (after "=" or rank 1/8).
    s = s.split('').map((c) => map[c] ?? c).join();
  }

  // A lowercase piece letter that cannot be a file ("nf3") is a piece.
  if (s.length >= 3) {
    final first = s[0];
    final pieceLetters = locale == NotationLocale.en
        ? const {'k', 'q', 'r', 'n'}
        : map.keys.map((k) => k.toLowerCase()).toSet();
    if (pieceLetters.contains(first) && !'abcdefgh'.contains(first)) {
      final up = first.toUpperCase();
      s = (map[up] ?? up) + s.substring(1);
    }
  }

  if (!s.contains('=')) {
    final m = _rePromotion.firstMatch(s);
    if (m != null) {
      // Uppercase letters were already remapped above; only a lowercase
      // promotion letter still needs the locale map.
      final p = m.group(2)!;
      final up = p.toUpperCase();
      final piece = p == up ? p : (map[up] ?? up);
      s = '${m.group(1)}=$piece${m.group(3)}';
    }
  }

  // Lowercase "l" written for the digit 1 after a file letter.
  final chars = s.split('');
  for (var i = 1; i < chars.length; i++) {
    if (chars[i] == 'l' && 'abcdefgh'.contains(chars[i - 1])) chars[i] = '1';
  }
  return chars.join();
}
