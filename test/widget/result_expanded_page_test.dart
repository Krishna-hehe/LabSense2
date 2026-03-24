import 'package:clear_health/core/ai_service.dart';
import 'package:clear_health/core/cache_service.dart';
import 'package:clear_health/core/models.dart';
import 'package:clear_health/core/providers.dart';
import 'package:clear_health/core/supabase_service.dart';
import 'package:clear_health/core/services/rate_limiter_service.dart';
import 'package:clear_health/core/vector_service.dart';
import 'package:clear_health/features/lab_results/result_expanded_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCacheService extends Mock implements CacheService {}

class _MockVectorService extends Mock implements VectorService {}

class _MockRateLimiterService extends Mock implements RateLimiterService {}

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  late _MockCacheService mockCache;
  late _MockVectorService mockVector;
  late _MockRateLimiterService mockRateLimiter;
  late _MockSupabaseService mockSupabaseService;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockCache = _MockCacheService();
    mockVector = _MockVectorService();
    mockRateLimiter = _MockRateLimiterService();
    mockSupabaseService = _MockSupabaseService();

    when(
      () => mockRateLimiter.checkLimit(
        any(),
        limit: any(named: 'limit'),
        window: any(named: 'window'),
      ),
    ).thenReturn(null);

    when(() => mockCache.getAiCache(any())).thenReturn(null);
    when(() => mockCache.cacheAiResponse(any(), any())).thenAnswer((_) async {});
    when(
      () => mockSupabaseService.logAccess(
        action: any(named: 'action'),
        resourceId: any(named: 'resourceId'),
        metadata: any(named: 'metadata'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets(
    'ResultExpandedPage AI summary renders markdown with non-placeholder text',
    (tester) async {
      final aiService = AiService(
        aiApiKey: 'dummy_key',
        aiProxyUrl: 'https://example.com/proxy',
        aiProxyAnonKey: 'dummy_anon',
        vectorService: mockVector,
        cacheService: mockCache,
        rateLimiter: mockRateLimiter,
        mockTextGenerator: (_) async =>
            '**Overall Assessment:** Stable profile.\n\n- Keep hydration.',
      );

      final selectedReport = LabReport(
        id: 'r-1',
        date: DateTime(2026, 1, 10),
        labName: 'Lab A',
        testCount: 1,
        abnormalCount: 0,
        status: 'Normal',
        testResults: [
          TestResult(
            name: 'Hemoglobin',
            loinc: '718-7',
            result: '13.6',
            unit: 'g/dL',
            reference: '12-16',
            status: 'Normal',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiServiceProvider.overrideWithValue(aiService),
            supabaseServiceProvider.overrideWith((ref) => mockSupabaseService),
            selectedReportProvider.overrideWith((ref) => selectedReport),
          ],
          child: const MaterialApp(home: Scaffold(body: ResultExpandedPage())),
        ),
      );

      await tester.pumpAndSettle();

      final markdownWidget = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody).first,
      );
      expect(markdownWidget.data, isNotEmpty);
      expect(markdownWidget.data, isNot(contains('Analyzing your results with AI')));
      expect(markdownWidget.data, contains('Overall Assessment'));

      // Ensure summary row uses same object value+unit and unit is not duplicated.
      expect(find.text('13.6 g/dL'), findsOneWidget);
    },
  );
}
