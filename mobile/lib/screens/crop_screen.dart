import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/providers.dart';

class CropScreen extends ConsumerWidget {
  final XFile imageFile;

  const CropScreen({super.key, required this.imageFile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytesAsync = ref.watch(cropImageBytesProvider(imageFile));
    final isUploading = ref.watch(uploadProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Align Document'),
        actions: [
          if (isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
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
                    onPressed: () => _upload(context, ref),
                    child: const Text(
                      'Upload',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
            style: const TextStyle(color: Colors.red),
          ),
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
        context.go(
          '/processing/${response.job_id}',
          extra: response.game_id,
        );
      }
    });

    if (uploadResult.hasError && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${uploadResult.error}'),
          backgroundColor: Colors.red,
        ),
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
    final corners = ref.watch(cropCornersProvider);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final newSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (_containerSize != newSize && corners.isEmpty) {
                // Initialize corners on first layout
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _containerSize = newSize;
                  ref.read(cropCornersProvider.notifier).init(newSize);
                });
              }
              _containerSize = newSize;

              return Stack(
                children: [
                  // Background image
                  Positioned.fill(
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),

                  // Crop overlay
                  if (corners.length == 4)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(corners: corners),
                      ),
                    ),

                  // Draggable corner handles
                  if (corners.length == 4)
                    for (int i = 0; i < 4; i++)
                      _CornerHandle(
                        position: corners[i],
                        index: i,
                        containerSize: _containerSize,
                      ),
                ],
              );
            },
          ),
        ),

        // Hint text
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.black87,
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white54, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag the corner handles to align with the scoresheet edges.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Corner handle ─────────────────────────────────────────────────────────────

class _CornerHandle extends ConsumerWidget {
  final Offset position;
  final int index;
  final Size containerSize;

  const _CornerHandle({
    required this.position,
    required this.index,
    required this.containerSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const handleRadius = 16.0;
    return Positioned(
      left: position.dx - handleRadius,
      top: position.dy - handleRadius,
      child: GestureDetector(
        onPanUpdate: (details) {
          ref.read(cropCornersProvider.notifier).move(
                index,
                details.delta,
                containerSize,
              );
        },
        child: Container(
          width: handleRadius * 2,
          height: handleRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFF4A6FA5), width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Crop overlay painter ──────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  const _CropOverlayPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final linePaint = Paint()
      ..color = const Color(0xFF4A6FA5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.blue.withAlpha(25)
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
  bool shouldRepaint(_CropOverlayPainter old) => old.corners != corners;
}
