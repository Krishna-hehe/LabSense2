import '../utils/unit_sanitizer.dart';

class ChatCitation {
  final String sourceTag;
  final String? docId;
  final int? chunkIndex;
  final String? hintedTestName;
  final bool isRetrievedSource;

  const ChatCitation({
    required this.sourceTag,
    this.docId,
    this.chunkIndex,
    this.hintedTestName,
    this.isRetrievedSource = false,
  });
}

class ChatConfidence {
  final double score;
  final String level;
  final String rationale;
  final List<String> factors;

  const ChatConfidence({
    required this.score,
    required this.level,
    required this.rationale,
    required this.factors,
  });
}

class CriticalAlert {
  final String testName;
  final String details;
  final String severity;
  final String recommendedAction;

  const CriticalAlert({
    required this.testName,
    required this.details,
    required this.severity,
    required this.recommendedAction,
  });
}

class MedicationLabInteraction {
  final String medication;
  final String labMarker;
  final String explanation;
  final String recommendation;
  final String severity;
  final double severityScore;
  final String provenance;

  const MedicationLabInteraction({
    required this.medication,
    required this.labMarker,
    required this.explanation,
    required this.recommendation,
    this.severity = 'moderate',
    this.severityScore = 0.6,
    this.provenance = 'Rule-based clinical heuristic',
  });
}

