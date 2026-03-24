import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'services/log_service.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final _secureStorage = const FlutterSecureStorage();
  static const String _profileBox = 'profile_box_enc';
  static const String _labResultsBox = 'lab_results_box_enc';
  static const String _prescriptionsBox = 'prescriptions_box_enc';
  static const String _aiCacheBox = 'ai_results_box_enc';
  static const String _syncQueueBox = 'sync_queue';

  Future<void> init() async {
    AppLogger.info('📦 CacheService: Initializing Hive...');
    try {
      await Hive.initFlutter();
      AppLogger.info('📦 CacheService: Hive initialized.');

      // Web: avoid persistent PHI caching. Keep only sync queue box for app wiring.
      if (kIsWeb) {
        AppLogger.warning(
          '🌐 Web mode: disabling persistent PHI cache for HIPAA safety.',
        );
        await Hive.openBox(_syncQueueBox);
        return;
      }

      // Get or create encryption key
      final encryptionKeyString = await _secureStorage.read(
        key: 'hive_encryption_key',
      );
      Uint8List encryptionKey;

      if (encryptionKeyString == null) {
        final key = Hive.generateSecureKey();
        await _secureStorage.write(
          key: 'hive_encryption_key',
          value: base64Url.encode(key),
        );
        encryptionKey = Uint8List.fromList(key);
      } else {
        encryptionKey = base64Url.decode(encryptionKeyString);
      }

      // Open boxes with encryption
      await Hive.openBox(
        _profileBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _labResultsBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _prescriptionsBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _syncQueueBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
      await Hive.openBox(
        _aiCacheBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
    } catch (e) {
      AppLogger.error('❌ CacheService init failed: $e');
    }
  }

  // Profile Cache
  Future<void> cacheProfile(Map<String, dynamic>? profile) async {
    if (kIsWeb) return;
    if (profile == null) return;
    final box = Hive.box(_profileBox);
    await box.put('current', profile);
  }

  Map<String, dynamic>? getCachedProfile() {
    if (kIsWeb || !Hive.isBoxOpen(_profileBox)) return null;
    final box = Hive.box(_profileBox);
    final data = box.get('current');
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // Lab Results Cache
  Future<void> cacheLabResults(List<Map<String, dynamic>> results) async {
    if (kIsWeb) return;
    final box = Hive.box(_labResultsBox);
    await box.put('list', results);
  }

  List<Map<String, dynamic>> getCachedLabResults() {
    if (kIsWeb || !Hive.isBoxOpen(_labResultsBox)) return [];
    final box = Hive.box(_labResultsBox);
    final data = box.get('list');
    return data != null ? List<Map<String, dynamic>>.from(data) : [];
  }

  // Prescriptions Cache
  Future<void> cachePrescriptions(
    List<Map<String, dynamic>> prescriptions,
  ) async {
    if (kIsWeb) return;
    final box = Hive.box(_prescriptionsBox);
    await box.put('list', prescriptions);
  }

  List<Map<String, dynamic>> getCachedPrescriptions() {
    if (kIsWeb || !Hive.isBoxOpen(_prescriptionsBox)) return [];
    final box = Hive.box(_prescriptionsBox);
    final data = box.get('list');
    return data != null ? List<Map<String, dynamic>>.from(data) : [];
  }

  // AI Cache
  Future<void> cacheAiResponse(String key, dynamic data) async {
    if (kIsWeb || !Hive.isBoxOpen(_aiCacheBox)) return;
    final box = Hive.box(_aiCacheBox);
    // Cache for 24 hours by storing timestamp
    await box.put(key, {
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  dynamic getAiCache(String key) {
    if (!Hive.isBoxOpen(_aiCacheBox)) return null;
    final box = Hive.box(_aiCacheBox);
    final entry = box.get(key);

    if (entry != null && entry is Map) {
      final timestamp = DateTime.tryParse(entry['timestamp'] ?? '');
      if (timestamp != null) {
        // Check 24 hour expiry
        if (DateTime.now().difference(timestamp).inHours < 24) {
          return entry['data'];
        } else {
          // Clean up expired
          box.delete(key);
        }
      }
    }
    return null;
  }

  Future<void> clearAll() async {
    if (Hive.isBoxOpen(_profileBox)) {
      await Hive.box(_profileBox).clear();
    }
    if (Hive.isBoxOpen(_labResultsBox)) {
      await Hive.box(_labResultsBox).clear();
    }
    if (Hive.isBoxOpen(_prescriptionsBox)) {
      await Hive.box(_prescriptionsBox).clear();
    }
    if (Hive.isBoxOpen(_aiCacheBox)) {
      await Hive.box(_aiCacheBox).clear();
    }
  }
}
