"""Generate a differential-test fixture with python-chess as an independent oracle.

Random games are steered towards repetitions (pieces moving back) and long
endgames (50/75-move rule). The Dart test replays the same SAN moves and must
agree on SAN, FEN, check/mate/stalemate, dead position, repetition counts and
automatic game ends.

    PYTHONPATH=/path/to/python-chess python3 tool/gen_oracle_fixture.py
"""
import json
import random

import chess

SEED = 20261101
START_FENS = [
    chess.STARTING_FEN,
    "8/8/4k3/8/8/3K4/8/R6r w - - 0 1",
    "8/5k2/8/3b4/8/2N5/4K3/8 w - - 0 1",
    "4k3/8/8/8/2q5/8/3R4/4K3 w - - 0 1",
    "r3k2r/pppq1ppp/2n2n2/3pp3/3PP3/2N2N2/PPPQ1PPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
    "8/8/8/4k3/8/8/4p3/R3K3 w - - 90 80",
]


def pick(board: chess.Board, rng: random.Random, history: list) -> chess.Move:
    moves = list(board.legal_moves)
    if len(history) >= 2 and rng.random() < 0.45:
        back = history[-2]
        undo = [m for m in moves if m.from_square == back.to_square and m.to_square == back.from_square]
        if undo:
            return undo[0]
    if rng.random() < 0.3:
        quiet = [m for m in moves if not board.is_capture(m) and board.piece_type_at(m.from_square) != chess.PAWN]
        if quiet:
            return rng.choice(quiet)
    return rng.choice(moves)


def main() -> None:
    rng = random.Random(SEED)
    games = []
    for g in range(160):
        assert chess.Board(START_FENS[g % len(START_FENS)]).is_valid()
        fen = START_FENS[g % len(START_FENS)]
        board = chess.Board(fen)
        history: list = []
        sans, flags, clocks, fens = [], [], [], {}
        limit = 260 if fen != chess.STARTING_FEN else 140
        while len(sans) < limit and not board.is_game_over(claim_draw=False):
            move = pick(board, rng, history)
            san = board.san(move)
            board.push(move)
            history.append(move)
            i = len(sans)
            sans.append(san)
            # c=check M=mate S=stalemate D=dead 3=threefold 5=fivefold 7=75-move
            flags.append("".join(code for code, on in [
                ("c", board.is_check()), ("M", board.is_checkmate()),
                ("S", board.is_stalemate()), ("D", board.is_insufficient_material()),
                ("3", board.is_repetition(3)), ("5", board.is_fivefold_repetition()),
                ("7", board.is_seventyfive_moves()),
            ] if on))
            clocks.append(board.halfmove_clock)
            if i % 7 == 0:
                fens[str(i)] = board.fen()
        fens[str(len(sans) - 1)] = board.fen()
        games.append({"start": fen, "sans": " ".join(sans), "flags": ",".join(flags),
                      "clocks": clocks, "fens": fens})
    with open("test/fixtures/oracle_games.json", "w") as f:
        json.dump(games, f, separators=(",", ":"))
    flags = ",".join(g["flags"] for g in games)
    print(f"{len(games)} games, {sum(len(g['clocks']) for g in games)} plies, "
          + ", ".join(f"{flags.count(c)}x{c}" for c in "cMSD357"))


if __name__ == "__main__":
    main()
