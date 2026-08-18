import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/emg_provider.dart';

/// Oscilloscope-style waveform drawn with CustomPainter instead of a chart
/// library. The x-axis pixel range is fixed (never recomputed per frame) and
/// values are read straight out of [EmgSignalController]'s ring buffers, so
/// a new sample only triggers a canvas repaint - never a widget rebuild or
/// layout pass - which is what keeps a 20fps sliding window flicker-free.
///
/// Split into two stacked painters: axes/grid/labels are static (painted
/// once, never repainted) and the waveform lines are the only thing that
/// redraws every frame - text layout for axis labels is real work, and
/// there's no reason to pay it 20 times a second when only the trace changes.
class EmgChart extends StatelessWidget {
  const EmgChart({super.key, required this.controller});

  final EmgSignalController controller;

  static const _plotMargin = _PlotMargin(left: 42, bottom: 22, top: 6, right: 6);

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
          child: Stack(
            children: [
              CustomPaint(size: Size.infinite, painter: _EmgAxesPainter(_plotMargin)),
              CustomPaint(size: Size.infinite, painter: _EmgWaveformPainter(controller, _plotMargin)),
            ],
          ),
        );
      },
    );
  }
}

class _PlotMargin {
  const _PlotMargin({required this.left, required this.bottom, required this.top, required this.right});
  final double left;
  final double bottom;
  final double top;
  final double right;
}

const double _yRange = 60;
const int _gridDivisions = 4;
// emgWindowSize samples at the ~20fps (50ms/sample) rate EmgSignalController
// flushes at, so the window spans this many seconds of history.
const double _windowSeconds = emgWindowSize * 0.05;

Rect _plotRect(Size size, _PlotMargin m) {
  return Rect.fromLTRB(m.left, m.top, size.width - m.right, size.height - m.bottom);
}

class _EmgAxesPainter extends CustomPainter {
  _EmgAxesPainter(this.margin);
  final _PlotMargin margin;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _plotRect(size, margin);

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.75;
    final axisPaint = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 1;

    for (var i = 0; i <= _gridDivisions; i++) {
      final x = plot.left + plot.width * i / _gridDivisions;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      final y = plot.top + plot.height * i / _gridDivisions;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);

      // X-axis tick label: seconds ago, 0 = now (right edge).
      final seconds = -_windowSeconds + _windowSeconds * i / _gridDivisions;
      _drawText(
        canvas,
        seconds == 0 ? '0s' : '${seconds.toStringAsFixed(1)}s',
        Offset(x, plot.bottom + 4),
        align: TextAlign.center,
      );

      // Y-axis tick label: amplitude, centered vertically at each gridline.
      final amplitude = _yRange - (2 * _yRange) * i / _gridDivisions;
      _drawText(
        canvas,
        amplitude.toStringAsFixed(0),
        Offset(margin.left - 6, y),
        align: TextAlign.right,
        anchorMiddleY: true,
      );
    }

    canvas.drawRect(plot, axisPaint..style = PaintingStyle.stroke);

    _drawText(canvas, 'Time (s)', Offset(plot.left + plot.width / 2, size.height - 2), align: TextAlign.center, bold: true);

    canvas.save();
    canvas.translate(10, plot.top + plot.height / 2);
    canvas.rotate(-1.5708); // -90deg
    _drawText(canvas, 'Amplitude', Offset.zero, align: TextAlign.center, bold: true);
    canvas.restore();
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    required TextAlign align,
    bool anchorMiddleY = false,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double dx;
    switch (align) {
      case TextAlign.center:
        dx = anchor.dx - painter.width / 2;
      case TextAlign.right:
        dx = anchor.dx - painter.width;
      default:
        dx = anchor.dx;
    }
    final dy = anchorMiddleY ? anchor.dy - painter.height / 2 : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _EmgAxesPainter oldDelegate) => false;
}

class _EmgWaveformPainter extends CustomPainter {
  _EmgWaveformPainter(this.controller, this.margin) : super(repaint: controller);

  final EmgSignalController controller;
  final _PlotMargin margin;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _plotRect(size, margin);
    canvas.save();
    canvas.clipRect(plot);

    final dx = plot.width / (emgWindowSize - 1);
    final midY = plot.top + plot.height / 2;
    final scaleY = (plot.height / 2) / _yRange;

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
        final x = plot.left + (startIndex + i) * dx;
        final y = midY - (buffer[i] * scaleY);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  // Repainting is driven entirely by the `repaint` listenable above, not by
  // widget rebuilds, so there's nothing to compare here.
  @override
  bool shouldRepaint(covariant _EmgWaveformPainter oldDelegate) => false;
}
