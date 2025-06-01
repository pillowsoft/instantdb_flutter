import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';

import '../core/types.dart';
import '../core/logging.dart';

/// Local triple store implementation using SQLite
class TripleStore {
  late final Database _db;
  final String appId;
  final StreamController<TripleChange> _changeController = StreamController.broadcast();

  /// Stream of all changes to the triple store
  Stream<TripleChange> get changes => _changeController.stream;

  TripleStore._(this.appId, this._db);

  /// Initialize the triple store
  static Future<TripleStore> init({
    required String appId,
    String? persistenceDir,
  }) async {
    final dbPath = persistenceDir != null
        ? join(persistenceDir, '$appId.db')
        : join(await getDatabasesPath(), '$appId.db');

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );

    return TripleStore._(appId, db);
  }

  static Future<void> _createTables(Database db, int version) async {
    // Triples table - core data storage
    await db.execute('''
      CREATE TABLE triples (
        entity_id TEXT NOT NULL,
        attribute TEXT NOT NULL,
        value TEXT NOT NULL,
        tx_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retracted BOOLEAN DEFAULT FALSE,
        PRIMARY KEY (entity_id, attribute, value, tx_id)
      )
    ''');

    // Indexes for performance
    await db.execute('CREATE INDEX idx_entity ON triples(entity_id)');
    await db.execute('CREATE INDEX idx_attribute ON triples(attribute)');
    await db.execute('CREATE INDEX idx_tx ON triples(tx_id)');
    await db.execute('CREATE INDEX idx_created_at ON triples(created_at)');

    // Transactions table - track transaction status
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        synced BOOLEAN DEFAULT FALSE,
        data TEXT NOT NULL
      )
    ''');

    // Metadata table - store app state
    await db.execute('''
      CREATE TABLE metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Handle database schema migrations here
    if (oldVersion < newVersion) {
      // Future migration logic
    }
  }

  /// Add a triple to the store
  Future<void> addTriple(Triple triple) async {
    await _db.insert(
      'triples',
      {
        'entity_id': triple.entityId,
        'attribute': triple.attribute,
        'value': jsonEncode(triple.value),
        'tx_id': triple.txId,
        'created_at': triple.createdAt.millisecondsSinceEpoch,
        'retracted': triple.retracted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _changeController.add(TripleChange(
      type: ChangeType.add,
      triple: triple,
    ));
  }

  /// Retract a triple (soft delete)
  Future<void> retractTriple(Triple triple) async {
    await _db.update(
      'triples',
      {'retracted': 1},
      where: 'entity_id = ? AND attribute = ? AND value = ? AND tx_id = ?',
      whereArgs: [
        triple.entityId,
        triple.attribute,
        jsonEncode(triple.value),
        triple.txId,
      ],
    );

    _changeController.add(TripleChange(
      type: ChangeType.retract,
      triple: triple,
    ));
  }

  /// Query triples by entity ID
  Future<List<Triple>> queryByEntity(String entityId) async {
    final results = await _db.query(
      'triples',
      where: 'entity_id = ? AND retracted = FALSE',
      whereArgs: [entityId],
      orderBy: 'created_at ASC',
    );

    return results.map(_mapToTriple).toList();
  }

  /// Query triples by attribute
  Future<List<Triple>> queryByAttribute(String attribute) async {
    final results = await _db.query(
      'triples',
      where: 'attribute = ? AND retracted = FALSE',
      whereArgs: [attribute],
      orderBy: 'created_at ASC',
    );

    return results.map(_mapToTriple).toList();
  }

  /// Query all entities of a specific type
  Future<List<String>> queryEntityIdsByType(String entityType) async {
    final results = await _db.query(
      'triples',
      columns: ['entity_id'],
      where: 'attribute = ? AND value = ? AND retracted = FALSE',
      whereArgs: ['__type', jsonEncode(entityType)],
      distinct: true,
    );

    return results.map((row) => row['entity_id'] as String).toList();
  }

  /// Execute a complex query with WHERE conditions
  Future<List<Map<String, dynamic>>> queryEntities({
    String? entityType,
    Map<String, dynamic>? where,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final entities = <String, Map<String, dynamic>>{};

    // Get entity IDs
    List<String> entityIds;
    if (entityType != null) {
      entityIds = await queryEntityIdsByType(entityType);
    } else {
      final results = await _db.query(
        'triples',
        columns: ['entity_id'],
        where: 'retracted = FALSE',
        distinct: true,
      );
      entityIds = results.map((row) => row['entity_id'] as String).toList();
    }

    // Build entities from triples
    for (final entityId in entityIds) {
      final triples = await queryByEntity(entityId);
      final entity = <String, dynamic>{'id': entityId};

      for (final triple in triples) {
        entity[triple.attribute] = triple.value;
      }

      entities[entityId] = entity;
    }

    var result = entities.values.toList();

    // Apply WHERE filtering
    if (where != null) {
      result = result.where((entity) => _matchesWhere(entity, where)).toList();
    }

    // Apply ordering
    if (orderBy != null) {
      result.sort((a, b) => _compareEntities(a, b, orderBy));
    }

    // Apply pagination
    if (offset != null) {
      result = result.skip(offset).toList();
    }
    if (limit != null) {
      result = result.take(limit).toList();
    }

    return result;
  }

  bool _matchesWhere(Map<String, dynamic> entity, Map<String, dynamic> where) {
    for (final entry in where.entries) {
      final key = entry.key;
      final value = entry.value;

      if (!entity.containsKey(key)) return false;

      final entityValue = entity[key];
      if (entityValue != value) return false;
    }
    return true;
  }

  int _compareEntities(Map<String, dynamic> a, Map<String, dynamic> b, String orderBy) {
    // Simple ordering implementation
    final parts = orderBy.split(' ');
    final field = parts[0];
    final direction = parts.length > 1 ? parts[1].toLowerCase() : 'asc';

    final aValue = a[field];
    final bValue = b[field];

    if (aValue == null && bValue == null) return 0;
    if (aValue == null) return direction == 'asc' ? -1 : 1;
    if (bValue == null) return direction == 'asc' ? 1 : -1;

    final comparison = Comparable.compare(aValue, bValue);
    return direction == 'desc' ? -comparison : comparison;
  }

  Triple _mapToTriple(Map<String, dynamic> row) {
    return Triple(
      entityId: row['entity_id'] as String,
      attribute: row['attribute'] as String,
      value: jsonDecode(row['value'] as String),
      txId: row['tx_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      retracted: (row['retracted'] as int) == 1,
    );
  }

  /// Apply a transaction to the store
  Future<void> applyTransaction(Transaction transaction) async {
    // Check if transaction already exists
    final existing = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transaction.id],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      // Transaction already applied, skip
      InstantLogger.debug('Transaction ${transaction.id} already applied, skipping');
      return;
    }
    
    // Collect change events to emit after the transaction completes
    final pendingChanges = <TripleChange>[];
    
    await _db.transaction((txn) async {
      // Store transaction record
      await txn.insert('transactions', {
        'id': transaction.id,
        'timestamp': transaction.timestamp.millisecondsSinceEpoch,
        'status': transaction.status.name,
        'synced': transaction.status == TransactionStatus.synced ? 1 : 0,
        'data': jsonEncode(transaction.toJson()),
      });

      // Apply operations and collect changes
      for (final operation in transaction.operations) {
        final changes = await _applyOperationWithChanges(txn, operation, transaction.id);
        pendingChanges.addAll(changes);
      }
    });
    
    // Emit all changes after transaction completes
    InstantLogger.debug('TripleStore: Transaction ${transaction.id} complete, emitting ${pendingChanges.length} changes');
    for (final change in pendingChanges) {
      InstantLogger.debug('TripleStore: Emitting change - ${change.type} for entity ${change.triple.entityId}, attribute ${change.triple.attribute}');
      _changeController.add(change);
    }
  }

  Future<List<TripleChange>> _applyOperationWithChanges(DatabaseExecutor txn, Operation operation, String txId) async {
    final changes = <TripleChange>[];
    final now = DateTime.now();

    switch (operation.type) {
      case OperationType.add:
        if (operation.attribute != null) {
          await txn.insert('triples', {
            'entity_id': operation.entityId,
            'attribute': operation.attribute!,
            'value': jsonEncode(operation.value),
            'tx_id': txId,
            'created_at': now.millisecondsSinceEpoch,
            'retracted': 0, // Use 0 for false
          });

          changes.add(TripleChange(
            type: ChangeType.add,
            triple: Triple(
              entityId: operation.entityId,
              attribute: operation.attribute!,
              value: operation.value,
              txId: txId,
              createdAt: now,
            ),
          ));
        }
        break;

      case OperationType.update:
        if (operation.attribute != null) {
          // Retract old value
          await txn.update(
            'triples',
            {'retracted': 1},
            where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
            whereArgs: [operation.entityId, operation.attribute!],
          );

          // Add new value
          await txn.insert('triples', {
            'entity_id': operation.entityId,
            'attribute': operation.attribute!,
            'value': jsonEncode(operation.value),
            'tx_id': txId,
            'created_at': now.millisecondsSinceEpoch,
            'retracted': 0, // Use 0 for false
          });

          changes.add(TripleChange(
            type: ChangeType.add,
            triple: Triple(
              entityId: operation.entityId,
              attribute: operation.attribute!,
              value: operation.value,
              txId: txId,
              createdAt: now,
            ),
          ));
        }
        break;

      case OperationType.delete:
        // Get all triples for this entity before deletion (use txn for consistency)
        final triplesToDelete = await txn.query(
          'triples',
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );
        
        // Retract all triples for this entity
        await txn.update(
          'triples',
          {'retracted': 1},
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );
        
        // Emit change events for each retracted triple
        for (final tripleData in triplesToDelete) {
          changes.add(TripleChange(
            type: ChangeType.retract,
            triple: Triple(
              entityId: tripleData['entity_id'] as String,
              attribute: tripleData['attribute'] as String,
              value: jsonDecode(tripleData['value'] as String),
              txId: txId,
              createdAt: DateTime.fromMillisecondsSinceEpoch(tripleData['created_at'] as int),
              retracted: true,
            ),
          ));
        }
        break;

      case OperationType.retract:
        if (operation.attribute != null) {
          await txn.update(
            'triples',
            {'retracted': 1},
            where: 'entity_id = ? AND attribute = ? AND value = ? AND retracted = FALSE',
            whereArgs: [
              operation.entityId,
              operation.attribute!,
              jsonEncode(operation.value),
            ],
          );

          changes.add(TripleChange(
            type: ChangeType.retract,
            triple: Triple(
              entityId: operation.entityId,
              attribute: operation.attribute!,
              value: operation.value,
              txId: txId,
              createdAt: now,
            ),
          ));
        }
        break;
    }
    
    return changes;
  }
  

  /// Rollback a transaction
  Future<void> rollbackTransaction(String txId) async {
    await _db.transaction((txn) async {
      // Mark transaction as failed
      await txn.update(
        'transactions',
        {'status': TransactionStatus.failed.name},
        where: 'id = ?',
        whereArgs: [txId],
      );

      // Retract all triples from this transaction
      await txn.update(
        'triples',
        {'retracted': 1},
        where: 'tx_id = ?',
        whereArgs: [txId],
      );
    });
  }

  /// Get transaction by ID
  Future<Transaction?> getTransaction(String txId) async {
    final results = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [txId],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final row = results.first;
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    return Transaction.fromJson(data);
  }

  /// Get all pending transactions
  Future<List<Transaction>> getPendingTransactions() async {
    final results = await _db.query(
      'transactions',
      where: 'synced = FALSE AND status != ?',
      whereArgs: [TransactionStatus.failed.name],
      orderBy: 'timestamp ASC',
    );

    return results.map((row) {
      final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      return Transaction.fromJson(data);
    }).toList();
  }

  /// Mark transaction as synced
  Future<void> markTransactionSynced(String txId) async {
    await _db.update(
      'transactions',
      {'synced': 1, 'status': TransactionStatus.synced.name},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Close the database
  Future<void> close() async {
    await _changeController.close();
    await _db.close();
  }
}