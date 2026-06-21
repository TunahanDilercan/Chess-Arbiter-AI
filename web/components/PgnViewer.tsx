"use client";

import type { MoveAnalysis } from "@/lib/types";

// Renders the game's moves as a rich, clickable PGN: muted move numbers,
// monospace SAN tokens (illegal reads flagged), and the result token. The
// tokens are built from the analyzed `moves` array (not the raw PGN string)
// so every SAN maps back to a ply_index for click-to-jump. The raw PGN is
// only mined for the trailing result token (1-0 / 0-1 / 1/2-1/2 / *).

const RESULT_RE = /(1-0|0-1|1\/2-1\/2|\*)\s*$/;

function extractResult(pgn: string | null | undefined): string | null {
  if (!pgn) return null;
  const m = pgn.trim().match(RESULT_RE);
  return m ? m[1] : null;
}

function sanText(move: MoveAnalysis): string {
  return move.selected_san ?? move.normalized_text ?? move.ocr_raw_text;
}

export default function PgnViewer({
  moves,
  pgn,
  selectedPly,
  onSelect,
}: {
  moves: MoveAnalysis[];
  pgn?: string | null;
  selectedPly: number | null;
  onSelect: (ply: number) => void;
}) {
  const result = extractResult(pgn);

  if (moves.length === 0) {
    return (
      <div className="empty-state">
        <span className="empty-state-glyph">♟</span>
        <p>No PGN available yet.</p>
      </div>
    );
  }

  // Pair plies into full moves (white ply = even ply_index).
  const pairs: { num: number; white?: MoveAnalysis; black?: MoveAnalysis }[] = [];
  for (const m of moves) {
    const num = Math.floor(m.ply_index / 2) + 1;
    let pair = pairs[pairs.length - 1];
    if (!pair || pair.num !== num) {
      pair = { num };
      pairs.push(pair);
    }
    if (m.ply_index % 2 === 0) pair.white = m;
    else pair.black = m;
  }

  return (
    <div className="pgn">
      {pairs.map((pair) => (
        <span key={pair.num}>
          <span className="pgn-num">{pair.num}.</span>{" "}
          {pair.white && (
            <>
              <PgnMove
                move={pair.white}
                selected={pair.white.ply_index === selectedPly}
                onSelect={onSelect}
              />{" "}
            </>
          )}
          {pair.black && (
            <>
              <PgnMove
                move={pair.black}
                selected={pair.black.ply_index === selectedPly}
                onSelect={onSelect}
              />{" "}
            </>
          )}
        </span>
      ))}
      {result && <span className="pgn-result">{result}</span>}
    </div>
  );
}

function PgnMove({
  move,
  selected,
  onSelect,
}: {
  move: MoveAnalysis;
  selected: boolean;
  onSelect: (ply: number) => void;
}) {
  return (
    <button
      type="button"
      className={`pgn-move${selected ? " current" : ""}${move.is_legal ? "" : " illegal"}`}
      onClick={() => onSelect(move.ply_index)}
      title={`ply ${move.ply_index}`}
    >
      {sanText(move)}
    </button>
  );
}
