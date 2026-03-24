import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';

import '../providers/core_providers.dart';
import '../providers/lab_providers.dart';
import '../providers/user_providers.dart';
import 'audit_service.dart';
import 'log_service.dart';

enum UploadPhase {
  idle,
  uploading,
  parsing,
  extracting,
  saving,
  embedding,
  done,
  error,
}

class UploadState {
  final bool isUploading;
  final String? error;
  final String? status;
  final UploadPhase phase;
  final double progress;

  UploadState({
    this.isUploading = false,
    this.error,
    this.status,
    this.phase = UploadPhase.idle,
    this.progress = 0,
  });

  UploadState copyWith({
    bool? isUploading,
    String? error,
    String? status,
    UploadPhase? phase,
    double? progress,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      error: error,
      status: status ?? this.status,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
    );
  }
}

class UploadController extends StateNotifier<UploadState> {
  final Ref _ref;

  UploadController(this._ref) : super(UploadState());

  Future<Map<String, dynamic>?> pickAndUpload(dynamic context) async {
    try {
      state = state.copyWith(
        isUploading: true,
        status: 'Picking file...',
        phase: UploadPhase.uploading,
        progress: 5,
      );

      final result = await fp.FilePicker.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        state = UploadState();
        return null;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file bytes');

      final fileName = file.name;
      final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';
      await _ref
          .read(auditServiceProvider)
          .log(
            AuditAction.uploadLabResult,
            details: 'Upload started for $fileName',
          );

      state = state.copyWith(
        status: 'Uploading report to secure ingestion queue...',
        phase: UploadPhase.uploading,
        progress: 20,
      );
      final ingestionResult = await _ref
          .read(edgeIngestionServiceProvider)
          .ingestAndWait(
            fileBytes: bytes,
            fileName: fileName,
            mimeType: mimeType,
            onProgress: (job) {
              final stage = (job['stage'] ?? '').toString().toLowerCase();
              final message =
                  (job['message'] ?? '').toString().trim().isNotEmpty
                  ? job['message'].toString()
                  : _defaultMessageForStage(stage);
              final progress =
                  (job['progress'] as num?)?.toDouble() ?? state.progress;

              state = state.copyWith(
                isUploading: true,
                status: message,
                phase: _phaseForIngestionStage(stage),
                progress: progress.clamp(0, 100).toDouble(),
              );
            },
          );

      final rawParsedData = ingestionResult['parsedData'];
      if (rawParsedData is! Map) {
        throw Exception('Ingestion completed without parsed data.');
      }
      final parsedData = Map<String, dynamic>.from(rawParsedData);
      final storagePath =
          (ingestionResult['storagePath'] ?? parsedData['storage_path'])
              ?.toString();
      if (storagePath == null || storagePath.isEmpty) {
        throw Exception('Ingestion completed without storage path.');
      }

      if (parsedData['test_results'] is! List) {
        throw Exception(
          'Ingestion parser returned invalid test_results payload.',
        );
      }

      state = state.copyWith(
        isUploading: false,
        status: 'Review extracted results before saving.',
        phase: UploadPhase.done,
        progress: 100,
      );

      return {
        ...parsedData,
        'storage_path': storagePath,
        'ingestion_job_id': ingestionResult['jobId'],
      };
    } catch (e) {
      await _ref
          .read(auditServiceProvider)
          .log(
            AuditAction.ingestionFailed,
            details: 'Upload parsing failed: $e',
          );
      state = state.copyWith(
        isUploading: false,
        error: e.toString(),
        status: 'Upload failed',
        phase: UploadPhase.error,
        progress: 0,
      );
      rethrow;
    }
  }

  UploadPhase _phaseForIngestionStage(String stage) {
    switch (stage) {
      case 'queued':
      case 'uploading':
        return UploadPhase.uploading;
      case 'processing':
      case 'parsing':
        return UploadPhase.parsing;
      case 'extracting':
        return UploadPhase.extracting;
      case 'indexing':
        return UploadPhase.embedding;
      case 'done':
        return UploadPhase.done;
      default:
        return state.phase;
    }
  }

