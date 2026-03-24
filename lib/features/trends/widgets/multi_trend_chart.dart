import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/models.dart';
import '../../../core/services/trend_analysis_service.dart';
import '../../../core/utils/unit_sanitizer.dart';
import 'package:intl/intl.dart';

class MultiTrendChart extends StatelessWidget {
  final Map<String, List<LabReport>> data;
  final Map<String, List<NormalizedPoint>>? normalizedData;
  final bool isNormalized;

  const MultiTrendChart({
    super.key,
    required this.data,
    this.normalizedData,
    this.isNormalized = false,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No Data'));

    final keys = data.keys.toList();
    final colors = [
      AppColors.primary,
      AppColors.secondary,
      AppColors.success,
      AppColors.danger,
    ];

    LineChartData chartData;

    if (isNormalized) {
      chartData = _buildNormalizedChart(keys, colors);
    } else if (keys.length == 2) {
      chartData = _buildDualAxisChart(
        keys,
        colors,
      ); // Not fully supported by fl_chart out of box easily without side titles trickery
      // Actually fl_chart supports multiple axes but it's complex.
      // Simplified approach: Use Left and Right titles.
      chartData = _buildDualAxisChart(keys, colors);
    } else {
      chartData = _buildStandardChart(keys, colors);
    }

    return LineChart(chartData);
  }

  LineChartData _buildStandardChart(List<String> keys, List<Color> colors) {
    // Collect all points to find min/max X (Date) and Y (Value)
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    final List<LineChartBarData> lineBars = [];

    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final points = data[key]!;
      if (points.isEmpty) continue;

      final spots = <FlSpot>[];
      for (var r in points) {
        final date = r.date.millisecondsSinceEpoch.toDouble();
        final test = r.testResults?.firstWhere(
          (t) => t.name == key,
          orElse: () => TestResult(
            name: '',
            loinc: '',
            result: '',
            unit: '',
            reference: '',
            status: '',
          ),
        );
        final value = double.tryParse(test?.result ?? '') ?? 0;
        spots.add(FlSpot(date, value));

        if (date < minX) minX = date;
        if (date > maxX) maxX = date;
        if (value < minY) minY = value;
        if (value > maxY) maxY = value;
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[i % colors.length],
          barWidth: 3,
          shadow: Shadow(color: colors[i % colors.length], blurRadius: 10),
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: colors[i % colors.length],
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: colors[i % colors.length].withValues(alpha: 0.1),
          ),
        ),
      );
    }

    // Add margin to Y-axis
    final yMargin = (maxY - minY) * 0.1;
    minY = (minY - yMargin).clamp(0, double.infinity);
    maxY += yMargin;

    return LineChartData(
      lineBarsData: lineBars,
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) => _bottomTitleWidgets(value, meta),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      gridData: const FlGridData(show: false), // No grid lines
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) =>
              Colors.black.withValues(alpha: 0.8), // Dark tooltip
          tooltipBorder: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              final testName = keys[touchedSpot.barIndex];
              final report = data[testName]![touchedSpot.spotIndex];
              final test = report.testResults?.firstWhere(
                (t) => t.name == testName,
                orElse: () => TestResult(
                  name: '',
                  loinc: '',
                  result: '',
                  unit: '',
                  reference: '',
                  status: '',
                ),
              );
              final date = DateFormat('MMM dd, yyyy').format(report.date);
              final displayUnit = getDisplayUnit({'unit': test?.unit ?? ''});

              return LineTooltipItem(
                displayUnit.isEmpty
                    ? '$testName\n$date\n${touchedSpot.y.toStringAsFixed(1)}'
                    : '$testName\n$date\n${touchedSpot.y.toStringAsFixed(1)} $displayUnit',
                TextStyle(
                  color: touchedSpot.bar.color, // Neon color text
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  LineChartData _buildDualAxisChart(List<String> keys, List<Color> colors) {
    if (keys.length != 2) return _buildStandardChart(keys, colors);

    // To simulate dual axis, we normalize the second series to the first series' scale visually,
    // but show the correct tooltips.
    // Use trendAnalysisService-like logic, but just mapping ranges.

    // For simplicity given implementation constraints, let's just stick to StandardChart
    // or NormalizedChart for now unless specifically requested.
    // The simplified plan handles scaling via normalization.
    // True dual axis in fl_chart requires mapping Y2 to Y1 coordinates and setting right titles manually.

    // Let's implement the normalization strategy for >1 marker as per Plan
    // "Percentage Normalization (displaying values as % of their max range or global max) by default for >2 markers"
    // "Dual Y-Axis for exactly 2 markers"

    // Let's implement proper visual mapping for Dual Axis
    // Series 1: Primary Y (Left)
    // Series 2: Secondary Y (Right) - Mapped to Left scale

    final s1 = data[keys[0]]!;
    final s2 = data[keys[1]]!;

    double min1 = double.infinity, max1 = -double.infinity;
    double min2 = double.infinity, max2 = -double.infinity;
    double minX = double.infinity, maxX = -double.infinity;

    for (var p in s1) {
      final test = p.testResults?.firstWhere(
        (t) => t.name == keys[0],
        orElse: () => TestResult(
          name: '',
          loinc: '',
          result: '',
          unit: '',
          reference: '',
          status: '',
        ),
      );
      final v = double.tryParse(test?.result ?? '') ?? 0;
      if (v < min1) min1 = v;
      if (v > max1) max1 = v;

      final d = p.date.millisecondsSinceEpoch.toDouble();
      if (d < minX) minX = d;
      if (d > maxX) maxX = d;
    }

    for (var p in s2) {
      final test = p.testResults?.firstWhere(
        (t) => t.name == keys[1],
        orElse: () => TestResult(
          name: '',
          loinc: '',
          result: '',
          unit: '',
          reference: '',
          status: '',
        ),
      );
      final v = double.tryParse(test?.result ?? '') ?? 0;
      if (v < min2) min2 = v;
      if (v > max2) max2 = v;

      final d = p.date.millisecondsSinceEpoch.toDouble();
      if (d < minX) minX = d;
      if (d > maxX) maxX = d;
    }

    if (max1 == min1) max1 += 1;
    if (max2 == min2) max2 += 1;

    // Scale factor for Series 2 to fit into Series 1 range
    // v2_scaled = (v2 - min2) / (max2 - min2) * (max1 - min1) + min1
    double scale(double v2) {
      return (v2 - min2) / (max2 - min2) * (max1 - min1) + min1;
    }

    final spots1 = s1.map((p) {
      final test = p.testResults?.firstWhere(
        (t) => t.name == keys[0],
        orElse: () => TestResult(
          name: '',
          loinc: '',
          result: '',
          unit: '',
          reference: '',
          status: '',
        ),
      );
      return FlSpot(
        p.date.millisecondsSinceEpoch.toDouble(),
        double.tryParse(test?.result ?? '') ?? 0,
      );
    }).toList();

    final spots2 = s2.map((p) {
      final test = p.testResults?.firstWhere(
        (t) => t.name == keys[1],
        orElse: () => TestResult(
          name: '',
          loinc: '',
          result: '',
          unit: '',
          reference: '',
          status: '',
        ),
      );
      return FlSpot(
        p.date.millisecondsSinceEpoch.toDouble(),
        scale(double.tryParse(test?.result ?? '') ?? 0),
      );
    }).toList();

    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots1,
          color: colors[0],
          isCurved: true,
          barWidth: 3,
          shadow: Shadow(color: colors[0], blurRadius: 10),
          belowBarData: BarAreaData(
            show: true,
            color: colors[0].withValues(alpha: 0.1),
          ),
        ),
        LineChartBarData(
          spots: spots2,
          color: colors[1],
          isCurved: true,
          barWidth: 3,
          shadow: Shadow(color: colors[1], blurRadius: 10),
          belowBarData: BarAreaData(
            show: true,
            color: colors[1].withValues(alpha: 0.1),
          ),
        ),
      ],
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: (max1 - min1) / 5,
            getTitlesWidget: (val, meta) => Text(
              val.toStringAsFixed(1),
              style: TextStyle(color: colors[0], fontSize: 10),
            ),
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            // We need to inverse map the titles
            getTitlesWidget: (val, meta) {
              // val is in scale of 1
              // inverse: (val - min1) / (max1 - min1) * (max2 - min2) + min2
              final original =
                  (val - min1) / (max1 - min1) * (max2 - min2) + min2;
              return Text(
                original.toStringAsFixed(1),
                style: TextStyle(color: colors[1], fontSize: 10),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) => _bottomTitleWidgets(value, meta),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      minY: min1 - (max1 - min1) * 0.1,
      maxY: max1 + (max1 - min1) * 0.1,
      minX: minX,
      maxX: maxX,
      gridData: const FlGridData(show: false), // No grid lines
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black.withValues(alpha: 0.8),
          tooltipBorder: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isS2 = spot.barIndex == 1;
              final color = colors[isS2 ? 1 : 0];
              final testName = keys[isS2 ? 1 : 0];
              final report = data[testName]![spot.spotIndex];
              final test = report.testResults?.firstWhere(
                (t) => t.name == testName,
                orElse: () => TestResult(
                  name: '',
                  loinc: '',
                  result: '',
                  unit: '',
                  reference: '',
                  status: '',
                ),
              );

              double val = spot.y;
              if (isS2) {
                // Inverse scale
                val = (val - min1) / (max1 - min1) * (max2 - min2) + min2;
              }

              final date = DateFormat('MMM dd, yyyy').format(report.date);
              final displayUnit = getDisplayUnit({'unit': test?.unit ?? ''});

              return LineTooltipItem(
                displayUnit.isEmpty
                    ? '$testName\n$date\n${val.toStringAsFixed(1)}'
                    : '$testName\n$date\n${val.toStringAsFixed(1)} $displayUnit',
                TextStyle(color: color, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  LineChartData _buildNormalizedChart(List<String> keys, List<Color> colors) {
    if (normalizedData == null) return LineChartData();

    final List<LineChartBarData> lineBars = [];
    double minX = double.infinity;
    double maxX = -double.infinity;

    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final points = normalizedData![key]!;

      final spots = <FlSpot>[];
      for (var p in points) {
        final date = p.date.millisecondsSinceEpoch.toDouble();
        spots.add(FlSpot(date, p.normalizedValue));

        if (date < minX) minX = date;
        if (date > maxX) maxX = date;
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[i % colors.length],
          barWidth: 3,
          shadow: Shadow(color: colors[i % colors.length], blurRadius: 10),
          belowBarData: BarAreaData(
            show: true,
            color: colors[i % colors.length].withValues(alpha: 0.1),
          ),
        ),
      );
    }

    return LineChartData(
      lineBarsData: lineBars,
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 20,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) => _bottomTitleWidgets(value, meta),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      minY: 0,
      maxY: 100,
      minX: minX,
      gridData: const FlGridData(show: false), // No grid lines
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black.withValues(alpha: 0.8),
          tooltipBorder: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final key = keys[spot.barIndex];
              final point = normalizedData![key]!.firstWhere(
                (p) => p.date.millisecondsSinceEpoch == spot.x.toInt(),
                orElse: () => normalizedData![key]!.first,
              );
              final displayUnit = getDisplayUnit({'unit': point.unit});

              return LineTooltipItem(
                displayUnit.isEmpty
                    ? '$key: ${point.originalValue.toStringAsFixed(1)}'
                    : '$key: ${point.originalValue.toStringAsFixed(1)} $displayUnit',
                TextStyle(color: spot.bar.color, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final text = DateFormat('MM/dd').format(date);
    return SideTitleWidget(
      meta: meta,
      space: 10,
      child: Text(text, style: style),
    );
  }
}
