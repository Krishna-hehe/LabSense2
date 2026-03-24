import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'log_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';

enum AuditAction {
  loginSuccess,
  loginFailure,
  signupSuccess,
  signupFailure,
  googleSignInAttempt,
  appleSignInAttempt,
  viewLabResult,
  uploadLabResult,
  ingestionQueued,
  ingestionFailed,
  deleteLabResult,
  escalationStarted,
  escalationChecklistCompleted,
  criticalAlertReminderScheduled,
}

class AuditService {
  final SupabaseClient? _client;
  bool _remoteLoggingDisabled = false;

  AuditService([this._client]);

  Future<void> log(AuditAction action, {String? details}) async {
    final detailText =
        details != null && details.isNotEmpty ? ' - $details' : '';
    AppLogger.info('AUDIT: ${action.name}$detailText', containsPII: true);

    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return;
    }
    if (kIsWeb) {
      return;
    }
    if (_remoteLoggingDisabled) {
      return;
    }

    try {
      final response = await _invokeAuditLogWithRetry(
        client: client,
        action: action,
        details: details,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('audit-log failed (${response.statusCode}): ${response.body}');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to persist audit event: ${action.name}',
        error: e,
        stackTrace: stackTrace,
      );
      final failureText = e.toString().toLowerCase();
      if (failureText.contains('404') ||
          failureText.contains('401') ||
          failureText.contains('cors') ||
          failureText.contains('failed to fetch') ||
          failureText.contains('function not found') ||
          failureText.contains('unauthorized')) {
        _remoteLoggingDisabled = true;
        AppLogger.warning(
          'Disabling remote audit logging for this session after auth/endpoint failure.',
        );
      }
    }
  }

  Future<http.Response> _invokeAuditLogWithRetry({
    required SupabaseClient client,
    required AuditAction action,
    required String? details,
  }) async {
    final supabaseUrl = AppConfig.supabaseUrl.trim();
    if (supabaseUrl.isEmpty) {
      throw Exception('SUPABASE_URL is missing for audit-log calls.');
    }
    final endpoint = Uri.parse('$supabaseUrl/functions/v1/audit-log');
    final anonKey = AppConfig.supabaseAnonKey.trim();
    if (anonKey.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY is missing for audit-log calls.');
    }

    Future<http.Response> send(String bearerToken) {
      return http
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'apikey': anonKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'action': action.name,
              'details': details,
            }),
          )
          .timeout(const Duration(seconds: 15));
    }

    final initialToken = client.auth.currentSession?.accessToken;
    if (initialToken == null || initialToken.isEmpty) {
      throw Exception('No active session token for audit-log.');
    }

    var response = await send(initialToken);
    if (response.statusCode == 401) {
      final refreshed = await client.auth.refreshSession();
      final refreshedToken = refreshed.session?.accessToken;
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await send(refreshedToken);
      }
    }
    return response;
  }
}
