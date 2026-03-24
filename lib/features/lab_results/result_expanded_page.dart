import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/services/upload_service.dart';
import '../../core/utils/unit_sanitizer.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ocr_review_dialog.dart';

class ResultExpandedPage extends ConsumerStatefulWidget {
  const ResultExpandedPage({super.key});

  @override
  ConsumerState<ResultExpandedPage> createState() => _ResultExpandedPageState();
}

class _ResultExpandedPageState extends ConsumerState<ResultExpandedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logAccess();
    });
  }

  void _logAccess() {
    final report = ref.read(selectedReportProvider);
    if (report != null) {
      ref
          .read(supabaseServiceProvider)
          .logAccess(
            action: 'View Lab Report',
            resourceId: report.id,
            metadata: {
              'lab_name': report.labName,
              'test_count': report.testCount,
            },
          );
    }
  }

  Future<void> _handleUpload(BuildContext context) async {
    try {
      final uploadNotifier = ref.read(uploadControllerProvider.notifier);
      final parsedData = await uploadNotifier.pickAndUpload(context);

      if (parsedData == null || !context.mounted) return;

      final confirmedData = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => OcrReviewDialog(initialData: parsedData),
      );

      if (confirmedData != null && context.mounted) {
        await uploadNotifier.saveResult(confirmedData);
        final postSaveState = ref.read(uploadControllerProvider);
        if (!context.mounted) return;
        if (postSaveState.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(postSaveState.error!),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lab report added successfully!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(selectedReportProvider);
    final citationSource = ref.watch(selectedCitationSourceProvider);
    final selectedTest = ref.watch(selectedTestProvider);

    if (report == null) {
      return const Center(
        child: Text(
          'No lab report selected. Please select one from the results list.',
        ),
      );
    }

    final tests = report.testResults ?? [];

    return GlassCard(
      opacity: 0.02,
      padding: EdgeInsets.zero, // ScrollView handles padding if needed
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, ref, report),
            if (citationSource != null)
              _buildCitationContextBanner(
                context,
                ref,
                citationSource.sourceTag,
              ),
            if (tests.isNotEmpty)
              _buildAiSummary(context, tests, report.date, ref),
            if (tests.isNotEmpty)
              _buildTable(context, tests, ref, selectedTest)
            else
              Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                  child: Column(
                    children: const [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: AppColors.border,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No detailed test data found for this report.',
                        style: TextStyle(color: AppColors.secondary),
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

  Widget _buildHeader(BuildContext context, WidgetRef ref, LabReport report) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(12),
            opacity: 0.1,
            child: const Icon(
              FontAwesomeIcons.fileLines,
              size: 20,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM d, yyyy').format(report.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      FontAwesomeIcons.hospital,
                      size: 12,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lab: ${report.labName}',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${report.testCount} tests',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.primary),
            tooltip: 'Share Report',
            onPressed: () {
              ref.read(navigationProvider.notifier).state =
                  NavItem.shareResults;
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined, color: AppColors.primary),
            tooltip: 'Upload Lab Report',
            onPressed: () => _handleUpload(context),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Report'),
                  content: const Text(
                    'Are you sure you want to delete this lab report? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                try {
                  await ref
                      .read(labRepositoryProvider)
                      .deleteLabResult(
                        report.id,
                        storagePath: report.storagePath,
                      );
                  ref.invalidate(labResultsProvider);
                  ref.invalidate(recentLabResultsProvider);
                  ref.read(navigationProvider.notifier).state =
                      NavItem.labResults;
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report deleted successfully'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error deleting report: $e')),
                    );
                  }
                }
              }
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.secondary),
            onPressed: () => ref.read(navigationProvider.notifier).state =
                NavItem.labResults,
          ),
        ],
      ),
    );
  }

  Widget _buildCitationContextBanner(
    BuildContext context,
    WidgetRef ref,
    String sourceTag,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.link, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Opened from chat citation: $sourceTag',
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(selectedCitationSourceProvider.notifier).state =
                      null,
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSummary(
    BuildContext context,
    List<TestResult> tests,
    DateTime reportDate,
    WidgetRef ref,
  ) {
    final testData = tests
        .map(
          (t) => <String, dynamic>{
            'test_results': [
              {
                'name': t.name,
                'value': t.result,
                'unit': getDisplayUnit({'unit': t.unit}),
                'status': t.status.isNotEmpty ? t.status : 'Normal',
              },
            ],
            'date': reportDate.toIso8601String(),
          },
        )
        .toList();

    return FutureBuilder<String>(
      future: ref.read(aiServiceProvider).getBatchSummary(testData),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? 'Analyzing your results with AI...';
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          tintColor: AppColors.primary, // Subtle tint for AI
          opacity: 0.05,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI Summary',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (isLoading) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              MarkdownBody(
                data: summary,
                softLineBreak: true,
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(context),
                ).copyWith(
                  p: const TextStyle(
                    fontSize: 14,
                    color: AppColors.secondary,
                    height: 1.5,
                  ),
                  strong: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTable(
    BuildContext context,
    List<TestResult> tests,
    WidgetRef ref,
    TestResult? selectedTest,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildTableHeader(),
          const Divider(height: 1),
          ...tests.map(
            (test) => _buildTableRow(context, test, ref, selectedTest),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'TEST',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'RESULT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'REFERENCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'STATUS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    TestResult test,
    WidgetRef ref,
    TestResult? selectedTest,
  ) {
    final bool isAbnormal = test.status != 'Normal';
    final bool isCitationTarget =
        selectedTest != null &&
        selectedTest.name.isNotEmpty &&
        selectedTest.name.toLowerCase() == test.name.toLowerCase();

    return InkWell(
      onTap: () {
        ref.read(selectedTestProvider.notifier).state = test;
        ref.read(navigationProvider.notifier).state = NavItem.resultDetail;
      },
      child: Container(
        decoration: BoxDecoration(
          color: isCitationTarget
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'LOINC: ${test.loinc}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatDisplayValueWithUnit({
                  'value': test.result,
                  'unit': test.unit,
                }),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isAbnormal ? AppColors.danger : AppColors.primary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                test.reference,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.secondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isAbnormal
                      ? AppColors.danger.withValues(alpha: 0.1)
                      : AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAbnormal
                        ? AppColors.danger.withValues(alpha: 0.3)
                        : AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAbnormal
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 12,
                      color: isAbnormal
                          ? AppColors.danger
                          : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      test.status,
                      style: TextStyle(
                        fontSize: 12,
                        color: isAbnormal
                            ? AppColors.danger
                            : const Color(0xFF059669),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: const Text(
                'Details',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
