# Web Review Tool — Claude Code Context

## Purpose
Review interface for inspecting processed games, viewing OCR crop images, and
manually correcting moves. Restyled to the "Wood Classic" design handoff.
NOT the primary product — mobile is primary.

## Stack (actual)
Next.js 14 (App Router), TypeScript (strict). **No Tailwind, no React Query,
no Axios.** Styling is design tokens (CSS custom properties) + plain CSS
classes; data fetching is the native `fetch` API; server state is local
component state with 2.5s polling while a job is processing.

## Structure (actual)
```
web/
├── app/
│   ├── tokens.css                # design tokens (colors/spacing/type/motion)
│   ├── globals.css               # base reset + .w-* (web screens) + .app (workspace) classes
│   ├── layout.tsx                # data-theme="dark", loads 4 Google fonts
│   ├── page.tsx                  # Home: My Scans grid ↔ Upload dropzone (w-page shell)
│   └── games/[id]/page.tsx       # Analysis Workspace (.app shell) + processing view
├── components/
│   ├── ChessBoard.tsx            # layered FEN board, Cburnett SVG pieces, palette + flip
│   ├── MoveList.tsx              # ml-* rows + confidence dots
│   ├── FindingsPanel.tsx        # alert-card; claimable-vs-automatic FIDE distinction
│   └── PlyDetailModal.tsx       # OCR compare + crop + candidate chips + SAN input
├── lib/
│   ├── api.ts                   # fetch wrapper (ngrok-skip header, client-side image downscale)
│   └── types.ts                 # API contract types (snake_case, mirror backend)
└── next.config.mjs              # rewrites /api + /storage to the backend
```

## TypeScript Rules
- strict: true in tsconfig — no any, no implicit returns
- All API response types defined in lib/types.ts
- Match backend Pydantic schema field names exactly (snake_case on the wire)

## Architecture (NEVER violate)
- Backend is the ONLY authority for chess move validation and FIDE rules.
- Frontend never validates chess logic — it only displays backend results.
  (This is why the design's chess.js-based SAN keyboard is intentionally NOT
  replicated; a plain SAN input + backend candidate chips is used instead.)
- FIDE: threefold/fifty = CLAIMABLE; fivefold/seventy-five = AUTOMATIC. The
  `is_automatic` flag from the backend is the single source of truth.

## Pieces
Cburnett SVG set under `public/piece/cburnett/*.svg` (codes like `wK`, `bN`).
Do not swap to Wikimedia/remote sources.

## Run Commands
```bash
npm run dev          # next dev -p 3000
npm run build        # next build (also typechecks)
npx tsc --noEmit     # typecheck only (there is NO "typecheck" npm script)
# npm run lint is unconfigured (interactive setup prompt) — skip
```

## API
Connects to the same FastAPI backend as mobile, via the Next.js rewrite proxy
(so the browser always talks to the web app's own origin).
`NEXT_PUBLIC_API_URL` / `BACKEND_URL` configures the proxy target.
