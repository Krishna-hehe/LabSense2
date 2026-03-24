import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/ai_service.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/providers.dart';
import '../../core/services/chat_insight_service.dart';
import '../../core/theme.dart';
import '../../core/notification_service.dart';
import '../../core/services/audit_service.dart';
import '../../widgets/glass_card.dart';

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final AiChatResponse? metadata;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.metadata,
  });
}

class _EscalationStep {
  final String title;
  final bool required;
  bool done = false;

  _EscalationStep({required this.title, this.required = false});
}

class HealthChatPage extends ConsumerStatefulWidget {
  const HealthChatPage({super.key});

  @override
  ConsumerState<HealthChatPage> createState() => _HealthChatPageState();
}

class _HealthChatPageState extends ConsumerState<HealthChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Message> _messages = [];
  final List<Map<String, String>> _conversationHistory = [];
  bool _isLoading = false;
  String _languageCode = 'en';
  final Map<String, String> _languageLabels = const {
    'en': 'English',
    'es': 'Spanish',
    'hi': 'Hindi',
    'fr': 'French',
  };
  final Map<String, String> _uiLabels = const {
    'chatTitle_en': 'Ask LabSense',
    'chatTitle_es': 'Pregunta a LabSense',
    'chatTitle_hi': 'LabSense से पूछें',
    'chatTitle_fr': 'Demandez à LabSense',
    'chatSubtitle_en': 'Context-aware AI assistant for your medical data',
    'chatSubtitle_es': 'Asistente con IA para tus datos médicos',
    'chatSubtitle_hi': 'आपके मेडिकल डेटा के लिए AI सहायक',
    'chatSubtitle_fr': 'Assistant IA pour vos données médicales',
    'inputHint_en': 'Ask about your results, trends, or health history...',
    'inputHint_es':
        'Pregunta sobre tus resultados, tendencias o historial de salud...',
    'inputHint_hi':
        'अपने परिणाम, रुझान या स्वास्थ्य इतिहास के बारे में पूछें...',
    'inputHint_fr':
        'Posez des questions sur vos résultats, tendances ou historique médical...',
  };
  final List<_EscalationStep> _escalationSteps = [
    _EscalationStep(
      title: 'Call your clinician office or telehealth line now',
      required: true,
    ),
    _EscalationStep(
      title: 'Keep latest lab report open while talking to clinician',
      required: true,
    ),
    _EscalationStep(
      title: 'List current medications and doses before the call',
      required: true,
    ),
    _EscalationStep(
      title: 'If severe symptoms appear, go to urgent care/ER',
      required: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      Message(
        text:
            "Hello! I'm LabSense AI. I can help you understand your lab results and medical history. What would you like to know today?",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _sendMessage() async {
    var query = _controller.text.trim();
    if (query.isEmpty) return;

    final validator = ref.read(inputValidationServiceProvider);
    query = validator.sanitizeInput(query);
    if (query.isEmpty) return;

    if (query.length > 500) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Message too long. Please shorten your message (max 500 chars).',
          ),
        ),
      );
      return;
    }

    final rateLimiter = ref.read(rateLimiterProvider);
    final waitDuration = rateLimiter.checkLimit('ask_labsense');
    if (waitDuration != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rate limit exceeded. Please wait ${waitDuration.inSeconds} seconds.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _messages.add(
        Message(text: query, isUser: true, timestamp: DateTime.now()),
      );
      _isLoading = true;
      _controller.clear();
    });

    final labResults = ref.read(labResultsProvider).value ?? [];
    final prescriptions = ref.read(prescriptionsProvider).value ?? [];
    final selectedProfile = ref.read(selectedProfileProvider).value;
    final conditions = selectedProfile?.conditions ?? [];

    final abnormalLabs = <Map<String, dynamic>>[];
    for (final report in labResults) {
      if (report.testResults != null) {
        for (final test in report.testResults!) {
          if (test.status.toLowerCase() == 'high' ||
              test.status.toLowerCase() == 'low') {
            abnormalLabs.add({
              'test_name': test.name,
              'value': test.result,
              'unit': test.unit,
              'status': test.status,
              'reference_range': test.reference,
              'loinc': test.loinc,
              'date': report.date.toIso8601String().split('T')[0],
            });
          }
        }
      }
    }

    final activePrescriptions = prescriptions
        .where((p) => p['is_active'] == true)
        .map(
          (p) => {
            'medication': p['medication_name'],
            'dosage': p['dosage'],
            'frequency': p['frequency'],
          },
        )
        .toList();

    try {
      final aiService = ref.read(aiServiceProvider);
      final response = await aiService.chatDetailed(
        query,
        languageCode: _languageCode,
        conversationHistory: _conversationHistory,
        healthContext: {
          'abnormal_labs': abnormalLabs,
          'active_prescriptions': activePrescriptions,
          'known_conditions': conditions,
        },
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          Message(
            text: response.text,
            isUser: false,
            timestamp: DateTime.now(),
            metadata: response,
          ),
        );
      });
      if (response.criticalAlerts.isNotEmpty) {
        final reminders = response.criticalAlerts
            .map((alert) => '${alert.testName}: ${alert.details}')
            .toList(growable: false);
        ref.read(hasPendingEscalationProvider.notifier).state = true;
        ref.read(pendingEscalationNotesProvider.notifier).state = reminders;
      }
      _conversationHistory.add({'role': 'user', 'content': query});
      _conversationHistory.add({'role': 'assistant', 'content': response.text});
      if (_conversationHistory.length > 24) {
        _conversationHistory.removeRange(0, _conversationHistory.length - 24);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          Message(
            text:
                "I'm sorry, I couldn't reach the AI service. Please try again.",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: GlassCard(
            margin: const EdgeInsets.symmetric(vertical: 24),
            padding: const EdgeInsets.all(24),
            opacity: 0.05,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageBubble(_messages[index]),
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(height: 16),
                _buildSuggestions(),
                const SizedBox(height: 12),
                _buildInputArea(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    final labResults = ref.watch(labResultsProvider).value ?? [];
    final prescriptions = ref.watch(prescriptionsProvider).value ?? [];

    final suggestions = <String>{
      'How can I improve my immunity?',
      'Explain my latest lab report',
      'What foods should I avoid?',
    };

    for (final report in labResults) {
      if (report.testResults != null) {
        for (final test in report.testResults!) {
          if (test.status.toLowerCase() == 'high') {
            suggestions.add('How to lower ${test.name}?');
            suggestions.add('Diet for high ${test.name}');
          } else if (test.status.toLowerCase() == 'low') {
            suggestions.add('How to increase ${test.name}?');
          }
        }
      }
    }

    for (final p in prescriptions) {
      if (p['is_active'] == true) {
        suggestions.add('Side effects of ${p['medication_name']}');
        suggestions.add('Interactions with ${p['medication_name']}');
      }
    }

    final initialList = suggestions.take(5).toList();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: initialList.length,
        separatorBuilder: (c, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(initialList[index]),
            backgroundColor: const Color(0xFFEEF2FF),
            labelStyle: const TextStyle(color: AppColors.primary, fontSize: 12),
            onPressed: () {
              _controller.text = initialList[index];
              _sendMessage();
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.transparent),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final title =
        _uiLabels['chatTitle_$_languageCode'] ?? _uiLabels['chatTitle_en']!;
    final subtitle =
        _uiLabels['chatSubtitle_$_languageCode'] ??
        _uiLabels['chatSubtitle_en']!;
    return Row(
      children: [
        GlassCard(
          padding: const EdgeInsets.all(12),
          opacity: 0.1,
          child: const Icon(
            FontAwesomeIcons.robot,
            size: 24,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.secondary, fontSize: 14),
            ),
          ],
        ),
        const Spacer(),
        DropdownButton<String>(
          value: _languageCode,
          underline: const SizedBox.shrink(),
          items: _languageLabels.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _languageCode = value);
          },
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Message message) {
    final metadata = message.metadata;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.primary : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : Colors.black87,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (!message.isUser && metadata != null) ...[
              const SizedBox(height: 12),
              _buildCitationChips(metadata.citations),
              const SizedBox(height: 10),
              _buildConfidencePanel(metadata.confidence),
              if (metadata.followUpPlan.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildFollowUpPlan(metadata.followUpPlan),
              ],
              if (metadata.medicationInteractions.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildInteractionPanel(metadata.medicationInteractions),
              ],
              if (metadata.criticalAlerts.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildCriticalAlertPanel(metadata.criticalAlerts),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCitationChips(List<ChatCitation> citations) {
    if (citations.isEmpty) {
      return const Text(
        'No source citations were detected in this answer.',
        style: TextStyle(fontSize: 12, color: AppColors.secondary),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: citations
          .map((citation) {
            return ActionChip(
              label: Text('Source: ${citation.sourceTag}'),
              avatar: const Icon(Icons.link, size: 16),
              onPressed: () => _openCitation(citation),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildConfidencePanel(ChatConfidence confidence) {
    final color = confidence.level == 'High'
        ? AppColors.success
        : (confidence.level == 'Medium' ? AppColors.warning : AppColors.danger);
    final pct = (confidence.score * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why this advice: ${confidence.level} confidence ($pct%)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            confidence.rationale,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          ...confidence.factors
              .take(3)
              .map(
                (factor) => Text(
                  '- $factor',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCriticalAlertPanel(List<CriticalAlert> alerts) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Critical value alert',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          ...alerts
              .take(3)
              .map(
                (alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- ${alert.testName}: ${alert.details}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showEscalationWorkflow,
            icon: const Icon(Icons.local_hospital),
            label: const Text('Open clinician escalation workflow'),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionPanel(List<MedicationLabInteraction> interactions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Medication-lab interactions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          ...interactions
              .take(4)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '- ${item.medication} ↔ ${item.labMarker}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '  ${item.explanation} ${item.recommendation}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        '  Severity: ${(item.severityScore * 100).round()}% (${item.severity}) • ${item.provenance}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFollowUpPlan(List<String> plan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personalized follow-up plan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 8),
          ...plan.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '- $step',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCitation(ChatCitation citation) async {
    final reports = ref.read(labResultsProvider).value ?? [];
    if (reports.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reports are available to open.')),
      );
      return;
    }

    final targetReport = citation.docId == null
        ? reports.first
        : reports.firstWhere(
            (report) => report.id == citation.docId,
            orElse: () => reports.first,
          );

    ref.read(selectedReportProvider.notifier).state = targetReport;
    ref.read(selectedCitationSourceProvider.notifier).state = citation;
    if (citation.hintedTestName != null &&
        citation.hintedTestName!.isNotEmpty) {
      final matched = targetReport.testResults?.firstWhere(
        (test) =>
            test.name.toLowerCase() == citation.hintedTestName!.toLowerCase(),
        orElse: () => TestResult(
          name: '',
          loinc: '',
          result: '',
          unit: '',
          reference: '',
          status: '',
        ),
      );
      if (matched != null && matched.name.isNotEmpty) {
        ref.read(selectedTestProvider.notifier).state = matched;
      }
    }
    ref.read(navigationProvider.notifier).state = NavItem.resultExpanded;
  }

  Future<void> _completeEscalationChecklist() async {
    if (!mounted) return;
    ref.read(hasPendingEscalationProvider.notifier).state = false;
    ref.read(pendingEscalationNotesProvider.notifier).state = <String>[];
    await ref
        .read(auditServiceProvider)
        .log(
          AuditAction.escalationChecklistCompleted,
          details: 'Escalation checklist completed in chat.',
        );
    await NotificationService().scheduleOneTimeReminder(
      reminderId: 'critical-escalation-followup',
      title: 'Critical alert follow-up',
      body: 'If you have not yet contacted your clinician, do so now.',
      delay: const Duration(hours: 4),
    );
    await ref
        .read(auditServiceProvider)
        .log(
          AuditAction.criticalAlertReminderScheduled,
          details: '4-hour escalation reminder scheduled.',
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Escalation checklist completed. Please contact your clinician now.',
        ),
      ),
    );
  }

  Future<void> _showEscalationWorkflow() async {
    if (!mounted) return;
    await ref
        .read(auditServiceProvider)
        .log(
          AuditAction.escalationStarted,
          details: 'Escalation dialog opened',
        );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final requiredDone = _escalationSteps
              .where((s) => s.required)
              .every((s) => s.done);
          return AlertDialog(
            title: const Text('Clinician Escalation Workflow'),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use this checklist before and during escalation.',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 10),
                  ..._escalationSteps.map(
                    (step) => CheckboxListTile(
                      value: step.done,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(step.title),
                      subtitle: step.required
                          ? const Text('Required')
                          : const Text('Optional'),
                      onChanged: (checked) {
                        setLocalState(() => step.done = checked ?? false);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: requiredDone
                    ? () async {
                        Navigator.pop(context);
                        await _completeEscalationChecklist();
                      }
                    : null,
                child: const Text('Mark Ready for Escalation'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputArea() {
    final inputHint =
        _uiLabels['inputHint_$_languageCode'] ?? _uiLabels['inputHint_en']!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: inputHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _isLoading ? null : _sendMessage,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Icon(Icons.send),
        ),
      ],
    );
  }
}
