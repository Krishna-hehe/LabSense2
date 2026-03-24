import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../core/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_shimmer.dart';

class ShareResultsPage extends ConsumerStatefulWidget {
  const ShareResultsPage({super.key});

  @override
  ConsumerState<ShareResultsPage> createState() => _ShareResultsPageState();
}

class _ShareResultsPageState extends ConsumerState<ShareResultsPage> {
  // New Form State
  bool _shareLabSummary = true;
  bool _shareDownloadReports = false;
  bool _shareMedicalConditions = false;
  bool _sharePrescriptions = false;
  String? _selectedRelationship = 'Healthcare Provider';
  String _selectedExpiration = '7 days';

  bool _isGenerating = false;

  final List<String> _expirationOptions = [
    'One Time',
    '7 days',
    '30 days',
    '90 days',
    'Never',
  ];
  final List<String> _relationships = [
    'Healthcare Provider',
    'Family Member',
    'Insurance Provider',
    'Fitness Coach',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background Decoration
        Positioned(
          top: -100,
          right: -100,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBrand.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 50,
          left: -50,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.1),
              ),
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          tween: Tween(begin: 0.1, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildCreateShareForm(),
                  const SizedBox(height: 16),
                  _buildSecureSharingTip(),
                  const SizedBox(height: 32),
                  _buildActiveSharesSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBrand,
                    AppColors.primaryBrand.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBrand.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.ios_share, color: Colors.black, size: 24),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share Results',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.lightTextPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Grant secure health record access',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.lightTextSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBrand,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: const Row(
            children: [
              Icon(Icons.add, size: 20),
              SizedBox(width: 8),
              Text(
                'Create Share',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreateShareForm() {
    return GlassCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primaryBrand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Create New Share',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // What to share
          const Text(
            'SELECT DATA ACCESS',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.lightTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _buildCheckbox(
            'Lab Summary & Results',
            _shareLabSummary,
            (v) => setState(() => _shareLabSummary = v!),
          ),
          _buildCheckbox(
            'Download PDF Reports',
            _shareDownloadReports,
            (v) => setState(() => _shareDownloadReports = v!),
          ),
          _buildCheckbox(
            'Medical Conditions History',
            _shareMedicalConditions,
            (v) => setState(() => _shareMedicalConditions = v!),
          ),
          _buildCheckbox(
            'Active Prescriptions',
            _sharePrescriptions,
            (v) => setState(() => _sharePrescriptions = v!),
          ),

          const SizedBox(height: 32),

          // Relationship
          const Text(
            'RECIPIENT TYPE',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.lightTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.lightBorder.withValues(alpha: 0.5),
              ),
              color: Colors.white.withValues(alpha: 0.3),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedRelationship,
                isExpanded: true,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.primaryBrand,
                ),
                items: _relationships
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedRelationship = val),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Expiration
          const Text(
            'LINK EXPIRATION',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.lightTextSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _expirationOptions
                .map((opt) => _buildExpirationPill(opt))
                .toList(),
          ),

          const SizedBox(height: 48),

          // Footer Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    side: BorderSide(color: AppColors.lightBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.lightTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBrand.withValues(alpha: 0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isGenerating
                        ? null
                        : _generateSecureLinkRedesigned,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBrand,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Generate Secure Link',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              height: 24,
              width: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? AppColors.primaryBrand : AppColors.lightBorder,
                  width: 2,
                ),
                color: value ? AppColors.primaryBrand : Colors.transparent,
              ),
              child: value
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: value
                    ? AppColors.lightTextPrimary
                    : AppColors.lightTextSecondary,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpirationPill(String label) {
    final isSelected = _selectedExpiration == label;
    return InkWell(
      onTap: () => setState(() => _selectedExpiration = label),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBrand
              : Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBrand
                : AppColors.lightBorder.withValues(alpha: 0.5),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBrand.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : AppColors.lightTextPrimary,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSecureSharingTip() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      opacity: 0.1,
      blur: 20,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBrand.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryBrand,
              size: 24,
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Sharing',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  'Share links are read-only and automatically expire based on your selection. No one can edit your original health records.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSharesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Active Shares',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
          child: Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    GlassShimmer(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBrand.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.history_toggle_off_rounded,
                      size: 40,
                      color: AppColors.primaryBrand.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'No Active Share Links',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your first secure link above to share your results with others.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.lightTextSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _generateSecureLinkRedesigned() async {
    try {
      setState(() => _isGenerating = true);
      final selectedProfile = ref.read(selectedProfileProvider).value;
      if (selectedProfile == null) {
        throw Exception('No profile selected for sharing.');
      }

      final duration = _durationFromSelection(_selectedExpiration);
      final token = await ref
          .read(supabaseServiceProvider)
          .createShareLink(profileId: selectedProfile.id, duration: duration);
      final link = _buildDoctorViewLink(token);

      if (!mounted) return;
      setState(() => _isGenerating = false);
      _showGeneratedLinkDialog(link);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate secure link: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Duration _durationFromSelection(String selected) {
    switch (selected) {
      case 'One Time':
        return const Duration(minutes: 30);
      case '7 days':
        return const Duration(days: 7);
      case '30 days':
        return const Duration(days: 30);
      case '90 days':
        return const Duration(days: 90);
      case 'Never':
        return const Duration(days: 3650);
      default:
        return const Duration(days: 7);
    }
  }

  String _buildDoctorViewLink(String token) {
    final configuredBase = AppConfig.shareBaseUrl.trim();
    final base = configuredBase.isNotEmpty
        ? configuredBase
        : 'https://labsense.app';
    return '$base/doctor_view?token=$token';
  }

  void _showGeneratedLinkDialog(String link) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBrand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.link,
                      color: AppColors.primaryBrand,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Share Link Created',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Share this secure, read-only link with your healthcare provider or family member.',
                style: TextStyle(
                  color: AppColors.lightTextSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.lightBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  link,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: AppColors.primaryBrand,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: AppColors.lightTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Expires in $_selectedExpiration',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: link));
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard!'),
                            backgroundColor: AppColors.primaryBrand,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBrand,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Copy Link',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
