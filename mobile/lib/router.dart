import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'models/models.dart';
import 'screens/correction_screen.dart';
import 'screens/crop_screen.dart';
import 'screens/game_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_entry_screen.dart';
import 'screens/processing_screen.dart';

// ── Transition helpers ────────────────────────────────────────────────────────

Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: child,
      ),
    );

Page<void> _slidePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
        child: child,
      ),
    );

Page<void> _slideUpPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
        child: child,
      ),
    );

// ── Router ────────────────────────────────────────────────────────────────────

final router = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) => const HomeScreen(),
  routes: [
    // Home
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _fadePage(state, const HomeScreen()),
    ),

    // Manual move entry
    GoRoute(
      path: '/manual',
      pageBuilder: (context, state) =>
          _slidePage(state, const ManualEntryScreen()),
    ),

    // Manual analysis result — game viewer with pre-loaded response (no API fetch)
    GoRoute(
      path: '/manual/result',
      pageBuilder: (context, state) {
        final game = state.extra! as GameAnalysisResponse;
        return _slidePage(
          state,
          GameScreen(gameId: game.game_id, preloadedGame: game),
        );
      },
    ),

    // Crop / document alignment
    GoRoute(
      path: '/crop',
      pageBuilder: (context, state) {
        final xFile = state.extra! as XFile;
        return _slidePage(state, CropScreen(imageFile: xFile));
      },
    ),

    // Processing (SSE job progress)
    GoRoute(
      path: '/processing/:jobId',
      pageBuilder: (context, state) {
        final jobId  = state.pathParameters['jobId']!;
        final gameId = state.extra as String? ?? '';
        return _slidePage(state, ProcessingScreen(jobId: jobId, gameId: gameId));
      },
    ),

    // Game viewer + nested correction modal
    GoRoute(
      path: '/game/:gameId',
      pageBuilder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return _slidePage(state, GameScreen(gameId: gameId));
      },
      routes: [
        GoRoute(
          path: 'correct/:plyIndex',
          pageBuilder: (context, state) {
            final gameId   = state.pathParameters['gameId']!;
            final plyIndex = int.parse(state.pathParameters['plyIndex']!);
            return _slideUpPage(
              state,
              CorrectionScreen(gameId: gameId, plyIndex: plyIndex),
            );
          },
        ),
      ],
    ),
  ],
);
