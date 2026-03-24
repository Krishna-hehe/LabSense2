import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'services/chunker.dart';
import 'services/log_service.dart';
import 'services/nvidia_service.dart';
import 'utils/unit_sanitizer.dart';

class VectorService {
  final SupabaseClient _client;
  final NvidiaService _nvidiaService;

  VectorService(
    this._client, {
    required String apiKey,
    String vectorBaseUrl = 'https://integrate.api.nvidia.com/v1',
    NvidiaService? nvidiaService,
  }) : _nvidiaService =
           nvidiaService ??
           NvidiaService(apiKey: apiKey, baseUrl: vectorBaseUrl);

  bool get isConfigured => _nvidiaService.isConfigured;

  /// Backward-compatible helper retained for existing callers.
  Future<List<double>> generateEmbedding(String text) async {
    if (kIsWeb) {
      return [];
    }
    if (!_nvidiaService.isConfigured) {
      AppLogger.warning(
        'VECTOR_API_KEY missing. Skipping embedding generation.',
      );
      return [];
    }
    return _nvidiaService.embedQuery(text);
  }

  Future<List<double>> embedPassage(String text) async {
    if (kIsWeb) {
      return [];
    }
    return _nvidiaService.embedPassage(text);
  }

  Future<List<double>> embedQuery(String text) async {
    if (kIsWeb) {
      return [];
    }
    return _nvidiaService.embedQuery(text);
  }

  /// Legacy single-item ingestion, kept for compatibility with scripts/tests.
  Future<void> ingestLabResult(TestResult result, String date) async {
    if (kIsWeb) {
      AppLogger.info(
        'Web mode: skipping direct NVIDIA embedding ingestion due to browser CORS limits.',
      );
      return;
    }
    if (!_nvidiaService.isConfigured) {
      AppLogger.warning(
        'VECTOR_API_KEY missing. Skipping vector ingestion for legacy entry.',
      );
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) return;

    final content =
        '''
Test: ${result.name}
Result: ${formatDisplayValueWithUnit({
          'value': result.result,
          'unit': result.unit,
        })}
Reference Range: ${result.reference}
Status: ${result.status}
Date: $date
''';

    final embedding = await embedPassage(content);

    await _client.from('test_embeddings').insert({
      'user_id': user.id,
      'test_name': result.name,
      'content': content,
      'metadata': {
        'date': date,
        'status': result.status,
        'loinc': result.loinc,
        'chunk_index': 0,
      },
      'chunk_index': 0,
      'embedding': embedding,
    });
  }

