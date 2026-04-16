# Web Review Tool — Claude Code Context

## Purpose
Temporary debug/review interface for inspecting processed games,
viewing OCR crop images, and manually correcting moves.
NOT the primary product — mobile is primary.

## Stack
Next.js 14 (App Router), TypeScript (strict), Tailwind CSS, React Query, Axios

## Structure
```
web/
├── app/
│   ├── layout.tsx
│   ├── page.tsx                  # Upload / game list
│   ├── games/[id]/page.tsx       # Game viewer
│   └── games/[id]/review/page.tsx # Manual correction
├── components/
│   ├── ChessBoard.tsx
│   ├── MoveList.tsx
│   ├── CropViewer.tsx
│   ├── FindingsPanel.tsx
│   └── ChessKeyboard.tsx
├── lib/
│   ├── api.ts                    # Axios client + API calls
│   └── types.ts                  # Shared TypeScript types
└── hooks/
    └── useGame.ts                # React Query hooks
```

## TypeScript Rules
- strict: true in tsconfig — no any, no implicit returns
- All API response types defined in lib/types.ts
- Match backend Pydantic schema field names exactly

## Run Commands
```bash
npm run dev
npm run build
npm run typecheck    # tsc --noEmit
npm run lint
```

## API
Connects to same FastAPI backend as mobile.
`NEXT_PUBLIC_API_URL=http://localhost:8000`
