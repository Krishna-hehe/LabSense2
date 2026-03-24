import 'package:flutter/foundation.dart';
import '../supabase_service.dart';
import '../cache_service.dart';
import '../models.dart';
import '../storage_service.dart';

class UserRepository {
  final SupabaseService _supabaseService;
  final StorageService _storageService;
  final CacheService _cacheService;

  UserRepository(
    this._supabaseService,
    this._storageService,
    this._cacheService,
  );

  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final data = await _supabaseService.getProfile();
      if (data != null) {
        await _cacheService.cacheProfile(data);
      }
      return data;
    } catch (e) {
      debugPrint('Supabase fetch failed, falling back to cache: $e');
      return _cacheService.getCachedProfile();
    }
  }

  // Phase 3: Family Profiles
  Future<List<UserProfile>> getProfiles() async {
    try {
      final List<Map<String, dynamic>> data = await _supabaseService
          .getProfiles();
      final profiles = data.map((json) => UserProfile.fromJson(json)).toList();
      profiles.sort((a, b) {
        final aIsSelf = a.id == a.userId;
        final bIsSelf = b.id == b.userId;
        if (aIsSelf != bIsSelf) {
          return aIsSelf ? -1 : 1;
        }
        return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });
      return profiles;
    } catch (e) {
      debugPrint('Error fetching profiles: $e');
      return [];
    }
  }

  Future<void> createProfile(UserProfile profile) async {
    await _supabaseService.createProfile(profile.toJson());
  }

  Future<void> deleteProfile(String id) async {
    await _supabaseService.deleteProfile(id);
  }

  Future<List<Map<String, dynamic>>> getPrescriptions() async {
    try {
      final data = await _supabaseService.getPrescriptions();
      await _cacheService.cachePrescriptions(data);
      return data;
    } catch (e) {
      debugPrint('Error fetching prescriptions: $e');
      return _cacheService.getCachedPrescriptions();
    }
  }

  Stream<Map<String, dynamic>?> getProfileStream() =>
      _supabaseService.getProfileStream();

  Future<void> updateProfile(Map<String, dynamic> data) =>
      _supabaseService.updateProfile(data);

  Future<void> saveConditions(List<String> conditions) =>
      _supabaseService.saveConditions(conditions);

  Future<void> addPrescription(Map<String, dynamic> data) =>
      _supabaseService.addPrescription(data);

  Future<void> updatePrescription(String id, Map<String, dynamic> data) =>
      _supabaseService.updatePrescription(id, data);

  Future<void> deletePrescription(String id) =>
      _supabaseService.deletePrescription(id);

  Future<int> getActivePrescriptionsCount() =>
      _supabaseService.getActivePrescriptionsCount();

  Future<List<Map<String, dynamic>>> getNotifications() =>
      _supabaseService.getNotifications();

  Stream<List<Map<String, dynamic>>> getNotificationsStream() =>
      _supabaseService.getNotificationsStream();

  Future<void> markNotificationAsRead(String id) =>
      _supabaseService.markNotificationAsRead(id);

  Future<void> deleteAccountData() => _supabaseService.deleteAccountData();

  Future<String?> uploadProfilePhoto(String profileId, Uint8List bytes) async {
    try {
      final url = await _storageService.uploadProfilePhoto(profileId, bytes);
      if (url != null) {
        await _supabaseService.updateProfileData(profileId, {
          'avatar_url': url,
        });
      }
      return url;
    } catch (e) {
      debugPrint('Error uploading profile photo: $e');
      return null;
    }
  }

  Future<String> generateShareLink() => _supabaseService.generateShareLink();
}
