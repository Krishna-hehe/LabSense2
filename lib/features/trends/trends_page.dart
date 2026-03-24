import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/utils/unit_sanitizer.dart';

class TrendsPage extends ConsumerStatefulWidget {
  const TrendsPage({super.key});

  @override
  ConsumerState<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends ConsumerState<TrendsPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;
  String? _selectedTest;
  List<Map<String, dynamic>> _rawData = [];
  List<FlSpot> _spots = [];
  final bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _aiAnalysis;
  String _unit = '';
  String _reference = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animations = List.generate(4, (index) {
      double start = index * 0.15;
      double end = (start + 0.4).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(distinctTestsProvider);
    
    return testsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
      data: (tests) {
        if (tests.isEmpty) return _buildNoDataState();
        
        // Auto-select first test if none selected
        _selectedTest ??= tests.contains('Cholesterol') ? 'Cholesterol' : tests.first;
        
        final trendDataAsync = ref.watch(trendDataProvider(_selectedTest!));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAnimatedItem(0, _buildHeader()),
              const SizedBox(height: 32),
              _buildAnimatedItem(1, _buildSelectionCard(tests)),
              const SizedBox(height: 24),
              trendDataAsync.when(
                loading: () => const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
                error: (e, s) => Center(child: Text('Error: $e')),
                data: (data) {
                  _rawData = data;
                  _updateSpots();
                  return Column(
                    children: [
                      _buildAnimatedItem(2, _buildChartCard()),
                      const SizedBox(height: 24),
                      _buildAnimatedItem(3, _buildAiTrendCard()),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateSpots() {
    if (_rawData.isNotEmpty) {
      _unit = UnitSanitizer.clean(_rawData.last['unit']?.toString()) ?? '';
      _reference = _rawData.last['reference'] ?? '';
      
      _spots = [];
      for (int i = 0; i < _rawData.length; i++) {
        _spots.add(FlSpot(i.toDouble(), _rawData[i]['value'] as double));
      }
    } else {
      _spots = [];
      _unit = '';
      _reference = '';
    }
    
    // Trigger animation controller if not already running
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  Future<void> _analyzeTrend() async {
    if (_rawData.isEmpty) return;

    setState(() => _isAnalyzing = true);

    try {
      final dataPoints = _rawData.map((d) {
        final date = d['date'].toString().split('T')[0];
        return '$date: ${formatDisplayValueWithUnit({'value': d['value'], 'unit': d['unit']})}';
      }).join(', ');

      final prompt = "Analyze the trend for $_selectedTest based on these historical data points: $dataPoints. "
          "Explain what the pattern suggests (e.g., improvement, stability, or concern) and provide context-specific health considerations. "
          "Keep the response professional, concise (max 3-4 sentences), and clear.";

      final analysis = await ref.read(aiServiceProvider).chat(prompt);
      if(mounted) setState(() => _aiAnalysis = analysis);
    } catch (e) {
      debugPrint('Error analyzing trend: $e');
      if(mounted) setState(() => _aiAnalysis = "Unable to generate analysis right now. Please try again later.");
    } finally {
      if(mounted) setState(() => _isAnalyzing = false);
    }
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return FadeTransition(
      opacity: _animations[index],
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(_animations[index]),
        child: child,
      ),
    );
  }

  Widget _buildNoDataState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: const [
          Icon(Icons.analytics_outlined, size: 48, color: AppColors.border),
          SizedBox(height: 24),
          Text(
            'No trend data available',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Upload your lab reports to see how your health metrics change over time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(FontAwesomeIcons.chartLine, size: 24, color: AppColors.secondary),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Trend Analysis',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Track how your lab results change over time',
              style: TextStyle(color: AppColors.secondary, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectionCard(List<String> tests) {
    String dateRange = 'No data';
    if (_rawData.isNotEmpty) {
      final start = DateTime.parse(_rawData.first['date']);
      final end = DateTime.parse(_rawData.last['date']);
      dateRange = '${DateFormat('MMM d, yy').format(start)} - ${DateFormat('MMM d, yy').format(end)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Test', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Text('Choose a lab test to visualize results over time.', style: TextStyle(color: AppColors.secondary, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Text(dateRange, style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTest,
                isExpanded: true,
                items: tests
                    .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedTest = val;
                    _aiAnalysis = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    final maxY = _spots.isEmpty ? 100.0 : _spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;
    final minY = _spots.isEmpty ? 0.0 : _spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.8;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedTest ?? 'Select a test', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('${_rawData.length} measurements in $_unit', style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Reference Range', style: TextStyle(color: AppColors.secondary, fontSize: 12)),
                  Text(_reference.isEmpty ? 'N/A' : _reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          if (_isLoading)
            const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
          else if (_spots.isEmpty)
             const SizedBox(height: 300, child: Center(child: Text('Not enough data to display chart.')))
          else
            SizedBox(
              height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.border.withAlpha((0.5 * 255).toInt()),
                    strokeWidth: 1,
                    dashArray: [5, 5],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _rawData.length) {
                          final date = DateTime.parse(_rawData[index]['date']);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(DateFormat('MMM d').format(date), 
                              style: const TextStyle(color: AppColors.secondary, fontSize: 10)),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toInt()}', style: const TextStyle(color: AppColors.secondary, fontSize: 11));
                      },
                      reservedSize: 40,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (_rawData.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 6,
                      color: Theme.of(context).scaffoldBackgroundColor,
                      strokeColor: Theme.of(context).colorScheme.primary,
                      strokeWidth: 2,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withAlpha((0.05 * 255).toInt()),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(AppColors.primary, 'Your Results'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {bool isDashed = false}) {
    return Row(
      children: [
        if (isDashed)
          Container(
            width: 16,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Colors.transparent],
                stops: const [0.5, 0.5],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
      ],
    );
  }

  Widget _buildAiTrendCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.waveSquare, size: 16, color: AppColors.secondary),
              const SizedBox(width: 12),
              const Text('AI Trend Analysis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              ElevatedButton.icon(
                icon: Icon(_isAnalyzing ? Icons.hourglass_empty : Icons.refresh, size: 14),
                label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze Trend'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isAnalyzing || _rawData.isEmpty ? null : _analyzeTrend,
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (_aiAnalysis != null)
             AnimatedOpacity(
               duration: const Duration(milliseconds: 500),
               opacity: _aiAnalysis != null ? 1.0 : 0.0,
               child: Container(
                 padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Row(
                       children: const [
                         Icon(FontAwesomeIcons.robot, size: 16, color: AppColors.primary),
                         SizedBox(width: 12),
                         Text('Assistant Guidance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
                       ],
                     ),
                     const SizedBox(height: 12),
                     Text(
                       _aiAnalysis!,
                       style: TextStyle(fontSize: 14, height: 1.5, color: Theme.of(context).colorScheme.onSurface),
                     ),
                  ],
                ),
              )
            )
          else
            Center(
              child: Column(
                children: [
                  Icon(FontAwesomeIcons.waveSquare, size: 48, color: Theme.of(context).dividerColor),
                  SizedBox(height: 24),
                  Text(
                    'Get AI-powered insights about your trend',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Click "Analyze Trend" to see what this pattern means',
                    style: TextStyle(color: AppColors.secondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
