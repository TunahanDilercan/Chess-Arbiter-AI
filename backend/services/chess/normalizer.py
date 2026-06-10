"""
OCR move text normalization pipeline.

Converts raw OCR output (potentially messy, locale-specific, containing Unicode
artifacts) into standard English SAN suitable for python-chess validation.

Pipeline order (applied in sequence):
  1. Strip leading move numbers   "14. Nf3" → "Nf3"
  2. Unicode substitutions        "×" → "x", en/em dashes → "-"
  3. Castling normalization       "0-0" | "o-o" | "OO" → "O-O"  (and -O-O-O)
  4. Locale piece remapping       Turkish "K" → "R", French "R" → "K", etc.
  5. Promotion normalization      "e8Q" | "e8(Q)" | "e8/Q" → "e8=Q"
  6. Rank confusion fix           "Nfl" → "Nf1"  (lowercase-L in rank position)

All rules are data-driven and locale mappings are extensible via LOCALE_PIECE_MAPS.
"""

from __future__ import annotations

import re
from typing import Dict


# ── Locale piece-initial maps ─────────────────────────────────────────────────
# Maps non-English uppercase piece letter → standard English piece letter (KQRBN).
# Only uppercase letters are remapped; file letters (a-h, always lowercase) are
# never touched, so there is no ambiguity.

LOCALE_PIECE_MAPS: Dict[str, Dict[str, str]] = {
    "en": {},  # No remapping required
    "tr": {
        # Turkish piece names → English (TSF standard notation)
        "Ş": "K",   # Şah (King)
        "V": "Q",   # Vezir (Queen)
        "K": "R",   # Kale (Rook)   ← NOTE: Turkish K ≠ English K
        "F": "B",   # Fil (Bishop)
        "A": "N",   # At (Knight)
    },
    "de": {
        # German piece names → English (König stays K)
        "D": "Q",   # Dame (Queen)
        "T": "R",   # Turm (Rook)
        "L": "B",   # Läufer (Bishop)
        "S": "N",   # Springer (Knight)
    },
    "fr": {
        # French piece names → English
        "R": "K",   # Roi (King)    ← French R ≠ English R (Rook)
        "D": "Q",   # Dame (Queen)
        "T": "R",   # Tour (Rook)
        "F": "B",   # Fou (Bishop)
        "C": "N",   # Cavalier (Knight)
    },
    "es": {
        # Spanish piece names → English
        "R": "K",   # Rey (King)    ← Spanish R ≠ English R (Rook)
        "D": "Q",   # Dama (Queen)
        "T": "R",   # Torre (Rook)
        "A": "B",   # Alfil (Bishop)
        "C": "N",   # Caballo (Knight)
    },
}

# ── Unicode OCR substitutions ─────────────────────────────────────────────────
# Characters that OCR engines commonly produce instead of their ASCII equivalents.

_UNICODE_SUBS: Dict[str, str] = {
    "\u00d7": "x",   # × (multiplication sign)
    "\u2715": "x",   # ✕ (multiplication X)
    "\u2717": "x",   # ✗ (ballot X)
    "\u2716": "x",   # ✖ (heavy multiplication X)
    # Hyphen/dash variants — all normalise to ASCII hyphen-minus (U+002D).
    # The castling regex expects "-" so every Unicode dash must be mapped here.
    "\u2010": "-",   # ‐ hyphen (typographic)
    "\u2011": "-",   # ‑ non-breaking hyphen (iOS Smart Punctuation)
    "\u2012": "-",   # ‒ figure dash
    "\u2013": "-",   # – en dash
    "\u2014": "-",   # — em dash
    "\u2015": "-",   # ― horizontal bar
    "\u2212": "-",   # − minus sign (mathematical)
    "\u00b7": "",    # · (middle dot — sometimes inserted by OCR)
    "\u200b": "",    # ​ (zero-width space)
}

# ── Compiled regexes ──────────────────────────────────────────────────────────

# Leading move number: "14." or "14. " at the start of a string
_RE_MOVE_NUMBER = re.compile(r"^\d+\.+\s*")

# Castling: any combination of O/0/o separated by dashes, with optional suffix
# e.g. "0-0", "O-O", "o-o", "0-0-0", "OOO", "0-0+", "O-O-O#"
_RE_CASTLE_LONG = re.compile(
    r"^[0Oo][-\s]?[0Oo][-\s]?[0Oo]([+#]?)$"
)
_RE_CASTLE_SHORT = re.compile(
    r"^[0Oo][-\s]?[0Oo]([+#]?)$"
)

