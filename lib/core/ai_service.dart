import 'dart:math';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'vector_service.dart';
import 'services/rate_limiter_service.dart';
import 'services/log_service.dart';
import 'services/chat_insight_service.dart';
import 'services/llamaparse_service.dart';
import 'cache_service.dart';
import 'utils/medical_terms.dart';
import 'utils/unit_sanitizer.dart';
import 'models.dart';

enum LabParseStage { parsing, extracting }

class LabTestAnalysis {
  final String description;
  final String status;
  final String keyInsight;
  final String clinicalSignificance;
  final String resultContext;
  final List<String> potentialCauses;
  final List<String> factors;
  final List<String> questions;
  final String recommendation;

  LabTestAnalysis({
    required this.description,
    required this.status,
    required this.keyInsight,
    required this.clinicalSignificance,
    required this.resultContext,
    required this.potentialCauses,
    required this.factors,
    required this.questions,
    required this.recommendation,
  });

  factory LabTestAnalysis.fromJson(Map<String, dynamic> json) {
    return LabTestAnalysis(
      description: json['description'] ?? '',
      status: json['status'] ?? '',
      keyInsight: json['keyInsight'] ?? '',
      clinicalSignificance: json['clinicalSignificance'] ?? '',
      resultContext: json['resultContext'] ?? '',
      potentialCauses: List<String>.from(json['potentialCauses'] ?? []),
      factors: List<String>.from(json['factors'] ?? []),
      questions: List<String>.from(json['questions'] ?? []),
      recommendation: json['recommendation'] ?? '',
    );
  }
}

class AiChatResponse {
  final String text;
  final List<Map<String, dynamic>> retrievedChunks;
  final List<ChatCitation> citations;
  final ChatConfidence confidence;
  final List<CriticalAlert> criticalAlerts;
  final List<MedicationLabInteraction> medicationInteractions;
  final List<String> followUpPlan;
  final String languageCode;

  const AiChatResponse({
    required this.text,
    required this.retrievedChunks,
    required this.citations,
    required this.confidence,
    required this.criticalAlerts,
    required this.medicationInteractions,
    required this.followUpPlan,
    required this.languageCode,
  });
}

class AiService {
  final String aiApiKey;
  final String aiBaseUrl;
  final String aiChatModel;
  final String aiProxyUrl;
  final String aiProxyAnonKey;
  final Future<String?> Function()? proxyAccessTokenProvider;
  final Future<String?> Function()? proxyAccessTokenRefreshProvider;
  final VectorService vectorService;
  final CacheService cacheService;
  final LlamaParseService _llamaParseService;
  final ChatInsightService _chatInsightService;
  final http.Client _httpClient;

  final RateLimiterService _rateLimiter;

  // Test hook
  final Future<String> Function(String prompt)? mockTextGenerator;

  AiService({
    this.aiApiKey = '',
    this.aiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.aiChatModel = 'gemini-flash-lite-latest',
    this.aiProxyUrl = '',
    this.aiProxyAnonKey = '',
    this.proxyAccessTokenProvider,
    this.proxyAccessTokenRefreshProvider,
    String? llamaParseApiKey,
    String llamaParseBaseUrl = 'https://api.cloud.llamaindex.ai',
    required this.vectorService,
    required this.cacheService,

    required RateLimiterService rateLimiter,
    LlamaParseService? llamaParseService,
    http.Client? httpClient,
    ChatInsightService? chatInsightService,
    this.mockTextGenerator,
  }) : _rateLimiter = rateLimiter,
       _chatInsightService = chatInsightService ?? ChatInsightService(),
       _httpClient = httpClient ?? http.Client(),
       _llamaParseService =
           llamaParseService ??
           LlamaParseService(
             apiKey: llamaParseApiKey ?? '',
             baseUrl: llamaParseBaseUrl,
            ) {
    if (aiApiKey.trim().isEmpty) {
      AppLogger.debug('❌ AiService: GEMINI_API_KEY is empty!');
    } else {
      AppLogger.debug(
        '🚀 AiService: Initializing Gemini with key starting: ${aiApiKey.substring(0, min(5, aiApiKey.length))}...',
      );
    }
    AppLogger.debug(
      '💬 AiService: Gemini chat ${aiBaseUrl.trim().isNotEmpty && aiApiKey.trim().isNotEmpty ? 'configured' : 'not configured'}',
    );
  }

  String _sanitizeInput(String input) {
    // 1. Length Check
    if (input.length > 2000) {
      input = input.substring(0, 2000);
    }
    // 2. Strip Control Characters (keep newlines/tabs)
    // This removes non-printable characters unless they are standard whitespace
    input = input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    // 3. Basic "Prompt Injection" keywords check (Simplistic, for obvious attacks)
    // We don't want to block medical terms, but we can check for strict system overrides
    // This is optional and simplistic.
    // if (input.toLowerCase().contains("ignore previous instructions")) ...

    return input.trim();
  }

  /// Generates a unique cache key based on operation name and input data hash
  String _generateCacheKey(String operation, dynamic data) {
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    final hash = sha256.convert(bytes).toString().substring(0, 16);
    return 'ai_${operation}_$hash';
  }

