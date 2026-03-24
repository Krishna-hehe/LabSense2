import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/utils/unit_sanitizer.dart';

import '../../core/theme.dart';
import 'package:intl/intl.dart';

class DoctorViewPage extends ConsumerStatefulWidget {
  final String token;

  const DoctorViewPage({super.key, required this.token});

  @override
  ConsumerState<DoctorViewPage> createState() => _DoctorViewPageState();
}

class _DoctorViewPageState extends ConsumerState<DoctorViewPage> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data = await ref
          .read(supabaseServiceProvider)
          .getSharedData(widget.token);
      if (data.containsKey('error')) {
        setState(() {
          _error = data['error'];
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            'Failed to load shared data. The link may be expired or invalid.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Doctor View - LabSense'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.lightTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_data == null) return const SizedBox.shrink();

    final profile = _data!['profile'] as Map<String, dynamic>;
    final results = (_data!['lab_results'] as List<dynamic>?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPatientCard(profile),
          const SizedBox(height: 32),
          Text(
            'Recent Lab Results (${results.length})',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            const Text('No lab results available for this profile.')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return _buildResultCard(result);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> profile) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary.withAlpha(25),
              child: const Icon(
                Icons.person,
                size: 30,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile['first_name']} ${profile['last_name'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gender: ${profile['gender'] ?? 'N/A'} • DOB: ${profile['date_of_birth'] ?? 'N/A'}',
                  style: const TextStyle(color: AppColors.lightTextSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final date = DateTime.tryParse(result['date']?.toString() ?? '');
    final formattedDate = date != null
        ? DateFormat.yMMMd().format(date)
        : 'Unknown Date';
    final testName = result['lab_name'] ?? result['test_name'] ?? 'Unknown Test';

    // Parse test results to find abnormalities
    final testItems = result['test_results'] as List<dynamic>? ?? [];
    final abnormalCount = testItems.where((t) {
      final status = (t['status'] as String? ?? '').toLowerCase();
      return status.contains('high') || status.contains('low');
    }).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          testName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(formattedDate),
        trailing: abnormalCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$abnormalCount Abnormal',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Icon(Icons.check_circle, color: AppColors.success),
        children: [
          ...testItems.map((item) {
            final name = item['test_name'] ?? item['name'] ?? '';
            final value = item['result_value'] ?? item['result'] ?? '';
            final unit = item['unit'] ?? '';
            final range = item['reference_range'] ?? item['reference'] ?? '';
            final status = (item['status'] as String? ?? '').toLowerCase();
            final isAbnormal =
                status.contains('high') || status.contains('low');

            return ListTile(
              title: Text(name),
              subtitle: Text('Ref: $range'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatDisplayValueWithUnit({'value': value, 'unit': unit}),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isAbnormal
                          ? AppColors.danger
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  if (isAbnormal) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 16,
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
