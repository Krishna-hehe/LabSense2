import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:clear_health/core/repositories/lab_repository.dart';
import 'package:clear_health/core/supabase_service.dart';
import 'package:clear_health/core/cache_service.dart';

import 'package:clear_health/core/services/sync_service.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockCacheService extends Mock implements CacheService {}

class MockSyncService extends Mock implements SyncService {}

void main() {
  late LabRepository labRepository;
  late MockSupabaseService mockSupabaseService;
  late MockCacheService mockCacheService;
  late MockSyncService mockSyncService;

  setUp(() {
    mockSupabaseService = MockSupabaseService();
    mockCacheService = MockCacheService();
    mockSyncService = MockSyncService();

    // Stub setActionHandler and isOnline
    when(() => mockSyncService.setActionHandler(any())).thenReturn(null);
    when(() => mockSyncService.isOnline).thenReturn(true);

    labRepository = LabRepository(
      mockSupabaseService,
      mockCacheService,
      mockSyncService,
    );
  });

  group('LabRepository', () {
    test(
      'getLabResults returns empty list on error and fallback to empty cache',
      () async {
        // Mock Supabase to throw
        when(
          () => mockSupabaseService.getLabResults(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenThrow(Exception('Network Error'));

        // Mock Cache to return empty list
        when(() => mockCacheService.getCachedLabResults()).thenReturn([]);

        final results = await labRepository.getLabResults();

        expect(results, isEmpty);

        // Verify both were called
        verify(
          () => mockSupabaseService.getLabResults(limit: 10, offset: 0),
        ).called(1);
        verify(() => mockCacheService.getCachedLabResults()).called(1);
      },
    );

    test('getLabResults returns cached data on network error', () async {
      final mockCachedJson = [
        {
          'id': '1',
          'date': '2023-01-01',
          'lab_name': 'Cached Lab',
          'status': 'Normal',
          'test_results': [],
        },
      ];

      when(
        () => mockSupabaseService.getLabResults(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenThrow(Exception('Network Error'));

      when(
        () => mockCacheService.getCachedLabResults(),
      ).thenReturn(mockCachedJson);

      final results = await labRepository.getLabResults();

      expect(results, isNotEmpty);
      expect(results.first.labName, 'Cached Lab');

      verify(
        () => mockSupabaseService.getLabResults(limit: 10, offset: 0),
      ).called(1);
      verify(() => mockCacheService.getCachedLabResults()).called(1);
    });

    test('createLabResult delegates to service', () async {
      final data = {'test': 'data'};
      when(
        () => mockSupabaseService.createLabResult(data),
      ).thenAnswer((_) async => 'doc-1');

      await labRepository.createLabResult(data);

      verify(() => mockSupabaseService.createLabResult(data)).called(1);
    });
  });
}
