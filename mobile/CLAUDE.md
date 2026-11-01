# Mobile (Flutter) — Claude Code Context

The product: "Hakem Masası", an offline arbiter analysis desk. Turkish-first UI,
"Wood Classic" design tokens.

## Stack
Flutter 3.x, Dart 3, Riverpod, go_router, flutter_svg (pieces), path_provider
(local storage), purchases_flutter (RevenueCat), pdf + share_plus (reports).
Dio/SSE/image_picker only for the optional cloud OCR flow.

## Layout
```
mobile/lib/
├── core/                         # PURE DART — no Flutter imports
│   ├── chess/                    # types, position (move gen + FEN), san (write +
│   │                             # tolerant parse + illegal explanations),
│   │                             # notation (TR/DE/FR/ES), pgn, fuzzy ranking
│   └── arbiter/                  # analysis (replay + FIDE timeline + repetitions),
│                                 # tools (claim / illegal move / flag fall),
│                                 # compare (two scoresheets), material (mate ability),
│                                 # fide (article catalogue), report, game_record, sample
├── data/                         # GameRepository: files on device, prefs on web
├── monetization/                 # plans (product ids, prices, gating), subscription
│                                 # (RevenueCat + preview), quota (3 free Pro uses/week)
├── providers/providers.dart      # Riverpod wiring (games, analysis, entitlement, settings, OCR)
├── screens/                      # home, board_entry, pgn_import, analysis, move_edit_sheet,
│                                 # claim, illegal_move, tool_sheets (flag fall), compare,
│                                 # paywall, game_info_sheet, crop + processing (OCR)
├── services/                     # report_pdf, share_service, api/sse/crop (OCR)
└── widgets/                      # chess_board, chess_keyboard, analysis_panels, desk_ui,
                                  # pro_gate, settings_sheet
```

## Architecture (NEVER violate)
- lib/core is the only place with chess/FIDE logic; it must stay pure Dart and
  GPL-free. Widgets display core results and never re-implement rules.
- Every feature except OCR must work offline.
- Never discard the scoresheet tokens as written. Replay stops at the first
  unresolved move; later tokens are kept as "not reached".
- Never silently guess between two legal moves (ambiguous → arbiter decides).
- FIDE: threefold/fifty = CLAIMABLE (game continues); fivefold/75 moves, mate,
  stalemate, dead position = AUTOMATIC end. Mate takes precedence over 75 moves.
  Repetition identity follows 9.2.2 (side to move, castling rights, LEGAL en passant).
- Every verdict cites FideArticle(s); the UI says the arbiter decides.
- Pro gating goes through `ensureProAccess` (widgets/pro_gate.dart).

## Custom chess keyboard
- Never the system keyboard for move entry/correction.
- Piece row uses the game's notation letters (TR: Ş V K F A).
- Suggestion chips come from lib/core (legal moves ranked by similarity).

## Theme
- Colors/spacing/type via `arbiter_tokens.dart` and `context.arbiterColors`.
- Use `trUpper()` (core/arbiter/report.dart) for Turkish uppercase, never
  `toUpperCase()` on user-facing Turkish text.

## Build-time configuration (`--dart-define`)
- `REVENUECAT_ANDROID_KEY`, `REVENUECAT_IOS_KEY` — public SDK keys; without them the
  app uses the preview subscription service (debug: fake purchases; release: disabled).
- `RC_ENTITLEMENT` (default `pro`).
- `BACKEND_URL` — OCR service; empty hides the photo option. `ARBITER_AUTH=user:pass`
  for a basic-auth tunnel.

## Verify Commands
```bash
flutter pub get
flutter analyze                  # must be clean
flutter test                     # perft, FIDE rules, claims, compare, widgets, PDF
flutter build web --release --no-web-resources-cdn   # UI smoke test in a browser
```
