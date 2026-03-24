import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:clear_health/core/ai_service.dart';
import 'package:clear_health/core/cache_service.dart';
import 'package:clear_health/core/vector_service.dart';
import 'package:clear_health/core/services/rate_limiter_service.dart';

// Mocks
class MockCacheService extends Mock implements CacheService {}

class MockVectorService extends Mock implements VectorService {}

class MockRateLimiterService extends Mock implements RateLimiterService {}

void main() {
  late AiService aiService;
  late MockCacheService mockCacheService;
  late MockVectorService mockVectorService;
  late MockRateLimiterService mockRateLimiterService;

  setUp(() {
    mockCacheService = MockCacheService();
    mockVectorService = MockVectorService();
    mockRateLimiterService = MockRateLimiterService();
    registerFallbackValue(const Duration(seconds: 1));

    // Default rate limiter allow
    when(
      () => mockRateLimiterService.checkLimit(
        any(),
        limit: any(named: 'limit'),
        window: any(named: 'window'),
      ),
    ).thenReturn(null);

    // Default cache miss
    when(() => mockCacheService.getAiCache(any())).thenReturn(null);
    when(
      () => mockCacheService.cacheAiResponse(any(), any()),
    ).thenAnswer((_) async {});
  });

  test(
    'getHealthPredictions should call hook on cache miss and cache result',
    () async {
      // Arrange
      final history = [
        {
          'date': '2024-01-01',
          'testResults': [
            {'name': 'A1c', 'value': 6.0, 'unit': '%', 'status': 'Normal'},
          ],
        },
        {
          'date': '2024-02-01',
          'testResults': [
            {'name': 'A1c', 'value': 6.2, 'unit': '%', 'status': 'Normal'},
          ],
        },
      ];

      int apiCallCount = 0;

      // Use the hook
      Future<String> mockGenerator(String prompt) async {
        apiCallCount++;
        return '[{"metric": "A1c", "predicted_value": "6.4"}]';
      }

      aiService = AiService(
        aiApiKey: 'dummy_key',
        vectorService: mockVectorService,
        cacheService: mockCacheService,
        rateLimiter: mockRateLimiterService,
        mockTextGenerator: mockGenerator,
      );

      // Act
      final result = await aiService.getHealthPredictions(history);

      // Assert
      expect(result.isNotEmpty, true);
      expect(result.first['metric'], 'A1c');
      expect(apiCallCount, 1);

      // Verify Cache Set
      verify(() => mockCacheService.cacheAiResponse(any(), any())).called(1);
    },
  );

  test(
    'getHealthPredictions should return cached data and NOT call hook',
    () async {
      // Arrange
      final history = [
        {
          'date': '2024-01-01',
          'testResults': [
            {'name': 'A1c', 'value': 6.0, 'unit': '%', 'status': 'Normal'},
          ],
        },
        {
          'date': '2024-02-01',
          'testResults': [
            {'name': 'A1c', 'value': 6.2, 'unit': '%', 'status': 'Normal'},
          ],
        },
      ];

      final cachedData = [
        {'metric': 'A1c', 'predicted_value': '6.4', 'source': 'cache'},
      ];

      // Simulate Cache Hit
      when(() => mockCacheService.getAiCache(any())).thenReturn(cachedData);

      int apiCallCount = 0;
      Future<String> mockGenerator(String prompt) async {
        apiCallCount++;
        throw Exception('Should not be called');
      }

      aiService = AiService(
        aiApiKey: 'dummy_key',
        vectorService: mockVectorService,
        cacheService: mockCacheService,
        rateLimiter: mockRateLimiterService,
        mockTextGenerator: mockGenerator,
      );

      // Act
      final result = await aiService.getHealthPredictions(history);

      // Assert
      expect(result.first['source'], 'cache');
      expect(apiCallCount, 0);
    },
  );
}
