import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';

import '../../core/services/upload_service.dart';
import '../glass_card.dart';
import '../ocr_review_dialog.dart';

class FloatingDock extends ConsumerStatefulWidget {
  const FloatingDock({super.key});

  @override
  ConsumerState<FloatingDock> createState() => _FloatingDockState();
}

class _FloatingDockState extends ConsumerState<FloatingDock> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;
    final navItems = _getNavItems();

    return GlassCard(
      opacity: 0.2, // Higher opacity for dock
      blur: 15,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 12 : 24,
        vertical: isDesktop ? 24 : 12,
      ),
      child: Flex(
        direction: isDesktop ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(navItems.length, (index) {
          final item = navItems[index];
          return _buildDockItem(context, index, item, isDesktop);
        }),
      ),
    );
  }

  Widget _buildDockItem(
    BuildContext context,
    int index,
    _DockItem item,
    bool isVertical,
  ) {
    final currentNav = ref.watch(navigationProvider);
    final isSelected =
        item.navItem == currentNav ||
        (item.navItem == NavItem.labResults &&
            (currentNav == NavItem.resultDetail ||
                currentNav == NavItem.resultExpanded));

    final isHovered = _hoveredIndex == index;

    // Upload special case
    if (item.isAction) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: isVertical ? 8 : 0,
          horizontal: isVertical ? 0 : 8,
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = index),
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            tween: Tween(begin: 1.0, end: isHovered ? 1.2 : 1.0),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: AppColors.primaryBrand,
                  onPressed: item.onTap ?? () {},
                  child: Icon(item.icon, size: 20, color: Colors.black),
                ),
              );
            },
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: Tooltip(
        message: item.label,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          tween: Tween(begin: 1.0, end: isHovered ? 1.2 : 1.0),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: isSelected
                  ? 1.1
                  : scale, // Selected items are slightly larger
              child: GestureDetector(
                onTap: () {
                  if (item.navItem != null) {
                    ref.read(navigationProvider.notifier).state = item.navItem!;
                  }
                },
                child: Container(
                  margin: EdgeInsets.symmetric(
                    vertical: isVertical ? 8 : 0,
                    horizontal: isVertical ? 0 : 8,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primaryBrand.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    item.icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primaryBrand
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.black54),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<_DockItem> _getNavItems() {
    return [
      _DockItem(
        icon: FontAwesomeIcons.house,
        label: 'Dashboard',
        navItem: NavItem.dashboard,
      ),
      _DockItem(
        icon: FontAwesomeIcons.vial,
        label: 'Lab Results',
        navItem: NavItem.labResults,
      ),
      _DockItem(
        icon: FontAwesomeIcons.chartLine,
        label: 'Trends',
        navItem: NavItem.trends,
      ),
      _DockItem(
        icon: FontAwesomeIcons.heartPulse,
        label: 'Conditions',
        navItem: NavItem.conditions,
      ),
      _DockItem(
        icon: FontAwesomeIcons.pills,
        label: 'Prescriptions',
        navItem: NavItem.prescriptions,
      ),
      _DockItem(
        icon: FontAwesomeIcons.robot,
        label: 'Ask LabSense',
        navItem: NavItem.healthChat,
      ),
      _DockItem(
        icon: FontAwesomeIcons.shareFromSquare,
        label: 'Share Results',
        navItem: NavItem.shareResults,
      ),
      _DockItem(
        icon: FontAwesomeIcons.leaf,
        label: 'Optimization',
        navItem: NavItem.healthOptimization,
      ),
      // Divider-like spacer logic could be added here if needed,
      // but for simplicity we assume action is at end or handled separately.
      _DockItem(
        icon: FontAwesomeIcons.upload,
        label: 'Upload',
        isAction: true,
        onTap: () => _handleUpload(context, ref),
      ),
      _DockItem(
        icon: FontAwesomeIcons.gear,
        label: 'Settings',
        navItem: NavItem.settings,
      ),
    ];
  }

  Future<void> _handleUpload(BuildContext context, WidgetRef ref) async {
    try {
      final uploadNotifier = ref.read(uploadControllerProvider.notifier);
      final parsedData = await uploadNotifier.pickAndUpload(context);

      if (parsedData == null || !context.mounted) return;

      final confirmedData = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => OcrReviewDialog(initialData: parsedData),
      );

      if (confirmedData != null && context.mounted) {
        await uploadNotifier.saveResult(confirmedData);

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
}

class _DockItem {
  final IconData icon;
  final String label;
  final NavItem? navItem;
  final bool isAction;
  final VoidCallback? onTap;

  _DockItem({
    required this.icon,
    required this.label,
    this.navItem,
    this.isAction = false,
    this.onTap,
  });
}
