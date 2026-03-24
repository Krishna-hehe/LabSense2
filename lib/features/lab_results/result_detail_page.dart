import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/ai_service.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/pdf_service.dart';

class ResultDetailPage extends ConsumerWidget {
  const ResultDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTest = ref.watch(selectedTestProvider);
    final selectedReport = ref.watch(selectedReportProvider);
    final allReports = ref.watch(labResultsProvider).value ?? [];

    if (selectedTest == null) {
      return const Center(
        child: Text(
          'No test selected. Please select a test from the results list.',
        ),
      );
    }

    final testName = selectedTest.name;
    final valueStr = selectedTest.result.replaceAll(RegExp(r'[^0-9.]'), '');
    final value = double.tryParse(valueStr) ?? 0.0;
    final unit = selectedTest.unit;
    final referenceRange = selectedTest.reference;

    // Extract history for trend analysis
    final history = <Map<String, dynamic>>[];
    for (var report in allReports) {
      if (report.testResults != null) {
        try {
          final match = report.testResults!.firstWhere(
            (t) => t.name.toLowerCase() == testName.toLowerCase(),
            orElse: () => TestResult(
              name: '',
              loinc: '',
              result: '',
              unit: '',
              reference: '',
              status: '',
            ),
          );

          if (match.name.isNotEmpty) {
            final v = double.tryParse(
              match.result.replaceAll(RegExp(r'[^0-9.]'), ''),
            );
            if (v != null) {
              history.add({'date': report.date.toIso8601String(), 'value': v});
            }
          }
        } catch (_) {}
      }
    }

    final profile = ref.watch(selectedProfileProvider).value;

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        ref
            .read(aiServiceProvider)
            .getSingleTestAnalysis(
              testName: testName,
              value: value,
              unit: unit,
              referenceRange: referenceRange,
              profile: profile,
            ),
        ref
            .read(aiServiceProvider)
            .getTrendAnalysis(testName: testName, history: history),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final analysis = snapshot.data![0] as LabTestAnalysis;
        final trend = snapshot.data![1] as Map<String, dynamic>;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRangeBanner(context, analysis.status),
              const SizedBox(height: 24),
              _buildResultHeader(
                context,
                testName,
                value,
                unit,
                referenceRange,
                selectedReport?.date,
                ref,
              ),
              const SizedBox(height: 24),
              _buildAnalysisSection(context, analysis),
              const SizedBox(height: 24),
              _buildTrendSection(context, trend, history.length),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRangeBanner(BuildContext context, String status) {
    final isNormal = status == 'Normal';
    final isHigh = status == 'High';
    final color = isNormal
        ? AppColors.success
        : (isHigh ? AppColors.danger : Colors.orange);
    final bgColor = isNormal
        ? AppColors.success.withValues(alpha: 0.1)
        : (isHigh
              ? AppColors.danger.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 1.0,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isNormal ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNormal
                    ? 'Within Normal Range'
                    : (isHigh ? 'High - Outside Range' : 'Low - Outside Range'),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                isNormal
                    ? 'This result falls within the typical reference range.'
                    : 'Follow up with your doctor regarding this $status result.',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultHeader(
    BuildContext context,
    String name,
    double value,
    String unit,
    String referenceRange,
    DateTime? date,
    WidgetRef ref,
  ) {
    final dateStr = date != null
        ? DateFormat('MMMM d, yyyy').format(date)
        : 'Unknown Date';
    final selectedTest = ref.read(selectedTestProvider);
    final loinc = selectedTest?.loinc.trim();
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FontAwesomeIcons.bolt,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    loinc != null && loinc.isNotEmpty
                        ? 'LOINC: $loinc'
                        : 'LOINC unavailable',
                    style: TextStyle(color: AppColors.secondary, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              _buildDownloadButton(context, ref),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildValueCard(context, 'Your Result', value.toString(), unit),
              const SizedBox(width: 16),
              _buildValueCard(context, 'Reference Range', referenceRange, ''),
              const SizedBox(width: 16),
              _buildValueCard(context, 'Test Date', dateStr, ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValueCard(
    BuildContext context,
    String label,
    String value,
    String unit,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.secondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisSection(BuildContext context, LabTestAnalysis analysis) {
    return Column(
      children: [
        // Key Insight Highlight
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    FontAwesomeIcons.lightbulb,
                    size: 16,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'KEY INSIGHT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                analysis.keyInsight,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoBlock(
                FontAwesomeIcons.circleQuestion,
                'What This Test Measures',
                analysis.description,
              ),
              _buildInfoBlock(
                FontAwesomeIcons.stethoscope,
                'Clinical Significance',
                analysis.clinicalSignificance,
              ),
              const Divider(height: 32),
              const Text(
                'Potential Causes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: analysis.potentialCauses
                    .map(
                      (cause) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          cause,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 32),
              // Next Step Recommendation
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      FontAwesomeIcons.arrowRight,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RECOMMENDED NEXT STEP',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            analysis.recommendation,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildQuestionsSection(context, analysis.questions),
      ],
    );
  }

  Widget _buildQuestionsSection(BuildContext context, List<String> questions) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Questions to Ask Your Doctor',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ...questions.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'This is educational information, not medical advice. Please discuss your results with your healthcare provider.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock(IconData icon, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.secondary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.secondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSection(
    BuildContext context,
    Map<String, dynamic> trend,
    int count,
  ) {
    final direction = trend['direction'] ?? 'Unknown';
    final change = trend['change_percent'] ?? '--';
    final analysis = trend['analysis'] ?? 'No trend analysis available.';

    IconData icon;
    Color color;

    if (direction == 'Increasing') {
      icon = FontAwesomeIcons.arrowTrendUp;
      color = Colors
          .red; // Assuming higher is bad for many tests, but context matters.
    } else if (direction == 'Decreasing') {
      icon = FontAwesomeIcons.arrowTrendDown;
      color = Colors.orange;
    } else {
      icon = FontAwesomeIcons.minus;
      color = Colors.blue;
    }

    // Simple heuristic: if "Stable" or "Normal", green. Else orange/red.
    if (direction == 'Stable') color = Colors.green;

    return Container(
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
              const Icon(
                FontAwesomeIcons.chartLine,
                size: 16,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 12),
              Text(
                'Trend Analysis ($count results)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (count < 2)
            const Text(
              'Not enough data to show trend analysis.',
              style: TextStyle(color: AppColors.secondary),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.03),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        direction,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      Text(
                        '$change change',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Analysis',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            analysis,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.secondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.download_outlined, size: 16),
      label: const Text('Download Report'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () async {
        final selectedTest = ref.read(selectedTestProvider);
        final selectedReport = ref.read(selectedReportProvider);
        if (selectedTest == null || selectedReport == null) return;

        final profile = ref.read(userProfileProvider).asData?.value;
        final patientName = profile != null
            ? "${profile['first_name']} ${profile['last_name']}"
            : null;

        await PdfService.generateLabReportPdf(selectedReport, [
          selectedTest,
        ], patientName: patientName);
      },
    );
  }
}