  /// Chunk-level ingestion for full report markdown.
  Future<void> ingestLabReportFromParsedData(
    Map<String, dynamic> parsedData, {
    String? docId,
  }) async {
    if (kIsWeb) {
      AppLogger.info(
        'Web mode: skipping direct NVIDIA report indexing due to browser CORS limits.',
      );
      return;
    }
    if (!_nvidiaService.isConfigured) {
      AppLogger.warning(
        'VECTOR_API_KEY missing. Report saved without semantic indexing.',
      );
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) return;

    final markdown = _resolveMarkdown(parsedData);
    final chunks = chunkMarkdown(markdown);

    if (chunks.isEmpty) {
      AppLogger.warning('No chunks generated for report embedding.');
      return;
    }

    final metadataTemplate = <String, dynamic>{
      'date': parsedData['date'],
      'status': parsedData['status'] ?? _deriveOverallStatus(parsedData),
      'lab_name': parsedData['lab_name'],
      if (docId != null && docId.isNotEmpty) 'doc_id': docId,
    };

    final testName =
        (parsedData['lab_name']?.toString().trim().isNotEmpty ?? false)
        ? parsedData['lab_name'].toString()
        : 'Lab Report Chunk';

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final vector = await embedPassage(chunk);
      await _client.from('test_embeddings').insert({
        'user_id': user.id,
        'test_name': testName,
        'content': chunk,
        'metadata': {...metadataTemplate, 'chunk_index': i},
        'chunk_index': i,
        'embedding': vector,
      });
    }
  }

  /// Retrieves candidates from pgvector and reranks before returning top chunks.
  Future<List<Map<String, dynamic>>> searchSimilarChunks(
    String query, {
    int limit = 4,
    int candidateLimit = 20,
    double minSimilarity = 0.5,
    Map<String, String>? metadataFilters,
  }) async {
    if (kIsWeb) {
      AppLogger.info(
        'Web mode: skipping direct NVIDIA vector retrieval due to browser CORS limits.',
      );
      return [];
    }
    if (!_nvidiaService.isConfigured) {
      AppLogger.warning(
        'VECTOR_API_KEY missing. Returning no vector context for chat.',
      );
      return [];
    }

    final queryEmbedding = await embedQuery(query);
    dynamic response;
    try {
      response = await _client.rpc(
        'match_test_embeddings',
        params: {
          'query_embedding': queryEmbedding,
          'match_threshold': minSimilarity,
          'match_count': candidateLimit,
        },
      );
    } catch (e) {
      AppLogger.warning(
        'Vector RPC failed (likely pre-migration schema or function mismatch): $e',
      );
      return [];
    }

    var candidates = List<Map<String, dynamic>>.from(response as List);
    if (candidates.isEmpty) {
      return [];
    }

    if (metadataFilters != null && metadataFilters.isNotEmpty) {
      candidates = candidates
          .where((candidate) {
            final rawMetadata = candidate['metadata'];
            if (rawMetadata is! Map) return false;
            final metadata = Map<String, dynamic>.from(rawMetadata);

            for (final entry in metadataFilters.entries) {
              final value = metadata[entry.key]?.toString().toLowerCase() ?? '';
              if (value != entry.value.toLowerCase()) {
                return false;
              }
            }
            return true;
          })
          .toList(growable: false);
      if (candidates.isEmpty) return [];
    }

    final candidateTexts = candidates
        .map((chunk) => chunk['content']?.toString() ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList(growable: false);

    if (candidateTexts.isEmpty) {
      return [];
    }

    List<String> rerankedTexts;
    try {
      rerankedTexts = await _nvidiaService.rerank(
        query,
        candidateTexts,
        topN: limit,
      );
    } catch (e) {
      AppLogger.warning(
        'Reranker failed; falling back to pgvector ordering. Error: $e',
      );
      return _annotateCandidates(
        candidates.take(limit).toList(growable: false),
      );
    }

    final bucketed = <String, Queue<Map<String, dynamic>>>{};
    for (final candidate in candidates) {
      final content = candidate['content']?.toString() ?? '';
      if (content.isEmpty) continue;
      bucketed
          .putIfAbsent(content, () => Queue<Map<String, dynamic>>())
          .add(candidate);
    }

    final rerankedRows = <Map<String, dynamic>>[];
    for (final text in rerankedTexts) {
      final queue = bucketed[text];
      if (queue == null || queue.isEmpty) continue;
      rerankedRows.add(queue.removeFirst());
    }

    if (rerankedRows.isEmpty) {
      return _annotateCandidates(
        candidates.take(limit).toList(growable: false),
      );
    }

    return _annotateCandidates(rerankedRows);
  }

  String _resolveMarkdown(Map<String, dynamic> parsedData) {
    final sourceMarkdown = parsedData['source_markdown']?.toString();
    if (sourceMarkdown != null && sourceMarkdown.trim().isNotEmpty) {
      return sourceMarkdown;
    }

    final buffer = StringBuffer();
    final labName = parsedData['lab_name']?.toString() ?? 'Lab Report';
    final date = parsedData['date']?.toString();
    buffer.writeln('# $labName');
    if (date != null && date.trim().isNotEmpty) {
      buffer.writeln('Date: $date');
    }
    buffer.writeln();
    buffer.writeln('| Test | Result | Unit | Reference Range | Status |');
    buffer.writeln('| --- | --- | --- | --- | --- |');

    final results = parsedData['test_results'];
    if (results is List) {
      for (final entry in results) {
        if (entry is! Map) continue;
        final row = Map<String, dynamic>.from(entry);
        final testName = row['name'] ?? row['test_name'] ?? '';
        final result = row['result'] ?? row['result_value'] ?? '';
        final unit = getDisplayUnit(row);
        final reference = row['reference'] ?? row['reference_range'] ?? '';
        final status = row['status'] ?? '';

        buffer.writeln(
          '| ${_escapeCell(testName)} | ${_escapeCell(result)} | '
          '${_escapeCell(unit)} | ${_escapeCell(reference)} | '
          '${_escapeCell(status)} |',
        );
      }
    }

    return buffer.toString();
  }

  String _deriveOverallStatus(Map<String, dynamic> parsedData) {
    final results = parsedData['test_results'];
    if (results is! List) return 'Normal';

    for (final item in results) {
      if (item is! Map) continue;
      final status = (item['status']?.toString().toLowerCase() ?? '').trim();
      if (status == 'high' || status == 'low' || status == 'abnormal') {
        return 'Abnormal';
      }
    }
    return 'Normal';
  }

  String _escapeCell(dynamic value) {
    return (value?.toString() ?? '')
        .replaceAll('|', r'\|')
        .replaceAll('\n', ' ')
        .trim();
  }

  List<Map<String, dynamic>> _annotateCandidates(
    List<Map<String, dynamic>> rows,
  ) {
    final annotated = <Map<String, dynamic>>[];
    final seenContent = <String>{};

    for (final row in rows) {
      final content = row['content']?.toString().trim() ?? '';
      if (content.isEmpty || seenContent.contains(content)) {
        continue;
      }
      seenContent.add(content);

      final enriched = Map<String, dynamic>.from(row);
      final metadata = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : <String, dynamic>{};

      final similarity = (row['similarity'] as num?)?.toDouble() ?? 0.0;
      final confidence = _confidenceFromSimilarity(similarity);
      enriched['retrieval_confidence'] = confidence;

      final docId = metadata['doc_id']?.toString();
      final chunkIndex = metadata['chunk_index']?.toString();
      enriched['source_tag'] = (docId != null && chunkIndex != null)
          ? '$docId#$chunkIndex'
          : (chunkIndex != null ? 'chunk-$chunkIndex' : 'chunk');

      annotated.add(enriched);
    }

    return annotated;
  }

  double _confidenceFromSimilarity(double similarity) {
    if (similarity.isNaN) return 0.0;
    final clamped = similarity.clamp(0.0, 1.0);
    return (clamped * 100).roundToDouble() / 100;
  }
}
