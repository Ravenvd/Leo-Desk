import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Formats a rupee value compactly for axis labels (₹1.2k, ₹3.4L).
String compactRupees(double value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 100000) {
    return '$sign₹${(abs / 100000).toStringAsFixed(1)}L';
  }
  if (abs >= 1000) {
    return '$sign₹${(abs / 1000).toStringAsFixed(1)}k';
  }
  return '$sign₹${abs.toStringAsFixed(0)}';
}

/// A line chart comparing this month against last month, day by day.
///
/// [lastMonth] and [thisMonth] are cumulative values indexed by day of
/// month (index 0 = the 1st). Series may have different lengths — the
/// x-axis always spans the longer one.
class MonthComparisonChart extends StatelessWidget {
  const MonthComparisonChart({
    super.key,
    required this.title,
    required this.lastMonth,
    required this.thisMonth,
    this.formatValue = compactRupees,
  });

  final String title;
  final List<double> lastMonth;
  final List<double> thisMonth;
  final String Function(double value) formatValue;

  List<FlSpot> _spots(List<double> values) {
    return [
      for (var i = 0; i < values.length; i++)
        FlSpot((i + 1).toDouble(), values[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxX = lastMonth.length > thisMonth.length
        ? lastMonth.length.toDouble()
        : thisMonth.length.toDouble();

    final allValues = [...lastMonth, ...thisMonth];
    final maxY = allValues.isEmpty
        ? 1.0
        : allValues.reduce((a, b) => a > b ? a : b) * 1.15;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                _Legend(color: Colors.grey, label: 'Last month'),
                const SizedBox(width: 16),
                _Legend(color: colorScheme.primary, label: 'This month'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: maxX < 1 ? 1 : maxX,
                  minY: 0,
                  maxY: maxY <= 0 ? 1 : maxY,
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final day = value.toInt();
                          if (day < 1 || day > maxX) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            '$day',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value == meta.min) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            formatValue(value),
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return [
                          for (final spot in spots)
                            LineTooltipItem(
                              'Day ${spot.x.toInt()}: '
                              '${formatValue(spot.y)}',
                              TextStyle(
                                color: spot.bar.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ];
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _spots(lastMonth),
                      color: Colors.grey,
                      barWidth: 2.5,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: _spots(thisMonth),
                      color: colorScheme.primary,
                      barWidth: 3,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: colorScheme.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cumulative net worth over time: initial investment plus cumulative net
/// profit (revenue minus expenses).
class NetworthChart extends StatelessWidget {
  const NetworthChart({
    super.key,
    required this.points,
    this.formatValue = compactRupees,
  });

  /// Net worth per day, oldest first. X labels show every few dates.
  final List<NetworthPoint> points;
  final String Function(double value) formatValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].networthRupees),
    ];

    final values = points.map((p) => p.networthRupees);
    final minValue = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);

    final padding = (maxValue - minValue).abs() * 0.1 + 1;
    final labelInterval = (points.length / 6).ceilToDouble().clamp(
      1,
      double.infinity,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Net worth', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Initial investment plus cumulative net profit.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: points.length <= 1 ? 1 : points.length - 1.0,
                  minY: minValue - padding,
                  maxY: maxValue + padding,
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0,
                        color: Colors.grey,
                        dashArray: [6, 4],
                        strokeWidth: 1.5,
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: labelInterval.toDouble(),
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }
                          final date = points[index].date;
                          return Text(
                            '${date.day}/${date.month}',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 64,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value == meta.min) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            formatValue(value),
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return [
                          for (final spot in spots)
                            LineTooltipItem(
                              '${points[spot.x.toInt()].date.day}/'
                              '${points[spot.x.toInt()].date.month}: '
                              '${formatValue(spot.y)}',
                              const TextStyle(fontWeight: FontWeight.w600),
                            ),
                        ];
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: colorScheme.tertiary,
                      barWidth: 3,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: colorScheme.tertiary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NetworthPoint {
  final DateTime date;
  final double networthRupees;

  const NetworthPoint({required this.date, required this.networthRupees});
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
