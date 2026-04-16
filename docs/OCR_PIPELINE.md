# OCR Pipeline Reference

## Model Choice Rationale

TrOCR (`microsoft/trocr-large-handwritten`) is used because:
- Tesseract is designed for printed text — fails on cursive/handwriting
- Chess notation errors are costly: Nf3 vs Nf5 = single pixel = game-changing
- TrOCR is transformer-based, trained on handwritten text datasets
- Tesseract available as dev-only comparison via OCRProvider interface

## OCRProvider Interface

Every OCR implementation must implement:
```python
class OCRProvider(ABC):
    @abstractmethod
    async def recognize(self, image: np.ndarray) -> list[OCRCandidate]:
        # Returns top-3 candidates with confidence scores
        ...
```

Never instantiate TrOCR directly in route handlers.
Import and use via the provider interface only.

## Expected OCR Inputs

Cropped move cell images (grayscale, ~100x50px after preprocessing).
Expected outputs (SAN-like):
- Simple: e4, d5, Nf3, Bc4
- Captures: Bxh6, exd5, Nxf7
- Castling: O-O, O-O-O (may come as 0-0, 0-0-0)
- Promotion: axb8=Q, e8=R
- Check/Mate: Qh7+, Rxf8#

## Normalization Rules (normalizer.py)

Applied BEFORE legal move matching:
```
0-0     → O-O
0-0-0   → O-O-O
×       → x       (unicode × vs ASCII x)
l       → 1       (lowercase L vs digit 1, in rank positions)
e8Q     → e8=Q    (promotion without equals sign)
e8(Q)   → e8=Q    (promotion with parens)
```

Piece initial remapping (configurable, default English):
```python
PIECE_MAP = {
    "tr": {"Ş": "K", "F": "Q", "K": "R", "V": "B", "A": "N"},
    "de": {"K": "K", "D": "Q", "T": "R", "L": "B", "S": "N"},
}
```

## Candidate Matching (candidate_matcher.py)

Scoring formula per legal move candidate:
```
score = (1 - levenshtein_ratio) * 0.5
      + ocr_confidence * 0.4
      + confusion_matrix_bonus * 0.1
```

Chess-specific confusion pairs (common OCR mistakes):
- B ↔ 8
- O ↔ 0
- l ↔ 1
- x ↔ × (unicode)
- Q ↔ O

Auto-accept threshold: 0.85 (set in config.py as OCR_CONFIDENCE_THRESHOLD)
Below threshold: needs_manual_review = True, stop playback, show correction UI

## TrOCR Performance Notes

- Inference time: ~2-5 sec per cell on CPU, ~200ms on GPU
- A full 40-move game = ~80 cells
- CPU: ~4-6 minutes total → acceptable with async + progress SSE
- Production: GPU inference recommended (add to docker-compose as optional service)
- Batch inference: process all crops in one forward pass where possible