# Promotion without '=': file + dest rank 1 or 8 + optional separator + piece
# Handles: e8Q, exd8Q, e8(Q), exd8(Q), e8/Q
# Does NOT match if '=' is already present.
_RE_PROMOTION = re.compile(
    r"^([a-h](?:x[a-h])?[18])"   # source + optional capture + destination square
    r"[\(=/]?"                    # optional separator
    r"([QRBN])"                   # promotion piece
    r"\)?"                        # optional closing paren
    r"([+#]?)$"                   # optional check/checkmate marker
)


class MoveNormalizer:
    """
    Stateless normalization pipeline.  Call normalize() on each raw OCR string.

    Example:
        normalizer = MoveNormalizer()
        normalizer.normalize("0-0",  "en")  → "O-O"
        normalizer.normalize("Kf3",  "tr")  → "Rf3"   (Turkish K = Rook)
        normalizer.normalize("e8Q",  "en")  → "e8=Q"
        normalizer.normalize("Nfl",  "en")  → "Nf1"   (l/1 rank confusion)
        normalizer.normalize("14. Nf3", "en") → "Nf3"
    """

    def normalize(self, text: str, locale: str = "en") -> str:
        """
        Full normalization pipeline.  Returns cleaned SAN string.
        Returns the original stripped text unchanged if it is empty.
        """
        s = text.strip()
        if not s:
            return s

        # Step 1: Strip leading move numbers ("14. Nf3" → "Nf3")
        s = _RE_MOVE_NUMBER.sub("", s).strip()

        # Step 2: Unicode substitutions
        s = self._apply_unicode_subs(s)

        # Step 3: Castling normalization (must be before locale remapping,
        # because some locales map 'R' or 'K' which would corrupt castling)
        castled = self._normalize_castling(s)
        if castled is not None:
            return castled  # castling needs no further processing

        # Step 4: Locale piece remapping
        s = self._apply_locale_map(s, locale)

        # Step 5: Promotion normalization
        s = self._normalize_promotion(s)

        # Step 6: Rank/file OCR confusion (l ↔ 1 in rank position)
        s = self._fix_rank_confusion(s)

        return s

    # ── Private helpers ───────────────────────────────────────────────────────

    def _apply_unicode_subs(self, text: str) -> str:
        for src, dst in _UNICODE_SUBS.items():
            text = text.replace(src, dst)
        return text

    def _normalize_castling(self, text: str) -> str | None:
        """
        Returns the canonical castling string ("O-O" or "O-O-O") if the text
        is a recognized castling notation, or None if it is not castling.
        """
        # Try long castling first (must come before short to avoid false match)
        m = _RE_CASTLE_LONG.match(text)
        if m:
            return f"O-O-O{m.group(1)}"

        m = _RE_CASTLE_SHORT.match(text)
        if m:
            return f"O-O{m.group(1)}"

        return None

    def _apply_locale_map(self, text: str, locale: str) -> str:
        """
        Replace non-English piece initials character-by-character.
        Only uppercase characters appear in the locale maps (piece symbols);
        lowercase file letters (a-h) and rank digits are never remapped.
        """
        piece_map = LOCALE_PIECE_MAPS.get(locale, {})
        if not piece_map:
            return text
        return "".join(piece_map.get(ch, ch) for ch in text)

    def _normalize_promotion(self, text: str) -> str:
        """
        Ensure promotion notation uses the '=' separator required by python-chess.

        Handles: e8Q → e8=Q, exd8Q → exd8=Q, e8(Q) → e8=Q, e8/Q → e8=Q
        Leaves alone: e8=Q, e8=Q+, e8=Q# (already correct).
        """
        if "=" in text:
            return text  # already normalized

        m = _RE_PROMOTION.match(text)
        if m:
            return f"{m.group(1)}={m.group(2)}{m.group(3)}"

        return text

    def _fix_rank_confusion(self, text: str) -> str:
        """
        Fix OCR confusion between lowercase 'l' (letter) and '1' (digit).

        In SAN notation:
          - Files are always lowercase a-h (never 'l')
          - Ranks are always digits 1-8

        Strategy: if a character is 'l' and the preceding character is a valid
        file letter (a-h), the 'l' is almost certainly the digit '1'.
        """
        chars = list(text)
        for i, ch in enumerate(chars):
            if ch == "l" and i > 0 and chars[i - 1] in "abcdefgh":
                chars[i] = "1"
        return "".join(chars)
