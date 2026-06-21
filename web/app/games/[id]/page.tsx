"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  Ban,
  Check,
  ChevronLeft,
  ChevronRight,
  HelpCircle,
  Moon,
  Palette as PaletteIcon,
  RotateCcw,
  SkipBack,
  SkipForward,
  Sun,
  X,
} from "lucide-react";
import ChessBoard, { PALETTES, type Palette } from "@/components/ChessBoard";
import MoveList from "@/components/MoveList";
import FindingsPanel from "@/components/FindingsPanel";
import PgnViewer from "@/components/PgnViewer";
import PlyDetailModal from "@/components/PlyDetailModal";
import { ApiError, getGame, listGames } from "@/lib/api";
import type {
  GameAnalysisResponse,
  GameSummary,
  MoveAnalysis,
} from "@/lib/types";

const SESSION_KEY = "arbiter_session_id";
const THEME_KEY = "arbiter_theme";
const PALETTE_KEY = "arbiter_palette";
const PALETTE_LABELS: Record<Palette, string> = {
  wood: "Wood",
  slate: "Slate",
  mono: "Mono",
  oled: "OLED",
};
const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
const PROCESSING = new Set([
  "processing",
  "queued",
  "preprocessing",
  "cropping",
  "ocr_processing",
  "ocr_complete",
  "analyzing",
]);

// Ordered backend statuses, used to decide which pipeline step is done/active.
const STATUS_ORDER = [
  "queued",
  "processing",
  "preprocessing",
  "cropping",
  "ocr_processing",
  "ocr_complete",
  "analyzing",
  "completed",
];
const STEPS: { label: string; statuses: string[] }[] = [
  { label: "Queued", statuses: ["queued", "processing"] },
  { label: "Preprocessing image", statuses: ["preprocessing", "cropping"] },
  { label: "Reading handwriting (OCR)", statuses: ["ocr_processing", "ocr_complete"] },
  { label: "Validating moves", statuses: ["analyzing"] },
];

type Tab = "alerts" | "pgn" | "stats";

function statusBadge(status: string): { cls: string; label: string } {
  if (status === "completed") return { cls: "status-ready", label: "Ready" };
  if (status === "failed") return { cls: "status-failed", label: "Failed" };
  return { cls: "status-processing", label: "Processing" };
}

