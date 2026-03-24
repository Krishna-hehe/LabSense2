import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../core/providers.dart';
import '../core/utils/unit_sanitizer.dart';

class OcrReviewDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> initialData;

  const OcrReviewDialog({super.key, required this.initialData});

  @override
  ConsumerState<OcrReviewDialog> createState() => _OcrReviewDialogState();
}

class _OcrReviewDialogState extends ConsumerState<OcrReviewDialog> {
  late TextEditingController _labNameController;
  late TextEditingController _dateController;
  late List<Map<String, dynamic>> _testResults;

  @override
  void initState() {
    super.initState();
    _labNameController = TextEditingController(
      text: widget.initialData['lab_name'],
    );
    _dateController = TextEditingController(text: widget.initialData['date']);
    _testResults = List<Map<String, dynamic>>.from(
      (widget.initialData['test_results'] as List).map((t) {
        final map = Map<String, dynamic>.from(t);
        // Normalize keys
        if (map['name'] == null && map['test_name'] != null) {
          map['name'] = map['test_name'];
        }
        if (map['result'] == null && map['result_value'] != null) {
          map['result'] = map['result_value'];
        }
        return map;
      }),
    );
  }

  @override
  void dispose() {
    _labNameController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review Extracted Data'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The AI has extracted the following information. Please verify and correct any errors.',
                style: TextStyle(fontSize: 13, color: AppColors.secondary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildField('Lab Name', _labNameController)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField('Date (YYYY-MM-DD)', _dateController),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Test Results',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              ..._testResults.asMap().entries.map((entry) {
                final idx = entry.key;
                final test = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTestField(
                          'Name',
                          test['name'],
                          (v) => _testResults[idx]['name'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _buildTestField(
                          'Result',
                          test['result'],
                          (v) => _testResults[idx]['result'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: _buildTestField(
                          'Unit',
                          test['unit'],
                          (v) => _testResults[idx]['unit'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () =>
                            setState(() => _testResults.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final validator = ref.read(inputValidationServiceProvider);

            // Validate Top Level
            if (_labNameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lab Name is required')),
              );
              return;
            }
            // Date validation (basic)
            if (_dateController.text.trim().isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Date is required')));
              return;
            }

            // Filter out empty results
            final validTests = _testResults.where((test) {
              return (test['result']?.toString().trim() ?? '').isNotEmpty;
            }).toList();

            if (validTests.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('At least one test result is required'),
                ),
              );
              return;
            }

            // Validate Results & Numbers
            for (var test in validTests) {
              final resultStr = test['result']?.toString() ?? '';
              final err = validator.validateLabValue(resultStr);
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error in ${test['name'] ?? 'Test'}: $err'),
                  ),
                );
                return;
              }
            }

            // Sanitize & Save
            final sourceMarkdown = widget.initialData['source_markdown']
                ?.toString();
            Navigator.pop(context, {
              'lab_name': validator.sanitizeInput(_labNameController.text),
              'date': validator.sanitizeInput(_dateController.text),
              if (sourceMarkdown != null && sourceMarkdown.trim().isNotEmpty)
                'source_markdown': sourceMarkdown,
              'test_results': validTests
                  .map(
                    (t) => {
                      ...t,
                      'name': validator.sanitizeInput(
                        t['name']?.toString() ??
                            t['test_name']?.toString() ??
                            '',
                      ),
                      'test_name': validator.sanitizeInput(
                        t['name']?.toString() ??
                            t['test_name']?.toString() ??
                            '',
                      ),
                       // Result is already validated as number, but keep as string or parse
                       'result': t['result'] ?? t['result_value'],
                       'result_value': t['result'] ?? t['result_value'],
                       'unit':
                           UnitSanitizer.clean(
                             validator.sanitizeInput(
                               t['unit']?.toString() ?? '',
                             ),
                           ) ??
                           '',
                     },
                   )
                   .toList(),
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm & Save'),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildTestField(
    String hint,
    dynamic initialValue,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: TextEditingController(text: initialValue?.toString()),
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
