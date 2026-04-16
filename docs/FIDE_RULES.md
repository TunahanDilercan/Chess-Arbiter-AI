# FIDE Rules Reference

## python-chess Methods

```python
# Always use these — never hardcode rule logic manually
board.is_legal(move)                    # single move check
list(board.legal_moves)                 # all legal moves in position

board.can_claim_threefold_repetition()  # CLAIMABLE — player must request
board.is_fivefold_repetition()          # AUTOMATIC — enforced immediately

board.can_claim_fifty_moves()           # CLAIMABLE — player must request
board.is_seventyfive_moves()            # AUTOMATIC — enforced immediately

board.is_checkmate()                    # game over, current side loses
board.is_stalemate()                    # game over, draw
board.is_insufficient_material()        # game over, draw
board.result()                          # "1-0", "0-1", "1/2-1/2", "*"
```

## Automatic vs Claimable — CRITICAL DISTINCTION

| Condition | Type | Behavior |
|---|---|---|
| Fivefold repetition | AUTOMATIC | Stop game, apply draw immediately |
| 75-move rule | AUTOMATIC | Stop game, apply draw immediately |
| Threefold repetition | CLAIMABLE | Flag as available, do NOT apply |
| 50-move rule | CLAIMABLE | Flag as available, do NOT apply |

## Required UI Labels

AUTOMATIC: "Draw by fivefold repetition (automatic)"
CLAIMABLE: "Threefold repetition draw available — arbiter may be notified"

NEVER say "draw" for a claimable condition unless the player claims it.
NEVER skip reporting a claimable opportunity — the arbiter needs to know.

## RuleFinding Types (use these exact strings)

```python
class FindingType(str, Enum):
    THREEFOLD_CLAIM = "threefold_claim_available"   # claimable
    FIVEFOLD_AUTO = "fivefold_repetition_automatic"  # automatic
    FIFTY_CLAIM = "fifty_move_claim_available"       # claimable
    SEVENTY_FIVE_AUTO = "seventy_five_move_automatic" # automatic
    ILLEGAL_MOVE = "illegal_move"
    OCR_UNCERTAIN = "ocr_uncertain"
    CHECKMATE = "checkmate"
    STALEMATE = "stalemate"
    INSUFFICIENT_MATERIAL = "insufficient_material"
```

## Castling Normalization

Both notations are valid on handwritten sheets:
- `O-O` and `0-0` → normalize to `O-O`
- `O-O-O` and `0-0-0` → normalize to `O-O-O`

## Promotion Normalization

All of these mean the same thing:
- `e8Q`, `e8=Q`, `e8(Q)` → normalize to `e8=Q`
