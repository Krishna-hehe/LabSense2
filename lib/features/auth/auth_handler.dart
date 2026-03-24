import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/audit_service.dart';
import '../../core/navigation.dart';
import '../../core/providers.dart';
import 'login_page_state.dart';

final authHandlerProvider = Provider((ref) => AuthHandler(ref));

class AuthHandler {
  final Ref _ref;

  AuthHandler(this._ref);

  Future<void> handleAuth(
    BuildContext context,
    String email,
    String password,
    String confirmPassword, {
    String? firstName,
  }) async {
    final pageNotifier = _ref.read(loginPageProvider.notifier);
    final pageState = _ref.read(loginPageProvider);

    if (pageState.isSignUp &&
        (!pageState.agreeToTerms || !pageState.acknowledgeHipaa)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to terms and HIPAA guidelines.'),
        ),
      );
      return;
    }

    pageNotifier.setLoading(true);
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw 'Missing backend config. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env, then restart the app.';
      }
      final isSupabaseHost = Uri.tryParse(supabaseUrl)?.host
              .toLowerCase()
              .contains('supabase.co') ??
          false;
      if (!isSupabaseHost) {
        throw 'Invalid SUPABASE_URL in .env. Expected https://<project-ref>.supabase.co';
      }

      final validator = _ref.read(inputValidationServiceProvider);

      // Rate Limiting (5 attempts / 15 mins)
      final rateLimiter = _ref.read(rateLimiterProvider);
      final normalizedEmail = email.trim().toLowerCase();
      final waitTime = rateLimiter.checkLimit(
        'login_attempt:$normalizedEmail',
        limit: 5,
        window: const Duration(minutes: 15),
      );
      if (waitTime != null) {
        throw 'Too many login attempts. Please try again in ${waitTime.inMinutes + 1} minutes.';
      }

      final emailError = validator.validateEmail(email.trim());
      if (emailError != null) throw emailError;

      if (pageState.isSignUp) {
        final passwordError = validator.validatePassword(password);
        if (passwordError != null) throw passwordError;
      } else if (password.isEmpty) {
        throw 'Password is required';
      }

      if (pageState.isSignUp && password != confirmPassword) {
        throw 'Passwords do not match.';
      }

      final authService = _ref.read(authServiceProvider);
      if (pageState.isSignUp) {
        await authService.signUp(email, password, firstName: firstName);
        rateLimiter.reset('login_attempt:$normalizedEmail');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registration successful! Please check your email to verify.',
              ),
            ),
          );
        }
      } else {
        final response = await authService.signIn(email, password);
        rateLimiter.reset('login_attempt:$normalizedEmail');

        if (response.user != null) {
          final factors = await _ref
              .read(supabaseServiceProvider)
              .getMFAFactors();
          final verifiedFactors = factors.all
              .where((f) => f.status == FactorStatus.verified)
              .toList();

          if (verifiedFactors.isNotEmpty) {
            pageNotifier.setMfaChallengeFactorId(verifiedFactors.first.id);
            pageNotifier.setLoading(false);
            return;
          }
        }

        if (context.mounted) {
          _ref.read(navigationProvider.notifier).state = NavItem.dashboard;
        }
      }
    } catch (e) {
      final audit = _ref.read(auditServiceProvider);
      await audit.log(AuditAction.loginFailure, details: e.toString());
      if (context.mounted) {
        String message =
            'Authentication failed. Please check your credentials.';
        if (e is AuthException) {
          message = e.message;
        } else if (e is String) {
          message = e;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      pageNotifier.setLoading(false);
    }
  }

  Future<void> handleMfaVerify(BuildContext context, String mfaCode) async {
    final pageNotifier = _ref.read(loginPageProvider.notifier);
    final pageState = _ref.read(loginPageProvider);

    if (pageState.mfaChallengeFactorId == null || mfaCode.length < 6) return;

    pageNotifier.setLoading(true);
    try {
      await _ref
          .read(supabaseServiceProvider)
          .verifyMFA(factorId: pageState.mfaChallengeFactorId!, code: mfaCode);
      if (context.mounted) {
        _ref.read(navigationProvider.notifier).state = NavItem.dashboard;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MFA Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      pageNotifier.setLoading(false);
    }
  }

  Future<void> handleSocialAuth(BuildContext context, String provider) async {
    final pageNotifier = _ref.read(loginPageProvider.notifier);
    pageNotifier.setLoading(true);
    try {
      final authService = _ref.read(authServiceProvider);
      if (provider == 'Google') {
        await authService.signInWithGoogle();
      } else if (provider == 'Apple') {
        await authService.signInWithApple();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Social Login Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      pageNotifier.setLoading(false);
    }
  }
}
