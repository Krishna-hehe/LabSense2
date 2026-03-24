import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/theme.dart';
import '../../../core/navigation.dart';
import '../../../core/providers.dart';
import '../../../core/services/upload_service.dart';
import '../ocr_review_dialog.dart';
import 'profile_switcher.dart';

class AppSidebar extends ConsumerWidget {
  final NavItem currentNav;

  const AppSidebar({super.key, required this.currentNav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Optional: small logo in sidebar
                // Image.asset('assets/images/logo.png', width: 24, height: 24),
                // SizedBox(width: 8),
                Text(
                  'Clear Health',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          _buildUserCard(context, ref),
          const SizedBox(height: 24),
          _buildUploadButton(context, ref),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.dashboard,
                  FontAwesomeIcons.house,
                  'Dashboard',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.labResults,
                  FontAwesomeIcons.vial,
                  'Lab Results',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.trends,
                  FontAwesomeIcons.chartLine,
                  'Trends',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.conditions,
                  FontAwesomeIcons.heartPulse,
                  'Conditions',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.prescriptions,
                  FontAwesomeIcons.pills,
                  'Prescriptions',
                ),

                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.healthChat,
                  FontAwesomeIcons.robot,
                  'Ask Clear Health',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.shareResults,
                  FontAwesomeIcons.shareFromSquare,
                  'Share Results',
                ),
                _buildSidebarItem(
                  context,
                  ref,
                  NavItem.healthOptimization,
                  FontAwesomeIcons.leaf,
                  'Optimization',
                ),
              ],
            ),
          ),
          _buildSidebarItem(
            context,
            ref,
            NavItem.settings,
            FontAwesomeIcons.gear,
            'Settings',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(selectedProfileProvider);

    return profileAsync.when(
      data: (profile) {
        final name = profile?.fullName ?? 'Clear Health User';
        final avatarUrl = profile?.avatarUrl;
        final avatarColor = profile != null
            ? Color(int.parse(profile.avatarColor))
            : const Color(0xFFF3F4F6);
        final relationship = profile?.relationship ?? 'Personal';

        return InkWell(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black26,
              builder: (context) => Center(
                child: Hero(
                  tag: 'profile-switcher',
                  child: const ProfileSwitcher(),
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                Hero(
                  tag: 'profile-avatar',
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    backgroundColor: avatarColor,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(
                            (profile?.firstName[0] ?? 'L').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        relationship,
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.unfold_more_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, s) => const SizedBox.shrink(),
    );
  }

  Widget _buildUploadButton(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(uploadControllerProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            icon: const Icon(FontAwesomeIcons.upload, size: 14),
            label: const Text('Upload Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: uploadState.isUploading
                ? null
                : () => _handleUpload(context, ref),
          ),
          if (uploadState.isUploading && uploadState.status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                '${uploadState.status!} (${uploadState.progress.toStringAsFixed(0)}%)',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleUpload(BuildContext context, WidgetRef ref) async {
    try {
      final parsedData = await ref
          .read(uploadControllerProvider.notifier)
          .pickAndUpload(context);

      if (parsedData == null || !context.mounted) return;

      // 3. Review Step (We need the dialog widget which is still in MainLayout or move it)
      // For now, let's assume it's moved to a shared widget or accessible.
      // I will move _OcrReviewDialog to lib/widgets/ocr_review_dialog.dart next.

      final confirmedData = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => OcrReviewDialog(initialData: parsedData),
      );

      if (confirmedData != null && context.mounted) {
        await ref
            .read(uploadControllerProvider.notifier)
            .saveResult(confirmedData);

        final postSaveState = ref.read(uploadControllerProvider);
        if (context.mounted) {
          if (postSaveState.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(postSaveState.error!),
                backgroundColor: AppColors.warning,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Lab report added successfully!'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildSidebarItem(
    BuildContext context,
    WidgetRef ref,
    NavItem item,
    IconData icon,
    String title,
  ) {
    bool isSelected =
        item == currentNav ||
        (item == NavItem.labResults &&
            (currentNav == NavItem.resultDetail ||
                currentNav == NavItem.resultExpanded));

    return InkWell(
      onTap: () => ref.read(navigationProvider.notifier).state = item,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.secondary,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
