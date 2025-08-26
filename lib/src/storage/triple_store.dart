import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../core/types.dart';
import '../core/logging.dart';
import '../core/logging_config.dart';
import 'database_factory.dart';
import 'storage_interface.dart';

/// Local triple store implementation using SQLite
class TripleStore implements StorageInterface {
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
    // Initialize the platform-specific database factory
    await initializeDatabaseFactory();
    
    // Get the platform-specific database path
    final dbPath = await getDatabasePath(appId, persistenceDir: persistenceDir);
    
    // Get the platform-specific database factory
    final factory = getDatabaseFactory();

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      ),
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

  /// Get entity type for a specific entity ID
  Future<String?> getEntityType(String entityId) async {
    final results = await _db.query(
      'triples',
      columns: ['value'],
      where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
      whereArgs: [entityId, '__type'],
    );
    
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    
    return null;
  }

  /// Execute a complex query with WHERE conditions
  Future<List<Map<String, dynamic>>> queryEntities({
    String? entityType,
    String? entityId,
    Map<String, dynamic>? where,
    List<String>? orderBy,
    int? limit,
    int? offset,
    Map<String, dynamic>? aggregate,
    List<String>? groupBy,
  }) async {
    final entities = <String, Map<String, dynamic>>{};

    // Get entity IDs
    List<String> entityIds;
    if (entityId != null) {
      // Query specific entity
      entityIds = [entityId];
    } else if (entityType != null) {
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

    // Handle aggregations
    if (aggregate != null) {
      return _processAggregations(result, aggregate, groupBy);
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

      // Handle special logical operators
      if (key == '\$or') {
        if (value is List) {
          bool matchesAny = false;
          for (final condition in value) {
            if (condition is Map<String, dynamic> && _matchesWhere(entity, condition)) {
              matchesAny = true;
              break;
            }
          }
          if (!matchesAny) return false;
        }
        continue;
      }

      if (key == '\$and') {
        if (value is List) {
          for (final condition in value) {
            if (condition is Map<String, dynamic> && !_matchesWhere(entity, condition)) {
              return false;
            }
          }
        }
        continue;
      }

      if (key == '\$not') {
        if (value is Map<String, dynamic>) {
          // If the NOT condition matches, this fails
          if (_matchesWhere(entity, value)) return false;
        }
        continue;
      }

      if (!entity.containsKey(key)) return false;

      final entityValue = entity[key];

      // Handle complex operators
      if (value is Map<String, dynamic>) {
        if (!_matchesOperator(entityValue, value)) return false;
      } else {
        // Simple equality check
        if (entityValue != value) return false;
      }
    }
    return true;
  }

  bool _matchesOperator(dynamic entityValue, Map<String, dynamic> operators) {
    for (final entry in operators.entries) {
      final operator = entry.key;
      final operandValue = entry.value;

      switch (operator) {
        // Standard comparison operators
        case '>':
        case '\$gt':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue) <= 0) return false;
          break;
        case '>=':
        case '\$gte':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue) < 0) return false;
          break;
        case '<':
        case '\$lt':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue) >= 0) return false;
          break;
        case '<=':
        case '\$lte':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue) > 0) return false;
          break;
        case '!=':
        case '\$ne':
          if (entityValue == operandValue) return false;
          break;
        case 'in':
        case '\$in':
          if (operandValue is List && !operandValue.contains(entityValue)) return false;
          break;
        case 'not_in':
        case '\$nin':
          if (operandValue is List && operandValue.contains(entityValue)) return false;
          break;

        // String pattern matching operators
        case '\$like':
          if (entityValue is! String || operandValue is! String) return false;
          final pattern = operandValue.replaceAll('%', '.*');
          final regex = RegExp(pattern, caseSensitive: true);
          if (!regex.hasMatch(entityValue)) return false;
          break;
        case '\$ilike':
          if (entityValue is! String || operandValue is! String) return false;
          final pattern = operandValue.toLowerCase().replaceAll('%', '.*');
          final regex = RegExp(pattern, caseSensitive: false);
          if (!regex.hasMatch(entityValue.toLowerCase())) return false;
          break;

        // Null checking operators  
        case '\$isNull':
          final shouldBeNull = operandValue == true;
          final isNull = entityValue == null;
          if (shouldBeNull != isNull) return false;
          break;

        // Existence operators
        case '\$exists':
          // For our implementation, we consider a field to exist if it's not null
          final shouldExist = operandValue == true;
          final exists = entityValue != null;
          if (shouldExist != exists) return false;
          break;

        // Array/Collection operators
        case '\$contains':
          if (entityValue is List) {
            if (!entityValue.contains(operandValue)) return false;
          } else if (entityValue is String && operandValue is String) {
            if (!entityValue.contains(operandValue)) return false;
          } else {
            return false;
          }
          break;
        case '\$size':
          if (entityValue is List) {
            if (entityValue.length != operandValue) return false;
          } else if (entityValue is String) {
            if (entityValue.length != operandValue) return false;
          } else {
            return false;
          }
          break;

        // Logical operators (handled at higher level but included for completeness)
        case '\$not':
          if (operandValue is Map<String, dynamic>) {
            if (_matchesOperator(entityValue, operandValue)) return false;
          } else {
            if (entityValue == operandValue) return false;
          }
          break;

        default:
          // Unknown operator, treat as equality
          if (entityValue != operandValue) return false;
      }
    }
    return true;
  }

  /// Resolve a lookup reference to find entity ID by attribute value
  Future<String?> resolveLookup(String entityType, String attribute, dynamic value) async {
    final results = await queryEntities(
      entityType: entityType,
      where: {attribute: value},
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      return results.first['id'] as String?;
    }
    
    return null;
  }

  /// Resolve multiple lookup references at once
  Future<Map<LookupRef, String?>> resolveLookupsMap(List<LookupRef> lookups) async {
    final results = <LookupRef, String?>{};
    
    for (final lookup in lookups) {
      final entityId = await resolveLookup(
        lookup.entityType,
        lookup.attribute,
        lookup.value,
      );
      results[lookup] = entityId;
    }
    
    return results;
  }

  int _compareEntities(Map<String, dynamic> a, Map<String, dynamic> b, dynamic orderBy) {
    if (orderBy is String) {
      // Simple single field ordering
      final parts = orderBy.split(' ');
      final field = parts[0];
      final direction = parts.length > 1 ? parts[1].toLowerCase() : 'asc';
      return _compareSingleField(a, b, field, direction);
    } else if (orderBy is List) {
      // Multiple field ordering
      for (final orderSpec in orderBy) {
        if (orderSpec is Map<String, dynamic>) {
          final field = orderSpec.keys.first;
          final direction = orderSpec[field]?.toString().toLowerCase() ?? 'asc';
          final comparison = _compareSingleField(a, b, field, direction);
          if (comparison != 0) return comparison;
        }
      }
      return 0;
    } else if (orderBy is Map<String, dynamic>) {
      // Single field with explicit direction
      final field = orderBy.keys.first;
      final direction = orderBy[field]?.toString().toLowerCase() ?? 'asc';
      return _compareSingleField(a, b, field, direction);
    }
    
    return 0;
  }

  int _compareSingleField(Map<String, dynamic> a, Map<String, dynamic> b, String field, String direction) {
    final aValue = a[field];
    final bValue = b[field];

    if (aValue == null && bValue == null) return 0;
    if (aValue == null) return direction == 'asc' ? -1 : 1;
    if (bValue == null) return direction == 'asc' ? 1 : -1;

    int comparison;
    if (aValue is Comparable && bValue is Comparable) {
      comparison = (aValue as Comparable).compareTo(bValue as Comparable);
    } else {
      // Fallback to string comparison
      comparison = aValue.toString().compareTo(bValue.toString());
    }
    
    return direction == 'desc' ? -comparison : comparison;
  }

  List<Map<String, dynamic>> _processAggregations(
    List<Map<String, dynamic>> entities,
    Map<String, dynamic> aggregate,
    List<String>? groupBy,
  ) {
    if (groupBy != null && groupBy.isNotEmpty) {
      // Group by specified fields
      final groups = <String, List<Map<String, dynamic>>>{};
      
      for (final entity in entities) {
        final groupKey = groupBy.map((field) => entity[field]?.toString() ?? '').join('|');
        groups.putIfAbsent(groupKey, () => []);
        groups[groupKey]!.add(entity);
      }
      
      // Apply aggregations to each group
      return groups.entries.map((entry) {
        final group = entry.value;
        final result = _calculateAggregates(group, aggregate);
        
        // Add group fields to result
        final groupKeys = entry.key.split('|');
        for (int i = 0; i < groupBy.length && i < groupKeys.length; i++) {
          result[groupBy[i]] = _parseValue(groupKeys[i]);
        }
        
        return result;
      }).toList();
    } else {
      // Apply aggregations to all entities
      return [_calculateAggregates(entities, aggregate)];
    }
  }

  Map<String, dynamic> _calculateAggregates(
    List<Map<String, dynamic>> entities,
    Map<String, dynamic> aggregate,
  ) {
    final result = <String, dynamic>{};
    
    for (final entry in aggregate.entries) {
      final aggregateType = entry.key;
      final field = entry.value;
      
      switch (aggregateType) {
        case 'count':
          result['count'] = entities.length;
          break;
          
        case 'sum':
          if (field is String && field != '*') {
            final values = entities
                .map((e) => e[field])
                .where((v) => v is num)
                .cast<num>();
            result['sum'] = values.isEmpty ? 0 : values.reduce((a, b) => a + b);
          }
          break;
          
        case 'avg':
          if (field is String && field != '*') {
            final values = entities
                .map((e) => e[field])
                .where((v) => v is num)
                .cast<num>();
            result['avg'] = values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
          }
          break;
          
        case 'min':
          if (field is String && field != '*') {
            final values = entities
                .map((e) => e[field])
                .where((v) => v is Comparable)
                .cast<Comparable>();
            if (values.isNotEmpty) {
              result['min'] = values.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
            }
          }
          break;
          
        case 'max':
          if (field is String && field != '*') {
            final values = entities
                .map((e) => e[field])
                .where((v) => v is Comparable)
                .cast<Comparable>();
            if (values.isNotEmpty) {
              result['max'] = values.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
            }
          }
          break;
      }
    }
    
    return result;
  }

  dynamic _parseValue(String value) {
    // Try to parse as number
    if (value.isEmpty) return null;
    final intValue = int.tryParse(value);
    if (intValue != null) return intValue;
    final doubleValue = double.tryParse(value);
    if (doubleValue != null) return doubleValue;
    // Try to parse as boolean
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
    // Return as string
    return value;
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
      InstantDBLogging.root.debug('Transaction ${transaction.id} already applied, skipping');
      return;
    }

    // Resolve any lookup references first (outside DB transaction)
    final resolvedOperations = await _resolveLookupReferences(transaction.operations);
    
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

      // Apply resolved operations and collect changes
      for (final operation in resolvedOperations) {
        final changes = await _applyOperationWithChanges(txn, operation, transaction.id);
        pendingChanges.addAll(changes);
      }
    });
    
    // Emit all changes after transaction completes
    InstantDBLogging.root.debug('TripleStore: Transaction ${transaction.id} complete, emitting ${pendingChanges.length} changes');
    for (final change in pendingChanges) {
      InstantDBLogging.root.debug('TripleStore: Emitting change - ${change.type} for entity ${change.triple.entityId}, attribute ${change.triple.attribute}');
      _changeController.add(change);
    }
  }

  /// Resolve any LookupRef references in operation data to actual entity IDs
  Future<List<Operation>> _resolveLookupReferences(List<Operation> operations) async {
    final resolvedOperations = <Operation>[];
    
    for (final operation in operations) {
      if (operation.data == null) {
        resolvedOperations.add(operation);
        continue;
      }
      
      final resolvedData = <String, dynamic>{};
      bool hasChanges = false;
      
      for (final entry in operation.data!.entries) {
        final value = entry.value;
        if (value is LookupRef) {
          // Resolve the lookup reference
          final entityId = await resolveLookup(value.entityType, value.attribute, value.value);
          if (entityId != null) {
            resolvedData[entry.key] = entityId;
            hasChanges = true;
          } else {
            throw InstantException(
              message: 'Could not resolve lookup reference: ${value.entityType}.${value.attribute} = ${value.value}',
              code: 'lookup_failed',
            );
          }
        } else {
          resolvedData[entry.key] = value;
        }
      }
      
      if (hasChanges) {
        resolvedOperations.add(Operation(
          type: operation.type,
          entityType: operation.entityType,
          entityId: operation.entityId,
          data: resolvedData,
          options: operation.options,
        ));
      } else {
        resolvedOperations.add(operation);
      }
    }
    
    return resolvedOperations;
  }

  Future<List<TripleChange>> _applyOperationWithChanges(DatabaseExecutor txn, Operation operation, String txId) async {
    final changes = <TripleChange>[];
    final now = DateTime.now();

    switch (operation.type) {
      case OperationType.add:
        // Add operation with data map
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
            });

            changes.add(TripleChange(
              type: ChangeType.add,
              triple: Triple(
                entityId: operation.entityId,
                attribute: entry.key,
                value: entry.value,
                txId: txId,
                createdAt: now,
              ),
            ));
          }
        }
        break;

      case OperationType.update:
        // Update operation with data map
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            // Retract old value
            await txn.update(
              'triples',
              {'retracted': 1},
              where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
              whereArgs: [operation.entityId, entry.key],
            );

            // Add new value
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
            });

            changes.add(TripleChange(
              type: ChangeType.add,
              triple: Triple(
                entityId: operation.entityId,
                attribute: entry.key,
                value: entry.value,
                txId: txId,
                createdAt: now,
              ),
            ));
          }
        }
        break;

      case OperationType.merge:
        // Merge operation - deep merge with existing data
        final existingTriples = await txn.query(
          'triples',
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );
        
        final existingData = <String, dynamic>{};
        for (final triple in existingTriples) {
          existingData[triple['attribute'] as String] = jsonDecode(triple['value'] as String);
        }
        
        if (operation.data != null) {
          final mergedData = _deepMerge(existingData, operation.data!);
          
          // Update changed fields
          for (final entry in mergedData.entries) {
            if (existingData[entry.key] != entry.value) {
              // Retract old value
              await txn.update(
                'triples',
                {'retracted': 1},
                where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
                whereArgs: [operation.entityId, entry.key],
              );

              // Add merged value
              await txn.insert('triples', {
                'entity_id': operation.entityId,
                'attribute': entry.key,
                'value': jsonEncode(entry.value),
                'tx_id': txId,
                'created_at': now.millisecondsSinceEpoch,
                'retracted': 0,
              });

              changes.add(TripleChange(
                type: ChangeType.add,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                ),
              ));
            }
          }
        }
        break;

      case OperationType.link:
        // Link operation - create relationship triples
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            // Add link triple
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
            });

            changes.add(TripleChange(
              type: ChangeType.add,
              triple: Triple(
                entityId: operation.entityId,
                attribute: entry.key,
                value: entry.value,
                txId: txId,
                createdAt: now,
              ),
            ));
          }
        }
        break;

      case OperationType.unlink:
        // Unlink operation - remove relationship triples
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.update(
              'triples',
              {'retracted': 1},
              where: 'entity_id = ? AND attribute = ? AND value = ? AND retracted = FALSE',
              whereArgs: [operation.entityId, entry.key, jsonEncode(entry.value)],
            );

            changes.add(TripleChange(
              type: ChangeType.retract,
              triple: Triple(
                entityId: operation.entityId,
                attribute: entry.key,
                value: entry.value,
                txId: txId,
                createdAt: now,
                retracted: true,
              ),
            ));
          }
        }
        break;

      case OperationType.delete:
        // Get all triples for this entity before deletion
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
        // Legacy retract operation for backward compatibility
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.update(
              'triples',
              {'retracted': 1},
              where: 'entity_id = ? AND attribute = ? AND value = ? AND retracted = FALSE',
              whereArgs: [operation.entityId, entry.key, jsonEncode(entry.value)],
            );

            changes.add(TripleChange(
              type: ChangeType.retract,
              triple: Triple(
                entityId: operation.entityId,
                attribute: entry.key,
                value: entry.value,
                txId: txId,
                createdAt: now,
                retracted: true,
              ),
            ));
          }
        }
        break;
    }

    return changes;
  }

  /// Deep merge two maps, recursively merging nested maps
  Map<String, dynamic> _deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(target);
    
    for (final entry in source.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is Map<String, dynamic> && result[key] is Map<String, dynamic>) {
        result[key] = _deepMerge(result[key] as Map<String, dynamic>, value);
      } else {
        result[key] = value;
      }
    }
    
    return result;
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

    final transactions = <Transaction>[];
    final corruptedIds = <String>[];
    
    for (final row in results) {
      try {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final transaction = Transaction.fromJson(data);
        
        // Check if this transaction has corrupted entity IDs
        bool hasCorruptedIds = false;
        for (final op in transaction.operations) {
          if (op.type == OperationType.delete && 
              op.entityId.startsWith('[') && 
              op.entityId.endsWith(']')) {
            hasCorruptedIds = true;
            break;
          }
        }
        
        if (hasCorruptedIds) {
          // Mark corrupted transactions as failed
          corruptedIds.add(transaction.id);
          InstantDBLogging.root.debug('Found corrupted transaction ${transaction.id}, marking as failed');
        } else {
          transactions.add(transaction);
        }
      } catch (e) {
        InstantDBLogging.root.severe('Error parsing transaction', e);
      }
    }
    
    // Mark corrupted transactions as failed so they won't be retried
    if (corruptedIds.isNotEmpty) {
      await _markTransactionsAsFailed(corruptedIds);
    }
    
    return transactions;
  }
  
  /// Mark multiple transactions as failed
  Future<void> _markTransactionsAsFailed(List<String> txIds) async {
    if (txIds.isEmpty) return;
    
    final batch = _db.batch();
    for (final txId in txIds) {
      batch.update(
        'transactions',
        {'status': TransactionStatus.failed.name, 'synced': 0},
        where: 'id = ?',
        whereArgs: [txId],
      );
    }
    await batch.commit();
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

  /// Clear all data from the database (useful for development/debugging)
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete('triples');
      await txn.delete('transactions');
      await txn.delete('entities');
      await txn.delete('attributes');
    });
    
    // Emit a change event to update any listeners
    _changeController.add(TripleChange.clear());
  }

  /// Close the database
  Future<void> close() async {
    await _changeController.close();
    await _db.close();
  }
}