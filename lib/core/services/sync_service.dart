import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

import '../services/log_service.dart';

class SyncService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  final Box _syncBox;
  bool _isOnline = true;
  bool _isProcessingQueue = false;
  StreamSubscription? _subscription;

  SyncService(this._syncBox) {
    _init();
  }

  bool get isOnline => _isOnline;

  Future<void> _init() async {
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);

    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // connectivity_plus 6.0 returns a List<ConnectivityResult>
    final status = results.firstWhere(
      (r) => r != ConnectivityResult.none,
      orElse: () => ConnectivityResult.none,
    );

    _isOnline = status != ConnectivityResult.none;
    notifyListeners();
    AppLogger.debug(
      '🌐 Network Status: ${_isOnline ? "Online" : "Offline"} ($status)',
    );

    if (_isOnline) {
      _processQueue();
    }
  }

  Future<void> addToQueue(String action, Map<String, dynamic> data) async {
    final item = {
      'action': action,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _syncBox.add(item);
    AppLogger.debug('📥 Added to Sync Queue: $action');

    if (_isOnline) {
      // Best-effort immediate processing so newly added follow-up actions are not stranded.
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _syncBox.isEmpty) return;
    _isProcessingQueue = true;

    AppLogger.debug('🔄 Processing Sync Queue (${_syncBox.length} items)...');

    try {
      // Process until the queue stabilizes so follow-up actions enqueued during sync are also handled.
      while (_isOnline && _syncBox.isNotEmpty) {
        var progressed = false;
        final keys = _syncBox.keys.toList();
        for (var key in keys) {
          if (!_isOnline) break;

          try {
            final rawItem = _syncBox.get(key);
            if (rawItem is! Map) {
              AppLogger.error('Dropping malformed sync queue item at key: $key');
              await _syncBox.delete(key);
              progressed = true;
              continue;
            }
            final item = Map<String, dynamic>.from(rawItem);
            final action = item['action']?.toString() ?? '';
            final rawData = item['data'];

            if (!_allowedActions.contains(action)) {
              AppLogger.error('Blocked unauthorized action in queue: $action');
              await _syncBox.delete(key);
              progressed = true;
              continue;
            }

            if (rawData is! Map) {
              AppLogger.error('Dropping malformed sync payload for action: $action');
              await _syncBox.delete(key);
              progressed = true;
              continue;
            }

            final success = await _executeAction(
              action,
              Map<String, dynamic>.from(rawData),
            );

            if (success) {
              await _syncBox.delete(key);
              progressed = true;
              AppLogger.debug('✅ Synced: ${item['action']}');
            }
          } catch (e) {
            AppLogger.error('❌ Sync Failed for $key: $e');
            // Keep in queue to retry later
          }
        }

        if (!progressed) {
          break;
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // This will be injected or set by the repository to avoid circular dependencies
  Future<bool> Function(String action, Map<String, dynamic> data)?
  _actionHandler;

  void setActionHandler(
    Future<bool> Function(String action, Map<String, dynamic> data) handler,
  ) {
    _actionHandler = handler;
  }

  // Whitelist allowed actions
  static const _allowedActions = {
    'createLabResult',
    'indexLabEmbeddings',
  };

  Future<bool> _executeAction(String action, Map<String, dynamic> data) async {
    if (!_allowedActions.contains(action)) {
      AppLogger.error('Blocked unauthorized action: $action');
      return false;
    }
    if (_actionHandler != null) {
      return await _actionHandler!(action, data);
    }
    return false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