class ChatInsightService {
  List<ChatCitation> extractCitations(
    String text, {
    Set<String> retrievedSourceTags = const <String>{},
    Map<String, String> sourceTagToHintedTestName = const <String, String>{},
  }) {
    final regex = RegExp(
      r'\[Source:\s*([^\]]+)\]',
      caseSensitive: false,
      multiLine: true,
    );
    final unique = <String>{};
    final parsed = <ChatCitation>[];

    for (final match in regex.allMatches(text)) {
      final sourceBlock = match.group(1);
      if (sourceBlock == null || sourceBlock.trim().isEmpty) continue;

      final tags = sourceBlock
          .split(RegExp(r'[,;]'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList(growable: false);

      for (final tag in tags) {
        if (!unique.add(tag)) continue;
        final target = parseSourceTag(tag);
        parsed.add(
          ChatCitation(
            sourceTag: tag,
            docId: target.$1,
            chunkIndex: target.$2,
            hintedTestName: sourceTagToHintedTestName[tag],
            isRetrievedSource: retrievedSourceTags.contains(tag),
          ),
        );
      }
    }

    return parsed;
  }

  String? inferTestNameFromChunk(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) return null;

    final explicitLabel = RegExp(
      r'^(Test|Marker)\s*:\s*(.+)$',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = explicitLabel.firstMatch(line);
      if (match != null) {
        return match.group(2)?.trim();
      }
    }

    final firstPipeRow = lines.firstWhere(
      (line) => line.startsWith('|') && line.split('|').length >= 3,
      orElse: () => '',
    );
    if (firstPipeRow.isNotEmpty) {
      final cells = firstPipeRow
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .toList(growable: false);
      if (cells.isNotEmpty) {
        final candidate = cells.first;
        if (!candidate.toLowerCase().contains('test') &&
            !candidate.contains('---')) {
          return candidate;
        }
      }
    }

    return null;
  }

  (String?, int?) parseSourceTag(String sourceTag) {
    if (sourceTag.contains('#')) {
      final parts = sourceTag.split('#');
      if (parts.length == 2) {
        return (parts[0], int.tryParse(parts[1]));
      }
    }

    if (sourceTag.startsWith('chunk-')) {
      return (null, int.tryParse(sourceTag.replaceFirst('chunk-', '')));
    }

    return (null, null);
  }

  List<CriticalAlert> detectCriticalAlerts(
    List<Map<String, dynamic>> abnormalLabs,
  ) {
    final alerts = <CriticalAlert>[];

    for (final lab in abnormalLabs) {
      final testName = (lab['test_name'] ?? '').toString();
      final normalized = testName.toLowerCase();
      final value = _parseNumeric(lab['value']?.toString());
      final unit = UnitSanitizer.clean(lab['unit']?.toString()) ?? '';
      if (value == null) continue;

      if (_containsAny(normalized, ['glucose', 'blood sugar'])) {
        if (value >= 300 || value <= 54) {
          alerts.add(
            CriticalAlert(
              testName: testName,
              details:
                  'Critical glucose value detected ($value ${unit.isEmpty ? '' : unit}).',
              severity: 'critical',
              recommendedAction:
                  'Contact a clinician today. If symptoms are severe, seek urgent care immediately.',
            ),
          );
        }
      }

      if (_containsAny(normalized, ['potassium', 'k+'])) {
        if (value >= 6.0 || value < 3.0) {
          alerts.add(
            CriticalAlert(
              testName: testName,
              details:
                  'Critical potassium value detected ($value ${unit.isEmpty ? '' : unit}).',
              severity: 'critical',
              recommendedAction:
                  'Escalate urgently to your care team because severe potassium imbalance may affect heart rhythm.',
            ),
          );
        }
      }

      if (_containsAny(normalized, ['sodium', 'na+'])) {
        if (value >= 155 || value < 125) {
          alerts.add(
            CriticalAlert(
              testName: testName,
              details:
                  'Critical sodium value detected ($value ${unit.isEmpty ? '' : unit}).',
              severity: 'critical',
              recommendedAction:
                  'Contact your clinician urgently, especially if confusion, weakness, or neurologic symptoms are present.',
            ),
          );
        }
      }

      if (_containsAny(normalized, ['hemoglobin'])) {
        if (value < 7.0 || value > 20.0) {
          alerts.add(
            CriticalAlert(
              testName: testName,
              details:
                  'Critical hemoglobin value detected ($value ${unit.isEmpty ? '' : unit}).',
              severity: 'critical',
              recommendedAction:
                  'Discuss same-day with your clinician. Severe anemia or polycythemia may need urgent evaluation.',
            ),
          );
        }
      }

      if (_containsAny(normalized, ['platelet'])) {
        if (value < 50 || value > 1000) {
          alerts.add(
            CriticalAlert(
              testName: testName,
              details:
                  'Critical platelet value detected ($value ${unit.isEmpty ? '' : unit}).',
              severity: 'critical',
              recommendedAction:
                  'Escalate promptly to a clinician due to possible bleeding or clotting risk.',
            ),
          );
        }
      }
    }

    return alerts;
  }

  List<MedicationLabInteraction> detectMedicationLabInteractions(
    List<Map<String, dynamic>> activePrescriptions,
    List<Map<String, dynamic>> abnormalLabs,
  ) {
    if (activePrescriptions.isEmpty || abnormalLabs.isEmpty) return [];

    final interactions = <MedicationLabInteraction>[];
    final seen = <String>{};

    for (final rx in activePrescriptions) {
      final medication = (rx['medication'] ?? '').toString();
      final medLower = medication.toLowerCase();

      for (final lab in abnormalLabs) {
        final testName = (lab['test_name'] ?? '').toString();
        final testLower = testName.toLowerCase();

        void addInteraction({
          required String explanation,
          required String recommendation,
          String severity = 'moderate',
          double severityScore = 0.6,
          String provenance = 'Rule-based clinical heuristic',
        }) {
          final key = '${medLower}_$testLower';
          if (!seen.add(key)) return;
          interactions.add(
            MedicationLabInteraction(
              medication: medication,
              labMarker: testName,
              explanation: explanation,
              recommendation: recommendation,
              severity: severity,
              severityScore: severityScore,
              provenance: provenance,
            ),
          );
        }

        if (_containsAny(medLower, [
              'statin',
              'atorvastatin',
              'rosuvastatin',
            ]) &&
            _containsAny(testLower, ['alt', 'ast', 'liver', 'ck'])) {
          addInteraction(
            explanation:
                'This medication can affect liver or muscle-related markers in some patients.',
            recommendation:
                'Review trends with your clinician before changing therapy.',
            severityScore: 0.55,
            provenance: 'Known class effect: statins and liver/muscle markers',
          );
        }

        if (_containsAny(medLower, ['metformin']) &&
            _containsAny(testLower, ['vitamin b12', 'b12', 'creatinine'])) {
          addInteraction(
            explanation:
                'Metformin may relate to B12 reduction and needs kidney function monitoring.',
            recommendation:
                'Ask your clinician whether B12 and renal monitoring should be repeated.',
            severityScore: 0.6,
            provenance: 'Medication monitoring guidance for metformin',
          );
        }

        if (_containsAny(medLower, [
              'lisinopril',
              'enalapril',
              'ace inhibitor',
            ]) &&
            _containsAny(testLower, ['potassium', 'creatinine'])) {
          addInteraction(
            explanation:
                'ACE inhibitors can raise potassium and may affect kidney markers.',
            recommendation:
                'Discuss whether dosage or interval monitoring needs adjustment.',
            severity: 'high',
            severityScore: 0.85,
            provenance:
                'Class interaction: ACE inhibitors with potassium/renal labs',
          );
        }

        if (_containsAny(medLower, [
              'furosemide',
              'hydrochlorothiazide',
              'diuretic',
            ]) &&
            _containsAny(testLower, ['potassium', 'sodium'])) {
          addInteraction(
            explanation:
                'Diuretics can shift electrolytes and may contribute to sodium/potassium changes.',
            recommendation:
                'Check hydration plan and follow-up labs with your clinician.',
            severityScore: 0.7,
            provenance: 'Electrolyte effect profile of diuretics',
          );
        }

        if (_containsAny(medLower, ['prednisone', 'steroid']) &&
            _containsAny(testLower, ['glucose', 'blood sugar', 'wbc'])) {
          addInteraction(
            explanation:
                'Steroids can elevate glucose and influence inflammatory markers.',
            recommendation:
                'Discuss risk-benefit and any glucose monitoring adjustments.',
            severityScore: 0.65,
            provenance: 'Known corticosteroid impact on glucose/inflammation',
          );
        }

        if (_containsAny(medLower, ['warfarin']) &&
            _containsAny(testLower, ['inr', 'pt'])) {
          addInteraction(
            explanation:
                'Warfarin requires close coagulation monitoring to stay in therapeutic range.',
            recommendation: 'Confirm INR follow-up timing with your care team.',
            severity: 'high',
            severityScore: 0.9,
            provenance: 'Standard anticoagulation INR/PT monitoring guidance',
          );
        }
      }
    }

    return interactions;
  }

  ChatConfidence buildConfidence({
    required String answerText,
    required List<ChatCitation> citations,
    required List<Map<String, dynamic>> retrievedChunks,
    required List<CriticalAlert> criticalAlerts,
  }) {
    var score = 0.35;
    final factors = <String>[];

    if (retrievedChunks.isNotEmpty) {
      score += 0.25;
      factors.add('Used retrieved history context.');
    } else {
      factors.add('No retrieved history context was available.');
    }

    if (citations.isNotEmpty) {
      final citationBoost = citations.length >= 3
          ? 0.25
          : citations.length * 0.08;
      score += citationBoost;
      factors.add('Response cites source-backed evidence.');
    } else {
      factors.add('No explicit source citations were detected.');
    }

    final uncertaintySignals = RegExp(
      r'\b(insufficient|uncertain|not enough data|unable to confirm|may|might)\b',
      caseSensitive: false,
    ).allMatches(answerText).length;
    if (uncertaintySignals > 0) {
      score -= 0.12;
      factors.add('Uncertainty language detected in response.');
    } else {
      score += 0.08;
      factors.add('Response language was direct and specific.');
    }

    if (criticalAlerts.isNotEmpty) {
      factors.add('Critical values detected; escalation is prioritized.');
    }

    if (score < 0) score = 0;
    if (score > 1) score = 1;

    final level = score >= 0.75 ? 'High' : (score >= 0.5 ? 'Medium' : 'Low');
    final rationale =
        'Confidence is based on evidence grounding, source citation quality, and response certainty signals.';

    return ChatConfidence(
      score: score,
      level: level,
      rationale: rationale,
      factors: factors,
    );
  }

  String buildConversationSummary(
    List<Map<String, String>> turns, {
    int maxTurns = 6,
  }) {
    if (turns.isEmpty) return 'No prior conversation context.';
    final trimmed = turns.length <= maxTurns
        ? turns
        : turns.sublist(turns.length - maxTurns);
    final buffer = StringBuffer();
    for (final turn in trimmed) {
      final role = (turn['role'] ?? 'user').trim();
      final content = (turn['content'] ?? '').trim();
      if (content.isEmpty) continue;
      buffer.writeln('${role.toUpperCase()}: $content');
    }
    final built = buffer.toString().trim();
    return built.isEmpty ? 'No prior conversation context.' : built;
  }

  bool _containsAny(String input, List<String> keywords) {
    for (final keyword in keywords) {
      if (input.contains(keyword)) return true;
    }
    return false;
  }

  double? _parseNumeric(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final sanitized = raw.replaceAll(RegExp(r'[^0-9\.\-]'), '');
    return double.tryParse(sanitized);
  }
}
