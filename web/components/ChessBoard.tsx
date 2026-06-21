"use client";

// Pure display component. It renders whatever FEN the backend produced — it
// never computes legality, checks, or moves (that authority lives in the
// backend; see CLAUDE.md "Frontend never validates chess logic").

const ROLES: Record<string, string> = {
  k: "K",
  q: "Q",
  r: "R",
  b: "B",
  n: "N",
  p: "P",
};

const FILES = ["a", "b", "c", "d", "e", "f", "g", "h"];

export type Palette = "wood" | "slate" | "mono" | "oled";

export const PALETTES: Palette[] = ["wood", "slate", "mono", "oled"];

const PALETTE_VARS: Record<
  Palette,
  { light: string; dark: string; coord: string }
> = {
  wood: {
    light: "var(--color-board-wood-sq-light)",
    dark: "var(--color-board-wood-sq-dark)",
    coord: "var(--color-board-wood-coordinates)",
  },
  slate: {
    light: "var(--color-board-slate-sq-light)",
    dark: "var(--color-board-slate-sq-dark)",
    coord: "var(--color-board-slate-coordinates)",
  },
  mono: {
    light: "var(--color-board-mono-sq-light)",
    dark: "var(--color-board-mono-sq-dark)",
    coord: "var(--color-board-mono-coordinates)",
  },
  oled: {
    light: "var(--color-board-oled-sq-light)",
    dark: "var(--color-board-oled-sq-dark)",
    coord: "var(--color-board-oled-coordinates)",
  },
};

interface Piece {
  code: string;
  label: string;
}

function parseFen(fen: string): (Piece | null)[][] {
  const rows: (Piece | null)[][] = [];
  const placement = fen.split(" ")[0] ?? "";
  for (const rank of placement.split("/")) {
    const row: (Piece | null)[] = [];
    for (const ch of rank) {
      if (ch >= "1" && ch <= "8") {
        for (let i = 0; i < Number(ch); i++) row.push(null);
      } else {
        const role = ROLES[ch.toLowerCase()];
        if (role) {
          const isWhite = ch === ch.toUpperCase();
          row.push({
            code: `${isWhite ? "w" : "b"}${role}`,
            label: `${isWhite ? "White" : "Black"} ${role}`,
          });
        }
      }
    }
    while (row.length < 8) row.push(null);
    rows.push(row.slice(0, 8));
  }
  while (rows.length < 8) rows.push(new Array<Piece | null>(8).fill(null));
  return rows.slice(0, 8);
}

// Square name ("e4") → top-left percentage offset on an 8×8 grid.
function squarePos(square: string, flipped: boolean): { left: number; top: number } {
  const file = FILES.indexOf(square[0]);
  const rank = Number(square[1]); // 1..8
  if (file < 0 || !rank) return { left: 0, top: 0 };
  const col = flipped ? 7 - file : file;
  const row = flipped ? rank - 1 : 8 - rank;
  return { left: col * 12.5, top: row * 12.5 };
}

export default function ChessBoard({
  fen,
  lastMoveFrom,
  lastMoveTo,
  errorSquare,
  checkSquare,
  flipped = false,
  palette = "wood",
  dimmed = false,
}: {
  fen: string;
  lastMoveFrom?: string | null;
  lastMoveTo?: string | null;
  errorSquare?: string | null;
  checkSquare?: string | null;
  flipped?: boolean;
  palette?: Palette;
  dimmed?: boolean;
}) {
  const grid = parseFen(fen);
  const pal = PALETTE_VARS[palette];

  const squares: React.ReactNode[] = [];
  const overlays: React.ReactNode[] = [];
  const pieces: React.ReactNode[] = [];
  const coords: React.ReactNode[] = [];

  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const isLight = (r + f) % 2 === 0;
      squares.push(
        <div
          key={`sq-${r}-${f}`}
          className={isLight ? "board-sq-light" : "board-sq-dark"}
        />,
      );
    }
  }

  // Pieces & overlays are placed by absolute position so they animate when the
  // FEN changes and respect board flipping independently of the squares grid.
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const name = `${FILES[f]}${8 - r}`;
      const piece = grid[r][f];
      if (!piece) continue;
      const { left, top } = squarePos(name, flipped);
      pieces.push(
        <div
          key={piece.code + name}
          className="board-piece"
          style={{ left: `${left}%`, top: `${top}%` }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`/piece/cburnett/${piece.code}.svg`}
            alt={piece.label}
            draggable={false}
          />
        </div>,
      );
    }
  }

  for (const sq of [lastMoveFrom, lastMoveTo]) {
    if (!sq) continue;
    const { left, top } = squarePos(sq, flipped);
    overlays.push(
      <div
        key={`last-${sq}`}
        className="board-overlay ov-last"
        style={{ left: `${left}%`, top: `${top}%` }}
      />,
    );
  }
  if (errorSquare) {
    const { left, top } = squarePos(errorSquare, flipped);
    overlays.push(
      <div
        key={`err-${errorSquare}`}
        className="board-overlay ov-error"
        style={{ left: `${left}%`, top: `${top}%` }}
      />,
    );
  }
  if (checkSquare) {
    const { left, top } = squarePos(checkSquare, flipped);
    overlays.push(
      <div
        key={`chk-${checkSquare}`}
        className="board-overlay ov-check"
        style={{ left: `${left}%`, top: `${top}%` }}
      />,
    );
  }

  // Rank coords down the left edge, file coords along the bottom edge.
  for (let i = 0; i < 8; i++) {
    const rankLabel = flipped ? i + 1 : 8 - i;
    const fileLabel = FILES[flipped ? 7 - i : i];
    coords.push(
      <span
        key={`cr-${i}`}
        className="coord coord-rank"
        style={{ top: `${i * 12.5}%`, color: pal.coord }}
      >
        {rankLabel}
      </span>,
      <span
        key={`cf-${i}`}
        className="coord coord-file"
        style={{ left: `${i * 12.5}%`, width: "12.5%", color: pal.coord }}
      >
        {fileLabel}
      </span>,
    );
  }

  return (
    <div
      className={`board${dimmed ? " board-dimmed" : ""}`}
      style={
        {
          "--board-sq-light": pal.light,
          "--board-sq-dark": pal.dark,
        } as React.CSSProperties
      }
    >
      <div className="board-squares">{squares}</div>
      <div className="board-overlays">{overlays}</div>
      <div className="board-pieces">{pieces}</div>
      {coords}
    </div>
  );
}
