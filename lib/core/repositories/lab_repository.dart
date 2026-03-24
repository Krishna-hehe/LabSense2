import '../supabase_service.dart';
import '../services/sync_service.dart';
import '../models.dart';
import '../cache_service.dart';
import '../storage_service.dart';
import '../vector_service.dart';
import '../services/log_service.dart';
import '../services/audit_service.dart';
import '../utils/unit_sanitizer.dart';

class LabRepository {
  final SupabaseService _supabaseService;
  final CacheService _cacheService;
  final SyncService _syncService;
  final StorageService? _storageService;
  final AuditService? _auditService;
  final VectorService? _vectorService;

  LabRepository(
    this._supabaseService,
    this._cacheService,
    this._syncService, [
    this._storageService,
    this._auditService,
    this._vectorService,
  ]) {
    _syncService.setActionHandler(_handleSyncAction);
  }

  Future<List<LabReport>> getLabResults({
    int limit = 10,
    int offset = 0,
    String? profileId,
    String? searchQuery,
  }) async {
    try {
      final data = await _supabaseService.getLabResults(
        limit: limit,
        offset: offset,
        profileId: profileId,
        searchQuery: searchQuery,
      );
      if (offset == 0) {
        await _cacheService.cacheLabResults(data);
        _auditService?.log(
          AuditAction.viewLabResult,
          details: 'Fetched lab results list',
        );
      }
      return data.map((json) => LabReport.fromJson(json)).toList();
    } catch (e) {
      AppLogger.warning('Supabase fetch failed, falling back to cache: $e');
      if (offset == 0) {
        final cachedData = _cacheService.getCachedLabResults();
        return cachedData.map((json) => LabReport.fromJson(json)).toList();
      }
      return []; // Pagination fallback
    }
  }

  Future<String?> createLabResult(Map<String, dynamic> data) async {
    if (_syncService.isOnline) {
      return await _supabaseService.createLabResult(data);
    } else {
      AppLogger.debug('offline: queuing createLabResult');
      await _syncService.addToQueue('createLabResult', data);

      // Optimistic update - add to cache immediately
      // Note: We need a temporary ID for the UI
      // Optimistic update - add to cache immediately
      // Note: We need a temporary ID for the UI
      // For now we just queue. Full optimistic UI requires cache list manipulation which happens on fetch.
      return null;
    }
  }

  Future<void> deleteLabResult(String id, {String? storagePath}) async {
    // 1. Delete from DB first (if RLS fails, we shouldn't delete storage)
    await _supabaseService.deleteLabResult(id);

    // 2. Delete from Storage if path provided
    if (storagePath != null) {
      await _storageService?.deleteLabReportFile(storagePath);
    }
  }

  Future<List<Map<String, dynamic>>> getTrendData(String testName) async {
    try {
      return await _supabaseService.getTrendData(testName);
    } catch (e) {
      AppLogger.warning('Error fetching trend data: $e');
      return [];
    }
  }

  Future<Map<String, List<LabReport>>> getMultiMarkerHistory(
    List<String> markers,
  ) async {
    final Map<String, List<LabReport>> result = {};
    for (final marker in markers) {
      final trendData = await getTrendData(marker);
      // Map trend data points back to LabReport objects for the service to process
      result[marker] = trendData.map((d) {
        return LabReport(
          id: d['id'] ?? '',
          labName: d['lab_name'] ?? 'Unknown',
          date: DateTime.parse(d['date']),
          testCount: 1,
          status: d['status'] ?? 'Normal',
          testResults: [
            TestResult(
              name: marker,
              result: d['result'] ?? '',
              unit: UnitSanitizer.clean(d['unit']?.toString()) ?? '',
              status: d['status'] ?? 'Normal',
              loinc: '',
              reference: '',
            ),
          ],
        );
      }).toList();
    }
    return result;
  }

  Future<bool> _handleSyncAction(
    String action,
    Map<String, dynamic> data,
  ) async {
    try {
      switch (action) {
        case 'createLabResult':
          final docId = await _supabaseService.createLabResult(data);
          if (docId == null || docId.isEmpty) {
            AppLogger.warning(
              'Queued createLabResult could not persist (missing user/session).',
            );
            return false;
          }

          final vectorService = _vectorService;
          if (vectorService != null) {
            if (!vectorService.isConfigured) {
              AppLogger.warning(
                'VECTOR_API_KEY missing during sync; deferring indexing job.',
              );
              await _syncService.addToQueue('indexLabEmbeddings', {
                'doc_id': docId,
                'payload': data,
              });
              return true;
            }

            try {
              await vectorService.ingestLabReportFromParsedData(
                data,
                docId: docId,
              );
            } catch (e) {
              AppLogger.error(
                'Queued indexing after sync create failed, scheduling retry: $e',
              );
              await _syncService.addToQueue('indexLabEmbeddings', {
                'doc_id': docId,
                'payload': data,
              });
            }
          }
          return true;
        case 'indexLabEmbeddings':
          final payload = data['payload'];
          final docId = data['doc_id']?.toString();
          final vectorService = _vectorService;
          if (vectorService == null ||
              payload is! Map ||
              docId == null ||
              docId.isEmpty) {
            return false;
          }
          if (!vectorService.isConfigured) {
            AppLogger.warning(
              'VECTOR_API_KEY missing; keeping index job queued for retry.',
            );
            return false;
          }
          await vectorService.ingestLabReportFromParsedData(
            Map<String, dynamic>.from(payload),
            docId: docId,
          );
          return true;
        default:
          AppLogger.warning('Unknown sync action blocked: $action');
          return false;
      }
    } catch (e) {
      AppLogger.error('Sync action failed: $e');
      return false;
    }
  }

  Future<List<String>> getDistinctTests() async {
    return await _supabaseService.getDistinctTests();
  }
}
