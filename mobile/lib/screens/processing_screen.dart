import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

// ── Pipeline steps ─────────────────────────────────────────────────────────────

const _kPipelineSteps = [
  ('queued', 'Queued', Icons.hourglass_empty),
  ('preprocessing', 'Preprocessing', Icons.tune),
  ('cropping', 'Detecting Grid', Icons.grid_on),
  ('ocr_processing', 'Recognising Text', Icons.text_fields),
  ('ocr_complete', 'OCR Complete', Icons.check_circle_outline),
  ('analyzing', 'Analysing Moves', Icons.psychology),
  ('completed', 'Complete', Icons.emoji_events),
];

int _stepIndex(String status) =>
    _kPipelineSteps.indexWhere((s) => s.$1 == status);

class ProcessingScreen extends ConsumerWidget {
  final String jobId;
  final String gameId;

  const ProcessingScreen({
    super.key,
    required this.jobId,
    required this.gameId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(jobStatusProvider(jobId));

    return stream.when(
      loading: () => _Shell(
        jobId: jobId,
        child: _Timeline(currentStatus: 'queued', errorMessage: null),
      ),
      error: (e, _) => _Shell(
        jobId: jobId,
        child: _ErrorBody(message: e.toString()),
      ),
      data: (event) {
        if (event.status == 'completed') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/game/$gameId');
          });
        }

        return _Shell(
          jobId: jobId,
          child: event.status == 'failed'
              ? _ErrorBody(message: event.error_message ?? 'Processing failed.')
              : _Timeline(
                  currentStatus: event.status,
                  errorMessage: event.error_message,
                ),
        );
      },
    );
  }
}

// ── Shell ──────────────────────────────────────────────────────────────────────

class _Shell extends StatelessWidget {
  final String jobId;
  final Widget child;
  const _Shell({required this.jobId, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job: $jobId',
              style: AppTextStyles.caption,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

// ── Timeline ───────────────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final String currentStatus;
  final String? errorMessage;
  const _Timeline({required this.currentStatus, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final activeIdx = _stepIndex(currentStatus);
    final progress = activeIdx < 0
        ? 0.0
        : (activeIdx + 1) / _kPipelineSteps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Linear progress ────────────────────────────────────────────────
        ClipRRect(
          borderRadius: AppRadius.chipAll,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceVar,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Step list ──────────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            itemCount: _kPipelineSteps.length,
            itemBuilder: (context, index) {
              final (status, label, icon) = _kPipelineSteps[index];
              final isDone = activeIdx >= 0 && index < activeIdx;
              final isActive = index == activeIdx;
              final isPending = activeIdx < 0 || index > activeIdx;

              return _TimelineStep(
                icon: icon,
                label: label,
                status: status,
                isDone: isDone,
                isActive: isActive,
                isPending: isPending,
                isLast: index == _kPipelineSteps.length - 1,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final bool isDone;
  final bool isActive;
  final bool isPending;
  final bool isLast;

  const _TimelineStep({
    required this.icon,
    required this.label,
    required this.status,
    required this.isDone,
    required this.isActive,
    required this.isPending,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isDone
        ? AppColors.legal
        : isActive
            ? AppColors.accent
            : AppColors.surfaceHigh;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Connector column ─────────────────────────────────────────
          SizedBox(
            width: 44,
            child: Column(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: isActive
                      ? _PulsingIndicator(color: dotColor)
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor.withAlpha(isDone ? 30 : 20),
                            border: Border.all(color: dotColor, width: 2),
                          ),
                          child: Icon(
                            isDone ? Icons.check : icon,
                            size: 16,
                            color: dotColor,
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: isDone ? AppColors.legal.withAlpha(100) : AppColors.surfaceHigh,
                    ),
                  ),
              ],
            ),
          ),

          // ── Label ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 20),
            child: Text(
              label,
              style: TextStyle(
                color: isPending
                    ? AppColors.onSurfaceFaint
                    : isActive
                        ? AppColors.onBackground
                        : AppColors.onSurface,
                fontSize: 15,
                fontWeight:
                    isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing indicator for the active step ─────────────────────────────────────

class _PulsingIndicator extends StatefulWidget {
  final Color color;
  const _PulsingIndicator({required this.color});

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withAlpha((_anim.value * 40).round()),
          border: Border.all(
            color: widget.color.withAlpha((_anim.value * 255).round()),
            width: 2,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error body ─────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 36,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Processing Failed', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyDim,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Go Back'),
          ),
        ],
      ),
    );
  }
}
