import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '♟',
                        style: TextStyle(
                          fontSize: 40,
                          color: AppColors.accent,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Arbiter AI', style: AppTextStyles.headline),
                          const SizedBox(height: 2),
                          Text(
                            'FIDE scoresheet analyser',
                            style: AppTextStyles.bodyDim,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Upload area ────────────────────────────────────────
                  _UploadArea(
                    onCamera: () =>
                        _pickImage(context, ref, ImageSource.camera),
                    onGallery: () =>
                        _pickImage(context, ref, ImageSource.gallery),
                    onManual: () => context.push('/manual'),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Recent games header ────────────────────────────────
                  Text('Recent Games', style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.sm),
                ]),
              ),
            ),

            // ── Recent games list ──────────────────────────────────────────
            _RecentGamesList(),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    try {
      final picker = ref.read(imagePickerProvider);
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (file == null) return;
      if (!context.mounted) return;
      context.push('/crop', extra: file);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open image: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ── Upload area with dashed border ───────────────────────────────────────────

class _UploadArea extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onManual;

  const _UploadArea({
    required this.onCamera,
    required this.onGallery,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppColors.accent.withAlpha(120),
        radius: AppRadius.card,
        dashWidth: 8,
        dashGap: 5,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(
              Icons.upload_file_outlined,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: 12),
            Text(
              'Upload a Scoresheet',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: 6),
            Text(
              'Photograph or select a handwritten\nchess scoresheet for FIDE analysis.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyDim.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
              label: const Text('Enter Moves Manually'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceDim,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final start = distance;
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap;
}

// ── Recent games list ─────────────────────────────────────────────────────────

class _RecentGamesList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(recentGamesProvider);

    return gamesAsync.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: AppColors.error, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Could not load recent games.',
                  style: AppTextStyles.bodyDim,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (games) {
        if (games.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyRecentGames(),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index < games.length) {
                  return _GameTile(game: games[index]);
                }
                return null;
              },
              childCount: games.length,
            ),
          ),
        );
      },
    );
  }
}

class _EmptyRecentGames extends StatelessWidget {
  const _EmptyRecentGames();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: AppColors.onSurfaceFaint,
          ),
          const SizedBox(height: 16),
          Text(
            'No games yet',
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.onSurfaceDim,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload a scoresheet above to get started.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final GameSummary game;
  const _GameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = _statusInfo(game.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
      ),
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: () => context.push('/game/${game.game_id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Status dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),

              // Game info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.upload_filename ?? 'Scoresheet',
                      style: AppTextStyles.titleSmall.copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${game.total_moves ?? 0} moves · $statusLabel',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceDim,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static (Color, String) _statusInfo(String status) {
    return switch (status) {
      'completed' => (AppColors.legal, 'Done'),
      'needs_review' => (AppColors.review, 'Review needed'),
      'failed' => (AppColors.illegal, 'Failed'),
      'processing' => (Colors.lightBlue, 'Processing…'),
      _ => (AppColors.onSurfaceDim, status),
    };
  }
}

