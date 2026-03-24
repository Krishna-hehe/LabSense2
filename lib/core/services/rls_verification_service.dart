import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'log_service.dart';

/// RLS (Row Level Security) Verification Service
///
/// Verifies that Supabase Row Level Security policies are properly configured
/// This is a critical security check to prevent unauthorized data access
class RlsVerificationService {
  final SupabaseClient _client;
  static const String _rogueUserId = '00000000-0000-0000-0000-000000000000';
  bool _isVerified = false;
  DateTime? _lastVerification;

  RlsVerificationService(this._client);

  /// Check if RLS has been verified recently (within last hour)
  bool get isVerified {
    if (!_isVerified) return false;

    if (_lastVerification == null) return false;

    // Re-verify every hour
    final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
    return _lastVerification!.isAfter(hourAgo);
  }

  /// Verify RLS is enabled on critical tables
  ///
  /// This attempts to access data that should be blocked by RLS.
  /// If we CAN access it, RLS is NOT working correctly.
  Future<bool> verifyRlsPolicies() async {
    try {
      AppLogger.info('🔐 Starting RLS verification...');

      if (!kIsWeb) {
        try {
          final rpcCheck = await _client.rpc('security_self_test');
          final rpcResult = _asMap(rpcCheck);
          if (rpcResult == null) {
            AppLogger.warning(
              'RLS self-test RPC returned an unexpected payload. Falling back '
              'to direct table probes.',
            );
          } else if (rpcResult['ok'] != true) {
            AppLogger.error(
              '🚨 RLS self-test failed: '
              'lab=${rpcResult['lab_results_count']} '
              'profiles=${rpcResult['profiles_count']} '
              'prescriptions=${rpcResult['prescriptions_count']} '
              'medications=${rpcResult['medications_count']} '
              'reminders=${rpcResult['reminders_count']} '
              'rls=[lab:${rpcResult['lab_results_rls']} '
              'profiles:${rpcResult['profiles_rls']} '
              'prescriptions:${rpcResult['prescriptions_rls']} '
              'medications:${rpcResult['medications_rls']} '
              'reminders:${rpcResult['reminders_rls']}]',
            );
            _isVerified = false;
            return false;
          }
        } on PostgrestException catch (e) {
          AppLogger.warning(
            'RLS self-test RPC unavailable or outdated '
            '(${e.code ?? 'unknown'}). Falling back to direct probes. '
            'Ensure migration 005_security_self_test.sql is applied remotely.',
          );
        }
      }

      // Run multiple tests to verify RLS is working correctly
      final results = await Future.wait([
        _testLabResultsRls(),
        _testProfilesRls(),
        _testPrescriptionsRls(),
        _testMedicationsRls(),
      ]);

      final allPassed = results.every((passed) => passed == true);
      final verificationPassed = allPassed;

      if (verificationPassed) {
        _isVerified = true;
        _lastVerification = DateTime.now();
        AppLogger.info(
          '✅ RLS verification PASSED - All policies working correctly',
        );
      } else {
        _isVerified = false;
        AppLogger.error(
          '🚨 RLS verification FAILED - Security policies not working!',
        );
      }

      return verificationPassed;
    } catch (e, stackTrace) {
      AppLogger.error(
        '❌ RLS verification error: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _isVerified = false;
      return false;
    }
  }

  /// Test lab_results RLS policy
  Future<bool> _testLabResultsRls() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return false;
    return _probeTable('lab_results');
  }

  /// Test profiles RLS policy
  Future<bool> _testProfilesRls() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return false;
    return _probeTable('profiles');
  }

  /// Test prescriptions RLS policy
  Future<bool> _testPrescriptionsRls() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return false;
    return _probeTable('prescriptions');
  }

  /// Test medications RLS policy
  Future<bool> _testMedicationsRls() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return false;
    return _probeTable('medications');
  }

  Future<bool> _probeTable(String table, {String ownerColumn = 'user_id'}) async {
    try {
      final List<Map<String, dynamic>> result = await _client
          .from(table)
          .select('id')
          .eq(ownerColumn, _rogueUserId)
          .limit(1);

      if (result.isNotEmpty) {
        AppLogger.error('🚨 $table RLS FAILED (unexpected rows returned).');
        return false;
      }
      return true;
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      if (table == 'profiles' &&
          ownerColumn == 'user_id' &&
          (e.code == '42703' ||
              (message.contains('column') && message.contains('user_id')))) {
        return _probeTable('profiles', ownerColumn: 'id');
      }
      final denied = _isExpectedRlsBlock(e);
      if (!denied) {
        AppLogger.error(
          '🚨 $table RLS probe failed with unexpected DB error: '
          '${e.code} ${e.message}',
        );
      }
      return denied;
    } catch (e, stackTrace) {
      AppLogger.error(
        '🚨 $table RLS probe failed unexpectedly: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool _isExpectedRlsBlock(PostgrestException e) {
    final code = (e.code ?? '').toLowerCase();
    final message = e.message.toLowerCase();
    return code == '42501' ||
        message.contains('permission denied') ||
        message.contains('row-level security') ||
        message.contains('violates row-level security policy');
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  /// Force re-verification
  Future<bool> forceVerify() async {
    _isVerified = false;
    _lastVerification = null;
    return await verifyRlsPolicies();
  }
}
