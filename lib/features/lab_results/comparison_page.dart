import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/navigation.dart';
import '../../core/utils/unit_sanitizer.dart';
import '../../widgets/glass_card.dart';

class ComparisonPage extends ConsumerStatefulWidget {
  const ComparisonPage({super.key});

  @override
  ConsumerState<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends ConsumerState<ComparisonPage> {
  @override
  Widget build(BuildContext context) {
    final selectedReports = ref.watch(selectedComparisonReportsProvider);

    if (selectedReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.compare_arrows, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            const Text(
              'No reports selected for comparison',
              style: TextStyle(color: AppColors.secondary, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.read(navigationProvider.notifier).state =
                  NavItem.labResults,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Go to Lab Results'),
            ),
          ],
        ),
      );
    }

    // Sort reports by date
    final sortedReports = List<LabReport>.from(selectedReports)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Get all unique test names across all reports
    final allTestNames = <String>{};
    for (var report in sortedReports) {
      if (report.testResults != null) {
        for (var test in report.testResults!) {
          allTestNames.add(test.name);
        }
      }
    }
    final sortedTestNames = allTestNames.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => ref.read(navigationProvider.notifier).state =
                  NavItem.labResults,
            ),
            const Text(
              'Lab Result Comparison',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${sortedReports.length} Reports Selected',
              style: const TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 800) {
                return _buildMobileList(sortedReports, sortedTestNames);
              }
              return _buildDesktopTable(sortedReports, sortedTestNames);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTable(
    List<LabReport> sortedReports,
    List<String> sortedTestNames,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      opacity: 0.05,
      padding: EdgeInsets.zero, // Table handles spacing
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              isDark ? Colors.grey[900] : const Color(0xFFF9FAFB),
            ),
            columnSpacing: 40,
            columns: [
              const DataColumn(
                label: Text(
                  'Test Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              ...sortedReports.map(
                (report) => DataColumn(
                  label: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.date.toString().split(' ')[0],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        report.labName,
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            rows: sortedTestNames.map((testName) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      testName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  ...sortedReports.map((report) {
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

                    final value = test?.result.isEmpty == true
                        ? '-'
                        : test?.result ?? '-';
                    final unit = getDisplayUnit({
                      'unit': test?.unit ?? '',
                    });
                    final isAbnormal =
                        test?.status.toLowerCase().contains('high') == true ||
                        test?.status.toLowerCase().contains('low') == true;

                    return DataCell(
                      Row(
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontWeight: isAbnormal
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isAbnormal
                                  ? AppColors.danger
                                  : (isDark ? Colors.white : Colors.black),
                            ),
                          ),
                          if (unit.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              unit,
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          // Show trend arrow if not the first column
                          if (sortedReports.indexOf(report) > 0)
                            _buildTrendIndicator(
                              testName,
                              report,
                              sortedReports[sortedReports.indexOf(report) - 1],
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList(
    List<LabReport> sortedReports,
    List<String> sortedTestNames,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: sortedTestNames.length,
      itemBuilder: (context, index) {
        final testName = sortedTestNames[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.zero,
          opacity: 0.05,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF9FAFB),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        testName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: sortedReports.map((report) {
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
                    final hasValue = test?.result.isNotEmpty == true;
                    final value = hasValue ? test!.result : '-';
                    final unit = getDisplayUnit({
                      'unit': test?.unit ?? '',
                    });
                    final isAbnormal =
                        hasValue &&
                        (test?.status.toLowerCase().contains('high') == true ||
                            test?.status.toLowerCase().contains('low') == true);

                    final reportIndex = sortedReports.indexOf(report);
                    final hasPrevious = reportIndex > 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.2)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAbnormal
                              ? AppColors.danger.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('MMM d, yyyy').format(report.date),
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                report.labName,
                                style: TextStyle(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (hasPrevious)
                            _buildTrendIndicator(
                              testName,
                              report,
                              sortedReports[reportIndex - 1],
                            ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                value,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isAbnormal ? AppColors.danger : null,
                                ),
                              ),
                              if (unit.isNotEmpty)
                                Text(
                                  unit,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrendIndicator(
    String testName,
    LabReport current,
    LabReport previous,
  ) {
    final currentTest = current.testResults?.firstWhere(
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
    final prevTest = previous.testResults?.firstWhere(
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

    if (currentTest == null ||
        prevTest == null ||
        currentTest.name.isEmpty ||
        prevTest.name.isEmpty) {
      return const SizedBox.shrink();
    }

    final curVal = double.tryParse(currentTest.result);
    final preVal = double.tryParse(prevTest.result);

    if (curVal == null || preVal == null) return const SizedBox.shrink();

    if (curVal > preVal) {
      return const Padding(
        padding: EdgeInsets.only(left: 8.0),
        child: Icon(Icons.trending_up, color: AppColors.danger, size: 16),
      );
    } else if (curVal < preVal) {
      return const Padding(
        padding: EdgeInsets.only(left: 8.0),
        child: Icon(Icons.trending_down, color: AppColors.success, size: 16),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.only(left: 8.0),
        child: Icon(Icons.trending_flat, color: AppColors.secondary, size: 16),
      );
    }
  }
}
