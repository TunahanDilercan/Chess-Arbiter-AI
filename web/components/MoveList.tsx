"use client";

import { useEffect, useRef } from "react";
import { X } from "lucide-react";
import type { MoveAnalysis } from "@/lib/types";

// Confidence band → dot class. Mirrors the design's confidence tokens
// (low <0.5, medium <0.8, high <0.95, certain otherwise). A dot is only
// shown when the read is not yet "certain", to flag where attention is needed.
function confDot(move: MoveAnalysis): string | null {
  if (move.confidence >= 0.95) return null;
  if (move.confidence < 0.5) return "conf-low";
  if (move.confidence < 0.8) return "conf-medium";
  return "conf-high-dot";
}

function Cell({
  move,
  selected,
  onSelect,
}: {
  move?: MoveAnalysis;
  selected: boolean;
  onSelect: (ply: number) => void;
}) {
  if (!move) return <span className="ml-cell empty" aria-hidden="true" />;

  const dot = confDot(move);
  const text = move.selected_san ?? move.normalized_text ?? move.ocr_raw_text;
  const underline = move.is_legal && move.needs_manual_review;

  return (
    <button
      type="button"
      data-ply={move.ply_index}
      className={`ml-cell${selected ? " current" : ""}${move.is_legal ? "" : " illegal"}`}
      onClick={() => onSelect(move.ply_index)}
    >
      {dot && <span className={`conf-dot ${dot}`} />}
      <span className={underline ? "ml-san-underline" : undefined}>
        {!move.is_legal && (
          <X
            size={12}
            strokeWidth={2.5}
            style={{ display: "inline", verticalAlign: "-1px", marginRight: 2 }}
          />
        )}
        {text}
      </span>
    </button>
  );
}

export default function MoveList({
  moves,
  selectedPly,
  onSelect,
  emptyMessage = "No moves yet.",
}: {
  moves: MoveAnalysis[];
  selectedPly: number | null;
  onSelect: (ply: number) => void;
  emptyMessage?: string;
}) {
  const listRef = useRef<HTMLDivElement>(null);
  const pairs = moves.reduce<
    { moveNumber: number; white?: MoveAnalysis; black?: MoveAnalysis }[]
  >((acc, move) => {
    let pair = acc.find((p) => p.moveNumber === move.move_number);
    if (!pair) {
      pair = { moveNumber: move.move_number };
      acc.push(pair);
    }
    if (move.color === "white") pair.white = move;
    else pair.black = move;
    return acc;
  }, []);

  useEffect(() => {
    if (selectedPly === null || !listRef.current) return;
    const row = listRef.current.querySelector<HTMLElement>(
      `[data-ply="${selectedPly}"]`,
    );
    row?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [selectedPly]);

  if (moves.length === 0) {
    return (
      <div className="movelist">
        <div className="empty-state">
          <span className="empty-state-glyph">♟</span>
          <p>{emptyMessage}</p>
        </div>
      </div>
    );
  }

  return (
    <div ref={listRef} className="movelist">
      {pairs.map((pair) => (
        <div key={pair.moveNumber} className="ml-row">
          <span className="ml-num">{pair.moveNumber}.</span>
          <Cell
            move={pair.white}
            selected={pair.white?.ply_index === selectedPly}
            onSelect={onSelect}
          />
          <Cell
            move={pair.black}
            selected={pair.black?.ply_index === selectedPly}
            onSelect={onSelect}
          />
        </div>
      ))}
    </div>
  );
}
