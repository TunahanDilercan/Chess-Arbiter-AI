"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, Files, Moon, Search, Sun, Upload } from "lucide-react";
import { ApiError, listGames, uploadScoresheet } from "@/lib/api";
import type { GameSummary } from "@/lib/types";

const ICON = { size: 20, strokeWidth: 1.75 } as const;

const SESSION_KEY = "arbiter_session_id";
const THEME_KEY = "arbiter_theme";
const LOCALES = [
  { value: "en", label: "English (KQRBN)" },
  { value: "tr", label: "Türkçe (ŞVKFA)" },
  { value: "de", label: "Deutsch (KDTLS)" },
  { value: "fr", label: "Français (RDTFC)" },
  { value: "es", label: "Español (RDTAC)" },
];
const ACCEPT = "image/jpeg,image/png,image/webp,image/tiff,application/pdf";

function newSessionId(): string {
  return `web-${crypto.randomUUID()}`;
}

// Maps the backend's many in-flight statuses onto the three design badges.
function badge(status: string): { cls: string; label: string } {
  if (status === "completed") return { cls: "w-badge-ready", label: "Ready" };
  if (status === "failed") return { cls: "w-badge-failed", label: "Failed" };
  if (status === "queued") return { cls: "w-badge-queued", label: "Queued" };
  return { cls: "w-badge-processing", label: "Processing" };
}

