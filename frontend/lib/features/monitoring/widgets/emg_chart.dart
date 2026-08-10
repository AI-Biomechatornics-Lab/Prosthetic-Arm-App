import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class EmgChart extends StatelessWidget {
  const EmgChart({super.key, required this.channels});

  final List<List<double>> channels;

  @override
  Widget build(BuildContext context) {
    final hasData = channels.any((c) => c.isNotEmpty);
    if (!hasData) {
      return const Center(
        child: Text('Waiting for signal...', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return LineChart(
      LineChartData(
        minY: -1.2,
        maxY: 1.2,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          for (var i = 0; i < channels.length; i++)
            LineChartBarData(
              spots: [
                for (var j = 0; j < channels[i].length; j++) FlSpot(j.toDouble(), channels[i][j]),
              ],
              isCurved: false,
              color: AppColors.emgChannels[i % AppColors.emgChannels.length].withValues(alpha: 0.85),
              barWidth: 1.4,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
