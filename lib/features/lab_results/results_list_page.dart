import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../widgets/glass_card.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/services/upload_service.dart';
import '../../widgets/ocr_review_dialog.dart';
import '../../core/pdf_service.dart' deferred as pdf_service;

class ResultsListPage extends ConsumerStatefulWidget {
  const ResultsListPage({super.key});

  @override
  ConsumerState<ResultsListPage> createState() => _ResultsListPageState();
}

class _ResultsListPageState extends ConsumerState<ResultsListPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(labResultsProvider.notifier).fetchNextPage();
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(labResultsProvider.notifier).search(query);
    });
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
    final labResultsAsync = ref.watch(labResultsProvider);
    final isComparisonMode = ref.watch(isComparisonModeProvider);
    final selectedReportsForComparison = ref.watch(
      selectedComparisonReportsProvider,
    );
    final searchQuery = _searchController.text;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverToBoxAdapter(
            child: _buildHeader(
              context,
              ref,
              isComparisonMode,
              selectedReportsForComparison,
            ),
          ),
        ),
        labResultsAsync.when(
          data: (data) {
            if (data.isEmpty) {
              return SliverToBoxAdapter(
                child: searchQuery.isEmpty
                    ? _buildEmptyState(context)
                    : _buildNoSearchResults(context),
              );
            }

            final notifier = ref.watch(labResultsProvider.notifier);

            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _buildPdfDownloadCard(context, ref, data),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == data.length) {
                      return _buildLoader(notifier);
                    }
                    final result = data[index];
                    return _buildResultCard(
                      context,
                      ref,
                      result,
                      isComparisonMode,
                      selectedReportsForComparison,
                    );
                  }, childCount: data.length + (notifier.hasMore ? 1 : 0)),
                ),
              ],
            );
          },
          error: (err, stack) =>
              SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
          loading: () => const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 64,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No lab results found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload your first lab report to get started.',
            style: TextStyle(color: AppColors.secondary),
          ),
          const SizedBox(height: 24),
           ElevatedButton(
            onPressed: () => _handleUpload(context),
            child: const Text('Upload Lab Report'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 64),
          const Icon(Icons.search_off, size: 64, color: AppColors.secondary),
          const SizedBox(height: 16),
          const Text(
            'No matches found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your search criteria.',
            style: TextStyle(color: AppColors.secondary),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              _searchController.clear();
              _onSearchChanged('');
            },
            child: const Text('Clear Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader(LabResultsNotifier notifier) {
    if (!notifier.hasMore) return const SizedBox.shrink();
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isComparisonMode,
    List<LabReport> selectedReports,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Lab History',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                if (isComparisonMode) ...[
                  Text(
                    '${selectedReports.length} selected',
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: selectedReports.length >= 2
                        ? () => ref.read(navigationProvider.notifier).state =
                              NavItem.comparison
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Compare Now'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ref.read(isComparisonModeProvider.notifier).state = false;
                      ref
                              .read(selectedComparisonReportsProvider.notifier)
                              .state =
                          [];
                    },
                    child: const Text('Cancel'),
                  ),
                ] else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.upload_file_outlined, size: 16),
                        label: const Text('Upload Lab Report'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _handleUpload(context),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.compare_arrows, size: 16),
                        label: const Text('Compare Results'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () =>
                            ref.read(isComparisonModeProvider.notifier).state =
                                true,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search by test name, lab, or date...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(width: 0, style: BorderStyle.none),
            ),
            filled: true,
            fillColor: Theme.of(context).dividerColor.withAlpha(25),
          ),
        ),
      ],
    );
  }

  Widget _buildPdfDownloadCard(
    BuildContext context,
    WidgetRef ref,
    List<LabReport> results,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      tintColor: AppColors.primary,
      opacity: 0.05,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Includes known conditions, lab tests, and AI summaries.',
                  style: TextStyle(color: AppColors.secondary, fontSize: 13),
                ),
                InkWell(
                  onTap: () {
                    ref.read(navigationProvider.notifier).state =
                        NavItem.conditions;
                  },
                  child: Text(
                    'Manage conditions.',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          _buildDateField(
            context,
            'From',
            results.isNotEmpty
                ? DateFormat('dd-MM-yyyy').format(results.last.date)
                : 'Start',
          ),
          const SizedBox(width: 12),
          _buildDateField(
            context,
            'To',
            results.isNotEmpty
                ? DateFormat('dd-MM-yyyy').format(results.first.date)
                : 'End',
          ),
          const SizedBox(width: 24),
          ElevatedButton.icon(
            icon: const Icon(FontAwesomeIcons.download, size: 14),
            label: const Text('Download PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final profile = ref.read(userProfileProvider).asData?.value;
              final patientName = profile != null
                  ? "${profile['first_name']} ${profile['last_name']}"
                  : null;

              final aiSummaryAsync = ref.read(healthHistoryAiSummaryProvider);
              final aiSummary = aiSummaryAsync.asData?.value;

              await pdf_service.loadLibrary();
              await pdf_service.PdfService.generateSummaryPdf(
                results,
                patientName: patientName,
                aiSummary: aiSummary,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(BuildContext context, String label, String date) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.secondary),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(date, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              const Icon(
                Icons.calendar_today,
                size: 14,
                color: AppColors.secondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    WidgetRef ref,
    LabReport result,
    bool isComparisonMode,
    List<LabReport> selectedReports,
  ) {
    final status = result.status;
    final isAbnormal = status == 'Abnormal';
    final isSelected = selectedReports.any((r) => r.id == result.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () {
          if (isComparisonMode) {
            final newList = List<LabReport>.from(selectedReports);
            if (isSelected) {
              newList.removeWhere((r) => r.id == result.id);
            } else {
              if (newList.length < 3) {
                newList.add(result);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Select up to 3 reports for comparison'),
                  ),
                );
              }
            }
            ref.read(selectedComparisonReportsProvider.notifier).state =
                newList;
          } else {
            ref.read(selectedReportProvider.notifier).state = result;
            ref.read(navigationProvider.notifier).state =
                NavItem.resultExpanded;
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          tintColor: isSelected ? AppColors.primary : null,
          opacity: isSelected ? 0.1 : 0.05, // Subtle highlight if selected
          child: Row(
            children: [
              if (isComparisonMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    final newList = List<LabReport>.from(selectedReports);
                    if (val == true) {
                      if (newList.length < 3) newList.add(result);
                    } else {
                      newList.removeWhere((r) => r.id == result.id);
                    }
                    ref.read(selectedComparisonReportsProvider.notifier).state =
                        newList;
                  },
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppColors.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lab Result - ${result.date.toString().split(' ')[0]}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.testCount} lab results found',
                      style: TextStyle(
                        color: result.abnormalCount > 0
                            ? AppColors.danger
                            : AppColors.secondary,
                        fontSize: 13,
                        fontWeight: result.abnormalCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (result.abnormalCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${result.abnormalCount} Abnormal Result${result.abnormalCount > 1 ? "s" : ""}',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isAbnormal
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    if (status == 'Pending Sync') ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Syncing...',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        isAbnormal
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 14,
                        color: isAbnormal
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(
                          color: isAbnormal
                              ? AppColors.danger
                              : AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isComparisonMode) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.secondary,
                    size: 20,
                  ),
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
                              result.id,
                              storagePath: result.storagePath,
                            );
                        ref.invalidate(labResultsProvider);
                        ref.invalidate(recentLabResultsProvider);
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
                            SnackBar(
                              content: Text('Error deleting report: $e'),
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.picture_as_pdf,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                  onPressed: () async {
                    if (result.testResults != null) {
                      final profile = ref
                          .read(userProfileProvider)
                          .asData
                          ?.value;
                      final patientName = profile != null
                          ? "${profile['first_name']} ${profile['last_name']}"
                          : null;

                      await pdf_service.loadLibrary();
                      await pdf_service.PdfService.generateLabReportPdf(
                        result,
                        result.testResults!,
                        patientName: patientName,
                      );
                    }
                  },
                ),
                const Icon(Icons.chevron_right, color: AppColors.border),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
