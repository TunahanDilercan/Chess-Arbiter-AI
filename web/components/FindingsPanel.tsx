"use client";

import { AlertTriangle, Ban, CheckCircle2 } from "lucide-react";
import type { GameAnalysisResponse, RuleFinding } from "@/lib/types";

// FIDE distinction (critical — see CLAUDE.md): automatic findings (fivefold
// repetition, 75-move rule, checkmate, stalemate, dead position) end the game
// with no claim needed — the arbiter must intervene. Claimable findings
// (threefold repetition, fifty-move rule) only matter if a player claims them.
// The `is_automatic` flag from the backend is the single source of truth; the
// frontend only renders the distinction, never decides it.

function FindingCard({
  finding,
  onJump,
}: {
  finding: RuleFinding;
  onJump: (ply: number) => void;
}) {
  const automatic = finding.is_automatic;
  const kind = automatic ? "automatic" : "claimable";
  return (
    <div className={`alert-card ${kind}`}>
      <div className="alert-head">
        <span
          className="alert-icon"
          style={{
            color: automatic
              ? "var(--color-feedback-danger)"
              : "var(--color-feedback-warning)",
          }}
        >
          {automatic ? (
            <Ban size={18} strokeWidth={2} />
          ) : (
            <AlertTriangle size={18} strokeWidth={2} />
          )}
        </span>
        <span className="alert-title">
          {finding.type.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())}
        </span>
        <span className={`alert-kind ${kind}`}>{kind}</span>
      </div>
      <div className="alert-body">{finding.description}</div>
      <div className="alert-foot">
        <span className="article-ref">
          {automatic ? "Arbiter must end" : "Player may claim"}
        </span>
        <button
          type="button"
          className="ply-chip"
          onClick={() => onJump(finding.ply_index)}
        >
          ply {finding.ply_index} →
        </button>
      </div>
    </div>
  );
}

export default function FindingsPanel({
  game,
  onJump,
}: {
  game: GameAnalysisResponse;
  onJump: (ply: number) => void;
}) {
  const automatic = game.findings.filter((f) => f.is_automatic);
  const claimable = game.findings.filter((f) => !f.is_automatic);
  const nothing =
    game.findings.length === 0 &&
    !game.arbiter_must_end &&
    !game.requires_player_claim;

  if (nothing) {
    return (
      <div className="empty-state">
        <span
          className="empty-state-glyph"
          style={{ color: "var(--color-feedback-success)" }}
        >
          <CheckCircle2 size={40} strokeWidth={1.75} />
        </span>
        <h3>No findings</h3>
        <p>Nothing in this game requires arbiter attention.</p>
      </div>
    );
  }

  return (
    <>
      {game.arbiter_must_end && (
        <div className="alert-card automatic">
          <div className="alert-head">
            <span
              className="alert-icon"
              style={{ color: "var(--color-feedback-danger)" }}
            >
              <Ban size={18} strokeWidth={2} />
            </span>
            <span className="alert-title">Arbiter must end the game</span>
            <span className="alert-kind automatic">automatic</span>
          </div>
          <div className="alert-body">{game.draw_reason ?? game.draw_decision}</div>
        </div>
      )}
      {!game.arbiter_must_end && game.requires_player_claim && (
        <div className="alert-card claimable">
          <div className="alert-head">
            <span
              className="alert-icon"
              style={{ color: "var(--color-feedback-warning)" }}
            >
              <AlertTriangle size={18} strokeWidth={2} />
            </span>
            <span className="alert-title">Draw claimable by a player</span>
            <span className="alert-kind claimable">claimable</span>
          </div>
          <div className="alert-body">{game.draw_reason ?? game.draw_decision}</div>
        </div>
      )}

      {automatic.map((f, i) => (
        <FindingCard key={`a-${i}`} finding={f} onJump={onJump} />
      ))}
      {claimable.map((f, i) => (
        <FindingCard key={`c-${i}`} finding={f} onJump={onJump} />
      ))}
    </>
  );
}
