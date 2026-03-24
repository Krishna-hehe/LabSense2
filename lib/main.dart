import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/app_config.dart';
import 'core/supabase_config.dart';

import 'core/theme.dart';
import 'core/providers.dart';
import 'widgets/main_layout.dart';
import 'core/biometric_service.dart';
import 'features/auth/login_page.dart';
import 'core/notification_service.dart';
import 'core/cache_service.dart';
import 'core/services/session_timeout_manager.dart';
import 'core/services/log_service.dart';
// import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:flutter/foundation.dart';
import 'features/splash/splash_page.dart';
import 'features/share/doctor_view_page.dart';

void main() async {
  // Ensure binding initialized before anything else
  WidgetsFlutterBinding.ensureInitialized();

  runZonedGuarded(
    () {
      // Start the app
      runApp(const ProviderScope(child: AppEntryPoint()));
    },
    (error, stack) {
      Sentry.captureException(error, stackTrace: stack);
      AppLogger.error(
        '🔴 Uncaught error in main zone: $error',
        stackTrace: stack,
      );
    },
  );
}

class AppEntryPoint extends ConsumerStatefulWidget {
  const AppEntryPoint({super.key});

  @override
  ConsumerState<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends ConsumerState<AppEntryPoint> {
  bool _isInitialized = false;
  String _status = 'Initializing...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      // 1. Env is loaded at compile time
      try {
        await dotenv.load(fileName: ".env");
        AppLogger.info('✅ Environment configuration loaded');
      } catch (e) {
        AppLogger.error('❌ Failed to load .env file: $e');
        // Continue, as some might be set via --dart-define (fallback not implemented but good practice)
      }

      // 2. Initialize Sentry
      final sentryDsn = AppConfig.sentryDsn.trim();
      if (sentryDsn.isNotEmpty) {
        unawaited(_initSentry(sentryDsn));
      }

      // 3. Initialize Supabase
      if (mounted) setState(() => _status = 'Connecting to services...');
      try {
        final supabaseUrl = SupabaseConfig.url.trim();
        final supabaseAnonKey = SupabaseConfig.anonKey.trim();
        if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
          throw Exception(
            'Missing Supabase configuration. Set SUPABASE_URL and '
            'SUPABASE_ANON_KEY in .env and rebuild the web app.',
          );
        }
        final isSupabaseHost = Uri.tryParse(supabaseUrl)?.host
                .toLowerCase()
                .contains('supabase.co') ??
            false;
        if (!isSupabaseHost) {
          throw Exception(
            'Invalid SUPABASE_URL ($supabaseUrl). It should look like '
            'https://<project-ref>.supabase.co',
          );
        }
        AppLogger.info('🔌 Initializing Supabase...');
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
        AppLogger.info('✅ Supabase initialized');

        // Set up RLS verification on auth state changes
        _setupRlsVerification();
        _startStartupRlsProbe();
      } catch (e) {
        throw Exception('Failed to connect to backend: $e');
      }

      // 4. Initialize Local Services
      if (mounted) setState(() => _status = 'Starting local services...');

