# Mobile (Flutter) — Claude Code Context

## Stack
Flutter 3.x, Dart, Riverpod (state management), Dio (HTTP), flutter_sse_client (SSE),
go_router (navigation), image_picker, camera

## Screen Map
```
mobile/lib/
├── main.dart
├── router.dart                  # go_router route definitions
├── screens/
│   ├── home_screen.dart         # Upload / capture entry point
│   ├── crop_screen.dart         # 4-corner document rectification UI
│   ├── processing_screen.dart   # SSE job progress display
│   ├── game_screen.dart         # Main game viewer
│   └── correction_screen.dart  # Manual move correction modal
├── widgets/
│   ├── chess_board.dart         # Interactive board with highlighting
│   ├── move_list.dart           # Move list with status badges
│   ├── chess_keyboard.dart      # Custom chess SAN keyboard (MANDATORY)
│   ├── findings_panel.dart      # FIDE alerts and warnings
│   └── crop_preview.dart        # Shows OCR crop image per move
├── models/                      # Dart data classes (freezed)
├── providers/                   # Riverpod providers
└── services/
    ├── api_service.dart          # Dio HTTP client
    └── sse_service.dart          # SSE job status stream
```

## Custom Chess Keyboard Rules (IMPORTANT)
chess_keyboard.dart must NEVER use the system keyboard.
Key groups: Pieces (K Q R B N) | Files (a-h) | Ranks (1-8) |
Symbols (x + # = O-O O-O-O) | Promotion (=Q =R =B =N) | Utility (⌫ Clear Confirm)
Legal SAN suggestions shown as tappable chips above the keyboard.
Tapping a chip fills the input field instantly.

## State Management Rules
- All server state via Riverpod AsyncNotifier providers
- No setState() in screens — screens are dumb, providers hold logic
- SSE stream exposed as a StreamProvider

## Flutter Style
- Use const constructors wherever possible
- Freezed for all data models (immutable)
- No business logic in widgets — widgets render, providers compute
- Use go_router for all navigation (no Navigator.push directly)

## Run Commands
```bash
flutter pub get
flutter run                     # default device
flutter run -d ios
flutter run -d android
flutter test
flutter analyze
```

## Backend URL
Configured via --dart-define or .env:
`BACKEND_URL=http://localhost:8000`