export default function GamePage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const gameId = params.id;

  const [game, setGame] = useState<GameAnalysisResponse | null>(null);
  const [recent, setRecent] = useState<GameSummary[]>([]);
  const [selectedPly, setSelectedPly] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [flipped, setFlipped] = useState(false);
  const [tab, setTab] = useState<Tab>("alerts");
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const [palette, setPaletteState] = useState<Palette>("wood");
  const [showSettings, setShowSettings] = useState(false);
  const [showHelp, setShowHelp] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const g = await getGame(gameId);
      setGame(g);
      setError(null);
      return g;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Could not load game");
      return null;
    }
  }, [gameId]);

  // Initial load + poll every 2.5s while the pipeline is still running.
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancelled = false;
    async function tick() {
      const g = await load();
      if (!cancelled && g && PROCESSING.has(g.status)) {
        timer = setTimeout(tick, 2500);
      }
    }
    void tick();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [load]);

  // Recent jobs for the sidebar (same anonymous session).
  useEffect(() => {
    const sid = localStorage.getItem(SESSION_KEY);
    if (!sid) return;
    void listGames(sid)
      .then(setRecent)
      .catch(() => undefined);
  }, [gameId]);

  // Restore persisted appearance prefs on mount (theme is applied to <html>).
  useEffect(() => {
    const savedTheme = localStorage.getItem(THEME_KEY);
    if (savedTheme === "light" || savedTheme === "dark") {
      setTheme(savedTheme);
      document.documentElement.setAttribute("data-theme", savedTheme);
    }
    const savedPalette = localStorage.getItem(PALETTE_KEY);
    if (savedPalette && (PALETTES as string[]).includes(savedPalette)) {
      setPaletteState(savedPalette as Palette);
    }
  }, []);

  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem(THEME_KEY, next);
  }

  function setPalette(next: Palette) {
    setPaletteState(next);
    localStorage.setItem(PALETTE_KEY, next);
  }

  const moves = useMemo(() => game?.moves ?? [], [game]);
  const selected: MoveAnalysis | null = useMemo(
    () => moves.find((m) => m.ply_index === selectedPly) ?? null,
    [moves, selectedPly],
  );

  const goto = useCallback(
    (ply: number | null) => {
      setSelectedPly(ply);
    },
    [],
  );

  // Keyboard navigation. Disabled while typing or while a modal is open.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null;
      if (target && ["INPUT", "SELECT", "TEXTAREA"].includes(target.tagName)) return;
      if (modalOpen) return;
      if (e.key === "?") {
        setShowHelp((v) => !v);
        return;
      }
      if (e.key === "f" || e.key === "F") {
        setFlipped((v) => !v);
        return;
      }
      if (moves.length === 0) return;
      const idx =
        selectedPly === null
          ? -1
          : moves.findIndex((m) => m.ply_index === selectedPly);
      if (e.key === "ArrowRight" && idx < moves.length - 1) {
        e.preventDefault();
        goto(moves[idx + 1].ply_index);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        goto(idx > 0 ? moves[idx - 1].ply_index : null);
      } else if (e.key === "Home") {
        e.preventDefault();
        goto(null);
      } else if (e.key === "End") {
        e.preventDefault();
        goto(moves[moves.length - 1].ply_index);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [moves, selectedPly, modalOpen, goto]);

  const title = game?.upload_metadata.filename ?? gameId;

  // ---- loading ----
  if (!game && !error) {
    return (
      <div className="w-page" style={{ gridTemplateColumns: "1fr" }}>
        <div className="w-center">
          <div className="w-reconnect">
            <span className="w-spinner" /> Loading game…
          </div>
        </div>
      </div>
    );
  }

  // ---- load error ----
  if (error && !game) {
    return (
      <div className="w-center" style={{ height: "100%" }}>
        <div className="w-error-card">
          <div
            className="w-empty-glyph"
            style={{ color: "var(--color-feedback-danger)" }}
          >
            <AlertTriangle size={56} strokeWidth={1.75} />
          </div>
          <h2>Could not load this game</h2>
          <div className="w-error-detail">{error}</div>
          <button
            type="button"
            className="w-btn w-btn-primary"
            onClick={() => router.push("/")}
          >
            <ArrowLeft size={18} strokeWidth={1.75} /> Back to scans
          </button>
        </div>
      </div>
    );
  }

  if (!game) return null;

  // ---- processing ----
  if (PROCESSING.has(game.status)) {
    const curIdx = STATUS_ORDER.indexOf(game.status);
    return (
      <div className="w-page" style={{ gridTemplateColumns: "1fr" }}>
        <div className="w-center">
          <div className="w-proc-card">
            <div className="w-proc-head">
              <span className="w-knight" style={{ fontSize: 32 }}>
                ♞
              </span>
              <div>
                <div className="w-proc-title">Analyzing scoresheet</div>
                <div className="w-proc-sub">{title}</div>
              </div>
            </div>
            <div className="w-steps">
              {STEPS.map((step) => {
                const stepMax = Math.max(
                  ...step.statuses.map((s) => STATUS_ORDER.indexOf(s)),
                );
                const active = step.statuses.includes(game.status);
                const done = curIdx > stepMax;
                const dotCls = done
                  ? "w-step-dot-done"
                  : active
                    ? "w-step-dot-active"
                    : "w-step-dot-pending";
                return (
                  <div className="w-step" key={step.label}>
                    <div className="w-step-row">
                      <span className={`w-step-dot ${dotCls}`}>
                        {done ? <Check size={14} strokeWidth={2.5} /> : null}
                      </span>
                      <span
                        className={`w-step-label${!done && !active ? " pending" : ""}`}
                      >
                        {step.label}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
            <div className="w-reconnect">
              <span className="w-spinner" /> Live updates — this page refreshes
              automatically.
            </div>
          </div>
        </div>
      </div>
    );
  }

  // ---- ready / failed workspace ----
  const fen = selected ? selected.fen_after : START_FEN;
  const lastFrom = selected?.selected_uci ? selected.selected_uci.slice(0, 2) : null;
  const lastTo = selected?.selected_uci ? selected.selected_uci.slice(2, 4) : null;
  const errorSquare = selected && !selected.is_legal ? lastTo : null;
  const isFailed = game.status === "failed";
  const sideToMove = fen.split(" ")[1] === "b" ? "black" : "white";
  const atEnd =
    moves.length > 0 && selectedPly === moves[moves.length - 1].ply_index;
  const badge = statusBadge(game.status);

  const idx =
    selectedPly === null
      ? -1
      : moves.findIndex((m) => m.ply_index === selectedPly);

  const banner =
    isFailed && atEnd
      ? "Replay stopped — illegal move"
      : atEnd && game.draw_decision && game.draw_decision !== "none"
        ? game.arbiter_must_end
          ? "Arbiter must end — draw"
          : "Draw claimable"
        : null;

  function PlayerBar({ color }: { color: "white" | "black" }) {
    return (
      <div className="player-bar">
        <span className="player-name">
          {color === "white" ? "White" : "Black"}
        </span>
        {sideToMove === color && !isFailed && (
          <span className="turn-tag">to move</span>
        )}
      </div>
    );
  }

  const topColor: "white" | "black" = flipped ? "white" : "black";
  const bottomColor: "white" | "black" = flipped ? "black" : "white";

  return (
    <div className="app">
      <header className="app-header">
        <div className="wordmark">
          <span className="knight-mark">♞</span> Arbiter AI
        </div>
        <div className="header-divider" />
        <div className="job-context">
          <span className="job-title">{title}</span>
          <span className="job-sub">{game.game_id}</span>
        </div>
        <div className="header-spacer" />
        <span className={`status-badge ${badge.cls}`}>{badge.label}</span>
        {game.failure_point_ply !== null && (
          <span className="status-badge status-failed">
            stops @ ply {game.failure_point_ply}
          </span>
        )}
        <div className="settings-anchor">
          <button
            type="button"
            className={`icon-btn${showSettings ? " active" : ""}`}
            onClick={() => setShowSettings((v) => !v)}
            aria-label="Board palette"
            aria-expanded={showSettings}
            title="Board palette"
          >
            <PaletteIcon size={20} strokeWidth={1.75} />
          </button>
          {showSettings && (
            <>
              <div
                className="settings-scrim"
                onClick={() => setShowSettings(false)}
              />
              <div className="settings-pop" role="menu">
                <div className="settings-pop-label">Board palette</div>
                {PALETTES.map((p) => (
                  <button
                    key={p}
                    type="button"
                    role="menuitemradio"
                    aria-checked={palette === p}
                    className={`palette-row${palette === p ? " active" : ""}`}
                    onClick={() => {
                      setPalette(p);
                      setShowSettings(false);
                    }}
                  >
                    <span className={`palette-swatch palette-swatch-${p}`} />
                    {PALETTE_LABELS[p]}
                    {palette === p && (
                      <Check
                        size={15}
                        strokeWidth={2.5}
                        style={{ marginLeft: "auto" }}
                      />
                    )}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
        <button
          type="button"
          className="icon-btn"
          onClick={toggleTheme}
          aria-label="Toggle theme"
          title="Toggle theme"
        >
          {theme === "dark" ? (
            <Sun size={20} strokeWidth={1.75} />
          ) : (
            <Moon size={20} strokeWidth={1.75} />
          )}
        </button>
        <button
          type="button"
          className="icon-btn"
          onClick={() => setShowHelp(true)}
          aria-label="Keyboard shortcuts"
          title="Keyboard shortcuts (?)"
        >
          <HelpCircle size={20} strokeWidth={1.75} />
        </button>
      </header>

      <aside className="sidebar">
        <button
          type="button"
          className="w-nav-item"
          onClick={() => router.push("/")}
        >
          <ArrowLeft size={18} strokeWidth={1.75} /> All scans
        </button>
        <div className="side-label">Recent jobs</div>
        <div className="job-list">
          {recent.map((g) => (
            <button
              key={g.game_id}
              type="button"
              className={`job-row${g.game_id === gameId ? " active" : ""}`}
              onClick={() => router.push(`/games/${g.game_id}`)}
            >
              <span className="job-thumb" />
              <span className="job-row-main">
                <span className="job-row-title">
                  {g.upload_filename ?? g.game_id}
                </span>
                <span className="job-row-sub">{g.status}</span>
              </span>
              <span className="job-row-meta">
                {g.has_findings && <span className="job-alert-dot" />}
                {g.total_moves !== null && (
                  <span className="job-plies">{g.total_moves}</span>
                )}
              </span>
            </button>
          ))}
        </div>
      </aside>

      <main className="main">
        <div className="board-column">
          <PlayerBar color={topColor} />
          <div className="board-wrap">
            <ChessBoard
              fen={fen}
              lastMoveFrom={lastFrom}
              lastMoveTo={lastTo}
              errorSquare={errorSquare}
              checkSquare={selected?.check_square ?? null}
              flipped={flipped}
              palette={palette}
              dimmed={Boolean(banner)}
            />
            {banner && <div className="board-banner">{banner}</div>}
          </div>
          <PlayerBar color={bottomColor} />

          <div className="board-controls">
            <button
              type="button"
              className="icon-btn"
              title="Start"
              onClick={() => goto(null)}
              disabled={selectedPly === null}
            >
              <SkipBack size={18} strokeWidth={1.75} />
            </button>
            <button
              type="button"
              className="icon-btn"
              title="Previous"
              onClick={() => goto(idx > 0 ? moves[idx - 1].ply_index : null)}
              disabled={selectedPly === null}
            >
              <ChevronLeft size={18} strokeWidth={1.75} />
            </button>
            <button
              type="button"
              className="icon-btn"
              title="Next"
              onClick={() =>
                goto(
                  idx < moves.length - 1 ? moves[idx + 1].ply_index : selectedPly,
                )
              }
              disabled={moves.length === 0 || idx === moves.length - 1}
            >
              <ChevronRight size={18} strokeWidth={1.75} />
            </button>
            <button
              type="button"
              className="icon-btn"
              title="End"
              onClick={() =>
                moves.length && goto(moves[moves.length - 1].ply_index)
              }
              disabled={moves.length === 0 || atEnd}
            >
              <SkipForward size={18} strokeWidth={1.75} />
            </button>
            <button
              type="button"
              className="icon-btn"
              title="Flip board (F)"
              onClick={() => setFlipped((v) => !v)}
            >
              <RotateCcw size={18} strokeWidth={1.75} />
            </button>
            <div className="ply-readout">
              <span className="ply-readout-san">
                {selected
                  ? (selected.selected_san ?? selected.normalized_text ?? "—")
                  : "Start"}
              </span>
              <span className="ply-readout-idx">
                {selectedPly === null
                  ? "position"
                  : `ply ${selectedPly + 1} / ${moves.length}`}
              </span>
            </div>
          </div>
        </div>
      </main>

      <section className="rail">
        <div className="movelist-pane">
          <div className="pane-head">
            <span className="pane-title">Moves</span>
            <span className="pane-hint">click to inspect · ← → to step</span>
          </div>
          <MoveList
            moves={moves}
            selectedPly={selectedPly}
            onSelect={(ply) => {
              setSelectedPly(ply);
              setModalOpen(true);
            }}
            emptyMessage={isFailed ? "No moves were produced." : undefined}
          />
        </div>

        <div className="rail-divider" />

        <div className="findings-pane">
          <div className="tab-strip">
            {(
              [
                ["alerts", `Alerts (${game.findings.length})`],
                ["pgn", "PGN"],
                ["stats", "Stats"],
              ] as [Tab, string][]
            ).map(([t, label]) => (
              <button
                key={t}
                type="button"
                className={`tab${tab === t ? " active" : ""}`}
                onClick={() => setTab(t)}
              >
                {label}
              </button>
            ))}
          </div>
          <div className="tab-body">
            {tab === "alerts" && (
              <>
                {isFailed && (
                  <div className="alert-card automatic">
                    <div className="alert-head">
                      <span
                        className="alert-icon"
                        style={{ color: "var(--color-feedback-danger)" }}
                      >
                        <Ban size={18} strokeWidth={2} />
                      </span>
                      <span className="alert-title">Processing failed</span>
                    </div>
                    <div className="alert-body">
                      {game.processing_error ??
                        "The worker did not return an error message. Check the backend worker logs."}
                    </div>
                  </div>
                )}
                <FindingsPanel
                  game={game}
                  onJump={(ply) => {
                    setSelectedPly(ply);
                    setModalOpen(true);
                  }}
                />
              </>
            )}
            {tab === "pgn" && (
              <PgnViewer
                moves={moves}
                pgn={game.pgn}
                selectedPly={selectedPly}
                onSelect={(ply) => setSelectedPly(ply)}
              />
            )}
            {tab === "stats" && (
              <div className="stat-grid">
                <div className="stat-cell">
                  <div className="stat-value">{game.stats.total_moves}</div>
                  <div className="stat-label">Moves</div>
                </div>
                <div className="stat-cell">
                  <div
                    className="stat-value"
                    style={{ color: "var(--color-feedback-success)" }}
                  >
                    {game.stats.auto_resolved}
                  </div>
                  <div className="stat-label">Auto-resolved</div>
                </div>
                <div className="stat-cell">
                  <div
                    className="stat-value"
                    style={{ color: "var(--color-feedback-warning)" }}
                  >
                    {game.stats.manual_review_required}
                  </div>
                  <div className="stat-label">Needs review</div>
                </div>
                <div className="stat-cell">
                  <div
                    className="stat-value"
                    style={{ color: "var(--color-feedback-danger)" }}
                  >
                    {game.stats.illegal_moves}
                  </div>
                  <div className="stat-label">Illegal</div>
                </div>
                <div className="stat-cell">
                  <div className="stat-value">
                    {(game.stats.ocr_avg_confidence * 100).toFixed(0)}%
                  </div>
                  <div className="stat-label">OCR confidence</div>
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      {modalOpen && selected && (
        <PlyDetailModal
          gameId={game.game_id}
          move={selected}
          locale={game.locale || "en"}
          onCorrected={(updated) => {
            setGame(updated);
            setModalOpen(false);
          }}
          onClose={() => setModalOpen(false)}
        />
      )}

      {showHelp && (
        <div
          className="scrim"
          onClick={(e) => {
            if (e.target === e.currentTarget) setShowHelp(false);
          }}
        >
          <div className="modal" role="dialog" aria-modal="true">
            <div className="modal-head">
              <span className="modal-title" style={{ fontFamily: "var(--font-family-ui)" }}>
                Keyboard shortcuts
              </span>
              <button
                type="button"
                className="icon-btn modal-close"
                aria-label="Close"
                onClick={() => setShowHelp(false)}
              >
                <X size={18} strokeWidth={2} />
              </button>
            </div>
            <div className="shortcut-grid">
              <span className="kbd">←</span>
              <span className="shortcut-desc">Previous move</span>
              <span className="kbd">→</span>
              <span className="shortcut-desc">Next move</span>
              <span className="kbd">Home</span>
              <span className="shortcut-desc">Jump to start</span>
              <span className="kbd">End</span>
              <span className="shortcut-desc">Jump to final position</span>
              <span className="kbd">F</span>
              <span className="shortcut-desc">Flip board</span>
              <span className="kbd">?</span>
              <span className="shortcut-desc">Toggle this help</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
