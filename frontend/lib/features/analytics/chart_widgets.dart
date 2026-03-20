import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';

class StatusPieChart extends StatelessWidget {
  final Map<String, int> statusCounts;

  const StatusPieChart({super.key, required this.statusCounts});

  @override
  Widget build(BuildContext context) {
    final total = statusCounts.values.fold(0, (a, b) => a + b);

    return AspectRatio(
      aspectRatio: 1.3,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 50,
          sections: [
            PieChartSectionData(
              color: AppColors.pendingText,
              value: (statusCounts['pending'] ?? 0).toDouble(),
              title: total > 0 ? '${((statusCounts['pending'] ?? 0) / total * 100).toInt()}%' : '',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            PieChartSectionData(
              color: AppColors.inProgressText,
              value: (statusCounts['in_progress'] ?? 0).toDouble(),
              title: total > 0 ? '${((statusCounts['in_progress'] ?? 0) / total * 100).toInt()}%' : '',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            PieChartSectionData(
              color: AppColors.closedText,
              value: (statusCounts['closed'] ?? 0).toDouble(),
              title: total > 0 ? '${((statusCounts['closed'] ?? 0) / total * 100).toInt()}%' : '',
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusLegend extends StatelessWidget {
  final Map<String, int> statusCounts;

  const StatusLegend({super.key, required this.statusCounts});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _legendItem('Pending', statusCounts['pending'] ?? 0, AppColors.pendingText),
        const SizedBox(height: 8),
        _legendItem('In Progress', statusCounts['in_progress'] ?? 0, AppColors.inProgressText),
        const SizedBox(height: 8),
        _legendItem('Closed', statusCounts['closed'] ?? 0, AppColors.closedText),
      ],
    );
  }

  Widget _legendItem(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Spacer(),
        Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}

class SimpleBarChart extends StatelessWidget {
  final List<ChartDataPoint> data;
  final Color barColor;

  const SimpleBarChart({
    super.key,
    required this.data,
    this.barColor = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final maxY = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);

    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          barGroups: data.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.value,
                  color: barColor,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < data.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        data[value.toInt()].label,
                        style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true, drawVerticalLine: false),
        ),
      ),
    );
  }
}

class ChartDataPoint {
  final String label;
  final double value;

  ChartDataPoint(this.label, this.value);
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
