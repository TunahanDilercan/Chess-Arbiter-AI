"use client";

import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { ApiError, correctMove } from "@/lib/api";
import type { GameAnalysisResponse, MoveAnalysis } from "@/lib/types";

// Confidence band → token class for the pill (low <0.5, medium <0.8,
// high <0.95, certain otherwise).
function confBand(c: number): { cls: string; label: string } {
  if (c < 0.5) return { cls: "conf-band-low", label: "low" };
  if (c < 0.8) return { cls: "conf-band-medium", label: "medium" };
  if (c < 0.95) return { cls: "conf-band-high", label: "high" };
  return { cls: "conf-band-certain", label: "certain" };
}

export default function PlyDetailModal({
  gameId,
  move,
  locale,
  onCorrected,
  onClose,
}: {
  gameId: string;
  move: MoveAnalysis;
  locale: string;
  onCorrected: (updated: GameAnalysisResponse) => void;
  onClose: () => void;
}) {
  const currentSan = move.selected_san || move.normalized_text || move.ocr_raw_text;
  const [san, setSan] = useState(currentSan ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const band = confBand(move.confidence);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  // The backend is the validation authority: we POST the chosen SAN and it
  // returns the re-validated game. The frontend never decides legality.
  async function submit(value: string) {
    const trimmed = value.trim();
    if (!trimmed || busy) return;
    const sessionId = localStorage.getItem("arbiter_session_id");
    if (!sessionId) {
      setError("No session — reopen this game from the device that uploaded it.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const updated = await correctMove(
        gameId,
        move.ply_index,
        trimmed,
        sessionId,
        locale,
      );
      onCorrected(updated);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Correction failed");
      setBusy(false);
    }
  }

  const normalized = move.normalized_text || move.selected_san || "—";

  return (
    <div
      className="scrim"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="modal" role="dialog" aria-modal="true">
        <div className="modal-head">
          <span className="modal-title">
            {move.move_number}
            {move.color === "white" ? "." : "…"} {currentSan}
          </span>
          <span className={`conf-pill ${band.cls}`}>
            {band.label} {(move.confidence * 100).toFixed(0)}%
          </span>
          <button
            type="button"
            className="icon-btn modal-close"
            aria-label="Close"
            onClick={onClose}
          >
            <X size={18} strokeWidth={2} />
          </button>
        </div>

        {move.crop_image_url && (
          <div className="crop-frame">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={move.crop_image_url}
              alt={`Handwriting crop for move ${move.move_number} (${move.color})`}
            />
          </div>
        )}

        <div className="ocr-compare">
          <div className="ocr-cell">
            <span className="ocr-cell-label">OCR read</span>
            <span className="ocr-cell-value">{move.ocr_raw_text || "—"}</span>
          </div>
          <div className="ocr-cell ocr-cell-diff">
            <span className="ocr-cell-label">Normalized</span>
            <span className="ocr-cell-value">{normalized}</span>
          </div>
        </div>

        {!move.is_legal && (
          <div className="ocr-note" style={{ color: "var(--color-feedback-danger)" }}>
            This move is not legal from the current position — pick a candidate or
            enter the correct move.
          </div>
        )}

        {move.ocr_candidates.length > 0 && (
          <div>
            <div className="section-label" style={{ marginBottom: 8 }}>
              Candidates
            </div>
            <div className="cand-row">
              {move.ocr_candidates.slice(0, 6).map((c) => (
                <button
                  key={c.text}
                  type="button"
                  className={`cand-chip${san.trim() === c.text ? " selected" : ""}`}
                  disabled={busy}
                  onClick={() => {
                    setSan(c.text);
                    setError(null);
                  }}
                >
                  {c.text}
                  <span className="cand-p">{(c.confidence * 100).toFixed(0)}%</span>
                </button>
              ))}
            </div>
          </div>
        )}

        {move.review_reasons.length > 0 && (
          <div className="review-reasons">
            {move.review_reasons.map((r) => (
              <span key={r}>• {r}</span>
            ))}
          </div>
        )}

        <div>
          <div className="section-label" style={{ marginBottom: 8 }}>
            Corrected move (SAN)
          </div>
          <input
            className="san-input"
            placeholder="e.g. Nf3, O-O, exd5"
            value={san}
            onChange={(e) => setSan(e.target.value)}
            disabled={busy}
            spellCheck={false}
            onKeyDown={(e) => {
              if (e.key === "Enter") void submit(san);
            }}
          />
        </div>

        {error && (
          <div className="ocr-note" style={{ color: "var(--color-feedback-danger)" }}>
            {error}
          </div>
        )}

        <div className="modal-actions">
          <button
            type="button"
            className="btn btn-secondary btn-compact"
            onClick={onClose}
            disabled={busy}
          >
            Cancel
          </button>
          <button
            type="button"
            className="btn btn-primary btn-compact"
            onClick={() => void submit(san)}
            disabled={busy || !san.trim()}
          >
            {busy ? "Saving…" : "Save correction"}
          </button>
        </div>
      </div>
    </div>
  );
}
