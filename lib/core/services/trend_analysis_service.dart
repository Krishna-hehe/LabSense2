import '../models.dart';
import '../utils/unit_sanitizer.dart';

class TrendAnalysisService {
  /// Normalizes data series to a 0-100 scale based on the global max of all series
  /// This allows visualizing trends on the same chart even if scales differ wildly.
  Map<String, List<NormalizedPoint>> normalizeData(Map<String, List<LabReport>> data) {
    if (data.isEmpty) return {};

    final Map<String, List<NormalizedPoint>> result = {};

    // 1. Calculate max value for each series to normalize against ITSELF (percentage of max)
    // Or normalize against a shared axis?
    // Implementation Plan said: "Percentage Normalization (displaying values as % of their max range or global max)"
    // Better approach for trend comparison: Normalize each series to 0-1 range based on its OWN min/max.
    // This shows relative movement.
    
    data.forEach((testName, reports) {
      if (reports.isEmpty) {
        result[testName] = [];
        return;
      }

      final List<Map<String, dynamic>> validPoints = [];
      double minVal = double.maxFinite;
      double maxVal = -double.maxFinite;

      for (var report in reports) {
        final test = report.testResults?.firstWhere(
          (t) => t.name == testName,
          orElse: () => TestResult(name: '', loinc: '', result: '', unit: '', reference: '', status: ''),
        );
        
        if (test != null && test.result.isNotEmpty && _isNumeric(test.result)) {
          final val = double.tryParse(test.result) ?? 0;
          if (val < minVal) minVal = val;
          if (val > maxVal) maxVal = val;
          validPoints.add({'report': report, 'val': val, 'test': test});
        }
      }

      if (validPoints.isEmpty) {
        result[testName] = [];
        return;
      }

      // Avoid division by zero
      final range = maxVal - minVal;
      final effectiveRange = range == 0 ? 1.0 : range;

      result[testName] = validPoints.map((p) {
        final val = p['val'] as double;
        final report = p['report'] as LabReport;
        final test = p['test'] as TestResult;
        
        // Min-Max Normalization: (val - min) / range * 100
        final normalized = ((val - minVal) / effectiveRange) * 100;
        
        return NormalizedPoint(
          date: report.date,
          originalValue: val,
          normalizedValue: normalized,
          unit: UnitSanitizer.clean(test.unit) ?? '',
        );
      }).toList();
      
      // Sort by date
      result[testName]!.sort((a, b) => a.date.compareTo(b.date));
    });

    return result;
  }

  MarkerStats calculateStats(List<LabReport> reports, String testName) {
    if (reports.isEmpty) return MarkerStats.empty(testName);

    final points = <double>[];
    String unit = '';
    
    for (var r in reports) {
      final test = r.testResults?.firstWhere((t) => t.name == testName, orElse: () => TestResult(name: '', loinc: '', result: '', unit: '', reference: '', status: ''));
      if (test != null && _isNumeric(test.result)) {
        points.add(double.tryParse(test.result) ?? 0);
        unit = UnitSanitizer.clean(test.unit) ?? '';
      }
    }

    if (points.isEmpty) return MarkerStats.empty(testName);

    final current = points.last;
    final first = points.first;
    final change = first == 0 ? 0.0 : ((current - first) / first) * 100;
    
    double min = points.reduce((a, b) => a < b ? a : b);
    double max = points.reduce((a, b) => a > b ? a : b);
    double avg = points.reduce((a, b) => a + b) / points.length;

    String direction = 'Stable';
    if (change > 5) direction = 'Increasing';
    if (change < -5) direction = 'Decreasing';

    return MarkerStats(
      testName: testName,
      currentValue: current,
      unit: unit,
      percentageChange: change,
      trendDirection: direction,
      min: min,
      max: max,
      average: avg,
    );
  }

  bool _isNumeric(String? s) {
    if (s == null) return false;
    return double.tryParse(s) != null;
  }
}

class NormalizedPoint {
  final DateTime date;
  final double originalValue;
  final double normalizedValue;
  final String unit;

  NormalizedPoint({
    required this.date,
    required this.originalValue,
    required this.normalizedValue,
    required this.unit,
  });
}

class MarkerStats {
  final String testName;
  final double currentValue;
  final String unit;
  final double percentageChange;
  final String trendDirection;
  final double min;
  final double max;
  final double average;

  MarkerStats({
    required this.testName,
    required this.currentValue,
    required this.unit,
    required this.percentageChange,
    required this.trendDirection,
    required this.min,
    required this.max,
    required this.average,
  });

  factory MarkerStats.empty(String name) => MarkerStats(
    testName: name,
    currentValue: 0,
    unit: '',
    percentageChange: 0,
    trendDirection: 'N/A',
    min: 0,
    max: 0,
    average: 0,
  );
}
