import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/navigation.dart';
import '../core/providers.dart';
import '../core/services/upload_service.dart';
import '../core/theme.dart';
import '../features/shared/ambient_background.dart';
import 'navigation/floating_dock.dart';
import 'navigation/app_navbar.dart';
import '../features/home/dashboard_page.dart';
import '../features/lab_results/results_list_page.dart';
import '../features/lab_results/result_detail_page.dart';
import '../features/lab_results/result_expanded_page.dart';
import '../features/trends/trends_page.dart';
import '../features/conditions/conditions_page.dart';
import '../features/prescriptions/prescriptions_page.dart';
import '../features/settings/settings_page.dart';

import '../features/notifications/notifications_page.dart';
import '../features/chat/health_chat_page.dart';
import '../features/auth/login_page.dart';
import '../features/share/share_results_page.dart';
import 'onboarding_overlay.dart';
import 'offline_banner.dart';
import '../features/lab_results/comparison_page.dart';
import '../features/optimization/recipes_page.dart';
import '../features/home/landing_page.dart';
import '../features/admin/admin_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainLayout extends ConsumerStatefulWidget {
  final Widget child;
  const MainLayout({super.key, required this.child});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  String _email = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authServiceProvider).currentUser;
      if (mounted && user != null) {
        setState(() {
          _email = user.email ?? '';
        });

        // Fix: If user is logged in but nav state is default (landing/auth), go to dashboard
        final currentNav = ref.read(navigationProvider);
        if (currentNav == NavItem.landing || currentNav == NavItem.auth) {
          ref.read(navigationProvider.notifier).state = NavItem.dashboard;
        }
      }
    });
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTour = prefs.getBool('has_seen_tour') ?? false;
    final currentUser = ref.read(authServiceProvider).currentUser;
    if (!hasSeenTour && currentUser != null) {
      ref.read(showOnboardingProvider.notifier).state = true;
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_tour', true);
    ref.read(showOnboardingProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final currentNav = ref.watch(navigationProvider);
    final uploadState = ref.watch(uploadControllerProvider);

    return Stack(
      children: [
        AmbientBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                const OfflineBanner(),
                if (currentNav == NavItem.auth)
                  const Expanded(child: LoginPage())
                else ...[
                  if (currentNav == NavItem.landing) _buildLandingNavbar(),

                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 800;
                        final showDock = currentNav != NavItem.landing;

                        final contentBody = Column(
                          children: [
                            if (uploadState.isUploading)
                              LinearProgressIndicator(
                                value: uploadState.progress > 0
                                    ? uploadState.progress / 100
                                    : null,
                                backgroundColor: const Color(
                                  0xFF00F0FF,
                                ).withValues(alpha: 0.2), // Cyan 20%
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00F0FF), // Cyan
                                ),
                              ),
                            if (uploadState.isUploading &&
                                uploadState.status != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  0,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    uploadState.status!,
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            if (currentNav != NavItem.landing)
                              AppNavbar(email: _email),
                            Expanded(
                              child: Padding(
                                padding: currentNav == NavItem.landing
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.all(24.0),
                                child: _getPageContent(currentNav),
                              ),
                            ),
                          ],
                        );

                        if (isDesktop && showDock) {
                          return Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 24),
                                child: Center(child: FloatingDock()),
                              ),
                              Expanded(child: contentBody),
                            ],
                          );
                        }

                        return Stack(
                          children: [
                            contentBody,
                            if (showDock)
                              const Positioned(
                                bottom: 24,
                                left: 0,
                                right: 0,
                                child: Center(child: FloatingDock()),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (ref.watch(showOnboardingProvider))
          OnboardingOverlay(onComplete: _completeOnboarding),
      ],
    );
  }

  Widget _buildLandingNavbar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Clear Health',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  ref.read(isSignUpModeProvider.notifier).state = false;
                  ref.read(navigationProvider.notifier).state = NavItem.auth;
                },
                child: const Text(
                  'Log in',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: () {
                  ref.read(isSignUpModeProvider.notifier).state = true;
                  ref.read(navigationProvider.notifier).state = NavItem.auth;
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D2D2D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Get Started',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getPageContent(NavItem item) {
    switch (item) {
      case NavItem.landing:
        return const LandingPage();
      case NavItem.dashboard:
        return const DashboardPage();
      case NavItem.labResults:
        return const ResultsListPage();
      case NavItem.trends:
        return const TrendsPage();
      case NavItem.conditions:
        return const ConditionsPage();
      case NavItem.prescriptions:
        return const PrescriptionsPage();

      case NavItem.settings:
        return const SettingsPage();
      case NavItem.notifications:
        return const NotificationsPage();
      case NavItem.resultDetail:
        return const ResultDetailPage();
      case NavItem.resultExpanded:
        return const ResultExpandedPage();
      case NavItem.healthChat:
        return const HealthChatPage();
      case NavItem.shareResults:
        return const ShareResultsPage();
      case NavItem.comparison:
        return const ComparisonPage();
      case NavItem.healthOptimization:
        return const RecipesPage();
      case NavItem.admin:
        return const AdminPage();
      default:
        return Center(child: Text('${item.name} Content - Coming Soon'));
    }
  }
}
