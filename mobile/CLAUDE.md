# Mobile (Flutter) — Claude Code Context

The product: "Hakem Masası", an offline arbiter analysis desk. Turkish-first UI,
"Wood Classic" design tokens.

## Stack
Flutter 3.x, Dart 3, Riverpod, go_router, vector_graphics (precompiled piece SVGs), path_provider
(local storage), purchases_flutter + purchases_ui_flutter (RevenueCat, Customer
Center), pdf + share_plus (reports).
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
- Pro gating (widgets/pro_gate.dart): dispute tools use `requestToolAccess` —
  never a paywall mid-dispute; without Pro/quota they show the verdict headline
  and `LockedDetails`. Reports, archive and OCR use `ensureProAccess`.
- No GPL / share-alike / non-commercial assets: pieces are Celtic, Spatial,
  Fantasy (MIT, Maurizio Monge) and Chessnut (Apache-2.0); fonts OFL. Licenses are
  registered in main.dart and shown from settings. lichess "cburnett"/"merida"
  are GPL and the sadsnake1 sets are CC BY-NC-SA: never add them
  (assets/pieces/NOTICE.md).
- Pieces: `PieceImage` / `PieceSetScope` (widgets/piece_image.dart) load
  build-time compiled vector_graphics assets. New sets: copy from lila, run
  `python3 tool/normalize_pieces.py <src> assets/pieces/<set>`, add the folder
  with the `vector_graphics_compiler` transformer in pubspec and a `PieceSet` value.

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
  app uses the preview subscription service (debug: fake purchases; release: FREE
  EDITION — everything unlocked, all purchase UI hidden; see `Entitlement.freeEdition`
  and `SubscriptionService.storeEnabled`).
- `RC_ENTITLEMENT` (default `pro`).
- `TERMS_URL`, `PRIVACY_URL`, `SUPPORT_URL` — legal/support links on the paywall and
  in settings. Must be publicly reachable before store submission (docs/APP_STORE_TR.md).

## Store compliance (docs/APP_STORE_TR.md)
- UI language is Turkish: `MaterialApp` locale `tr` with GlobalMaterialLocalizations;
  iOS development region `tr` (`tr.lproj/InfoPlist.strings`).
- Never name the other platform's store in the UI (App Store 2.3.10): use
  `storeAccountName()` for billing wording.
- Store listing text lives in `store/` (fastlane layout); `test/store_metadata_test.dart`
  enforces limits and banned phrases. Screenshots: `store/tool/` (seed → capture →
  compose).
- Paywall: billed amount + period most prominent; renewal sentence directly under
  the CTA (`billingTerms`); restore, manage/cancel, privacy, terms always reachable.
- Never block the app behind the paywall; it is always dismissible.
- iOS: `PrivacyInfo.xcprivacy` (required-reason APIs) and
  `ITSAppUsesNonExemptEncryption=false` in Info.plist — keep them when adding SDKs.
- Icons/splash are generated: edit `assets/icon/*` then
  `dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
- `test/ux_matrix_test.dart` renders every screen on small/large phones and iPad at
  text scale 1.0/1.35/2.0 and dark theme; any overflow fails it.
- `BACKEND_URL` — OCR service; empty hides the photo option. `ARBITER_AUTH=user:pass`
  for a basic-auth tunnel.

## Performance
- `lib/core` hot path: precomputed attack tables, pin-aware legal move
  generation (king-safety test only for king moves, pinned pieces, en passant
  and check evasions), make/unmake on one scratch board, single-entry `play()`
  cache so `toSan` and replay share the child position. Benchmark (AOT):
  `dart compile exe tool/bench.dart -o /tmp/bench && /tmp/bench <file.pgn>`
  (~34 µs per half-move incl. SAN parsing and FIDE checks; was ~80).
- PGN import parses large pastes on a background isolate (`compute`) with a
  250 ms debounce and stores games in one batch (`GamesNotifier.saveAll`).
- The board is a `RepaintBoundary`; move lists are lazy with fixed extents.
- Any core change: run `flutter test test_slow` (perft + python-chess oracle).

## Verify Commands
```bash
flutter pub get
flutter analyze                  # must be clean
flutter test                     # perft, python-chess oracle, FIDE rules, widgets, PDF
# regenerate the oracle fixture: PYTHONPATH=<python-chess> python3 tool/gen_oracle_fixture.py
flutter build web --release --no-web-resources-cdn   # UI smoke test in a browser
```
