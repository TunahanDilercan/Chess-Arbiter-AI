import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';

class CropScreen extends ConsumerWidget {
  final XFile imageFile;

  const CropScreen({super.key, required this.imageFile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final bytesAsync = ref.watch(cropImageBytesProvider(imageFile));
    final isUploading = ref.watch(uploadProvider).isLoading;

    // The crop editor is intentionally on a black canvas (camera/scan context),
    // independent of the app's light/dark theme.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Align Document'),
        actions: [
          if (isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: ArbiterSpacing.s4),
              child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            bytesAsync.whenOrNull(
                  data: (_) => TextButton(
                    onPressed: () => _upload(context, ref),
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
          child: Text('Failed to load image: $e',
              style: TextStyle(color: c.feedbackDanger)),
        ),
        data: (bytes) => _CropEditor(imageBytes: bytes, imageFile: imageFile),
      ),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(uploadProvider.notifier);
    await notifier.upload(imageFile);

    if (!context.mounted) return;
    final uploadResult = ref.read(uploadProvider);

    uploadResult.whenData((response) {
      if (response != null) {
        context.go('/processing/${response.job_id}', extra: response.game_id);
      }
    });

    if (uploadResult.hasError && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${uploadResult.error}')),
      );
    }
  }
}

// ── Crop editor ───────────────────────────────────────────────────────────────

class _CropEditor extends ConsumerStatefulWidget {
  final Uint8List imageBytes;
  final XFile imageFile;

  const _CropEditor({required this.imageBytes, required this.imageFile});

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
              final newSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (_containerSize != newSize && corners.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _containerSize = newSize;
                  ref.read(cropCornersProvider.notifier).init(newSize);
                });
              }
              _containerSize = newSize;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
                  ),
                  if (corners.length == 4)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                            corners: corners, accent: c.accentPrimary),
                      ),
                    ),
                  if (corners.length == 4)
                    for (int i = 0; i < 4; i++)
                      _CornerHandle(
                        position: corners[i],
                        index: i,
                        containerSize: _containerSize,
                        accent: c.accentPrimary,
                      ),
                ],
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
                      fontSize: ArbiterFontSize.bodySm),
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
              .move(index, details.delta, containerSize);
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
