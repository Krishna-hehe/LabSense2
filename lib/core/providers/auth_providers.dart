import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

import 'core_providers.dart';

// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(supabaseClientProvider),
    ref.watch(auditServiceProvider),
  );
});

// Auth State Provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).onAuthStateChange;
});

// Direct session fallback so web UI does not stay stuck if auth stream stalls.
final directCurrentUserProvider = Provider<User?>((ref) {
  return ref.watch(authServiceProvider).currentUser;
});

// Current User Provider
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.session?.user;
});

// App initialization state
final isAuthLoadingProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isLoading;
});

// Guardrail timeout to prevent indefinite splash on stalled auth stream.
final authLoadingTimeoutProvider = FutureProvider<bool>((ref) async {
  await Future<void>.delayed(const Duration(seconds: 6));
  return true;
});
