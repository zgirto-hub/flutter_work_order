import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineStorage {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'work_orders_offline.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE work_orders (
            id INTEGER PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id INTEGER,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveWorkOrder(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'work_orders',
      {
        'id': id,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getWorkOrders() async {
    final db = await database;
    final maps = await db.query('work_orders', orderBy: 'updated_at DESC');
    return maps.map((map) {
      return jsonDecode(map['data'] as String) as Map<String, dynamic>;
    }).toList();
  }

  Future<void> savePendingAction({
    required String actionType,
    required String entityType,
    int? entityId,
    required Map<String, dynamic> data,
  }) async {
    final db = await database;
    await db.insert('pending_actions', {
      'action_type': actionType,
      'entity_type': entityType,
      'entity_id': entityId,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final db = await database;
    final maps = await db.query('pending_actions', orderBy: 'created_at ASC');
    return maps.map((map) {
      return {
        'id': map['id'],
        'action_type': map['action_type'],
        'entity_type': map['entity_type'],
        'entity_id': map['entity_id'],
        'data': jsonDecode(map['data'] as String),
        'created_at': map['created_at'],
      };
    }).toList();
  }

  Future<void> deletePendingAction(int actionId) async {
    final db = await database;
    await db.delete('pending_actions', where: 'id = ?', whereArgs: [actionId]);
  }

  Future<void> updateSyncMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSyncMetadata(String key) async {
    final db = await database;
    final maps = await db.query('sync_metadata', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('work_orders');
    await db.delete('pending_actions');
    await db.delete('sync_metadata');
  }
}
