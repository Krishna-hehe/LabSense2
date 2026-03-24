import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class LlamaParseService {
  static const String _parsingInstruction =
      'This is a medical laboratory report. Preserve all tables exactly as '
      'structured using markdown table syntax. Keep every test name, numeric '
      'value, unit, and reference range on the same row. Do not summarize, '
      'interpret, or omit any values. If a value is flagged as HIGH or LOW, '
      'preserve that flag.';

  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  LlamaParseService({
    required this.apiKey,
    this.baseUrl = 'https://api.cloud.llamaindex.ai',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Future<String> parseLabPdf(
    Uint8List fileBytes, {
    required String filename,
  }) async {
    _assertConfigured();

    final uploadRequest =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/v1/parsing/upload'),
          )
          ..headers.addAll(_headers())
          ..fields['result_type'] = 'markdown'
          ..fields['premium_mode'] = 'true'
          ..fields['parsing_instruction'] = _parsingInstruction
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              fileBytes,
              filename: filename,
              contentType: MediaType('application', 'pdf'),
            ),
          );

    final uploaded = await uploadRequest.send().timeout(
      const Duration(seconds: 45),
    );
    final uploadResponse = await http.Response.fromStream(uploaded);

    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw Exception(
        'LlamaParse upload failed (${uploadResponse.statusCode}): ${uploadResponse.body}',
      );
    }

    final uploadBody = _safeDecodeObject(uploadResponse.body);
    final immediateMarkdown = _extractMarkdown(uploadBody);
    if (immediateMarkdown != null && immediateMarkdown.trim().isNotEmpty) {
      return immediateMarkdown;
    }

    final jobId = _extractJobId(uploadBody);
    if (jobId == null || jobId.isEmpty) {
      throw Exception('LlamaParse upload did not return a job id.');
    }

    return _pollForMarkdown(jobId);
  }

  Future<String> _pollForMarkdown(String jobId) async {
    for (var attempt = 0; attempt < 45; attempt++) {
      final statusResponse = await _httpClient
          .get(
            Uri.parse('$baseUrl/api/v1/parsing/job/$jobId'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 20));

      if (statusResponse.statusCode < 200 || statusResponse.statusCode >= 300) {
        throw Exception(
          'LlamaParse polling failed (${statusResponse.statusCode}): ${statusResponse.body}',
        );
      }

      final statusBody = _safeDecodeObject(statusResponse.body);
      final inlineMarkdown = _extractMarkdown(statusBody);
      if (inlineMarkdown != null && inlineMarkdown.trim().isNotEmpty) {
        return inlineMarkdown;
      }

      final status = _extractStatus(statusBody).toUpperCase();
      if (status == 'ERROR' || status == 'FAILED') {
        throw Exception('LlamaParse parsing job failed for jobId=$jobId');
      }

      if (status == 'SUCCESS' || status == 'COMPLETED' || status == 'DONE') {
        final markdown = await _fetchFinalMarkdown(jobId);
        if (markdown.trim().isEmpty) {
          throw Exception('LlamaParse completed but returned empty markdown.');
        }
        return markdown;
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    throw Exception('LlamaParse timed out waiting for markdown result.');
  }

  Future<String> _fetchFinalMarkdown(String jobId) async {
    final resultUris = <Uri>[
      Uri.parse('$baseUrl/api/v1/parsing/job/$jobId/result/markdown'),
      Uri.parse(
        '$baseUrl/api/v1/parsing/job/$jobId/result?result_type=markdown',
      ),
      Uri.parse('$baseUrl/api/v1/parsing/job/$jobId/result'),
    ];

    for (final uri in resultUris) {
      final response = await _httpClient
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        continue;
      }

      final markdownFromJson = _extractMarkdown(
        _safeDecodeObject(response.body),
      );
      if (markdownFromJson != null && markdownFromJson.trim().isNotEmpty) {
        return markdownFromJson;
      }

      final body = response.body.trim();
      if (body.isNotEmpty && !body.startsWith('{') && !body.startsWith('[')) {
        return body;
      }
    }

    return '';
  }

  String? _extractJobId(Map<String, dynamic> payload) {
    final directJobId = payload['job_id'] ?? payload['jobId'] ?? payload['id'];
    if (directJobId is String && directJobId.isNotEmpty) return directJobId;

    final data = payload['data'];
    if (data is Map) {
      final nested = data['job_id'] ?? data['jobId'] ?? data['id'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    return null;
  }

  String _extractStatus(Map<String, dynamic> payload) {
    final direct = payload['status'];
    if (direct is String) return direct;

    final data = payload['data'];
    if (data is Map && data['status'] is String) {
      return data['status'] as String;
    }
    return '';
  }

  String? _extractMarkdown(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['markdown'],
      payload['markdown_full'],
      payload['text'],
      payload['text_full'],
      (payload['result'] is Map)
          ? (payload['result'] as Map)['markdown']
          : null,
      (payload['data'] is Map) ? (payload['data'] as Map)['markdown'] : null,
      (payload['data'] is Map)
          ? (payload['data'] as Map)['markdown_full']
          : null,
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  Map<String, dynamic> _safeDecodeObject(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Map<String, String> _headers() {
    return {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'};
  }

  void _assertConfigured() {
    if (!isConfigured) {
      throw Exception(
        'LLAMAPARSE_API_KEY is missing. Set it in .env before uploading PDFs.',
      );
    }
  }
}