  /// Minifies lab history to reduce token usage
  List<Map<String, dynamic>> _minifyHistory(
    List<Map<String, dynamic>> history,
  ) {
    return history.map((report) {
      List<Map<String, dynamic>> meaningfulTests = [];
      final results = report['test_results'] ?? report['testResults'];
      if (results is List) {
        for (var test in results) {
          if (test is! Map) continue;
          final sanitizedUnit = UnitSanitizer.clean(test['unit']?.toString());
          // We only keep essential fields
          meaningfulTests.add({
            'n': test['name'] ?? test['test_name'],
            'v': test['result'] ?? test['value'] ?? test['result_value'],
            'u': sanitizedUnit,
            's': test['status'], // 'High', 'Low', 'Normal'
          });
        }
      } else if (results != null) {
        if (kDebugMode) {
          AppLogger.warning(
            '_minifyHistory received non-list test results payload. '
            'Expected List for test_results/testResults. '
            'Type: ${results.runtimeType}, keys: ${report.keys.toList()}',
          );
        }
      } else {
        // Support callers that provide a flat list of test rows instead of
        // report objects with nested test_results.
        final testName = (report['name'] ?? report['test_name'])?.toString();
        final testValue =
            (report['result'] ?? report['value'] ?? report['result_value'])
                ?.toString();
        final sanitizedUnit = UnitSanitizer.clean(report['unit']?.toString());
        if ((testName != null && testName.trim().isNotEmpty) ||
            (testValue != null && testValue.trim().isNotEmpty)) {
          meaningfulTests.add({
            'n': testName,
            'v': testValue,
            'u': sanitizedUnit,
            's': report['status'],
          });
        }
        if (kDebugMode &&
            (testName == null || testName.trim().isEmpty) &&
            (testValue == null || testValue.trim().isEmpty)) {
          AppLogger.warning(
            '_minifyHistory received report row with no recognizable test keys. '
            'Expected test_results/testResults or flat name+value keys. '
            'Available keys: ${report.keys.toList()}',
          );
        }
      }
      if (kDebugMode && results == null && meaningfulTests.isEmpty) {
        AppLogger.warning(
          '_minifyHistory skipped report with unrecognized shape. '
          'Available keys: ${report.keys.toList()}',
        );
      }
      return {'d': report['date'], 't': meaningfulTests};
    }).toList();
  }

  Future<LabTestAnalysis> getSingleTestAnalysis({
    required String testName,
    required double value,
    required String unit,
    required String referenceRange,
    UserProfile? profile,
  }) async {
    final cacheKey = _generateCacheKey('single_analysis', {
      'n': testName,
      'v': value,
      'u': unit,
    });
    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) {
      return LabTestAnalysis.fromJson(Map<String, dynamic>.from(cached));
    }

    final waitTime = _rateLimiter.checkLimit(
      'ai_analysis',
      limit: 20,
      window: const Duration(minutes: 10),
    );
    if (waitTime != null) {
      return LabTestAnalysis(
        description: 'Rate limit exceeded.',
        status: 'Error',
        keyInsight: 'Please wait before requesting another analysis.',
        clinicalSignificance: 'System is temporarily overloaded.',
        resultContext: 'Please try again in ${waitTime.inMinutes + 1} minutes.',
        potentialCauses: [],
        factors: [],
        questions: [],
        recommendation: 'Wait a moment and refresh.',
      );
    }

    testName = _sanitizeInput(testName);
    unit = _sanitizeInput(unit);
    referenceRange = _sanitizeInput(referenceRange);

    final prompt =
        '''
      You are a specialized medical interpreter for patients. Your goal is to translate a specific lab result into a detailed, educational, and reassuring narrative.
      
      LAB TEST CONTEXT:
      - Test Name: $testName
      - Patient Result: $value $unit
      - Reference Range: $referenceRange
      ${profile != null ? '- Patient Context: ${_getPatientContext(profile)}' : ''}
      
      CRITICAL INSTRUCTIONS:
      1. If the patient is pediatric (under 18), MUST use pediatric-specific reference ranges and insights.
      2. If gender-specific tests are present, consider the patient's biological sex.
      3. Reference range comparison should be the primary guide, but age/gender context should influence the narrative.
      
      OUTPUT FORMAT (JSON ONLY):
      {
        "description": "Definition (max 20 words).",
        "status": "Strictly: 'High', 'Low', or 'Normal'.",
        "keyInsight": "Bold summary sentence.",
        "clinicalSignificance": "Explanation (max 60 words).",
        "resultContext": "Conversational comparison to range.",
        "potentialCauses": ["List 3-5 factors."],
        "factors": ["3 primary factors."],
        "questions": ["3 specific doctor questions."],
        "recommendation": "Next step."
      }
    ''';

    try {
      final rawText = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a medical lab analysis assistant. Return strict JSON only.',
        temperature: 0.1,
        maxTokens: 700,
      );

      AppLogger.debug(
        '🤖 AI Raw Response ($testName): $rawText',
        containsPII: true,
      );

      String jsonStr = _extractJson(rawText);
      final data = jsonDecode(jsonStr);

      // Cache the result
      cacheService.cacheAiResponse(cacheKey, data);

