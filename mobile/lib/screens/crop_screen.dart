import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/providers.dart';
import '../services/crop_service.dart';
import '../theme/arbiter_tokens.dart';

class CropScreen extends ConsumerStatefulWidget {
  final XFile imageFile;

  const CropScreen({super.key, required this.imageFile});

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  bool _preparing = false;
  String _locale = 'en';

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final bytesAsync = ref.watch(cropImageBytesProvider(widget.imageFile));
    final isUploading = _preparing || ref.watch(uploadProvider).isLoading;
    ref.watch(cropCornersProvider);

    // The crop editor is intentionally on a black canvas (camera/scan context),
    // independent of the app's light/dark theme.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Align Document'),
        actions: [
          DropdownButton<String>(
            value: _locale,
            dropdownColor: Colors.black,
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
              DropdownMenuItem(value: 'de', child: Text('Deutsch')),
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'es', child: Text('Español')),
            ],
            onChanged: isUploading
                ? null
                : (value) => setState(() => _locale = value!),
          ),
          if (isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: ArbiterSpacing.s4),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            bytesAsync.whenOrNull(
                  data: (_) => TextButton(
                    onPressed: _upload,
                    child: Text(
                      'Upload',
                      style: TextStyle(
                        color: c.accentPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: ArbiterFontSize.bodyLg,
                      ),
                    ),
                  ),
                ) ??
                const SizedBox.shrink(),
        ],
      ),
      body: bytesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Failed to load image: $e',
            style: TextStyle(color: c.feedbackDanger),
          ),
        ),
        data: (image) => AbsorbPointer(
          absorbing: isUploading,
          child: _CropEditor(
            imageBytes: image.bytes,
            imageSize: Size(image.width.toDouble(), image.height.toDouble()),
          ),
        ),
      ),
    );
  }

  Future<void> _upload() async {
    if (_preparing) return;
    final notifier = ref.read(uploadProvider.notifier);
    final image = ref
        .read(cropImageBytesProvider(widget.imageFile))
        .requireValue;
    final corners = List<Offset>.of(ref.read(cropCornersProvider));
    setState(() => _preparing = true);
    try {
      final bytes = await compute(rectifyCrop, (image.bytes, corners));
      if (!mounted) return;
      await notifier.upload(
        XFile.fromData(bytes, name: 'scoresheet.jpg', mimeType: 'image/jpeg'),
        locale: _locale,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
      }
      return;
    } finally {
      if (mounted) setState(() => _preparing = false);
    }

    if (!mounted) return;
    final uploadResult = ref.read(uploadProvider);

    uploadResult.whenData((response) {
      if (response != null) {
        context.go('/processing/${response.job_id}', extra: response.game_id);
      }
    });

    if (uploadResult.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${uploadResult.error}')),
      );
    }
  }
}

// ── Crop editor ───────────────────────────────────────────────────────────────

class _CropEditor extends ConsumerStatefulWidget {
  final Uint8List imageBytes;
  final Size imageSize;

  const _CropEditor({required this.imageBytes, required this.imageSize});

  @override
  ConsumerState<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends ConsumerState<_CropEditor> {
  Size _containerSize = Size.zero;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final corners = ref.watch(cropCornersProvider);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ratio = widget.imageSize.width / widget.imageSize.height;
              final width = math.min(
                constraints.maxWidth,
                constraints.maxHeight * ratio,
              );
              _containerSize = Size(width, width / ratio);
              final displayCorners = corners
                  .map(
                    (p) => Offset(p.dx * width, p.dy * _containerSize.height),
                  )
                  .toList();

              return Center(
                child: SizedBox(
                  width: _containerSize.width,
                  height: _containerSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (corners.length == 4)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropOverlayPainter(
                              corners: displayCorners,
                              accent: c.accentPrimary,
                            ),
                          ),
                        ),
                      if (corners.length == 4)
                        for (int i = 0; i < 4; i++)
                          _CornerHandle(
                            position: displayCorners[i],
                            index: i,
                            containerSize: _containerSize,
                            accent: c.accentPrimary,
                          ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(ArbiterSpacing.s3),
          color: c.surfaceElevated,
          child: Row(
            children: [
              Icon(Icons.info_outline, color: c.contentSecondary, size: 16),
              const SizedBox(width: ArbiterSpacing.s2),
              Expanded(
                child: Text(
                  'Drag the corner handles to align with the scoresheet edges.',
                  style: TextStyle(
                    color: c.contentSecondary,
                    fontSize: ArbiterFontSize.bodySm,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CornerHandle extends ConsumerWidget {
  final Offset position;
  final int index;
  final Size containerSize;
  final Color accent;

  const _CornerHandle({
    required this.position,
    required this.index,
    required this.containerSize,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const handleRadius = 16.0;
    return Positioned(
      left: position.dx - handleRadius,
      top: position.dy - handleRadius,
      child: GestureDetector(
        onPanUpdate: (details) {
          ref
              .read(cropCornersProvider.notifier)
              .move(
                index,
                Offset(
                  details.delta.dx / containerSize.width,
                  details.delta.dy / containerSize.height,
                ),
                const Size(1, 1),
              );
        },
        child: Container(
          width: handleRadius * 2,
          height: handleRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: accent, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  final Color accent;
  const _CropOverlayPainter({required this.corners, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = accent.withAlpha(25)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.corners != corners || old.accent != accent;
}
