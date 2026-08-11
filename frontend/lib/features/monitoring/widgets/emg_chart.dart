import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/emg_provider.dart';

/// Oscilloscope-style waveform drawn with CustomPainter instead of a chart
/// library. The x-axis pixel range is fixed (never recomputed per frame) and
/// values are read straight out of [EmgSignalController]'s ring buffers, so
/// a new sample only triggers a canvas repaint - never a widget rebuild or
/// layout pass - which is what keeps a 20fps sliding window flicker-free.
class EmgChart extends StatelessWidget {
  const EmgChart({super.key, required this.controller});

  final EmgSignalController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.hasData,
      builder: (context, hasData, _) {
        if (!hasData) {
          return const Center(
            child: Text('Waiting for signal...', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _EmgPainter(controller),
          ),
        );
      },
    );
  }
}

class _EmgPainter extends CustomPainter {
  _EmgPainter(this.controller) : super(repaint: controller);

  final EmgSignalController controller;

  static const double _yRange = 60;
  static const int _gridDivisions = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade900
      ..strokeWidth = 0.5;
    for (var i = 0; i <= _gridDivisions; i++) {
      final x = size.width * i / _gridDivisions;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      final y = size.height * i / _gridDivisions;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dx = size.width / (emgWindowSize - 1);
    final midY = size.height / 2;
    final scaleY = (size.height / 2) / _yRange;

    for (var ch = 0; ch < controller.buffers.length; ch++) {
      final buffer = controller.buffers[ch];
      if (buffer.length < 2) continue;

      final paint = Paint()
        ..color = AppColors.emgChannels[ch % AppColors.emgChannels.length].withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      // Fixed x-axis: index 0 is always the leftmost pixel column. While the
      // buffer is still filling, new points are right-aligned so the trace
      // grows in from the right instead of stretching across the full width.
      final startIndex = emgWindowSize - buffer.length;
      final path = Path();
      for (var i = 0; i < buffer.length; i++) {
        final x = (startIndex + i) * dx;
        final y = midY - (buffer[i] * scaleY);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  // Repainting is driven entirely by the `repaint` listenable above, not by
  // widget rebuilds, so there's nothing to compare here.
  @override
  bool shouldRepaint(covariant _EmgPainter oldDelegate) => false;
}
