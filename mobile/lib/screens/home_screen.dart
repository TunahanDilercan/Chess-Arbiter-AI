import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/settings_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  ArbiterSpacing.s5, ArbiterSpacing.s7, ArbiterSpacing.s5, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '♞',
                        style: TextStyle(
                          fontSize: 40,
                          color: c.accentPrimary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: ArbiterSpacing.s3),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Arbiter AI',
                            style: TextStyle(
                              fontFamily: ArbiterFontFamily.display,
                              fontSize: ArbiterFontSize.headingLg,
                              fontWeight: ArbiterFontWeights.semibold,
                              color: c.contentPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'FIDE scoresheet analyser',
                            style: TextStyle(color: c.contentSecondary),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        color: c.contentSecondary,
                        tooltip: 'Appearance',
                        onPressed: () => showSettingsSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: ArbiterSpacing.s6),

                  // ── Upload area ────────────────────────────────────────
                  _UploadArea(
                    onCamera: () =>
                        _pickImage(context, ref, ImageSource.camera),
                    onGallery: () =>
                        _pickImage(context, ref, ImageSource.gallery),
                    onManual: () => context.push('/manual'),
                  ),
                  const SizedBox(height: ArbiterSpacing.s6),

                  // ── Recent games header ────────────────────────────────
                  Text(
                    'Recent Games',
                    style: TextStyle(
                      fontFamily: ArbiterFontFamily.display,
                      fontSize: ArbiterFontSize.headingMd,
                      fontWeight: ArbiterFontWeights.semibold,
                      color: c.contentPrimary,
                    ),
                  ),
                  const SizedBox(height: ArbiterSpacing.s2),
                ]),
              ),
            ),
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
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      // image_picker reports a denied OS permission via these codes.
      if (e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied') {
        _showPermissionDialog(context, source);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open image: $e')),
      );
    }
  }

  void _showPermissionDialog(BuildContext context, ImageSource source) {
    final isCamera = source == ImageSource.camera;
    final what = isCamera ? 'camera' : 'photo library';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text('${isCamera ? 'Camera' : 'Photos'} permission needed'),
        content: Text(
          'Arbiter AI needs access to your $what to scan a scoresheet. '
          'Enable it for this app in your device Settings, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    final c = context.arbiterColors;
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: c.contentTertiary,
        radius: ArbiterRadii.xl,
        dashWidth: 8,
        dashGap: 5,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s6),
        child: Column(
          children: [
            Icon(Icons.upload_file_outlined, size: 48, color: c.accentPrimary),
            const SizedBox(height: ArbiterSpacing.s3),
            Text(
              'Upload a Scoresheet',
              style: TextStyle(
                fontFamily: ArbiterFontFamily.display,
                fontSize: ArbiterFontSize.headingMd,
                fontWeight: ArbiterFontWeights.semibold,
                color: c.contentPrimary,
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s1),
            Text(
              'Photograph or select a handwritten\nchess scoresheet for FIDE analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm),
            ),
            const SizedBox(height: ArbiterSpacing.s5),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                  ),
                ),
                const SizedBox(width: ArbiterSpacing.s3),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s2),
            TextButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
              label: const Text('Enter Moves Manually'),
              style: TextButton.styleFrom(
                foregroundColor: c.contentSecondary,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
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
    final c = context.arbiterColors;
    final gamesAsync = ref.watch(recentGamesProvider);

    return gamesAsync.when(
      loading: () => const SliverPadding(
        padding: EdgeInsets.fromLTRB(
            ArbiterSpacing.s5, 0, ArbiterSpacing.s5, ArbiterSpacing.s6),
        sliver: SliverToBoxAdapter(child: _GameTileSkeletonList()),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ArbiterSpacing.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: c.feedbackDanger, size: 40),
                const SizedBox(height: ArbiterSpacing.s3),
                Text('Could not load recent games.',
                    style: TextStyle(color: c.contentSecondary)),
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
          padding: const EdgeInsets.fromLTRB(
              ArbiterSpacing.s5, 0, ArbiterSpacing.s5, ArbiterSpacing.s6),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  index < games.length ? _GameTile(game: games[index]) : null,
              childCount: games.length,
            ),
          ),
        );
      },
    );
  }
}

class _GameTileSkeletonList extends StatelessWidget {
  const _GameTileSkeletonList();

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          height: 64,
          margin: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(ArbiterRadii.lg),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentGames extends StatelessWidget {
  const _EmptyRecentGames();

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.all(ArbiterSpacing.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('♟',
              style: TextStyle(fontSize: 64, color: c.contentTertiary, height: 1)),
          const SizedBox(height: ArbiterSpacing.s4),
          Text(
            'No games yet',
            style: TextStyle(
              fontFamily: ArbiterFontFamily.display,
              fontSize: ArbiterFontSize.headingMd,
              fontWeight: ArbiterFontWeights.semibold,
              color: c.contentPrimary,
            ),
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          Text(
            'Upload a scoresheet above to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.contentSecondary),
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
    final c = context.arbiterColors;
    final (statusColor, statusLabel) = _statusInfo(c, game.status);

    return Container(
      margin: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ArbiterRadii.lg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ArbiterRadii.lg),
        onTap: () => context.push('/game/${game.game_id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ArbiterSpacing.s4, vertical: ArbiterSpacing.s3),
          child: Row(
            children: [
              // Scoresheet thumbnail stub.
              Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: c.surfaceInset,
                  borderRadius: BorderRadius.circular(ArbiterRadii.sm),
                ),
                child: Icon(Icons.description_outlined,
                    size: 18, color: c.contentTertiary),
              ),
              const SizedBox(width: ArbiterSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.upload_filename ?? 'Scoresheet',
                      style: TextStyle(
                        color: c.contentPrimary,
                        fontSize: ArbiterFontSize.bodyLg,
                        fontWeight: ArbiterFontWeights.medium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${game.total_moves ?? 0} moves',
                      style: TextStyle(
                          color: c.contentSecondary,
                          fontSize: ArbiterFontSize.bodySm),
                    ),
                  ],
                ),
              ),
              _StatusBadge(color: statusColor, label: statusLabel),
            ],
          ),
        ),
      ),
    );
  }

  static (Color, String) _statusInfo(ArbiterColors c, String status) {
    return switch (status) {
      'completed' => (c.feedbackSuccess, 'Ready'),
      'needs_review' => (c.feedbackWarning, 'Review'),
      'failed' => (c.feedbackDanger, 'Failed'),
      'queued' => (c.contentTertiary, 'Queued'),
      _ => (c.accentPrimary, 'Processing'),
    };
  }
}

class _StatusBadge extends StatelessWidget {
  final Color color;
  final String label;
  const _StatusBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        border: Border.all(color: color),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: ArbiterFontSize.labelSm,
          fontWeight: ArbiterFontWeights.semibold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
