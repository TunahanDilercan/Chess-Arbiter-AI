# Mobile (Flutter) — Claude Code Context

Primary product surface. Restyled to the "Wood Classic" design handoff.

## Stack
Flutter 3.x, Dart, Riverpod (state management), Dio (HTTP), SSE for job status,
go_router (navigation), image_picker (capture/gallery), flutter_svg (board pieces).

## Screen Map (actual)
```
mobile/lib/
├── main.dart                      # MaterialApp: ArbiterTheme light/dark, ThemeMode.system
├── router.dart                    # go_router route definitions
├── theme/
│   ├── arbiter_tokens.dart        # design tokens + ArbiterColors ThemeExtension (light/dark)
│   └── arbiter_theme.dart         # ArbiterTheme.light()/dark() + ArbiterNotationStyles
├── screens/
│   ├── home_screen.dart           # wordmark + upload area + recent games list
│   ├── crop_screen.dart           # 4-corner document rectification UI (black editor)
│   ├── processing_screen.dart     # job progress timeline
│   ├── game_screen.dart           # main game viewer (board + tabs + nav + stats)
│   ├── correction_screen.dart     # per-ply move correction (board + OCR read + keyboard)
│   └── manual_entry_screen.dart   # paste/type SAN moves, locale selector
├── widgets/
│   ├── chess_board.dart           # CustomPaint board + Cburnett SVG pieces, palette + flip
│   ├── move_list.dart             # move rows with confidence dots
│   ├── chess_keyboard.dart        # custom SAN keyboard (never the system keyboard)
│   └── findings_panel.dart        # FIDE alerts; claimable-vs-automatic distinction + articles
├── models/                        # freezed data classes (upload, analysis)
├── providers/                     # Riverpod providers
└── services/
    ├── api_service.dart           # Dio HTTP client
    └── sse_service.dart           # SSE job status stream
```

## Theme (Wood Classic)
- All color/spacing/type/radii/motion via `arbiter_tokens.dart`.
- Read colors in widgets with `context.arbiterColors` (the `ArbiterColors`
  ThemeExtension), NOT hard-coded `Color(0x…)`.
- Notation uses `ArbiterNotationStyles.large/medium/small(context)` (JetBrains
  Mono, tabular figures).
- Fonts bundled as TTF assets (Inter, JetBrains Mono, Fraunces) — see pubspec.
- Light + dark + `ThemeMode.system`. (Old `app_theme.dart` was deleted.)

## Custom Chess Keyboard Rules (IMPORTANT)
- `chess_keyboard.dart` must NEVER use the system keyboard.
- Key groups: Pieces (K Q R B N) | Files (a-h) | Ranks (1-8) |
  Symbols (x + # = O-O O-O-O) | Promotion (=Q =R =B =N) | Utility (⌫ Clear Confirm).
- Suggestion chips above the keyboard come from the BACKEND (selected SAN +
  OCR candidates). The keyboard does NOT compute legal moves client-side —
  that would violate the architecture rule below. Re-skinned to tokens only;
  legal-move filtering was intentionally NOT added.

## Architecture (NEVER violate)
- Backend is the ONLY authority for chess move validation and FIDE rules.
- Frontend never validates chess logic — it only displays backend results.
- OCR output is NEVER trusted directly — always matched against backend candidates.
- FIDE: threefold/fifty = CLAIMABLE; fivefold/seventy-five = AUTOMATIC. The
  backend `is_automatic` flag is the single source of truth; the findings panel
  must reflect this distinction exactly.

## Pieces
Cburnett SVG set under `assets/pieces/*.svg` (codes like `wK`, `bN`), rendered
via flutter_svg at 92% of the square. Do not swap to a remote/font source.

## State Management
- Server state via Riverpod providers (AsyncValue).
- go_router for all navigation.
- Freezed for data models (immutable).

## Verify Commands
```bash
flutter pub get
flutter analyze                 # must be clean
flutter build bundle            # asset/font bundling smoke test
flutter run                     # on a device/emulator (user-driven)
```

## Backend URL
Configured via --dart-define or .env:
`BACKEND_URL=http://localhost:8000`