  String _defaultMessageForStage(String stage) {
    switch (stage) {
      case 'queued':
      case 'uploading':
        return 'Uploading report...';
      case 'processing':
      case 'parsing':
        return 'Parsing report structure...';
      case 'extracting':
        return 'Extracting lab metrics...';
      case 'indexing':
        return 'Preparing semantic context...';
      case 'done':
        return 'Ingestion completed.';
      default:
        return 'Processing report...';
    }
  }

  Future<void> saveResult(Map<String, dynamic> finalData) async {
    try {
      final selectedProfile = _ref.read(selectedProfileProvider).value;
      final dataToSave = Map<String, dynamic>.from(finalData);
      dataToSave['profile_id'] =
          selectedProfile?.id ??
          _ref.read(supabaseServiceProvider).client.auth.currentUser?.id;

      state = state.copyWith(
        isUploading: true,
        status: 'Saving structured metrics...',
        phase: UploadPhase.saving,
        progress: 70,
      );

      final docId = await _ref
          .read(labRepositoryProvider)
          .createLabResult(dataToSave);

      String? indexingWarning;
      if (docId == null || docId.isEmpty) {
        final isOnline = _ref.read(syncServiceProvider).isOnline;
        if (isOnline) {
          throw Exception(
            'Failed to save report. Please verify your session and try again.',
          );
        }

        final vectorConfigured = _ref.read(vectorServiceProvider).isConfigured;
        indexingWarning = vectorConfigured
            ? 'Report queued offline. Semantic indexing will complete after online sync.'
            : 'Report queued offline, but VECTOR_API_KEY is missing. Semantic search is disabled until configured.';
        AppLogger.warning(indexingWarning);
      } else {
        final vectorService = _ref.read(vectorServiceProvider);
        if (!vectorService.isConfigured) {
          indexingWarning =
              'Report saved, but VECTOR_API_KEY is missing. Semantic search is disabled until configured.';
          AppLogger.warning(indexingWarning);
        }

        state = state.copyWith(
          isUploading: true,
          status: 'Embedding chunks for semantic search...',
          phase: UploadPhase.embedding,
          progress: 90,
        );

        try {
          final embeddingPayload = Map<String, dynamic>.from(finalData)
            ..remove('source_markdown');
          embeddingPayload['profile_id'] = dataToSave['profile_id'];
          await vectorService.ingestLabReportFromParsedData(
            embeddingPayload,
            docId: docId,
          );
        } catch (e) {
          indexingWarning =
              'Report saved, but semantic indexing failed. Chat context may be limited until reindex.';
          AppLogger.error('Vector indexing failed after report save: $e');
        }
      }

      _ref.invalidate(labResultsProvider);
      _ref.invalidate(recentLabResultsProvider);
      _ref.invalidate(dashboardAiInsightProvider);
      _ref.invalidate(optimizationTipsProvider);

      state = UploadState(
        isUploading: false,
        status: indexingWarning ?? 'Lab report processed successfully.',
        error: indexingWarning,
        phase: UploadPhase.done,
        progress: 100,
      );
      await _ref
          .read(auditServiceProvider)
          .log(
            AuditAction.ingestionQueued,
            details: indexingWarning ?? 'Report persisted and indexed.',
          );
    } catch (e) {
      await _ref
          .read(auditServiceProvider)
          .log(
            AuditAction.ingestionFailed,
            details: 'Save/index pipeline failed: $e',
          );
      state = state.copyWith(
        isUploading: false,
        error: e.toString(),
        status: 'Save failed',
        phase: UploadPhase.error,
        progress: 0,
      );
      rethrow;
    }
  }

  void reset() {
    state = UploadState();
  }
}

final uploadControllerProvider =
    StateNotifierProvider<UploadController, UploadState>((ref) {
      return UploadController(ref);
    });