export default function HomePage() {
  const router = useRouter();
  const [sessionId, setSessionId] = useState("");
  const [games, setGames] = useState<GameSummary[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [view, setView] = useState<"scans" | "upload">("scans");
  const [query, setQuery] = useState("");
  const [locale, setLocale] = useState("en");
  const [busy, setBusy] = useState(false);
  const [drag, setDrag] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const fileRef = useRef<HTMLInputElement>(null);

  // The persisted theme is applied to <html> pre-paint by the inline script in
  // layout.tsx; here we just sync local state so the toggle icon is correct.
  useEffect(() => {
    const saved = localStorage.getItem(THEME_KEY);
    if (saved === "light" || saved === "dark") setTheme(saved);
  }, []);

  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem(THEME_KEY, next);
  }

  const refresh = useCallback(async (sid: string) => {
    if (!sid) return;
    try {
      setGames(await listGames(sid));
      setError(null);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Could not load games");
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    const sid = localStorage.getItem(SESSION_KEY) ?? newSessionId();
    localStorage.setItem(SESSION_KEY, sid);
    setSessionId(sid);
    void refresh(sid);
  }, [refresh]);

  const upload = useCallback(
    async (file: File) => {
      if (!file || busy || !sessionId) return;
      setBusy(true);
      setError(null);
      try {
        const resp = await uploadScoresheet(file, sessionId, locale);
        router.push(`/games/${resp.game_id}`);
      } catch (err) {
        setError(
          err instanceof ApiError || err instanceof Error
            ? err.message
            : "Upload failed",
        );
        setBusy(false);
      }
    },
    [busy, sessionId, locale, router],
  );

  function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDrag(false);
    const file = e.dataTransfer.files?.[0];
    if (file) void upload(file);
  }

  const filtered = games.filter((g) =>
    (g.upload_filename ?? g.game_id).toLowerCase().includes(query.toLowerCase()),
  );

  return (
    <div className="w-page">
      <header className="w-header">
        <div className="w-wordmark">
          <span className="w-knight">♞</span> Arbiter AI
        </div>
        <div className="header-divider" />
        <span className="muted" style={{ fontSize: "var(--font-size-body-sm)" }}>
          Scoresheet Review
        </span>
        <div className="w-header-spacer" />
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
        <div className="w-avatar">AT</div>
      </header>

      <nav className="w-sidebar">
        <button
          type="button"
          className={`w-nav-item${view === "scans" ? " active" : ""}`}
          onClick={() => setView("scans")}
        >
          <Files {...ICON} /> My Scans
        </button>
        <button
          type="button"
          className={`w-nav-item${view === "upload" ? " active" : ""}`}
          onClick={() => setView("upload")}
        >
          <Upload {...ICON} /> Upload
        </button>
        <div style={{ flex: 1 }} />
        <button
          type="button"
          className="w-btn w-btn-primary"
          onClick={() => setView("upload")}
        >
          + New scan
        </button>
      </nav>

      <main className="w-main">
        {view === "scans" ? (
          <>
            <h1 className="w-page-title">My Scans</h1>
            <p className="w-page-sub">
              Uploaded scoresheets read by AI vision OCR and validated move-by-move
              against FIDE rules.
            </p>

            <div className="w-toolbar">
              <div className="w-search">
                <Search size={18} strokeWidth={1.75} />
                <input
                  placeholder="Search scans…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </div>
              <button
                type="button"
                className="w-btn w-btn-secondary btn-compact"
                onClick={() => void refresh(sessionId)}
              >
                Refresh
              </button>
            </div>

            {error && <div className="w-error-detail">{error}</div>}

            {!loaded ? (
              <div className="w-grid">
                {[0, 1, 2].map((i) => (
                  <div key={i} className="w-skel" style={{ height: 150 }} />
                ))}
              </div>
            ) : filtered.length === 0 ? (
              <div className="w-empty">
                <div className="w-empty-glyph">♟</div>
                <h2>No scans yet</h2>
                <p>
                  Upload a scoresheet photo or PDF to read and validate every move.
                </p>
                <button
                  type="button"
                  className="w-btn w-btn-primary"
                  onClick={() => setView("upload")}
                >
                  Upload a scoresheet
                </button>
              </div>
            ) : (
              <div className="w-grid">
                {filtered.map((g) => {
                  const b = badge(g.status);
                  return (
                    <button
                      key={g.game_id}
                      type="button"
                      className="w-card"
                      onClick={() => router.push(`/games/${g.game_id}`)}
                    >
                      <div className="w-card-top">
                        <div className="w-card-thumb" />
                        <div className="w-card-main">
                          <div className="w-card-title">
                            {g.upload_filename ?? g.game_id}
                          </div>
                          <div className="w-card-sub">
                            {new Date(g.created_at).toLocaleString()}
                          </div>
                          <div style={{ marginTop: 8 }}>
                            <span className={`w-badge ${b.cls}`}>{b.label}</span>
                          </div>
                        </div>
                      </div>
                      <div className="w-card-foot">
                        {g.has_findings && (
                          <span className="w-alert-tag">
                            <AlertTriangle size={13} strokeWidth={2} /> Findings
                          </span>
                        )}
                        {g.total_moves !== null && (
                          <span className="w-plies">{g.total_moves} moves</span>
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </>
        ) : (
          <>
            <h1 className="w-page-title">Upload a scoresheet</h1>
            <p className="w-page-sub">
              JPEG, PNG, WebP, TIFF or PDF. The sheet is read with AI vision OCR,
              then every move is validated by the chess engine.
            </p>

            <div className="w-upload-layout">
              <div
                className={`w-dropzone${drag ? " drag" : ""}`}
                onClick={() => fileRef.current?.click()}
                onDragOver={(e) => {
                  e.preventDefault();
                  setDrag(true);
                }}
                onDragLeave={() => setDrag(false)}
                onDrop={onDrop}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") fileRef.current?.click();
                }}
              >
                <div className="w-dropzone-glyph">
                  <Upload size={30} strokeWidth={1.75} />
                </div>
                <h3>{busy ? "Uploading…" : "Drop your scoresheet here"}</h3>
                <p>
                  or click to browse. Phone photos are downscaled automatically
                  before upload.
                </p>
                <input
                  ref={fileRef}
                  type="file"
                  accept={ACCEPT}
                  hidden
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) void upload(file);
                  }}
                />
              </div>

              <aside className="w-side-card">
                <div className="section-label">Notation language</div>
                <select
                  className="field"
                  value={locale}
                  onChange={(e) => setLocale(e.target.value)}
                  aria-label="Notation language"
                >
                  {LOCALES.map((l) => (
                    <option key={l.value} value={l.value}>
                      {l.label}
                    </option>
                  ))}
                </select>
                <p className="muted" style={{ fontSize: "var(--font-size-body-sm)" }}>
                  Pick the language the moves were written in — it sets the piece
                  letters the OCR expects.
                </p>
                {busy && (
                  <div className="w-uploading-row">
                    <div className="w-spinner" />
                    <span className="name">Processing upload…</span>
                  </div>
                )}
                {error && <div className="w-error-detail">{error}</div>}
              </aside>
            </div>
          </>
        )}
      </main>
    </div>
  );
}
