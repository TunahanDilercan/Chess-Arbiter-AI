"""Large-scale oracle data for test_slow/ (independent of our Dart engine).

Oracles:
  * python-chess replays real games and labels every ply (SAN, check, mate,
    stalemate, insufficient material, repetition counts, threefold / 50-move
    claim rights, clocks, FEN).
  * Stockfish ("go perft N") gives perft-divide counts for sampled positions;
    python-chess gives the full legal SAN list for the same positions.

    PYTHONPATH=<python-chess> python3 tool/gen_oracle_suite.py \
        --pgn-dir <dir with *.pgn> --stockfish <path> --out test_slow/data
"""
import argparse
import gzip
import io
import json
import multiprocessing as mp
import os
import random
import subprocess
from collections import Counter

import chess
import chess.pgn


def label_game(game: chess.pgn.Game):
    board = game.board()
    if board.fen() != chess.STARTING_FEN:
        return None
    seen = Counter([board._transposition_key()])
    sans, flags, clocks, fens = [], [], [], {}
    for i, move in enumerate(game.mainline_moves()):
        if move not in board.legal_moves:
            return None
        sans.append(board.san(move))
        board.push(move)
        key = board._transposition_key()
        seen[key] += 1
        reps = seen[key]
        claim3 = (max(seen.values()) >= 2) and board.can_claim_threefold_repetition()
        claim50 = board.halfmove_clock >= 99 and board.can_claim_fifty_moves()
        # c check, M mate, S stalemate, D dead (insufficient), 2/3/5 occurrence
        # counts, 7 seventy-five, T threefold claim right, F fifty claim right
        flags.append("".join(code for code, on in [
            ("c", board.is_check()), ("M", board.is_checkmate()),
            ("S", board.is_stalemate()), ("D", board.is_insufficient_material()),
            ("2", reps >= 2), ("3", reps >= 3), ("5", reps >= 5),
            ("7", board.is_seventyfive_moves()), ("T", claim3), ("F", claim50),
        ] if on))
        clocks.append(board.halfmove_clock)
        if i % 10 == 0:
            fens[str(i)] = board.fen()
        if board.is_game_over(claim_draw=False):
            break
    if not sans:
        return None
    fens[str(len(sans) - 1)] = board.fen()
    return {"sans": " ".join(sans), "flags": ",".join(flags), "clocks": clocks, "fens": fens}


def label_file(path: str):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        index = 0
        while True:
            try:
                game = chess.pgn.read_game(f)
            except Exception:  # noqa: BLE001 - malformed PGN is skipped
                index += 1
                continue
            if game is None:
                break
            if not game.errors:
                rec = label_game(game)
                if rec is not None:
                    rec["file"] = os.path.basename(path)
                    rec["index"] = index
                    out.append(rec)
            index += 1
    return out


def stockfish_divide(sf: subprocess.Popen, fen: str, depth: int):
    sf.stdin.write(f"position fen {fen}\ngo perft {depth}\n")
    sf.stdin.flush()
    divide = {}
    while True:
        line = sf.stdout.readline().strip()
        if line.startswith("Nodes searched"):
            return divide, int(line.split(":")[1])
        if ":" in line and len(line.split(":")[0]) in (4, 5):
            move, count = line.split(":")
            divide[move.strip()] = int(count)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pgn-dir", required=True)
    ap.add_argument("--stockfish", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--positions", type=int, default=2500)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    files = sorted(os.path.join(args.pgn_dir, f) for f in os.listdir(args.pgn_dir) if f.endswith(".pgn"))
    with mp.Pool() as pool:
        games = [g for chunk in pool.map(label_file, files) for g in chunk]
    with gzip.open(os.path.join(args.out, "real_games.jsonl.gz"), "wt") as f:
        for g in games:
            f.write(json.dumps(g, separators=(",", ":")) + "\n")
    flags = ",".join(g["flags"] for g in games)
    print(f"real games: {len(games)}, plies: {sum(len(g['clocks']) for g in games)}, "
          + ", ".join(f"{c}={flags.count(c)}" for c in "cMSD2357TF"))

    # Positions: sampled from real games plus steered random play (promotions,
    # en passant, castling edge cases), all verified by Stockfish perft.
    rng = random.Random(7)
    positions = set()
    for g in rng.sample(games, min(len(games), args.positions)):
        board = chess.Board()
        sans = g["sans"].split(" ")
        stop = rng.randrange(len(sans))
        for san in sans[:stop]:
            board.push_san(san)
        positions.add(board.fen())
    for _ in range(args.positions // 3):
        board = chess.Board()
        for _ in range(rng.randrange(20, 160)):
            moves = list(board.legal_moves)
            if not moves:
                break
            special = [m for m in moves if m.promotion or board.is_en_passant(m) or board.is_castling(m)]
            board.push(rng.choice(special) if special and rng.random() < 0.7 else rng.choice(moves))
        if not board.is_game_over():
            positions.add(board.fen())

    sf = subprocess.Popen([args.stockfish], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    sf.stdin.write("uci\n")
    sf.stdin.flush()
    while sf.stdout.readline().strip() != "uciok":
        pass
    records = []
    for fen in sorted(positions):
        board = chess.Board(fen)
        divide, total = stockfish_divide(sf, fen, 3)
        records.append({
            "fen": fen,
            "divide3": divide,
            "nodes3": total,
            "sans": sorted(board.san(m) for m in board.legal_moves),
        })
    deep = [
        (chess.STARTING_FEN, 5),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 4),
        ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 5),
        ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 4),
        ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 4),
        ("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 4),
    ]
    deep_records = []
    for fen, depth in deep:
        divide, total = stockfish_divide(sf, fen, depth)
        deep_records.append({"fen": fen, "depth": depth, "divide": divide, "nodes": total})
    sf.stdin.write("quit\n")
    sf.stdin.flush()
    with gzip.open(os.path.join(args.out, "perft_positions.json.gz"), "wt") as f:
        json.dump({"positions": records, "deep": deep_records}, f, separators=(",", ":"))
    print(f"perft positions: {len(records)}, perft3 nodes: {sum(r['nodes3'] for r in records)}, "
          f"deep: {[(d['depth'], d['nodes']) for d in deep_records]}")


if __name__ == "__main__":
    main()
