import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

class EdgeIngestionService {
  final SupabaseClient _client;
  final http.Client _httpClient;

  EdgeIngestionService(this._client, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> startIngestion({
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    final session = _client.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('User must be authenticated to start ingestion.');
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${SupabaseConfig.url}/functions/v1/ingest-lab-report'),
          )
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..fields['fileSize'] = fileBytes.lengthInBytes.toString()
          ..fields['fileName'] = fileName
          ..fields['mimeType'] = mimeType.isNotEmpty ? mimeType : 'application/pdf'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              fileBytes,
              filename: fileName,
              contentType: MediaType.parse(
                mimeType.isNotEmpty ? mimeType : 'application/pdf',
              ),
            ),
          );

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Ingestion start failed: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Ingestion start returned invalid payload.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> pollUntilComplete({
    required String jobId,
    Duration timeout = const Duration(minutes: 4),
    Duration pollInterval = const Duration(seconds: 3),
    void Function(Map<String, dynamic> status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _client.functions.invoke(
        'ingestion-status',
        body: {'jobId': jobId},
      );

      final payload = response.data;
      if (payload is! Map) {
        throw Exception('Invalid ingestion status payload.');
      }

      final statusMap = Map<String, dynamic>.from(payload);
      onProgress?.call(statusMap);

      final status = (statusMap['status'] ?? '').toString().toLowerCase();
      if (status == 'done') {
        return statusMap;
      }
      if (status == 'error' || status == 'dead_letter') {
        throw Exception(
          statusMap['message']?.toString() ?? 'Ingestion failed.',
        );
      }

      await Future.delayed(pollInterval);
    }

    throw Exception('Ingestion timed out. Please try again.');
  }

  Future<Map<String, dynamic>> ingestAndWait({
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
    void Function(Map<String, dynamic> status)? onProgress,
  }) async {
    final started = await startIngestion(
      fileBytes: fileBytes,
      fileName: fileName,
      mimeType: mimeType,
    );

    final jobId = (started['jobId'] ?? '').toString();
    if (jobId.isEmpty) {
      throw Exception('Ingestion start did not return jobId.');
    }

    final completed = await pollUntilComplete(
      jobId: jobId,
      onProgress: onProgress,
    );

    return {...started, ...completed, 'jobId': jobId};
  }

  void dispose() {
    _httpClient.close();
  }
}
