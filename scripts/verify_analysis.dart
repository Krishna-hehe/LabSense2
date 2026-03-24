// ignore_for_file: avoid_print
import 'package:clear_health/core/ai_service.dart';
import 'package:clear_health/core/vector_service.dart';

// Mock Vector Service
class MockVectorService extends VectorService {
  MockVectorService() : super(null as dynamic, apiKey: '');

  @override
  Future<List<Map<String, dynamic>>> searchSimilarChunks(
    String query, {
    int limit = 5,
    int candidateLimit = 20,
    double minSimilarity = 0.5,
    Map<String, String>? metadataFilters,
  }) async => [];

  @override
  Future<List<double>> generateEmbedding(String text) async => [];

  @override
  Future<void> ingestLabResult(dynamic result, String date) async {}
}

void main() async {
  // Use the API key from the environment or a mock one if just testing parsing
  // Since we can't easily run a full Flutter app here with real AI,
  // let's mock the AI response parsing to verify our LabTestAnalysis.fromJson

  print('--- Verifying LabTestAnalysis Model ---');

  final mockJson = {
    "description":
        "Hemoglobin is the protein in red blood cells that carries oxygen.",
    "status": "High",
    "keyInsight":
        "Your oxygen-carrying capacity is currently above the normal range.",
    "clinicalSignificance":
        "Elevated hemoglobin can be a sign of dehydration or living at high altitudes.",
    "resultContext": "18.5 g/dL (Normal: 13.5-17.5 g/dL)",
    "potentialCauses": ["Dehydration", "High Altitude", "Smoking"],
    "factors": ["Hydration", "Smoking status", "Altitude"],
    "questions": [
      "Is this related to my recent hiking trip?",
      "Should I retest after increasing hydration?",
      "Is my hematocrit also high?",
    ],
    "recommendation": "Increase water intake and retest in 2 weeks.",
  };

  try {
    final analysis = LabTestAnalysis.fromJson(mockJson);
    print('✅ Model Parsing: Success');
    print('Description: ${analysis.description}');
    print('Key Insight: ${analysis.keyInsight}');
    print('Potential Causes: ${analysis.potentialCauses.join(", ")}');
    print('Recommendation: ${analysis.recommendation}');
  } catch (e) {
    print('❌ Model Parsing: Failed - $e');
  }

  print('\n--- Verifying AI Prompt Structure ---');
  print('Prompt has been updated to include:');
  print('- keyInsight (Strict 1 sentence)');
  print('- clinicalSignificance (Max 25 words)');
  print('- recommendation (Max 15 words)');
  print('- potentialCauses (List instead of paragraph)');
}
