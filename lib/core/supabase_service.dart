import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'services/log_service.dart';
import 'package:uuid/uuid.dart';
import 'services/input_validation_service.dart';
import 'utils/unit_sanitizer.dart';
import '../core/utils/exceptions.dart';

class SupabaseService {
  final SupabaseClient client;
  final InputValidationService validator;
  static const String _rogueUserId = '00000000-0000-0000-0000-000000000000';

  SupabaseService(this.client, this.validator);

  // RLS Verification
  Future<void> verifyRlsEnabled() async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      AppLogger.info('ℹ️ Skipping startup RLS probe (no authenticated user yet).');
      return;
    }

    try {
      final testResult = await client
          .from('lab_results')
          .select('id')
          .eq('user_id', _rogueUserId)
          .limit(1);

      if (testResult.isNotEmpty) {
        throw SecurityException('RLS verification failed for lab_results.');
      }
      AppLogger.info('✅ Startup RLS probe passed.');
    } on PostgrestException catch (e) {
      if (_isExpectedRlsBlock(e)) {
        AppLogger.info('✅ Startup RLS probe blocked by policy as expected.');
        return;
      }
      throw SecurityException(
        'RLS verification error (${e.code ?? 'unknown'}): ${e.message}',
      );
    }
  }

  // MFA Operations
  Future<AuthMFAEnrollResponse> enrollMFA() async {
    return await client.auth.mfa.enroll(factorType: FactorType.totp);
  }

  Future<AuthMFAVerifyResponse> verifyMFA({
    required String factorId,
    required String code,
  }) async {
    final challenge = await client.auth.mfa.challenge(factorId: factorId);
    return await client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challenge.id,
      code: code,
    );
  }

  Future<void> removeMfaFactor(String factorId) async {
    await client.auth.mfa.unenroll(factorId);
  }

  Future<AuthMFAListFactorsResponse> getMFAFactors() async {
    return await client.auth.mfa.listFactors();
  }

  // Database Operations (Examples)
  Future<List<Map<String, dynamic>>> getLabResults({
    int limit = 10,
    int offset = 0,
    String? profileId,
    String? searchQuery,
  }) async {
    try {
      // Start the query chain
      var queryBuilder = client.from('lab_results').select();

      // Apply filter if needed. Note: eq returns a builder we must capture.
      if (profileId != null && profileId.isNotEmpty) {
        final currentUserId = client.auth.currentUser?.id;
        if (currentUserId != null && profileId == currentUserId) {
          queryBuilder = queryBuilder.or(
            'profile_id.eq.$profileId,profile_id.is.null',
          );
        } else {
          queryBuilder = queryBuilder.eq('profile_id', profileId);
        }
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryBuilder = queryBuilder.ilike('lab_name', '%$searchQuery%');
      }

      // Apply modifiers
      final response = await queryBuilder
          .order('date', ascending: false)
          .range(offset, offset + limit - 1);
      return response;
    } catch (e) {
      AppLogger.debug('Supabase fetch failed: $e');
      rethrow; // Let repository handle fallback
    }
  }

  Future<void> uploadLabResult(Map<String, dynamic> data) async {
    await client.from('lab_results').insert(_sanitizeMap(data));
  }

  Future<void> deleteLabResult(String id) async {
    if (client.auth.currentUser == null) return;
    await client
        .from('lab_results')
        .delete()
        .eq('id', id)
        .eq('user_id', client.auth.currentUser!.id);
  }

  // Profile Management
  Future<Map<String, dynamic>?> getProfile() async {
    if (client.auth.currentUser == null) return null;
    try {
      return await client
          .from('profiles')
          .select()
          .eq('id', client.auth.currentUser!.id)
          .single();
    } catch (e) {
      AppLogger.debug('Supabase fetch failed: $e');
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> getProfileStream() {
    if (client.auth.currentUser == null) return Stream.value(null);
    return client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', client.auth.currentUser!.id)
        .map((data) => data.isNotEmpty ? data.first : null);
  }

  Future<void> saveConditions(List<String> conditions) async {
    if (client.auth.currentUser == null) return;
    await client
        .from('profiles')
        .update({'conditions': conditions})
        .eq('id', client.auth.currentUser!.id);
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;

    // Sanitize input data
    final sanitizedData = _sanitizeMap(data);

    try {
      // Use upsert to create the profile if it doesn't exist
      await client.from('profiles').upsert({
        'id': client.auth.currentUser!.id,
        'user_id': client.auth.currentUser!.id,
        ...sanitizedData,
      });
    } on PostgrestException catch (e) {
      if (!_isLegacyProfilesSchemaError(e)) rethrow;

      AppLogger.warning(
        'Profiles table is on a legacy schema. Retrying profile update with '
        'legacy-safe fields only.',
      );
      await client.from('profiles').upsert({
        'id': client.auth.currentUser!.id,
        ..._legacyProfileFields(sanitizedData),
      });
    }
  }

  Future<void> updateProfileData(String id, Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;
    final sanitizedData = _sanitizeMap(data);
    try {
      await client
          .from('profiles')
          .update(sanitizedData)
          .eq('id', id)
          .eq('user_id', client.auth.currentUser!.id);
    } on PostgrestException catch (e) {
      if (!_isMissingColumnError(e, 'user_id')) rethrow;
      await client.from('profiles').update(sanitizedData).eq('id', id);
    }
  }

  // Phase 3: Family Profiles Support
  Future<List<Map<String, dynamic>>> getProfiles() async {
    if (client.auth.currentUser == null) return [];
    try {
      // Fetch all profiles linked to this user account
      return await client
          .from('profiles')
          .select()
          .eq('user_id', client.auth.currentUser!.id);
    } catch (e) {
      AppLogger.debug('Supabase getProfiles failed: $e');
      // Fallback for transition period: return single profile if generic fetch fails
      // This handles case where schema might not fully support multiple rows yet or column name mismatch
      try {
        final single = await getProfile();
        return single != null ? [single] : [];
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> createProfile(Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;
    // Helper to ensure user_id is set
    final profileData = {
      ..._sanitizeMap(data),
      'user_id': client.auth.currentUser!.id,
    };
    try {
      await client.from('profiles').insert(profileData);
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e, 'user_id')) {
        throw StateError(
          'Family profiles require the profiles schema migration '
          '(006_fix_profiles_family_schema.sql) before they can be created.',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteProfile(String profileId) async {
    if (client.auth.currentUser == null) return;
    try {
      await client
          .from('profiles')
          .delete()
          .eq('id', profileId)
          .eq('user_id', client.auth.currentUser!.id); // Security check
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e, 'user_id')) {
        throw StateError(
          'Family profile deletion requires the profiles schema migration '
          '(006_fix_profiles_family_schema.sql).',
        );
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPrescriptions() async {
    if (client.auth.currentUser == null) return [];
    try {
      return await client
          .from('prescriptions')
          .select()
          .eq('user_id', client.auth.currentUser!.id);
    } catch (e) {
      AppLogger.debug('Error fetching prescriptions: $e');
      rethrow;
    }
  }

  Future<void> addPrescription(Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;
    await client.from('prescriptions').insert({
      ..._sanitizeMap(data),
      'user_id': client.auth.currentUser!.id,
    });
  }

  Future<void> updatePrescription(String id, Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;
    await client
        .from('prescriptions')
        .update(_sanitizeMap(data))
        .eq('id', id)
        .eq('user_id', client.auth.currentUser!.id);
  }

  Future<void> deletePrescription(String id) async {
    if (client.auth.currentUser == null) return;
    await client
        .from('prescriptions')
        .delete()
        .eq('id', id)
        .eq('user_id', client.auth.currentUser!.id);
  }

  // Medication Reminders (Phase 4)
  Future<List<Map<String, dynamic>>> getMedications({String? profileId}) async {
    if (client.auth.currentUser == null) return [];
    try {
      var query = client.from('medications').select('*, reminder_schedules(*)');
      if (profileId != null) {
        query = query.eq('profile_id', profileId);
      } else {
        // Default to fetching for the user if no profile specified, OR fetch all for user
        query = query.eq('user_id', client.auth.currentUser!.id);
      }
      final response = await query;
      return (response as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      AppLogger.debug('Error fetching medications: $e');
      rethrow;
    }
  }

  Future<void> createMedication(Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;

    // transactional insert not easily supported without RPC, so we do two steps or use a single insert with nested data if Supabase supports it (it does for some cases, but safer to do separate for now or RPC).
    // Actually Supabase supports deep inserts if configured, but let's stick to standard inserts for safety.
    // Wait, deep insert is cleaner. Let's try deep insert structure: { ..., reminder_schedules: [...] }
    // functionality depends on Foreign Keys.
    // For now, I'll assume standard separate inserts for reliability.

    final medication = {..._sanitizeMap(data)};
    final schedules = medication.remove('reminder_schedules') as List?;

    final user = client.auth.currentUser!;
    medication['user_id'] = user.id;

    final response = await client
        .from('medications')
        .insert(medication)
        .select()
        .single();
    final medId = response['id'];

    if (schedules != null && schedules.isNotEmpty) {
      final List<Map<String, dynamic>> schedulesData = [];
      for (var s in schedules) {
        schedulesData.add({...s, 'medication_id': medId});
      }
      await client.from('reminder_schedules').insert(schedulesData);
    }
  }

  Future<void> updateMedication(String id, Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return;

    final modification = {..._sanitizeMap(data)};
    final schedules = modification.remove('reminder_schedules') as List?;

    await client.from('medications').update(modification).eq('id', id);

    if (schedules != null) {
      // Replace schedules strategy: Delete all for this medication and re-insert
      // This is simplest for "edit" logic
      await client.from('reminder_schedules').delete().eq('medication_id', id);

      if (schedules.isNotEmpty) {
        final List<Map<String, dynamic>> schedulesData = [];
        for (var s in schedules) {
          schedulesData.add({...s, 'medication_id': id});
        }
        await client.from('reminder_schedules').insert(schedulesData);
      }
    }
  }

  Future<void> deleteMedication(String id) async {
    if (client.auth.currentUser == null) return;
    // Cascade delete should handle schedules if DB configured, but we can delete manually to be safe
    await client.from('reminder_schedules').delete().eq('medication_id', id);
    await client.from('medications').delete().eq('id', id);
  }

  Future<int> getActivePrescriptionsCount() async {
    if (client.auth.currentUser == null) return 0;
    try {
      final response = await client
          .from('prescriptions')
          .select('id')
          .eq('user_id', client.auth.currentUser!.id)
          .eq('is_active', true)
          .count();
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getTrendData(String testName) async {
    if (client.auth.currentUser == null) return [];
    try {
      final results = await getLabResults(limit: 50); // Fetch more for trends
      List<Map<String, dynamic>> trendPoints = [];

      for (var report in results) {
        final date = report['date'];
        final testResults = report['test_results'] as List?;
        if (testResults != null) {
          final match = testResults.firstWhere(
            (t) => (t['test_name'] ?? t['name']) == testName,
            orElse: () => null,
          );
          if (match != null) {
            trendPoints.add({
              'date': date,
              'value':
                  double.tryParse(
                    match['result_value']?.toString() ??
                        match['result']?.toString() ??
                        '0',
                  ) ??
                  0.0,
              'unit': UnitSanitizer.clean(match['unit']?.toString()) ?? '',
              'reference': match['reference_range'] ?? match['reference'],
            });
          }
        }
      }
      // Sort by date ascending for charts
      trendPoints.sort(
        (a, b) =>
            DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])),
      );
      return trendPoints;
    } catch (e) {
      AppLogger.debug('Error fetching trend data: $e');
      return [];
    }
  }

  Future<List<String>> getDistinctTests() async {
    if (client.auth.currentUser == null) return [];
    try {
      final results = await getLabResults(limit: 50);
      Set<String> testNames = {};
      for (var report in results) {
        final testResults = report['test_results'] as List?;
        if (testResults != null) {
          for (var t in testResults) {
            final name = t['test_name'] ?? t['name'];
            if (name != null) testNames.add(name);
          }
        }
      }
      return testNames.toList()..sort();
    } catch (e) {
      AppLogger.debug('Error fetching distinct tests: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    if (client.auth.currentUser == null) return [];
    try {
      final response = await client
          .from('notifications')
          .select()
          .eq('user_id', client.auth.currentUser!.id)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      AppLogger.debug('Error fetching notifications: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> getNotificationsStream() {
    if (client.auth.currentUser == null) return Stream.value([]);
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', client.auth.currentUser!.id)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> markNotificationAsRead(String id) async {
    if (client.auth.currentUser == null) return;
    try {
      await client.from('notifications').update({'is_read': true}).eq('id', id);
    } catch (e) {
      AppLogger.debug('Error marking notification as read: $e');
    }
  }

  Future<String?> createLabResult(Map<String, dynamic> data) async {
    if (client.auth.currentUser == null) return null;
    try {
      final List<dynamic> rawTestResults = data['test_results'] ?? [];
      final List<Map<String, dynamic>> testResults = rawTestResults
          .whereType<Map>()
          .map((t) {
            final row = Map<String, dynamic>.from(t);
            row['unit'] = UnitSanitizer.clean(row['unit']?.toString()) ?? '';
            return row;
          })
          .toList(growable: false);
      final abnormalCount = testResults.where((t) {
        final s = t['status']?.toString().toLowerCase() ?? '';
        return s == 'abnormal' || s == 'high' || s == 'low';
      }).length;

      final status = abnormalCount > 0 ? 'Abnormal' : 'Normal';

      // Sanitize inputs
      final sanitizedLabName = validator.sanitizeInput(
        data['lab_name']?.toString() ?? 'Manual Upload',
      );

      final inserted = await client
          .from('lab_results')
          .insert({
            'user_id': client.auth.currentUser!.id,
            'profile_id':
                data['profile_id']?.toString().isNotEmpty == true
                ? data['profile_id']
                : client.auth.currentUser!.id,
            'lab_name': sanitizedLabName,
            'date':
                data['date'] ?? DateTime.now().toIso8601String().split('T')[0],
            'status': status,
            'test_count': testResults.length,
            'abnormal_count': abnormalCount,
            'test_results': _sanitizeValue(testResults),
            'storage_path': _sanitizeValue(data['storage_path']),
          })
          .select('id')
          .single();

      // Trigger notification
      await NotificationService().showNotification(
        DateTime.now().millisecond,
        'Upload Complete',
        'Your lab report has been successfully processed.',
      );

      return inserted['id']?.toString();
    } catch (e) {
      AppLogger.debug('Error creating lab result: $e');
      rethrow;
    }
  }

  Future<void> deleteAccountData() async {
    if (client.auth.currentUser == null) return;
    await client.rpc('delete_account_data');
  }

  Future<String> generateShareLink() async {
    if (client.auth.currentUser == null) throw Exception('User not logged in');
    final token = await client.rpc<String>('generate_share_link');
    return token;
  }

  Future<void> logAccess({
    required String action,
    String? resourceId,
    Map<String, dynamic>? metadata,
  }) async {
    if (client.auth.currentUser == null) return;
    try {
      await client.from('access_logs').insert({
        'user_id': client.auth.currentUser!.id,
        'action': action,
        'resource_id': resourceId,
        'metadata': metadata,
      });
    } catch (e) {
      AppLogger.debug('Failed to log access: $e');
    }
  }

  // Doctor Mode / Share Link
  Future<String> createShareLink({
    required String profileId,
    Duration duration = const Duration(days: 1),
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to share results');
    }
    if (duration <= Duration.zero) {
      throw const FormatException('Share link duration must be greater than zero');
    }

    final normalizedProfileId = profileId.trim();
    final profileIdRegex = RegExp(r'^[0-9a-fA-F-]{36}$');
    if (!profileIdRegex.hasMatch(normalizedProfileId)) {
      throw const FormatException('Invalid profile identifier');
    }

    final token = const Uuid().v4().replaceAll('-', '');
    final expiresAt = DateTime.now().toUtc().add(duration);

    await client.from('shared_links').insert({
      'user_id': user.id,
      'profile_id': normalizedProfileId,
      'token': token,
      'expires_at': expiresAt.toIso8601String(),
      'permissions': {'view_labs': true}, // Default permissions
    });

    return token;
  }

  Future<Map<String, dynamic>> getSharedData(String token) async {
    final normalizedToken = token.trim();
    final shareTokenRegex = RegExp(r'^[A-Za-z0-9-]{16,128}$');
    if (!shareTokenRegex.hasMatch(normalizedToken)) {
      throw const FormatException('Invalid share token format');
    }
    try {
      final response = await client.rpc(
        'get_shared_data',
        params: {'link_token': normalizedToken},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      AppLogger.debug('Failed to fetch shared data: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _sanitizeValue(value)));
  }

  dynamic _sanitizeValue(dynamic value) {
    if (value is String) {
      return validator.sanitizeForDb(value);
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList();
    }
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _sanitizeValue(nestedValue)),
      );
    }
    return value;
  }

  bool _isExpectedRlsBlock(PostgrestException e) {
    final code = (e.code ?? '').toLowerCase();
    final message = e.message.toLowerCase();
    return code == '42501' ||
        message.contains('permission denied') ||
        message.contains('row-level security') ||
        message.contains('violates row-level security policy');
  }

  bool _isMissingColumnError(PostgrestException e, String column) {
    final code = (e.code ?? '').toLowerCase();
    final message = e.message.toLowerCase();
    return code == '42703' ||
        (message.contains('column') && message.contains(column.toLowerCase()));
  }

  bool _isLegacyProfilesSchemaError(PostgrestException e) {
    return _isMissingColumnError(e, 'user_id') ||
        _isMissingColumnError(e, 'phone_number') ||
        _isMissingColumnError(e, 'state') ||
        _isMissingColumnError(e, 'postal_code') ||
        _isMissingColumnError(e, 'country') ||
        _isMissingColumnError(e, 'email_notifications') ||
        _isMissingColumnError(e, 'result_reminders');
  }

  Map<String, dynamic> _legacyProfileFields(Map<String, dynamic> data) {
    const allowed = {
      'first_name',
      'last_name',
      'relationship',
      'avatar_color',
      'avatar_url',
      'date_of_birth',
      'gender',
      'conditions',
    };
    return Map<String, dynamic>.fromEntries(
      data.entries.where((entry) => allowed.contains(entry.key)),
    );
  }
}
