import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/lab_repository.dart';
import 'core_providers.dart';
import '../cache_service.dart';
import '../models.dart';
import '../services/trend_analysis_service.dart';

import 'user_providers.dart';

final trendAnalysisServiceProvider = Provider<TrendAnalysisService>((ref) {
  return TrendAnalysisService();
});

final labRepositoryProvider = Provider<LabRepository>((ref) {
  return LabRepository(
    ref.watch(supabaseServiceProvider),
    CacheService(),
    ref.watch(syncServiceProvider),
    ref.watch(storageServiceProvider),
    ref.watch(auditServiceProvider),
    ref.watch(vectorServiceProvider),
  );
});

final labResultsProvider =
    AsyncNotifierProvider<LabResultsNotifier, List<LabReport>>(
      LabResultsNotifier.new,
    );

class LabResultsNotifier extends AsyncNotifier<List<LabReport>> {
  int _currentPage = 0;
  static const int _pageSize = 10;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String? _searchQuery;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<LabReport>> build() async {
    _currentPage = 0;
    _hasMore = true;
    final profileId = ref.watch(selectedProfileIdProvider);
    final repository = ref.watch(labRepositoryProvider);
    return repository.getLabResults(
      limit: _pageSize,
      offset: 0,
      profileId: profileId,
      searchQuery: _searchQuery,
    );
  }

  Future<void> fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    state = AsyncValue.data(
      state.value ?? [],
    ); // Trigger rebuild to show loading at bottom if needed

    try {
      final repository = ref.read(labRepositoryProvider);
      final profileId = ref.read(selectedProfileIdProvider);
      final nextPage = _currentPage + 1;
      final results = await repository.getLabResults(
        limit: _pageSize,
        offset: nextPage * _pageSize,
        profileId: profileId,
        searchQuery: _searchQuery,
      );

      if (results.isEmpty || results.length < _pageSize) {
        _hasMore = false;
      }

      _currentPage = nextPage;
      state = AsyncValue.data([...state.value ?? [], ...results]);
    } catch (e) {
      debugPrint('Error fetching next page: $e');
      // We don't change state to error to keep existing results visible
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> search(String query) async {
    _searchQuery = query;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _currentPage = 0;
      _hasMore = true;
      final profileId = ref.read(selectedProfileIdProvider);
      return ref
          .read(labRepositoryProvider)
          .getLabResults(
            limit: _pageSize,
            offset: 0,
            profileId: profileId,
            searchQuery: _searchQuery,
          );
    });
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _currentPage = 0;
      _hasMore = true;
      final profileId = ref.read(selectedProfileIdProvider);
      return ref
          .read(labRepositoryProvider)
          .getLabResults(
            limit: _pageSize,
            offset: 0,
            profileId: profileId,
            searchQuery: _searchQuery,
          );
    });
  }
}

final recentLabResultsProvider = FutureProvider<List<LabReport>>((ref) async {
  final repository = ref.watch(labRepositoryProvider);
  final profileId = ref.watch(selectedProfileIdProvider);
  return repository.getLabResults(limit: 3, profileId: profileId);
});

final optimizationTipsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final results = await ref.watch(labResultsProvider.future);
  if (results.isEmpty) return [];

  final latest = results.first;
  final abnormalTests =
      latest.testResults?.where((t) {
        final status = t.status.toLowerCase();
        return status.contains('high') || status.contains('low');
      }).toList() ??
      [];

  final aiService = ref.watch(aiServiceProvider);

  if (abnormalTests.isNotEmpty) {
    return aiService.getOptimizationTips(
      abnormalTests.map((t) => t.toJson()).toList(),
    );
  } else {
    // Healthy user! Get wellness/maintenance tips
    final normalTests =
        latest.testResults?.where((t) {
          final status = t.status.toLowerCase();
          return status.contains('normal');
        }).toList() ??
        [];

    return aiService.getWellnessTips(
      normalTests.map((t) => t.toJson()).toList(),
    );
  }
});
final dashboardAiInsightProvider = FutureProvider<String>((ref) async {
  final recentResults = await ref.watch(recentLabResultsProvider.future);
  if (recentResults.isEmpty) {
    return 'No recent lab results found. Upload a report to get AI insights.';
  }

  final aiService = ref.watch(aiServiceProvider);
  final profile = ref.watch(selectedProfileProvider).value;
  return aiService.getBatchSummary(
    recentResults.map((r) => r.toJson()).toList(),
    profile: profile,
  );
});
final healthHistoryAiSummaryProvider = FutureProvider<String>((ref) async {
  final reports = await ref.watch(recentLabResultsProvider.future);
  if (reports.isEmpty) return 'No recent lab reports found for analysis.';

  final aiService = ref.read(aiServiceProvider);
  final profile = ref.watch(selectedProfileProvider).value;
  return aiService.getBatchSummary(
    reports.map((r) => r.toJson()).toList(),
    profile: profile,
  );
});

final distinctTestsProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(labRepositoryProvider);
  return repository.getDistinctTests();
});

final trendDataProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      testName,
    ) async {
      final repository = ref.watch(labRepositoryProvider);
      return repository.getTrendData(testName);
    });

final healthPredictionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final results = await ref.watch(labResultsProvider.future);
  if (results.isEmpty) return [];

  final aiService = ref.watch(aiServiceProvider);
  // Pass raw JSON data to AI service
  final history = results.map((r) => r.toJson()).toList();
  return aiService.getHealthPredictions(history);
});
