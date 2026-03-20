import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../offline/offline_storage.dart';

enum SyncStatus { idle, syncing, success, error, offline }

class SyncResult {
  final bool success;
  final int syncedCount;
  final int failedCount;
  final List<String> errors;
  final Duration duration;

  SyncResult({
    required this.success,
    required this.syncedCount,
    required this.failedCount,
    required this.errors,
    required this.duration,
  });

  factory SyncResult.empty() {
    return SyncResult(
      success: true,
      syncedCount: 0,
      failedCount: 0,
      errors: [],
      duration: Duration.zero,
    );
  }
}

class SyncService {
  final http.Client _client;
  final OfflineStorage _offlineStorage;
  final Connectivity _connectivity;
  final String baseUrl;
  final Duration _timeout;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;
  
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncService({
    http.Client? client,
    OfflineStorage? offlineStorage,
    Connectivity? connectivity,
    String? baseUrl,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _offlineStorage = offlineStorage ?? OfflineStorage(),
        _connectivity = connectivity ?? Connectivity(),
        baseUrl = baseUrl ?? 'https://zorin.taila92fe8.ts.net/api',
        _timeout = timeout ?? const Duration(seconds: 30);

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<SyncResult> syncPendingActions() async {
    if (!await isOnline) {
      _updateStatus(SyncStatus.offline);
      return SyncResult(
        success: false,
        syncedCount: 0,
        failedCount: 0,
        errors: ['No internet connection'],
        duration: Duration.zero,
      );
    }

    _updateStatus(SyncStatus.syncing);
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];
    int syncedCount = 0;
    int failedCount = 0;

    try {
      final pendingActions = await _offlineStorage.getPendingActions();

      for (final action in pendingActions) {
        try {
          final success = await _processAction(action);
          if (success) {
            await _offlineStorage.deletePendingAction(action['id'] as int);
            syncedCount++;
          } else {
            failedCount++;
            errors.add('Failed to sync action: ${action['action_type']}');
          }
        } catch (e) {
          failedCount++;
          errors.add('Error syncing action ${action['id']}: $e');
        }
      }

      stopwatch.stop();
      
      if (failedCount == 0) {
        _updateStatus(SyncStatus.success);
      } else if (failedCount < syncedCount) {
        _updateStatus(SyncStatus.error);
      } else {
        _updateStatus(SyncStatus.error);
      }

      return SyncResult(
        success: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        errors: errors,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _updateStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        errors: [...errors, 'Sync failed: $e'],
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<bool> _processAction(Map<String, dynamic> action) async {
    final actionType = action['action_type'] as String;
    final entityType = action['entity_type'] as String;
    final data = action['data'] as Map<String, dynamic>;

    try {
      switch (actionType) {
        case 'create':
          return await _handleCreate(entityType, data);
        case 'update':
          return await _handleUpdate(entityType, data);
        case 'delete':
          return await _handleDelete(entityType, data);
        default:
          return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> _handleCreate(String entityType, Map<String, dynamic> data) async {
    switch (entityType) {
      case 'work_order':
        final response = await _client.post(
          Uri.parse('$baseUrl/api/work-orders'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ).timeout(_timeout);
        return response.statusCode == 201 || response.statusCode == 200;
      default:
        return false;
    }
  }

  Future<bool> _handleUpdate(String entityType, Map<String, dynamic> data) async {
    final id = data['id'];
    switch (entityType) {
      case 'work_order':
        final response = await _client.patch(
          Uri.parse('$baseUrl/api/work-orders/$id'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ).timeout(_timeout);
        return response.statusCode == 200;
      default:
        return false;
    }
  }

  Future<bool> _handleDelete(String entityType, Map<String, dynamic> data) async {
    final id = data['id'];
    switch (entityType) {
      case 'work_order':
        final response = await _client.delete(
          Uri.parse('$baseUrl/api/work-orders/$id'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(_timeout);
        return response.statusCode == 200 || response.statusCode == 204;
      default:
        return false;
    }
  }

  Future<void> fetchAndCacheWorkOrders() async {
    if (!await isOnline) return;
  }

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    _statusController.close();
    _client.close();
  }
}
