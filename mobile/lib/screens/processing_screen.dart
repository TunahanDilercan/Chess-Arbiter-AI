import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';

// ── Pipeline steps ─────────────────────────────────────────────────────────────

const _kPipelineSteps = [
  ('queued', 'Sırada', Icons.hourglass_empty),
  ('preprocessing', 'Ön işleme', Icons.tune),
  ('cropping', 'Tablo bulunuyor', Icons.grid_on),
  ('ocr_processing', 'Yazı okunuyor', Icons.text_fields),
  ('ocr_complete', 'Okuma tamam', Icons.check_circle_outline),
  ('analyzing', 'Hamleler analiz ediliyor', Icons.psychology),
  ('completed', 'Tamamlandı', Icons.emoji_events),
];

int _stepIndex(String status) =>
    _kPipelineSteps.indexWhere((s) => s.$1 == status);

class ProcessingScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String gameId;

  const ProcessingScreen({
    super.key,
    required this.jobId,
    required this.gameId,
  });

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  bool _importing = false;
  String? _importError;

  String get jobId => widget.jobId;

  /// OCR is done on the server; review and correction happen on-device.
  Future<void> _import() async {
    if (_importing) return;
    _importing = true;
    try {
      final rec = await importOcrGame(ref, widget.gameId);
      if (mounted) context.go('/game/${rec.id}');
    } on Exception catch (e) {
      if (mounted) setState(() => _importError = 'Sonuç cihaza aktarılamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_importError != null) {
      return _Shell(jobId: jobId, child: _ErrorBody(message: _importError!));
    }
    final stream = ref.watch(jobStatusProvider(jobId));

    return stream.when(
      loading: () => _Shell(
        jobId: jobId,
        child: const _Timeline(currentStatus: 'queued', errorMessage: null),
      ),
      error: (e, _) => _Shell(
        jobId: jobId,
        child: _ErrorBody(
          message: e.toString(),
          onRetry: () => ref.invalidate(jobStatusProvider(jobId)),
        ),
      ),
      data: (event) {
        if (event.status == 'completed') {
          WidgetsBinding.instance.addPostFrameCallback((_) => _import());
        }
        return _Shell(
          jobId: jobId,
          child: event.status == 'failed'
              ? _ErrorBody(message: event.error_message ?? 'İşlem başarısız.')
              : _Timeline(
                  currentStatus: event.status,
                  errorMessage: event.error_message,
                ),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  final String jobId;
  final Widget child;
  const _Shell({required this.jobId, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karne okunuyor'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job: $jobId',
              style: TextStyle(
                fontFamily: ArbiterFontFamily.mono,
                fontSize: ArbiterFontSize.notationSm,
                color: c.contentTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: ArbiterSpacing.s5),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final String currentStatus;
  final String? errorMessage;
  const _Timeline({required this.currentStatus, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final activeIdx = _stepIndex(currentStatus);
    final progress = activeIdx < 0
        ? 0.0
        : (activeIdx + 1) / _kPipelineSteps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ArbiterRadii.full),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: c.surfaceElevated,
            valueColor: AlwaysStoppedAnimation(c.accentPrimary),
          ),
        ),
        const SizedBox(height: ArbiterSpacing.s5),
        Expanded(
          child: ListView.builder(
            itemCount: _kPipelineSteps.length,
            itemBuilder: (context, index) {
              final (status, label, icon) = _kPipelineSteps[index];
              final isDone = activeIdx >= 0 && index < activeIdx;
              final isActive = index == activeIdx;
              final isPending = activeIdx < 0 || index > activeIdx;

              final dotColor = isDone
                  ? c.feedbackSuccess
                  : isActive
                  ? c.accentPrimary
                  : c.contentTertiary;

              return _TimelineStep(
                icon: icon,
                label: label,
                dotColor: dotColor,
                connectorColor: isDone
                    ? c.feedbackSuccess.withAlpha(100)
                    : c.surfaceElevated,
                labelColor: isPending
                    ? c.contentTertiary
                    : isActive
                    ? c.contentPrimary
                    : c.contentSecondary,
                isDone: isDone,
                isActive: isActive,
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
  final Color dotColor;
  final Color connectorColor;
  final Color labelColor;
  final bool isDone;
  final bool isActive;
  final bool isLast;

  const _TimelineStep({
    required this.icon,
    required this.label,
    required this.dotColor,
    required this.connectorColor,
    required this.labelColor,
    required this.isDone,
    required this.isActive,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      color: connectorColor,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 20),
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: ArbiterFontSize.bodyLg,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorBody({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.feedbackDanger.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, color: c.feedbackDanger, size: 36),
          ),
          const SizedBox(height: ArbiterSpacing.s4),
          Text(
            onRetry == null ? 'Processing Failed' : 'Connection interrupted',
            style: TextStyle(
              fontFamily: ArbiterFontFamily.display,
              fontSize: ArbiterFontSize.headingMd,
              fontWeight: ArbiterFontWeights.semibold,
              color: c.contentPrimary,
            ),
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ArbiterSpacing.s6),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.contentSecondary),
            ),
          ),
          const SizedBox(height: ArbiterSpacing.s6),
          if (onRetry != null)
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
            ),
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
