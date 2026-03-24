import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NvidiaService {
  static const String defaultEmbedModel = 'nvidia/llama-3.2-nv-embedqa-1b-v2';
  static const String defaultRerankModel = 'nvidia/llama-3.2-nv-rerankqa-1b-v2';

  final String apiKey;
  final String? embedApiKey;
  final String? rerankApiKey;
  final String baseUrl;
  final http.Client _httpClient;
  final String embedModel;
  final String rerankModel;

  NvidiaService({
    required this.apiKey,
    this.embedApiKey,
    this.rerankApiKey,
    this.baseUrl = 'https://integrate.api.nvidia.com/v1',
    this.embedModel = defaultEmbedModel,
    this.rerankModel = defaultRerankModel,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  bool get isConfigured =>
      apiKey.trim().isNotEmpty ||
      (embedApiKey?.trim().isNotEmpty ?? false) ||
      (rerankApiKey?.trim().isNotEmpty ?? false);

  Future<List<double>> embedPassage(String text) =>
      _embed(text, inputType: 'passage');

  Future<List<double>> embedQuery(String text) =>
      _embed(text, inputType: 'query');

  Future<List<String>> rerank(
    String query,
    List<String> chunks, {
    int topN = 4,
  }) async {
    if (kIsWeb) {
      // Browser CORS blocks direct NVIDIA API access.
      return chunks.take(topN).toList(growable: false);
    }
    if (chunks.isEmpty) return [];
    _assertConfigured(forRerank: true);

    final safeTopN = topN < 1
        ? 1
        : (topN > chunks.length ? chunks.length : topN);

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/ranking'),
          headers: _headers(forRerank: true),
          body: jsonEncode({
            'model': rerankModel,
            'query': {'text': query},
            'passages': chunks.map((chunk) => {'text': chunk}).toList(),
            'truncate': 'END',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Vector reranker failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = _decodeObject(response.body);
    final rankings = decoded['rankings'];
    if (rankings is! List) {
      throw Exception('Vector reranker returned invalid response shape.');
    }

    final rankingObjects = rankings
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();

    rankingObjects.sort((a, b) {
      final left = (a['logit'] as num?)?.toDouble() ?? double.negativeInfinity;
      final right = (b['logit'] as num?)?.toDouble() ?? double.negativeInfinity;
      return right.compareTo(left);
    });

    final reranked = <String>[];
    for (final ranking in rankingObjects.take(safeTopN)) {
      final index = (ranking['index'] as num?)?.toInt();
      if (index == null || index < 0 || index >= chunks.length) {
        continue;
      }
      reranked.add(chunks[index]);
    }

    return reranked;
  }

  Future<List<double>> _embed(String text, {required String inputType}) async {
    if (kIsWeb) {
      // Browser CORS blocks direct NVIDIA API access.
      return <double>[];
    }
    if (text.trim().isEmpty) return <double>[];
    _assertConfigured(forEmbed: true);

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/embeddings'),
          headers: _headers(forEmbed: true),
          body: jsonEncode({
            'input': [text],
            'model': embedModel,
            'encoding_format': 'float',
            'input_type': inputType,
            'truncate': 'END',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Vector embedding failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = _decodeObject(response.body);
    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw Exception('Vector embedding returned no vectors.');
    }

    final first = data.first;
    if (first is! Map) {
      throw Exception('Vector embedding returned malformed vector payload.');
    }

    final embeddingRaw = first['embedding'];
    if (embeddingRaw is! List) {
      throw Exception('Vector embedding payload does not include "embedding".');
    }

    return embeddingRaw
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
  }

  Map<String, String> _headers({bool forEmbed = false, bool forRerank = false}) {
    var selectedKey = apiKey;
    if (forEmbed && (embedApiKey?.trim().isNotEmpty ?? false)) {
      selectedKey = embedApiKey!.trim();
    } else if (forRerank && (rerankApiKey?.trim().isNotEmpty ?? false)) {
      selectedKey = rerankApiKey!.trim();
    }
    return {
      'Authorization': 'Bearer $selectedKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Vector response is not a JSON object.');
    }
    return decoded;
  }

  void _assertConfigured({bool forEmbed = false, bool forRerank = false}) {
    final hasGlobal = apiKey.trim().isNotEmpty;
    final hasEmbed = (embedApiKey?.trim().isNotEmpty ?? false);
    final hasRerank = (rerankApiKey?.trim().isNotEmpty ?? false);

    final okForEmbed = hasEmbed || hasGlobal;
    final okForRerank = hasRerank || hasGlobal;

    if ((forEmbed && !okForEmbed) || (forRerank && !okForRerank)) {
      throw Exception(
        'Missing VECTOR API key for requested operation. Set '
        'VECTOR_API_KEY or operation-specific keys.',
      );
    }

    if (!forEmbed && !forRerank && !isConfigured) {
      throw Exception(
        'VECTOR_API_KEY is missing. Set it in .env before using embeddings/reranker.',
      );
    }
  }
}
