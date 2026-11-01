# Arbiter AI — Claude Code Context

## What This Project Is
"Hakem Masası" — a mobile-first, OFFLINE app (iOS/Android) for chess arbiters at the
analysis/dispute desk. Arbiters enter a game (play on the board, type from a
scoresheet with the custom chess keyboard, paste PGN, compare two scoresheets) and
the app checks every move against the FIDE Laws of Chess (2023) and advises on
claims, illegal moves and flag falls. Scoresheet OCR is an optional, online input
method served by backend/. Monetized with a weekly/monthly/yearly Pro subscription.

## Monorepo Structure
```
arbiter-ai/
├── backend/        # Python 3.11 + FastAPI — optional cloud OCR service
├── mobile/         # Flutter 3.x — iOS + Android (the product; offline chess core)
├── web/            # Next.js 14 + TypeScript — review/debug tool
├── docs/           # Architecture and domain references
└── docker-compose.yml
```
Each subfolder has its own CLAUDE.md with stack-specific rules.

## Architecture Rules (NEVER violate)
- mobile/lib/core/ (pure Dart, no Flutter imports) is the authority for chess move
  validation and FIDE rules in the app. Widgets never compute chess logic themselves.
- The app must work fully offline; only optional OCR may use the network.
- No GPL code in mobile/lib/core (App Store distribution of a paid app).
- Raw scoresheet text is never discarded; replay stops at the first unresolved move.
- OCR output is NEVER trusted directly — always matched against legal board moves
- Manual correction is a first-class flow, not an edge case; corrections are logged
- The app advises; the arbiter decides. Cite the FIDE article for every verdict.

## FIDE Semantics (CRITICAL — get this wrong and the app is wrong)
- Threefold repetition → CLAIMABLE (not automatic, player must claim)
- Fifty-move rule → CLAIMABLE (not automatic)
- Fivefold repetition → AUTOMATIC draw (enforced by rules)
- Seventy-five move rule → AUTOMATIC draw (enforced by rules)
UI labels must reflect this distinction exactly.

## Tech Decisions Already Made
- Chess engine (app): own Dart move generator in mobile/lib/core/chess (perft-tested);
  python-chess remains in backend/ for the OCR pipeline only
- Storage (app): on-device JSON files (shared_preferences on web); no accounts
- Subscriptions: RevenueCat (`purchases_flutter`), entitlement `pro`; preview mode
  without keys
- OCR: Claude Vision API (full-sheet, default) with TrOCR fallback — NOT Tesseract (printed-text only)
- Async (OCR): SSE for job status — not WebSocket, not polling
- Auth: Anonymous sessions only (no login in this version)
- Queue (OCR): Celery + Redis

## Global Code Rules
- Typed everywhere: Python uses type hints + Pydantic, Flutter uses strong types, TS uses strict mode
- No magic strings — use enums/constants for statuses, alert types, move colors
- Modular: one responsibility per file/class/service
- When adding a FIDE rule check, always cite the python-chess method used

## Dev Commands
```bash
# Start all services
docker-compose up

# Backend only
cd backend && uvicorn main:app --reload

# Mobile (offline; tests include perft + FIDE rule cases)
cd mobile && flutter analyze && flutter test && flutter run

# Web
cd web && npm run dev
```

## For architecture details, see docs/ARCHITECTURE.md
## For FIDE rule reference, see docs/FIDE_RULES.md
## For OCR pipeline details, see docs/OCR_PIPELINE.md
## For subscription design and store setup, see docs/MONETIZATION_TR.md
