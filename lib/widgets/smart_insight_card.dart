import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/lab_providers.dart';
import '../core/theme.dart';

import 'glass_card.dart';

class SmartInsightCard extends ConsumerWidget {
  const SmartInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictionsAsync = ref.watch(healthPredictionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return predictionsAsync.when(
      data: (predictions) {
        if (predictions.isEmpty) return const SizedBox.shrink();

        return GlassCard(
          margin: const EdgeInsets.only(bottom: 24),
          opacity: isDark ? 0.15 : 0.7,
          tintColor: isDark
              ? const Color.fromARGB(255, 11, 21, 37) // Deep Blue tint
              : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF818CF8),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'AI Health Forecast',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF818CF8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'BETA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                color: isDark
                    ? const Color(0xFF334155)
                    : Colors.black.withValues(alpha: 0.1),
                height: 1,
              ),

              // Horizontal Scroll for multiple insights
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: predictions
                      .map(
                        (prediction) =>
                            _buildPredictionItem(context, prediction),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const CircularProgressIndicator(),
      ),
      error: (e, s) => Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Unable to load health forecast right now.',
          style: TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildPredictionItem(BuildContext context, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metric = data['metric'] ?? 'Metric';
    // final current = data['current_value'] ?? '-'; // Not used in snippet
    final current = data['current_value'] ?? '-';
    // final predicted = data['predicted_value'] ?? '-'; // Not used in snippet
    final predicted = data['predicted_value'] ?? '-';
    final direction = data['trend_direction'] ?? 'Stable';
    final risk = data['risk_level'] ?? 'Low';
    final insight = data['insight'] ?? '';
    final recommendation = data['recommendation'] ?? '';

    Color trendColor = AppColors.success;
    IconData trendIcon = Icons.trending_flat;

    if (direction == 'Increasing') {
      trendIcon = Icons.trending_up;
      trendColor = Colors.orange; // Context-dependent, but neutral for now
    } else if (direction == 'Decreasing') {
      trendIcon = Icons.trending_down;
      trendColor = Colors.blue;
    }

    Color riskColor = AppColors.success;
    if (risk == 'Medium') riskColor = Colors.orange;
    if (risk == 'High') riskColor = AppColors.danger;

    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = textColor.withValues(alpha: 0.7);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      child: Material(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: InkWell(
          onTap: () => _showInsightDialog(
            context,
            data,
            riskColor,
            trendColor,
            trendIcon,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        metric,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: riskColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '$risk Risk',
                        style: TextStyle(
                          color: riskColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildValueColumn('Current', current, secondaryTextColor),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.arrow_forward,
                      color: textColor.withValues(alpha: 0.3),
                      size: 16,
                    ),
                    const SizedBox(width: 12),
                    _buildValueColumn('Predicted (3mo)', predicted, textColor),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(trendIcon, color: trendColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Trend: $direction',
                      style: TextStyle(
                        color: trendColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  insight,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: Color(0xFF818CF8),
                        size: 12,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          recommendation,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFC7D2FE)
                                : const Color(0xFF312E81),
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInsightDialog(
    BuildContext context,
    Map<String, dynamic> data,
    Color riskColor,
    Color trendColor,
    IconData trendIcon,
  ) {
    final metric = data['metric'] ?? 'Metric';
    // final current = data['current_value'] ?? '-';
    // final predicted = data['predicted_value'] ?? '-';
    final direction = data['trend_direction'] ?? 'Stable';
    final risk = data['risk_level'] ?? 'Low';
    final insight = data['insight'] ?? '';
    final recommendation = data['recommendation'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = Theme.of(context).colorScheme.onSurface;

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        metric,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: riskColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '$risk Risk',
                        style: TextStyle(
                          color: riskColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(trendIcon, color: trendColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      direction,
                      style: TextStyle(
                        color: trendColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Analysis',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  insight,
                  style: TextStyle(color: textColor, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Color(0xFF818CF8),
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Recommendation',
                            style: TextStyle(
                              color: Color(0xFF818CF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        recommendation,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFE0E7FF)
                              : const Color(0xFF312E81),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildValueColumn(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
