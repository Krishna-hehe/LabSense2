import 'package:clear_health/core/services/chat_insight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChatInsightService service;

  setUp(() {
    service = ChatInsightService();
  });

  test('extractCitations parses source tags and metadata', () {
    const text = 'Evidence from [Source: abc-123#4] and [Source: chunk-2, S1].';
    final citations = service.extractCitations(
      text,
      retrievedSourceTags: {'abc-123#4', 'chunk-2'},
    );

    expect(citations.length, 3);
    expect(citations.first.sourceTag, 'abc-123#4');
    expect(citations.first.docId, 'abc-123');
    expect(citations.first.chunkIndex, 4);
    expect(citations.first.isRetrievedSource, isTrue);
  });

  test('detectCriticalAlerts flags severe potassium and glucose values', () {
    final alerts = service.detectCriticalAlerts([
      {'test_name': 'Potassium', 'value': '6.2', 'unit': 'mmol/L'},
      {'test_name': 'Glucose', 'value': '322', 'unit': 'mg/dL'},
      {'test_name': 'HDL', 'value': '45', 'unit': 'mg/dL'},
    ]);

    expect(alerts.length, 2);
    expect(alerts.first.severity, 'critical');
  });

  test('detectMedicationLabInteractions finds known pairings', () {
    final interactions = service.detectMedicationLabInteractions(
      [
        {'medication': 'Lisinopril', 'dosage': '10mg'},
        {'medication': 'Metformin', 'dosage': '500mg'},
      ],
      [
        {'test_name': 'Potassium', 'value': '5.8'},
        {'test_name': 'Vitamin B12', 'value': '180'},
      ],
    );

    expect(interactions.length, greaterThanOrEqualTo(2));
    expect(
      interactions.any((entry) => entry.medication.contains('Lisinopril')),
      isTrue,
    );
  });

  test('buildConfidence returns high score with citations and context', () {
    final confidence = service.buildConfidence(
      answerText: 'This appears stable [Source: doc-1#0].',
      citations: const [
        ChatCitation(
          sourceTag: 'doc-1#0',
          docId: 'doc-1',
          chunkIndex: 0,
          isRetrievedSource: true,
        ),
      ],
      retrievedChunks: const [
        {'source_tag': 'doc-1#0', 'content': 'Test content'},
      ],
      criticalAlerts: const [],
    );

    expect(confidence.score, greaterThan(0.6));
    expect(confidence.level, isNot('Low'));
  });

  test('inferTestNameFromChunk extracts test from explicit label', () {
    const chunk = '''
Test: Potassium
Result: 6.2 mmol/L
Reference Range: 3.5 - 5.1
''';
    final inferred = service.inferTestNameFromChunk(chunk);
    expect(inferred, 'Potassium');
  });

  test('extractCitations carries hinted test name map', () {
    const text = 'Please check [Source: abc-123#2].';
    final citations = service.extractCitations(
      text,
      sourceTagToHintedTestName: const {'abc-123#2': 'Glucose'},
    );
    expect(citations.single.hintedTestName, 'Glucose');
  });

  test('buildConversationSummary keeps recent turns in readable format', () {
    final summary = service.buildConversationSummary([
      {'role': 'user', 'content': 'My glucose is high'},
      {'role': 'assistant', 'content': 'Track fasting values for 1 week.'},
      {'role': 'user', 'content': 'Should I change diet?'},
    ]);

    expect(summary, contains('USER: My glucose is high'));
    expect(summary, contains('ASSISTANT: Track fasting values for 1 week.'));
  });
}
