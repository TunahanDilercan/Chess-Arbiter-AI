import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'monetization/plans.dart';
import 'screens/analysis_screen.dart';
import 'screens/board_entry_screen.dart';
import 'screens/claim_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/crop_screen.dart';
import 'screens/home_screen.dart';
import 'screens/illegal_move_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/pgn_import_screen.dart';
import 'screens/position_setup_screen.dart';
import 'screens/processing_screen.dart';

Page<void> _slide(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation),
        child: child,
      ),
    );

Page<void> _up(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation),
        child: child,
      ),
    );

int _int(GoRouterState s, String key, int fallback) =>
    int.tryParse(s.uri.queryParameters[key] ?? '') ?? fallback;

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      errorBuilder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/board',
          pageBuilder: (_, s) => _slide(
            s,
            BoardEntryScreen(
              gameId: s.uri.queryParameters['game'],
              initialMode: s.uri.queryParameters['mode'] == 'keyboard'
                  ? EntryMode.keyboard
                  : EntryMode.board,
            ),
          ),
        ),
        GoRoute(path: '/import', pageBuilder: (_, s) => _slide(s, const PgnImportScreen())),
        GoRoute(
          path: '/position',
          pageBuilder: (_, s) => _slide(
              s, PositionSetupScreen(initialFen: s.uri.queryParameters['fen'])),
        ),
        GoRoute(
          path: '/compare',
          pageBuilder: (_, s) =>
              _slide(s, CompareScreen(gameId: s.uri.queryParameters['game'])),
        ),
        GoRoute(
          path: '/pro',
          pageBuilder: (_, s) {
            final f = s.uri.queryParameters['feature'];
            return _up(
              s,
              PaywallScreen(
                feature: ProFeature.values.where((v) => v.name == f).firstOrNull,
              ),
            );
          },
        ),
        GoRoute(
          path: '/game/:id',
          pageBuilder: (_, s) => _slide(s, AnalysisScreen(gameId: s.pathParameters['id']!)),
          routes: [
            GoRoute(
              path: 'claim',
              pageBuilder: (_, s) => _slide(
                s,
                ClaimScreen(
                  gameId: s.pathParameters['id']!,
                  initialPosition: _int(s, 'pos', 0),
                ),
              ),
            ),
            GoRoute(
              path: 'illegal',
              pageBuilder: (_, s) => _slide(
                s,
                IllegalMoveScreen(
                  gameId: s.pathParameters['id']!,
                  initialPly: _int(s, 'ply', 0),
                ),
              ),
            ),
          ],
        ),
        // Optional cloud OCR flow (only shown when BACKEND_URL is configured).
        GoRoute(
          path: '/crop',
          pageBuilder: (_, s) => _slide(s, CropScreen(imageFile: s.extra! as XFile)),
        ),
        GoRoute(
          path: '/processing/:jobId',
          pageBuilder: (_, s) => _slide(
            s,
            ProcessingScreen(
              jobId: s.pathParameters['jobId']!,
              gameId: s.extra as String? ?? '',
            ),
          ),
        ),
      ],
    );
