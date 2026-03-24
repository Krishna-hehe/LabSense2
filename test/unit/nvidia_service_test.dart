import 'dart:convert';

import 'package:clear_health/core/services/nvidia_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('embedPassage parses embedding response', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.path, '/v1/embeddings');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['input_type'], 'passage');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'embedding': [0.1, 0.2, 0.3],
            },
          ],
        }),
        200,
      );
    });

    final service = NvidiaService(
      apiKey: 'test-key',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      httpClient: mockClient,
    );

    final vector = await service.embedPassage('Hemoglobin 13.2 g/dL');
    expect(vector, [0.1, 0.2, 0.3]);
  });

  test('rerank returns chunks ordered by descending logit', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.path, '/v1/ranking');
      return http.Response(
        jsonEncode({
          'rankings': [
            {'index': 1, 'logit': 1.2},
            {'index': 0, 'logit': 9.4},
            {'index': 2, 'logit': 0.3},
          ],
        }),
        200,
      );
    });

    final service = NvidiaService(
      apiKey: 'test-key',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      httpClient: mockClient,
    );

    final chunks = ['best match', 'second best', 'third best'];
    final reranked = await service.rerank(
      'What is my hemoglobin?',
      chunks,
      topN: 2,
    );

    expect(reranked, ['best match', 'second best']);
  });
}
