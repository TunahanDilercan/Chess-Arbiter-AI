# Arbiter AI — Claude Code Context

## What This Project Is
A mobile-first app (iOS/Android) that photographs handwritten chess scoresheets,
runs OCR + computer vision, validates every move against FIDE rules, and lets
arbiters correct errors via a custom chess keyboard.

## Monorepo Structure
```
arbiter-ai/
├── backend/        # Python 3.11 + FastAPI — chess logic authority
├── mobile/         # Flutter 3.x — iOS + Android
├── web/            # Next.js 14 + TypeScript — review/debug tool
├── docs/           # Architecture and domain references
└── docker-compose.yml
```
Each subfolder has its own CLAUDE.md with stack-specific rules.

## Architecture Rules (NEVER violate)
- Backend is the ONLY authority for chess move validation and FIDE rules
- Frontend never validates chess logic — it only displays backend results
- OCR output is NEVER trusted directly — always matched against legal board moves
- Manual correction is a first-class flow, not an edge case

## FIDE Semantics (CRITICAL — get this wrong and the app is wrong)
- Threefold repetition → CLAIMABLE (not automatic, player must claim)
- Fifty-move rule → CLAIMABLE (not automatic)
- Fivefold repetition → AUTOMATIC draw (enforced by rules)
- Seventy-five move rule → AUTOMATIC draw (enforced by rules)
UI labels must reflect this distinction exactly.

## Tech Decisions Already Made
- OCR: Claude Vision API (full-sheet, default) with TrOCR fallback — NOT Tesseract (printed-text only)
- Async: SSE (Server-Sent Events) for job status — not WebSocket, not polling
- Auth: Anonymous sessions only (no login in this version)
- Chess engine: python-chess (backend only)
- Queue: Celery + Redis

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

# Mobile
cd mobile && flutter run

# Web
cd web && npm run dev
```

## For architecture details, see docs/ARCHITECTURE.md
## For FIDE rule reference, see docs/FIDE_RULES.md
## For OCR pipeline details, see docs/OCR_PIPELINE.md