      return LabTestAnalysis.fromJson(data);
    } catch (e, stackTrace) {
      AppLogger.debug('❌ AI Analysis Error for $testName: $e');
      AppLogger.debug(stackTrace.toString());

      return LabTestAnalysis(
        description: 'Analysis unavailable. This measures $testName.',
        status: 'Normal', // Default
        keyInsight: 'Consult your doctor.',
        clinicalSignificance:
            'Individual test results should be viewed as part of your complete clinical picture.',
        resultContext: 'Your level is $value $unit.',
        potentialCauses: [],
        factors: [],
        questions: [],
        recommendation: 'Discuss with your doctor.',
      );
    }
  }

  Future<Map<String, dynamic>> getTrendAnalysis({
    required String testName,
    required List<Map<String, dynamic>> history,
  }) async {
    final waitTime = _rateLimiter.checkLimit(
      'ai_trend',
      limit: 20,
      window: const Duration(minutes: 10),
    );
    if (waitTime != null) {
      return {
        'direction': 'Stable',
        'change_percent': '--',
        'analysis':
            'Rate limit exceeded. Please try again in ${waitTime.inMinutes + 1} minutes.',
      };
    }
    if (history.length < 2) {
      return {
        'direction': 'Stable',
        'change_percent': '0.0%',
        'analysis': 'Not enough data to identify a trend.',
      };
    }

    history.sort(
      (a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])),
    );

    // Only use dates and values for cache/prompt to save tokens
    final minifiedHistory = history
        .map((h) => {'d': h['date'], 'v': h['value']})
        .toList();
    final cacheKey = _generateCacheKey('trend', {
      't': testName,
      'h': minifiedHistory,
    });

    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) return Map<String, dynamic>.from(cached);

    final prompt =
        '''
      Analyze the trend for: $testName
      Data: ${jsonEncode(minifiedHistory)}
      
      JSON ONLY:
      {
        "direction": "Increasing, Decreasing, or Stable",
        "change_percent": "e.g. +10%",
        "analysis": "1 sentence explanation."
      }
    ''';

    try {
      final rawText = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a trend analysis assistant. Return strict JSON only.',
        temperature: 0.1,
        maxTokens: 500,
      );
      String jsonStr = _extractJson(rawText);
      final data = jsonDecode(jsonStr);

      cacheService.cacheAiResponse(cacheKey, data);
      return data;
    } catch (e) {
      AppLogger.debug('Trend Analysis Error: $e');
      return {
        'direction': 'Unknown',
        'change_percent': '--',
        'analysis': 'Unable to calculate trend at this time.',
      };
    }
  }

  Future<String> getTrendCorrelationAnalysis({
    required Map<String, List<Map<String, dynamic>>> data,
    required List<String> markers,
  }) async {
    final waitTime = _rateLimiter.checkLimit(
      'ai_correlation',
      limit: 20,
      window: const Duration(minutes: 10),
    );
    if (waitTime != null) {
      return 'Rate limit exceeded. Please wait ${waitTime.inMinutes + 1} minutes.';
    }
    if (markers.isEmpty) return 'No markers selected for correlation analysis.';

    final minifiedData = <String, List<Map<String, dynamic>>>{};
    data.forEach((key, value) {
      if (markers.contains(key)) {
        minifiedData[key] = value.take(5).map((v) {
          // Extract value from test_results since passing LabReport json
          // LabRepository puts the trend result in test_results[0]
          String? val;
          String? status;
          final tests = v['test_results'] as List?;
          if (tests != null && tests.isNotEmpty) {
            val = tests[0]['result_value'] ?? tests[0]['result'];
            status = tests[0]['status'];
          }

          return {
            'd': v['date'],
            'v': val ?? v['value'] ?? v['result_value'],
            's': status ?? v['status'],
          };
        }).toList();
      }
    });

    final cacheKey = _generateCacheKey('correlation', {
      'm': markers,
      'd': minifiedData,
    });

    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) return cached.toString();

    final prompt =
        '''
      You are a specialized Medical Analyst. Analyze the correlation and relationships between these lab markers.
      
      Markers: ${markers.join(', ')}
      Historical Data: ${jsonEncode(minifiedData)}
      
      Provide a concise (3-5 sentences) insight explaining:
      1. If the trends are moving together or inversely.
      2. Clinical significance of these correlations.
      3. Potential lifestyle or medical factors that explain these patterns.
      
      Patient-friendly but scientifically grounded.
    ''';

    try {
      final text = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a clinical correlation assistant. Keep answers concise and evidence-grounded.',
        temperature: 0.2,
        maxTokens: 500,
      );
      cacheService.cacheAiResponse(cacheKey, text);
      return text;
    } catch (e) {
      AppLogger.error('Correlation analysis error: $e');
      return 'Unable to analyze marker correlations at this time.';
    }
  }

  Future<List<Map<String, dynamic>>> getOptimizationTips(
    List<Map<String, dynamic>> abnormalTests,
  ) async {
    if (_rateLimiter.checkLimit(
          'ai_tips',
          limit: 30,
          window: const Duration(minutes: 10),
        ) !=
        null) {
      return [];
    }
    if (abnormalTests.isEmpty) return [];

    // Minimize input
    final minifiedTests = abnormalTests
        .map(
          (t) => {
            'n': t['name'] ?? t['test_name'],
            'v': t['result'] ?? t['value'],
            's': t['status'],
          },
        )
        .toList();

    final cacheKey = _generateCacheKey('opt_tips', minifiedTests);

    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) {
      return (cached as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    final prompt =
        '''
      You are a health optimization expert. Provide 4-6 nutritional tips for these abnormal results.
      
      Results: ${jsonEncode(minifiedTests)}
      
      Include Veg and Non-Veg.
      
      JSON Format:
      [
        {
          "title": "Title",
          "description": "Why it helps",
          "ingredients": ["Item 1"],
          "instructions": "Action",
          "metric_targeted": "Test Name",
          "benefit": "Benefit",
          "type": "Veg/Non-Veg"
        }
      ]
    ''';

    try {
      final rawText = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a nutrition and lifestyle assistant. Return strict JSON array only.',
        temperature: 0.2,
        maxTokens: 700,
      );
      final jsonStr = _extractJson(rawText);
      final List<dynamic> data = jsonDecode(jsonStr);

      cacheService.cacheAiResponse(cacheKey, data);

      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      AppLogger.debug('Error fetching optimization tips: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getWellnessTips(
    List<Map<String, dynamic>> recentNormalTests,
  ) async {
    if (_rateLimiter.checkLimit(
          'ai_wellness',
          limit: 30,
          window: const Duration(minutes: 10),
        ) !=
        null) {
      return [];
    }
    if (recentNormalTests.isEmpty) {
      // If no data at all, return generic healthy living tips
      return [
        {
          "title": "Stay Hydrated",
          "description": "Water is essential for all bodily functions.",
          "type": "General",
        },
        {
          "title": "Regular Movement",
          "description": "Aim for 30 minutes of moderate activity daily.",
          "type": "General",
        },
      ];
    }

    // Take a sample of recent normal tests to contextualize (max 5)
    final sampleTests = recentNormalTests
        .take(5)
        .map(
          (t) => {
            'n': t['name'] ?? t['test_name'],
            'v': t['result'] ?? t['value'],
          },
        )
        .toList();

    final cacheKey = _generateCacheKey('wellness_tips', sampleTests);

    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) {
      return (cached as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    final prompt =
        '''
      You are a high-performance wellness and longevity coach. The user has NORMAL lab results for: ${jsonEncode(sampleTests)}.
      Your goal is to provide 3 "Optimization Tips" that go beyond basic maintenance.
      Focus on how to take these already healthy metrics to "optimal" levels or ensure long-term stability using nutrition, lifestyle, and biohacking principles.
      
      JSON Format:
      [
        {
          "title": "Short Impactful Title",
          "description": "One sentence optimization tip (max 20 words).",
          "type": "Optimization"
        }
      ]
    ''';

    try {
      final rawText = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a wellness assistant. Return strict JSON array only.',
        temperature: 0.2,
        maxTokens: 500,
      );
      final jsonStr = _extractJson(rawText);
      final List<dynamic> data = jsonDecode(jsonStr);

      cacheService.cacheAiResponse(cacheKey, data);
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      AppLogger.debug('Error fetching wellness tips: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getHealthPredictions(
    List<Map<String, dynamic>> fullHistory,
  ) async {
    if (_rateLimiter.checkLimit(
          'ai_predict',
          limit: 30,
          window: const Duration(minutes: 10),
        ) !=
        null) {
      return [];
    }
    if (fullHistory.length < 2) return [];

    final recentHistory = fullHistory.take(5).toList();
    final minifiedHistory = _minifyHistory(recentHistory);

    final cacheKey = _generateCacheKey('predictions', minifiedHistory);
    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) {
      return (cached as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    final prompt =
        '''
      Predictive Analyst. Forecast trends (3mo) based on this history (d=date, n=test, v=val, s=status).
      
      Data: ${jsonEncode(minifiedHistory)}
      
      JSON Only:
      [
        {
          "metric": "HbA1c",
          "current_value": "6.1",
          "predicted_value": "6.3",
          "trend_direction": "Increasing",
          "risk_level": "Medium",
          "insight": "Insight...",
          "recommendation": "Advice..."
        }
      ]
    ''';

    try {
      final rawText = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a predictive health assistant. Return strict JSON array only.',
        temperature: 0.2,
        maxTokens: 700,
      );
      final jsonStr = _extractJson(rawText);
      final List<dynamic> data = jsonDecode(jsonStr);

      cacheService.cacheAiResponse(cacheKey, data);

      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      AppLogger.error('Error fetching health predictions: $e');
      return [];
    }
  }

  Future<String> getBatchSummary(
    List<Map<String, dynamic>> tests, {
    UserProfile? profile,
  }) async {
    final waitTime = _rateLimiter.checkLimit(
      'ai_summary',
      limit: 20,
      window: const Duration(minutes: 10),
    );
    if (waitTime != null) {
      return 'System is busy (Rate Limit). Please try again in ${waitTime.inMinutes + 1} minutes.';
    }
    if (tests.isEmpty) {
      return 'No lab results available.';
    }
    final minifiedTests = _minifyHistory(tests);
    final hasAnyValidRow = minifiedTests.any((report) {
      final rows = report['t'];
      if (rows is! List) return false;
      for (final row in rows) {
        if (row is! Map) continue;
        final value = (row['v'] ?? '').toString().trim();
        final name = (row['n'] ?? '').toString().trim();
        if (name.isNotEmpty && value.isNotEmpty && value.toLowerCase() != 'null') {
          return true;
        }
      }
      return false;
    });
    if (!hasAnyValidRow) {
      return 'No lab data was provided. Please enter your results.';
    }
    final cacheKey = _generateCacheKey('batch_summary', minifiedTests);

    final cached = cacheService.getAiCache(cacheKey);
    if (cached != null) return cached.toString();

    final prompt =
        '''
      Medical AI. Summarize these lab results (JSON).
      ${profile != null ? 'Patient Context: ${_getPatientContext(profile)}' : ''}
      
      Data: ${jsonEncode(minifiedTests)}
      
      Summary (5-7 sentences):
      1. Overall assessment (considering age and gender).
      2. Abnormal findings.
      3. Recommendations for optimization.
      
      CRITICAL: For pediatric patients (under 18), apply pediatric guidelines.
      
      Patient-friendly language.
    ''';

    try {
      final text = await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a medical summary assistant. Keep output concise and patient-friendly.',
        temperature: 0.2,
        maxTokens: 600,
      );

      cacheService.cacheAiResponse(cacheKey, text);
      return text;
    } catch (e) {
      AppLogger.error('getBatchSummary error: $e');
      return _userFacingAiServiceError();
    }
  }

  Future<String> chat(
    String query, {
    Map<String, dynamic>? healthContext,
    String languageCode = 'en',
  }) async {
    final response = await chatDetailed(
      query,
      healthContext: healthContext,
      languageCode: languageCode,
    );
    return response.text;
  }

  Future<AiChatResponse> chatDetailed(
    String query, {
    Map<String, dynamic>? healthContext,
    String languageCode = 'en',
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    final waitTime = _rateLimiter.checkLimit(
      'ai_chat',
      limit: 50,
      window: const Duration(minutes: 30),
    );
    if (waitTime != null) {
      return AiChatResponse(
        text:
            'Rate limit exceeded. Please wait ${waitTime.inMinutes + 1} minutes.',
        retrievedChunks: const [],
        citations: const [],
        confidence: const ChatConfidence(
          score: 0.2,
          level: 'Low',
          rationale:
              'Rate limit was reached, so a grounded response could not be generated.',
          factors: ['Rate limit exceeded for ai_chat.'],
        ),
        criticalAlerts: const [],
        medicationInteractions: const [],
        followUpPlan: const [],
        languageCode: languageCode,
      );
    }

    query = _sanitizeInput(query);
    final abnormalLabs =
        (healthContext?['abnormal_labs'] as List?)
            ?.whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final activePrescriptions =
        (healthContext?['active_prescriptions'] as List?)
            ?.whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];

    try {
      final relevantChunks = await vectorService.searchSimilarChunks(query);

      final contextChunks = relevantChunks.asMap().entries.map((entry) {
        final i = entry.key;
        final chunk = entry.value;
        final metadata = chunk['metadata'] is Map
            ? Map<String, dynamic>.from(chunk['metadata'] as Map)
            : <String, dynamic>{};
        final sourceTag = chunk['source_tag']?.toString() ?? 'S${i + 1}';
        final confidence =
            ((chunk['retrieval_confidence'] as num?)?.toDouble() ?? 0.0) * 100;
        final confidencePct = confidence.toStringAsFixed(0);
        return '[Source: $sourceTag | Confidence: $confidencePct%]\n'
            'Content: ${chunk['content']}\n'
            'Date: ${metadata['date'] ?? 'Unknown'}';
      }).toList();

      final text = await getChatResponseWithContext(
        query: query,
        contextChunks: contextChunks,
        healthContext: healthContext,
        languageCode: languageCode,
        conversationHistory: conversationHistory,
      );
      final sourceTags = relevantChunks
          .map((chunk) => chunk['source_tag']?.toString() ?? '')
          .where((tag) => tag.isNotEmpty)
          .toSet();
      final citationHints = <String, String>{};
      for (final chunk in relevantChunks) {
        final sourceTag = chunk['source_tag']?.toString() ?? '';
        if (sourceTag.isEmpty) continue;
        final content = chunk['content']?.toString() ?? '';
        final hintedTestName = _chatInsightService.inferTestNameFromChunk(
          content,
        );
        if (hintedTestName != null && hintedTestName.isNotEmpty) {
          citationHints[sourceTag] = hintedTestName;
        }
      }
      final citations = _chatInsightService.extractCitations(
        text,
        retrievedSourceTags: sourceTags,
        sourceTagToHintedTestName: citationHints,
      );
      final criticalAlerts = _chatInsightService.detectCriticalAlerts(
        abnormalLabs,
      );
      final medicationInteractions = _chatInsightService
          .detectMedicationLabInteractions(activePrescriptions, abnormalLabs);
      final confidence = _chatInsightService.buildConfidence(
        answerText: text,
        citations: citations,
        retrievedChunks: relevantChunks,
        criticalAlerts: criticalAlerts,
      );
      final followUpPlan = _buildFollowUpPlan(
        query: query,
        criticalAlerts: criticalAlerts,
        medicationInteractions: medicationInteractions,
      );
      return AiChatResponse(
        text: text,
        retrievedChunks: relevantChunks,
        citations: citations,
        confidence: confidence,
        criticalAlerts: criticalAlerts,
        medicationInteractions: medicationInteractions,
        followUpPlan: followUpPlan,
        languageCode: languageCode,
      );
    } catch (e) {
      return AiChatResponse(
        text: _userFacingAiServiceError(),
        retrievedChunks: const [],
        citations: const [],
        confidence: const ChatConfidence(
          score: 0.2,
          level: 'Low',
          rationale:
              'An upstream error occurred before evidence-grounded reasoning completed.',
          factors: ['Upstream query failure.'],
        ),
        criticalAlerts: const [],
        medicationInteractions: const [],
        followUpPlan: const [],
        languageCode: languageCode,
      );
    }
  }

  Future<String> getChatResponseWithContext({
    required String query,
    required List<String> contextChunks,
    Map<String, dynamic>? healthContext,
    String languageCode = 'en',
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    // Chat is dynamic, harder to cache effectively without strict keys, skipping for now

    final contextText = contextChunks.isEmpty
        ? "No specific records found in vector database."
        : contextChunks.join('\n\n---\n\n');

    String healthContextStr = '';
    if (healthContext != null) {
      // Enhanced context: Include units and refs for better AI analysis
      final abnormal = (healthContext['abnormal_labs'] as List?)
          ?.map(
            (t) => {
              'Test': t['test_name'],
              'Result': formatDisplayValueWithUnit(t, valueKey: 'value'),
              'Status': t['status'],
              'Ref': t['reference_range'],
            },
          )
          .toList();

      final meds = (healthContext['active_prescriptions'] as List?)
          ?.map((m) => '${m['medication']} (${m['dosage']})')
          .toList();

      final conditions = (healthContext['known_conditions'] as List?)
          ?.map((c) => c.toString())
          .toList();

      healthContextStr =
          '''
      PATIENT HEALTH CONTEXT:
      - Abnormal Lab Results: ${jsonEncode(abnormal)}
      - Active Medications: ${jsonEncode(meds)}
      - Known Conditions: ${jsonEncode(conditions)}
      ''';
    }

    final languageInstruction = _languageInstruction(languageCode);
    final historySummary = _chatInsightService.buildConversationSummary(
      conversationHistory,
      maxTurns: 6,
    );

    final prompt =
        '''
You are LabSense Clinical Assistant.
Goal: Answer the user using only relevant, necessary medical information.

Grounding rules:
- Use retrieved history when available and cite facts as [Source: ...].
- If data is missing or uncertain, clearly say so.
- Do not invent diagnoses or medications.
- Keep tone calm, practical, and non-alarming.
- Language rule: $languageInstruction

Output format (concise):
1) Direct answer (2-4 sentences)
2) Key findings (up to 4 bullets, include values/ranges when available)
3) What to do next (up to 4 actionable bullets)
4) Red flags (only if urgent signs are present; otherwise say "No urgent red flags from available data.")
5) End exactly with: _(Medical Disclaimer: Consult your doctor)_

$healthContextStr

RECENT CONVERSATION CONTEXT:
$historySummary

RETRIEVED HISTORY:
$contextText

USER QUESTION:
$query
''';
    try {
      return await _generateAiText(
        prompt: prompt,
        systemPrompt:
            'You are a concise, evidence-grounded medical education assistant. Use only necessary information and avoid speculation.',
        temperature: 0.2,
        maxTokens: 600,
      );
    } catch (e) {
      return _userFacingAiServiceError();
    }
  }

  Future<String> _generateAiText({
    required String prompt,
    required String systemPrompt,
    double temperature = 0.2,
    int maxTokens = 700,
  }) async {
    if (mockTextGenerator != null) {
      return (await mockTextGenerator!(prompt)).trim();
    }

    final configuredProxyUrl = aiProxyUrl.trim();
    if (configuredProxyUrl.isEmpty) {
      throw Exception(
        'AI_PROXY_URL must be configured. Direct Gemini API calls are disabled '
        'to protect API keys and avoid browser-side rate-limit failures.',
      );
    }
    try {
      return await _generateAiTextViaProxy(
        proxyUrl: configuredProxyUrl,
        prompt: prompt,
        systemPrompt: systemPrompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );
    } catch (e) {
      AppLogger.error('AI proxy request failed: $e');
      throw Exception(
        'AI proxy request failed. Verify gemini-chat-proxy deployment, CORS, '
        'and authenticated Supabase session.',
      );
    }
  }

  Future<String> _generateAiTextViaProxy({
    required String proxyUrl,
    required String prompt,
    required String systemPrompt,
    required double temperature,
    required int maxTokens,
  }) async {
    // Fallback for existing setups where only SUPABASE_ANON_KEY is defined.
    final proxyAnonKey = aiProxyAnonKey.trim();
    if (proxyAnonKey.isEmpty) {
      throw Exception(
        'Missing anon key for AI proxy calls. Set AI_PROXY_ANON_KEY or SUPABASE_ANON_KEY in .env.',
      );
    }

    Future<http.Response> sendRequest(String bearerToken) {
      return _httpClient
          .post(
            Uri.parse(proxyUrl),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'apikey': proxyAnonKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'model': aiChatModel,
              'prompt': prompt,
              'systemPrompt': systemPrompt,
              'temperature': temperature,
              'maxTokens': maxTokens,
            }),
          )
          .timeout(const Duration(seconds: 45));
    }

    bool isProviderRateLimited(http.Response response) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) return false;
        return decoded['degraded'] == true &&
            decoded['reason']?.toString() == 'provider_rate_limited';
      } catch (_) {
        return false;
      }
    }

    final initialToken = (await proxyAccessTokenProvider?.call())?.trim();
    var activeToken = (initialToken != null && initialToken.isNotEmpty)
        ? initialToken
        : proxyAnonKey;
    var response = await sendRequest(activeToken);

    if (response.statusCode == 401) {
      String? refreshedToken;
      try {
        refreshedToken = (await proxyAccessTokenRefreshProvider?.call())?.trim();
      } catch (refreshError) {
        AppLogger.warning('AI proxy token refresh failed: $refreshError');
      }
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        activeToken = refreshedToken;
        response = await sendRequest(activeToken);
      }
    }

    if (response.statusCode == 401 && activeToken != proxyAnonKey) {
      response = await sendRequest(proxyAnonKey);
    }

    if (isProviderRateLimited(response)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      response = await sendRequest(activeToken);
      if (response.statusCode == 401 && activeToken != proxyAnonKey) {
        response = await sendRequest(proxyAnonKey);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw Exception(
          'AI proxy authentication failed (401). Re-login and verify '
          'gemini-chat-proxy auth settings.',
        );
      }
      throw Exception(
        'AI proxy failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('AI proxy returned invalid response shape.');
    }

    final text = decoded['text']?.toString().trim();
    if (text == null || text.isEmpty) {
      throw Exception('AI proxy returned empty text.');
    }

    return text;
  }

  Future<Map<String, dynamic>?> parseLabReport(
    Uint8List fileBytes,
    String mimeType, {
    String filename = 'lab_report.pdf',
    void Function(LabParseStage stage)? onStageChanged,
  }) async {
    final normalizedMime = mimeType.toLowerCase();

    try {
      if (!normalizedMime.contains('pdf')) {
        throw Exception(
          'Only PDF parsing is supported in current AI mode. Please upload a PDF lab report.',
        );
      }

      if (!_llamaParseService.isConfigured) {
        throw Exception(
          'LLAMAPARSE_API_KEY is required for PDF parsing in current AI mode.',
        );
      }

      onStageChanged?.call(LabParseStage.parsing);
      final markdown = await _llamaParseService.parseLabPdf(
        fileBytes,
        filename: filename,
      );

      onStageChanged?.call(LabParseStage.extracting);
      final parsed = await _extractFromMarkdown(markdown);
      parsed['source_markdown'] = markdown;
      return _normalizeParsedReport(parsed);
    } catch (e) {
      AppLogger.error('Error parsing lab report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _extractFromMarkdown(String markdown) async {
    final prompt =
        '''
You are an expert Medical Data Extractor.
You are given a medical lab report in MARKDOWN format.

CRITICAL INSTRUCTIONS:
1. Preserve every row-level measurement exactly from the markdown tables.
2. For each test, extract:
   - test_name
   - original_name
   - loinc_code
   - result_value
   - unit
   - reference_range
   - status (High/Low/Normal)
3. If status is missing, infer from result_value and reference_range.
4. Extract report-level metadata:
   - lab_provider
   - lab_name
   - date (YYYY-MM-DD)
5. Return STRICT JSON only.

OUTPUT FORMAT:
{
  "lab_provider": "Quest, Labcorp, or Other",
  "lab_name": "Full Lab Name",
  "date": "YYYY-MM-DD",
  "test_results": [
    {
      "test_name": "Standardized Name",
      "original_name": "Raw Name",
      "loinc_code": "LOINC Code",
      "result_value": "Numeric or String Value",
      "unit": "Unit",
      "reference_range": "Range String",
      "status": "High, Low, or Normal"
    }
  ]
}

MARKDOWN REPORT:
$markdown
''';

    final text = await _generateAiText(
      prompt: prompt,
      systemPrompt:
          'You are an expert medical data extractor. Return strict JSON only.',
      temperature: 0.1,
      maxTokens: 1200,
    );
    if (text.isEmpty) {
      throw Exception('Empty extraction response from AI model.');
    }

    final parsed = jsonDecode(_extractJson(text));
    if (parsed is! Map<String, dynamic> ||
        !parsed.containsKey('test_results')) {
      throw Exception('AI markdown extraction returned invalid JSON.');
    }

    return parsed;
  }

  Map<String, dynamic> _normalizeParsedReport(Map<String, dynamic> parsed) {
    final normalized = Map<String, dynamic>.from(parsed);
    final testResults = normalized['test_results'];

    if (testResults is! List) {
      throw Exception('Parsed report is missing test_results list.');
    }

    final cleanedTests = <Map<String, dynamic>>[];
    for (final raw in testResults) {
      if (raw is! Map) continue;
      final test = Map<String, dynamic>.from(raw);

      final sourceName =
          test['original_name']?.toString() ??
          test['test_name']?.toString() ??
          test['name']?.toString() ??
          '';
      final normalizedTerm = MedicalTermsNormalizer.normalize(sourceName);

      test['test_name'] = normalizedTerm.standardizedName;
      if (test['loinc_code'] == null || test['loinc_code'] == '') {
        test['loinc_code'] = normalizedTerm.loincCode;
      }

      if (test['result_value'] == null && test['result'] != null) {
        test['result_value'] = test['result'];
      }
      if (test['reference_range'] == null && test['reference'] != null) {
        test['reference_range'] = test['reference'];
      }

      if (test['status'] == null || test['status'] == '') {
        test['status'] =
            _calculateStatus(
              test['result_value']?.toString() ?? '',
              test['reference_range']?.toString() ?? '',
            ) ??
            'Normal';
      }

      final cleanedUnit = UnitSanitizer.clean(test['unit']?.toString());
      if (cleanedUnit != null) {
        test['unit'] = cleanedUnit;
      }

      cleanedTests.add(test);
    }

    normalized['test_results'] = cleanedTests;
    return normalized;
  }

  String? _calculateStatus(String resultValue, String referenceRange) {
    if (resultValue.isEmpty || referenceRange.isEmpty) return null;
    final resultLower = resultValue.toLowerCase();
    if (resultLower.contains('positive') || resultLower.contains('detected')) {
      return 'High';
    }
    if (resultLower.contains('negative') ||
        resultLower.contains('not detected')) {
      return 'Normal';
    }

    final numericMatch = RegExp(r'([0-9]+\.?[0-9]*)').firstMatch(resultValue);
    if (numericMatch == null) return null;
    final value = double.tryParse(numericMatch.group(1)!);
    if (value == null) return null;

    final rangeLower = referenceRange.toLowerCase();

    if (rangeLower.contains('<')) {
      final maxMatch = RegExp(r'<\s*([0-9]+\.?[0-9]*)').firstMatch(rangeLower);
      if (maxMatch != null) {
        final max = double.tryParse(maxMatch.group(1)!);
        if (max != null) return value >= max ? 'High' : 'Normal';
      }
    }

    if (rangeLower.contains('>')) {
      final minMatch = RegExp(r'>\s*([0-9]+\.?[0-9]*)').firstMatch(rangeLower);
      if (minMatch != null) {
        final min = double.tryParse(minMatch.group(1)!);
        if (min != null) return value <= min ? 'Low' : 'Normal';
      }
    }

    final rangeMatch = RegExp(
      r'([0-9]+\.?[0-9]*)\s*-\s*([0-9]+\.?[0-9]*)',
    ).firstMatch(rangeLower);
    if (rangeMatch != null) {
      final min = double.tryParse(rangeMatch.group(1)!);
      final max = double.tryParse(rangeMatch.group(2)!);
      if (min != null && max != null) {
        if (value < min) return 'Low';
        if (value > max) return 'High';
        return 'Normal';
      }
    }

    return null;
  }

  String _extractJson(String text) {
    if (text.isEmpty) return '{}';
    if (text.contains('```')) {
      final blocks = text.split('```');
      for (var block in blocks) {
        final trimmed = block.trim();
        if (trimmed.startsWith('{') ||
            trimmed.startsWith('[') ||
            trimmed.contains('{\n') ||
            trimmed.startsWith('json')) {
          text = trimmed.replaceFirst('json', '').trim();
          break;
        }
      }
    }
    final firstBrace = text.indexOf('{');
    final firstBracket = text.indexOf('[');
    bool isArray = false;
    if (firstBracket != -1) {
      if (firstBrace == -1 || firstBracket < firstBrace) isArray = true;
    }

    if (isArray) {
      final lastBracket = text.lastIndexOf(']');
      if (firstBracket != -1 &&
          lastBracket != -1 &&
          lastBracket > firstBracket) {
        return text.substring(firstBracket, lastBracket + 1).trim();
      }
    } else {
      final lastBrace = text.lastIndexOf('}');
      if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
        return text.substring(firstBrace, lastBrace + 1).trim();
      }
    }
    return text.trim();
  }

  String _languageInstruction(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
        return 'Respond in plain Spanish, short sentences, and avoid technical jargon unless necessary.';
      case 'hi':
        return 'Respond in plain Hindi, short sentences, and avoid technical jargon unless necessary.';
      case 'fr':
        return 'Respond in plain French, short sentences, and avoid technical jargon unless necessary.';
      case 'en':
      default:
        return 'Respond in plain English, short sentences, and avoid technical jargon unless necessary.';
    }
  }

  List<String> _buildFollowUpPlan({
    required String query,
    required List<CriticalAlert> criticalAlerts,
    required List<MedicationLabInteraction> medicationInteractions,
  }) {
    final plan = <String>[];

    if (criticalAlerts.isNotEmpty) {
      plan.add('Contact your clinician today about critical lab alerts.');
    }

    if (medicationInteractions.isNotEmpty) {
      final top = medicationInteractions.toList()
        ..sort((a, b) => b.severityScore.compareTo(a.severityScore));
      final first = top.first;
      plan.add(
        'Review ${first.medication} and ${first.labMarker} interaction at your next consultation.',
      );
    }

    final queryLower = query.toLowerCase();
    if (queryLower.contains('diet') || queryLower.contains('food')) {
      plan.add(
        'Track meals for 7 days and share pattern notes with your doctor.',
      );
    }
    if (queryLower.contains('exercise') || queryLower.contains('workout')) {
      plan.add(
        'Maintain a simple activity log to correlate with next lab check.',
      );
    }

    if (plan.isEmpty) {
      plan.add(
        'Recheck relevant labs at the interval advised by your clinician.',
      );
      plan.add('Bring this chat summary to your next medical visit.');
    }

    return plan.take(4).toList(growable: false);
  }

  String _getPatientContext(UserProfile profile) {
    if (profile.dateOfBirth == null) return 'Gender: ${profile.gender}';
    final age = DateTime.now().difference(profile.dateOfBirth!).inDays ~/ 365;
    final isPediatric = age < 18;
    return 'Age: $age (${isPediatric ? "Pediatric" : "Adult"}), Gender: ${profile.gender}';
  }

  String _userFacingAiServiceError() {
    if (kIsWeb) {
      return 'Unable to reach AI service right now. Please check your network and API configuration.';
    }
    return 'Unable to reach AI service right now. Please try again.';
  }
}