      // Keep cache initialization blocking so dependent providers can safely read boxes.
      await _initCache();
      // Notifications are non-critical at startup and can initialize in background.
      unawaited(_initNotifications());

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e, stack) {
      AppLogger.error('Failed to initialize app', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _initSentry(String sentryDsn) async {
    try {
      await SentryFlutter.init((options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 1.0;
        options.profilesSampleRate = 1.0;
      });
      AppLogger.info('✅ Sentry initialized');
    } catch (e) {
      AppLogger.warning('⚠️ Sentry init failed: $e');
    }
  }

  void _startStartupRlsProbe() {
    unawaited(() async {
      try {
        await ref
            .read(supabaseServiceProvider)
            .verifyRlsEnabled()
            .timeout(const Duration(seconds: 6));
      } on TimeoutException {
        AppLogger.warning('⚠️ Startup RLS probe timed out; continuing app boot.');
      } catch (e) {
        AppLogger.warning('⚠️ Startup RLS probe failed: $e');
      }
    }());
  }

  Future<void> _initNotifications() async {
    if (kIsWeb) {
      AppLogger.info('ℹ️ Skipping notification initialization on web.');
      return;
    }
    try {
      await NotificationService().init();
      AppLogger.info('✅ Notifications initialized');
    } catch (e) {
      AppLogger.warning('⚠️ Notification init failed: $e');
      // Don't block app start for this
    }
  }

  Future<void> _initCache() async {
    try {
      await CacheService().init();
      AppLogger.info('✅ Cache initialized');
    } catch (e) {
      AppLogger.warning('⚠️ Cache init failed: $e');
      // Don't block app start for this
    }
  }

  Widget _buildInitializationErrorApp(String errorText) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Failed',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  errorText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _initApp();
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Set up RLS verification to run when user authenticates
  void _setupRlsVerification() {
    final rlsService = ref.read(rlsVerificationServiceProvider);

    // Verify RLS when user authenticates
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        AppLogger.info('🔐 User authenticated - verifying RLS policies...');

        try {
          final rlsVerified = await rlsService.verifyRlsPolicies();

          if (!rlsVerified) {
            AppLogger.error(
              '🚨 CRITICAL: RLS verification failed! Data may be exposed!',
            );

            // Force sign out to protect data
            Supabase.instance.client.auth.signOut();
          }
        } catch (e) {
          AppLogger.error('❌ RLS verification error: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      final msg = details.exceptionAsString();
      AppLogger.error('Flutter widget error: $msg', stackTrace: details.stack);
      return _buildInitializationErrorApp(msg);
    };

    if (_error != null) {
      return _buildInitializationErrorApp(_error!);
    }

    if (!_isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashPage(statusMessage: _status),
      );
    }

    return const LabSenseApp();
  }
}

class LabSenseApp extends ConsumerWidget {
  const LabSenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthLoading = ref.watch(isAuthLoadingProvider);
    final authLoadingTimedOut =
        ref.watch(authLoadingTimeoutProvider).value ?? false;
    final themeMode = ref.watch(themeProvider);
    final streamCurrentUser = ref.watch(currentUserProvider);
    final directCurrentUser = ref.watch(directCurrentUserProvider);
    final currentUser = streamCurrentUser ?? directCurrentUser;

    if (isAuthLoading && !authLoadingTimedOut) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: const SplashPage(statusMessage: 'Authenticating...'),
      );
    }

    return MaterialApp(
      title: 'Clear Health',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: currentUser == null
          ? const LoginPage()
          : SessionTimeoutManager(
              duration: const Duration(minutes: 5),
              onTimeout: () {
                Supabase.instance.client.auth.signOut();
                ref.read(appLockProvider.notifier).state = false;
              },
              child: const SecurityWrapper(
                child: MainLayout(child: SizedBox()),
              ),
            ),
      onGenerateRoute: (settings) {
        // Handle public doctor link
        if (settings.name != null &&
            settings.name!.startsWith('/doctor_view')) {
          final uri = Uri.parse(settings.name!);
          final token = uri.queryParameters['token'];
          if (token != null) {
            // Import DoctorViewPage at top of file needed
            return MaterialPageRoute(
              builder: (_) => DoctorViewPage(token: token),
            );
          }
        }
        return null; // Fallback to home
      },
    );
  }
}

// Add a simple provider for app lock state
final appLockProvider = StateProvider<bool>((ref) => false);

class SecurityWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const SecurityWrapper({super.key, required this.child});

  @override
  ConsumerState<SecurityWrapper> createState() => _SecurityWrapperState();
}

class _SecurityWrapperState extends ConsumerState<SecurityWrapper>
    with WidgetsBindingObserver {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSecurity();
    _secureScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _secureScreen() async {
    try {
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android)) {
        // await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
      }
    } catch (e) {
      AppLogger.warning('Failed to set secure flags: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(appLockProvider.notifier).state = true;
    }
  }

  Future<void> _checkSecurity() async {
    final enabled = await BiometricService().isEnabled();

    // If biometrics NOT enabled, we don't force lock, but we obey the manual lock provider
    if (!enabled) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // Determine initial lock state
    // For now, assume locked on startup if biometrics enabled
    ref.read(appLockProvider.notifier).state = true;

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _authenticate();
  }

  Future<void> _authenticate() async {
    final success = await BiometricService().authenticate();
    if (success) {
      ref.read(appLockProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = ref.watch(appLockProvider);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (isLocked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: AppColors.secondary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Session Locked',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Clear Health secured for your privacy',
                style: TextStyle(color: AppColors.secondary),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                onPressed: _authenticate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text('Unlock'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Logout option in case they can't unlock
                  Supabase.instance.client.auth.signOut();
                  // Reset lock state so next login isn't weirdly locked immediately unless desired
                  ref.read(appLockProvider.notifier).state = false;
                },
                child: const Text('Log Out'),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
