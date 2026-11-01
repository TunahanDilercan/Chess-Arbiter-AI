# Slow verification suite

Independent oracles check the on-device chess core. Not part of `flutter test`
(it runs `test/` only); run before every release and after any change in
`lib/core/`.

| Test | Oracle | Last run |
| --- | --- | --- |
| `real_games_test.dart` | python-chess on 16,679 real tournament games (TWIC 996–999, Bundesliga 07/08–08/09, British Ch. 1979/2013/2014): 1,362,072 plies — SAN, check/mate/stalemate, dead position, repetition counts, clocks, FEN, 99,540 threefold/50-move claim checks via `checkClaim`; our PGN reader vs python-chess on the raw files | all pass |
| `perft_stockfish_test.dart` | Stockfish 17.1 `go perft`: perft-divide(3) on 3,132 positions (118,293,808 nodes) + deep divide on 6 reference positions; legal SAN lists vs python-chess; 100,244 legal moves round-tripped through SAN, 5 notations, UCI, missing "+"/"#", long algebraic | all pass |
| `random_games_test.dart` | python-chess on 4,000 steered random games (557,743 plies; 936 fivefold, 487 seventy-five-move, 1,287 dead positions) | all pass |

## Regenerate the data

```bash
# python-chess (pure Python) and a Stockfish binary are needed.
PYTHONPATH=<python-chess> python3 tool/gen_oracle_suite.py \
    --pgn-dir <folder with *.pgn> --stockfish <stockfish binary> --out test_slow/data
cp <folder with *.pgn>/*.pgn test_slow/data/pgn/        # PGN reader test
PYTHONPATH=<python-chess> python3 tool/gen_oracle_fixture.py 4000 test_slow/data/random_games.json 99
flutter test test_slow --concurrency=4
```

Real games used in the last run: `rozim/ChessData` on GitHub (Twic/twic996–999,
Bundesliga/bl0708, bl0809, Britbase/197908bcf, 201307britchamp, 201407britchamp).
Any large PGN collection works; more games = more confidence.

## Bugs this suite found (fixed)

- A game with no moves (bye/forfeit, movetext "1-0") swallowed the next game's
  headers in the PGN reader, attaching moves to the wrong players.
- UCI/long notation with a lowercase promotion letter (`c7c8q`) was rejected.
- Fivefold repetition and the 75-move rule on the same move: both are now
  recorded (9.6 "one or both").
