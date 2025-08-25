import 'dart:async';
import 'dart:convert';
import 'package:reaxdb_dart/reaxdb_dart.dart' as reax;

import '../core/types.dart';
import '../core/logging_config.dart';
import 'storage_interface.dart';

/// ReaxDB-based storage implementation for InstantDB
/// This provides a much simpler and faster alternative to the SQLite triple store
class ReaxStore implements StorageInterface {
  late final reax.SimpleReaxDB _db;
  final String appId;
  final StreamController<TripleChange> _changeController = StreamController.broadcast();
  final Set<StreamSubscription> _watchSubscriptions = {};
  
  // Loggers for different aspects of storage
  static final _logger = InstantDBLogging.reaxStore;
  static final _txLogger = InstantDBLogging.transaction;

  /// Stream of all changes to the store
  Stream<TripleChange> get changes => _changeController.stream;

  ReaxStore._(this.appId, this._db);

  /// Initialize the ReaxDB store
  static Future<ReaxStore> init({
    required String appId,
    String? persistenceDir,
    bool encrypted = false,
  }) async {
    try {
      // Platform detection logging
      InstantDBLogging.root.debug('ReaxStore: Platform detection - Web: ${_isWeb()}, Mobile: ${_isMobile()}, Desktop: ${_isDesktop()}');
      InstantDBLogging.root.debug('ReaxStore: Initializing ReaxDB for app: $appId');
      InstantDBLogging.root.debug('ReaxStore: Configuration - encrypted: $encrypted, persistenceDir: $persistenceDir');
      
      // Log ReaxDB version info if available
      InstantDBLogging.root.debug('ReaxStore: Starting SimpleReaxDB.open() call...');
      final stopwatch = Stopwatch()..start();
      
      // Create database with optional encryption
      final db = await reax.SimpleReaxDB.open(
        'instantdb_$appId',
        encrypted: encrypted,
        path: persistenceDir,
      );
      
      stopwatch.stop();
      InstantDBLogging.root.debug('ReaxStore: SimpleReaxDB.open() completed in ${stopwatch.elapsedMilliseconds}ms');
      InstantDBLogging.root.debug('ReaxStore: ReaxDB instance created successfully');
      
      // Test basic ReaxDB operations
      InstantDBLogging.root.debug('ReaxStore: Testing basic ReaxDB operations...');
      try {
        await db.put('__test_init__', {'timestamp': DateTime.now().millisecondsSinceEpoch});
        final testValue = await db.get('__test_init__');
        InstantDBLogging.root.debug('ReaxStore: Basic put/get test successful: $testValue');
        await db.delete('__test_init__');
        InstantDBLogging.root.debug('ReaxStore: Basic delete test successful');
      } catch (e, stackTrace) {
        InstantDBLogging.root.severe('ReaxStore: Basic operations test failed', e, stackTrace);
        // Continue anyway - this is just a test
      }
      
      final store = ReaxStore._(appId, db);
      InstantDBLogging.root.debug('ReaxStore: ReaxStore instance created, setting up watchers...');
      
      await store._setupWatchers();
      
      InstantDBLogging.root.debug('ReaxStore: Successfully initialized with all components');
      return store;
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Failed to initialize - Error Type: ${e.runtimeType}', e, stackTrace);
      
      // Add detailed error analysis
      if (e.toString().contains('_Namespace')) {
        InstantDBLogging.root.severe('ReaxStore: _Namespace error detected - this indicates dart:io incompatibility on web platform');
        InstantDBLogging.root.severe('ReaxStore: ReaxDB may not support web platform despite documentation claims');
      }
      
      if (e.toString().contains('dart:io')) {
        InstantDBLogging.root.severe('ReaxStore: dart:io dependency detected - web platform cannot access file system');
      }
      
      rethrow;
    }
  }

  // Platform detection helpers
  static bool _isWeb() {
    try {
      // This will throw on non-web platforms
      return identical(0, 0.0) == false; // Never true, used to detect web
    } catch (e) {
      return true; // If this fails, we're likely on web
    }
  }

  static bool _isMobile() {
    try {
      return const bool.fromEnvironment('dart.library.io') && 
             (const bool.fromEnvironment('dart.io.platform.isAndroid') || 
              const bool.fromEnvironment('dart.io.platform.isIOS'));
    } catch (e) {
      return false;
    }
  }

  static bool _isDesktop() {
    try {
      return const bool.fromEnvironment('dart.library.io') &&
             (const bool.fromEnvironment('dart.io.platform.isWindows') ||
              const bool.fromEnvironment('dart.io.platform.isLinux') ||
              const bool.fromEnvironment('dart.io.platform.isMacOS'));
    } catch (e) {
      return false;
    }
  }

  /// Set up reactive watchers for all entity types
  Future<void> _setupWatchers() async {
    try {
      InstantDBLogging.root.debug('ReaxStore: Setting up ReaxDB watchers with pattern: "*"');
      
      // Watch all changes in the database using SimpleReaxDB pattern matching
      final watcher = _db.watch('*');
      InstantDBLogging.root.debug('ReaxStore: ReaxDB watch stream created successfully');
      
      _watchSubscriptions.add(
        watcher.listen((event) {
          InstantDBLogging.root.debug('ReaxStore: ReaxDB change event received: ${event.runtimeType}');
          _handleDatabaseChange(event);
        }, onError: (error, stackTrace) {
          InstantDBLogging.root.severe('ReaxStore: ReaxDB watch stream error', error, stackTrace);
        }, onDone: () {
          InstantDBLogging.root.debug('ReaxStore: ReaxDB watch stream closed');
        })
      );

      InstantDBLogging.root.debug('ReaxStore: Watchers set up successfully - ${_watchSubscriptions.length} active subscriptions');
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Failed to setup watchers', e, stackTrace);
      rethrow;
    }
  }

  void _handleDatabaseChange(dynamic event) {
    try {
      InstantDBLogging.root.debug('ReaxStore: Processing ReaxDB change event - Type: ${event.runtimeType}, Content: $event');
      
      // Handle ReaxDB change events
      // The exact event structure depends on the ReaxDB API
      String? key;
      dynamic value;
      String changeType = 'unknown';
      
      // Try to extract event details
      if (event != null) {
        try {
          // Check if event has key/value properties
          if (event.toString().contains('key:') || event.toString().contains('value:')) {
            InstantDBLogging.root.debug('ReaxStore: Event appears to have key/value structure');
          }
          
          // For detailed event analysis
          if (event is Map) {
            key = event['key']?.toString();
            value = event['value'];
            changeType = event['type']?.toString() ?? 'change';
            InstantDBLogging.root.debug('ReaxStore: Map event - key: $key, valueType: ${value?.runtimeType}, changeType: $changeType');
          }
        } catch (e) {
          InstantDBLogging.root.debug('ReaxStore: Could not parse event structure: $e');
        }
      }
      
      // Create a synthetic triple change for compatibility with InstantDB
      final triple = Triple(
        entityId: key ?? 'unknown',
        attribute: '__reaxdb_change__',
        value: value ?? event.toString(),
        txId: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );
      
      final change = TripleChange(type: ChangeType.add, triple: triple);
      _logger.fine('Emitting change event: ${triple.entityId}');
      _changeController.add(change);
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Error handling database change', e, stackTrace);
    }
  }

  /// Apply a transaction to the store
  Future<void> applyTransaction(Transaction transaction) async {
    try {
      InstantDBLogging.logTransaction('APPLY_LOCAL', transaction.id, 
        operationCount: transaction.operations.length);
      final stopwatch = Stopwatch()..start();
      
      // Check if transaction already exists
      _logger.debug('Checking for existing transaction ${transaction.id}');
      final existingTx = await _db.get('tx:${transaction.id}');
      if (existingTx != null) {
        _txLogger.debug('Transaction ${transaction.id} already applied, skipping');
        return;
      }

      // Store transaction metadata
      _logger.debug('Storing transaction metadata for ${transaction.id}');
      final txMetadata = {
        'id': transaction.id,
        'timestamp': transaction.timestamp.millisecondsSinceEpoch,
        'status': transaction.status.name,
        'operations_count': transaction.operations.length,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _db.put('tx:${transaction.id}', txMetadata);
      InstantDBLogging.root.debug('ReaxStore: Transaction metadata stored successfully');

      // Apply each operation with detailed logging
      for (int i = 0; i < transaction.operations.length; i++) {
        final operation = transaction.operations[i];
        InstantDBLogging.root.debug('ReaxStore: Applying operation ${i + 1}/${transaction.operations.length} - Type: ${operation.type}, EntityType: ${operation.entityType}, EntityId: ${operation.entityId}');
        
        final opStopwatch = Stopwatch()..start();
        await _applyOperation(operation, transaction.id);
        opStopwatch.stop();
        
        InstantDBLogging.root.debug('ReaxStore: Operation ${i + 1} completed in ${opStopwatch.elapsedMilliseconds}ms');
      }

      stopwatch.stop();
      InstantDBLogging.root.debug('ReaxStore: Transaction ${transaction.id} applied successfully in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Failed to apply transaction ${transaction.id} - Error: ${e.runtimeType}', e, stackTrace);
      rethrow;
    }
  }

  /// Apply a single operation 
  Future<void> _applyOperation(Operation operation, String txId) async {
    InstantDBLogging.root.debug('ReaxStore: _applyOperation START - Type: ${operation.type}, EntityType: ${operation.entityType}, EntityId: ${operation.entityId}');
    
    // Handle entity type resolution for delete operations
    String resolvedEntityType = operation.entityType;
    if (operation.type == OperationType.delete && operation.entityType == 'unknown') {
      InstantDBLogging.root.debug('ReaxStore: DELETE operation with unknown entity type, attempting resolution for entity: ${operation.entityId}');
      resolvedEntityType = await _resolveEntityType(operation.entityId);
      InstantDBLogging.root.debug('ReaxStore: Entity type resolved from "unknown" to "$resolvedEntityType"');
    }
    
    final entityKey = '$resolvedEntityType:${operation.entityId}';
    InstantDBLogging.root.debug('ReaxStore: _applyOperation - EntityKey: $entityKey, Operation: ${operation.type}, Data: ${operation.data}');
    
    switch (operation.type) {
      case OperationType.add:
      case OperationType.update:
      case OperationType.merge:
        // Get existing entity data
        final existingData = await _db.get(entityKey) ?? <String, dynamic>{};
        Map<String, dynamic> entityData;
        
        if (operation.type == OperationType.add) {
          // For add operations, start fresh but preserve existing data if any
          entityData = Map<String, dynamic>.from(existingData);
          if (operation.data != null) {
            entityData.addAll(operation.data!);
          }
        } else if (operation.type == OperationType.merge) {
          // Deep merge for nested objects
          entityData = _deepMerge(existingData, operation.data ?? {});
        } else {
          // Update: replace specified fields
          entityData = Map<String, dynamic>.from(existingData);
          if (operation.data != null) {
            entityData.addAll(operation.data!);
          }
        }
        
        // Ensure required fields
        entityData['id'] = operation.entityId;
        entityData['__type'] = resolvedEntityType;
        entityData['__updated_at'] = DateTime.now().millisecondsSinceEpoch;
        entityData['__tx_id'] = txId;
        
        await _db.put(entityKey, entityData);
        InstantDBLogging.root.debug('ReaxStore: Entity stored successfully with key: $entityKey');
        break;

      case OperationType.delete:
        InstantDBLogging.root.debug('ReaxStore: DELETE operation - Checking if entity exists with key: $entityKey');
        
        // First check if entity exists
        final existingEntity = await _db.get(entityKey);
        if (existingEntity != null) {
          InstantDBLogging.root.debug('ReaxStore: Entity found, proceeding with deletion');
          await _db.delete(entityKey);
          InstantDBLogging.root.debug('ReaxStore: Entity deleted successfully with key: $entityKey');
        } else {
          InstantDBLogging.root.debug('ReaxStore: Entity not found with key: $entityKey - delete operation skipped');
          
          // If entity not found with resolved type, try searching all entity types
          if (resolvedEntityType == 'unknown') {
            InstantDBLogging.root.debug('ReaxStore: Attempting to find entity across all types for ID: ${operation.entityId}');
            final foundKey = await _findEntityAcrossTypes(operation.entityId);
            if (foundKey != null) {
              InstantDBLogging.root.debug('ReaxStore: Entity found with key: $foundKey, deleting...');
              await _db.delete(foundKey);
              InstantDBLogging.root.debug('ReaxStore: Entity deleted successfully with fallback key: $foundKey');
            } else {
              InstantDBLogging.root.debug('ReaxStore: Entity with ID ${operation.entityId} not found in any entity type');
            }
          }
        }
        break;

      case OperationType.retract:
        // For retract, we remove specific attributes
        final existingData = await _db.get(entityKey);
        if (existingData != null && operation.data != null) {
          final entityData = Map<String, dynamic>.from(existingData);
          for (final key in operation.data!.keys) {
            entityData.remove(key);
          }
          entityData['__updated_at'] = DateTime.now().millisecondsSinceEpoch;
          entityData['__tx_id'] = txId;
          await _db.put(entityKey, entityData);
        }
        break;

      case OperationType.link:
      case OperationType.unlink:
        // For now, treat links as simple attribute updates
        // In the future, we could implement proper relationship handling
        final existingData = await _db.get(entityKey) ?? <String, dynamic>{};
        final entityData = Map<String, dynamic>.from(existingData);
        
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            final relationKey = entry.key;
            final targetId = entry.value;
            
            if (operation.type == OperationType.link) {
              // Add to relationship (could be single value or list)
              final existing = entityData[relationKey];
              if (existing == null) {
                entityData[relationKey] = targetId;
              } else if (existing is List) {
                if (!existing.contains(targetId)) {
                  existing.add(targetId);
                }
              } else {
                // Convert to list
                entityData[relationKey] = [existing, targetId];
              }
            } else {
              // Unlink: remove from relationship
              final existing = entityData[relationKey];
              if (existing is List) {
                existing.remove(targetId);
                if (existing.isEmpty) {
                  entityData.remove(relationKey);
                }
              } else if (existing == targetId) {
                entityData.remove(relationKey);
              }
            }
          }
        }
        
        entityData['id'] = operation.entityId;
        entityData['__type'] = operation.entityType;
        entityData['__updated_at'] = DateTime.now().millisecondsSinceEpoch;
        entityData['__tx_id'] = txId;
        
        await _db.put(entityKey, entityData);
        break;
    }
  }

  /// Deep merge two maps (for merge operations)
  Map<String, dynamic> _deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(target);
    
    for (final entry in source.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (result.containsKey(key) && 
          result[key] is Map<String, dynamic> && 
          value is Map<String, dynamic>) {
        // Recursively merge nested maps
        result[key] = _deepMerge(result[key] as Map<String, dynamic>, value);
      } else {
        // Direct assignment for primitives, lists, and new keys
        result[key] = value;
      }
    }
    
    return result;
  }

  /// Query entities with filtering, sorting, and pagination
  /// This replaces the complex SQL queries from TripleStore
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
    try {
      InstantDBLogging.root.debug('ReaxStore: queryEntities called - entityType: $entityType, entityId: $entityId, where: $where, orderBy: $orderBy, limit: $limit, offset: $offset');
      final stopwatch = Stopwatch()..start();
      
      List<Map<String, dynamic>> entities;

      if (entityId != null && entityType != null) {
        // Query specific entity
        InstantDBLogging.root.debug('ReaxStore: Querying specific entity - $entityType:$entityId');
        final entityData = await _db.get('$entityType:$entityId');
        entities = entityData != null ? [entityData] : [];
        InstantDBLogging.root.debug('ReaxStore: Specific entity query result - found: ${entityData != null}, data: $entityData');
      } else if (entityType != null) {
        // Query all entities of a specific type
        InstantDBLogging.root.debug('ReaxStore: Querying entities by type - pattern: $entityType:*');
        final allData = await _db.getAll('$entityType:*');
        entities = allData.values.cast<Map<String, dynamic>>().toList();
        InstantDBLogging.root.debug('ReaxStore: Type-based query result - count: ${entities.length}, keys: ${allData.keys.toList()}');
      } else {
        // Query all entities (excluding tx and meta)
        InstantDBLogging.root.debug('ReaxStore: Querying all entities with pattern: *');
        final allEntities = await _db.getAll('*');
        entities = allEntities.entries
            .where((e) => !e.key.startsWith('tx:') && !e.key.startsWith('meta:'))
            .map((e) => e.value)
            .cast<Map<String, dynamic>>()
            .toList();
        InstantDBLogging.root.debug('ReaxStore: All entities query result - total keys: ${allEntities.length}, filtered entities: ${entities.length}');
      }

      // Apply WHERE filtering
      if (where != null) {
        entities = entities.where((entity) => _matchesWhere(entity, where)).toList();
      }

      // Handle aggregations
      if (aggregate != null) {
        return _processAggregations(entities, aggregate, groupBy);
      }

      // Apply ordering
      if (orderBy != null) {
        entities.sort((a, b) => _compareEntities(a, b, orderBy));
      }

      // Apply pagination  
      if (offset != null) {
        entities = entities.skip(offset).toList();
      }
      if (limit != null) {
        entities = entities.take(limit).toList();
        InstantDBLogging.root.debug('ReaxStore: Applied limit $limit - final count: ${entities.length}');
      }

      stopwatch.stop();
      InstantDBLogging.root.debug('ReaxStore: queryEntities completed in ${stopwatch.elapsedMilliseconds}ms - returning ${entities.length} entities');
      return entities;
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Query entities failed - Error: ${e.runtimeType}', e, stackTrace);
      rethrow;
    }
  }

  /// Check if entity matches WHERE conditions (copied from TripleStore)
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

  /// Check if value matches operator conditions (simplified from TripleStore)
  bool _matchesOperator(dynamic entityValue, Map<String, dynamic> operators) {
    for (final entry in operators.entries) {
      final operator = entry.key;
      final operandValue = entry.value;

      switch (operator) {
        case '>':
        case '\$gt':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue as Comparable) <= 0) return false;
          break;
        
        case '<':
        case '\$lt':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue as Comparable) >= 0) return false;
          break;
        
        case '>=':
        case '\$gte':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue as Comparable) < 0) return false;
          break;
        
        case '<=':
        case '\$lte':
          if (entityValue is! Comparable || operandValue is! Comparable) return false;
          if ((entityValue as Comparable).compareTo(operandValue as Comparable) > 0) return false;
          break;
        
        case '\$in':
          if (operandValue is List && !operandValue.contains(entityValue)) return false;
          break;
        
        case '\$nin':
          if (operandValue is List && operandValue.contains(entityValue)) return false;
          break;
        
        case '\$like':
          if (entityValue is! String || operandValue is! String) return false;
          final pattern = (operandValue as String).replaceAll('%', '.*');
          if (!RegExp(pattern, caseSensitive: true).hasMatch(entityValue as String)) return false;
          break;
        
        case '\$ilike':
          if (entityValue is! String || operandValue is! String) return false;
          final pattern = (operandValue as String).replaceAll('%', '.*');
          if (!RegExp(pattern, caseSensitive: false).hasMatch(entityValue as String)) return false;
          break;
        
        case '\$isNull':
          if (operandValue == true && entityValue != null) return false;
          if (operandValue == false && entityValue == null) return false;
          break;
        
        default:
          return false;
      }
    }
    return true;
  }

  /// Compare entities for sorting (simplified from TripleStore)
  int _compareEntities(Map<String, dynamic> a, Map<String, dynamic> b, List<String> orderBy) {
    for (final orderSpec in orderBy) {
      final parts = orderSpec.split(' ');
      final field = parts[0];
      final direction = parts.length > 1 ? parts[1].toLowerCase() : 'asc';
      
      final aValue = a[field];
      final bValue = b[field];
      
      if (aValue == null && bValue == null) continue;
      if (aValue == null) return direction == 'asc' ? -1 : 1;
      if (bValue == null) return direction == 'asc' ? 1 : -1;
      
      int comparison;
      if (aValue is Comparable && bValue is Comparable) {
        comparison = (aValue as Comparable).compareTo(bValue as Comparable);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }
      
      if (comparison != 0) {
        return direction == 'desc' ? -comparison : comparison;
      }
    }
    return 0;
  }

  /// Process aggregations (simplified from TripleStore)
  List<Map<String, dynamic>> _processAggregations(
    List<Map<String, dynamic>> entities,
    Map<String, dynamic> aggregate,
    List<String>? groupBy,
  ) {
    // For now, implement basic aggregations
    // This could be expanded later
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
          
        // Add more aggregation types as needed
      }
    }
    
    return [result];
  }

  /// Rollback a transaction (for ReaxDB, we rely on its atomic transactions)
  Future<void> rollbackTransaction(String txId) async {
    try {
      // ReaxDB transactions are atomic, so rollback is automatic on failure
      // We just need to remove the transaction record if it exists
      await _db.delete('tx:$txId');
      InstantDBLogging.root.debug('ReaxStore: Transaction $txId rolled back');
    } catch (e) {
      InstantDBLogging.root.severe('ReaxStore: Failed to rollback transaction $txId', e);
      rethrow;
    }
  }

  /// Mark a transaction as synced
  Future<void> markTransactionSynced(String txId) async {
    try {
      final txData = await _db.get('tx:$txId');
      if (txData != null && txData is Map<String, dynamic>) {
        final updatedTx = Map<String, dynamic>.from(txData);
        updatedTx['status'] = TransactionStatus.synced.name;
        updatedTx['synced'] = true;
        await _db.put('tx:$txId', updatedTx);
        InstantDBLogging.root.debug('ReaxStore: Transaction $txId marked as synced');
      }
    } catch (e) {
      InstantDBLogging.root.severe('ReaxStore: Failed to mark transaction $txId as synced', e);
      rethrow;
    }
  }

  /// Get pending (unsynced) transactions
  Future<List<Transaction>> getPendingTransactions() async {
    try {
      final allData = await _db.getAll('tx:*');
      final pendingTxs = <Transaction>[];
      
      for (final entry in allData.entries) {
        final txData = entry.value;
        if (txData is Map<String, dynamic>) {
          final synced = txData['synced'] as bool? ?? false;
          final status = txData['status'] as String? ?? 'pending';
          
          if (!synced && status != TransactionStatus.failed.name) {
            // Create a simplified Transaction for pending operations
            final transaction = Transaction(
              id: txData['id'] as String,
              operations: [], // Operations are not stored in metadata
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                txData['timestamp'] as int,
              ),
              status: TransactionStatus.values
                  .firstWhere((s) => s.name == status, 
                             orElse: () => TransactionStatus.pending),
            );
            pendingTxs.add(transaction);
          }
        }
      }
      
      InstantDBLogging.root.debug('ReaxStore: Found ${pendingTxs.length} pending transactions');
      return pendingTxs;
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Failed to get pending transactions', e, stackTrace);
      rethrow;
    }
  }

  /// Clear all data from the store
  Future<void> clearAll() async {
    try {
      InstantDBLogging.root.debug('ReaxStore: Clearing all data');
      
      // Get all keys and delete them
      final allData = await _db.getAll('*');
      for (final key in allData.keys) {
        await _db.delete(key);
      }
      
      // Emit clear event
      _changeController.add(TripleChange.clear());
      InstantDBLogging.root.debug('ReaxStore: All data cleared');
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Failed to clear data', e, stackTrace);
      rethrow;
    }
  }

  /// Resolve entity type by searching for an existing entity with the given ID
  Future<String> _resolveEntityType(String entityId) async {
    try {
      InstantDBLogging.root.debug('ReaxStore: Resolving entity type for ID: $entityId');
      
      // Common entity types to check
      final commonTypes = ['todos', 'users', 'posts', 'comments', 'goals', 'tasks'];
      
      for (final entityType in commonTypes) {
        final entityKey = '$entityType:$entityId';
        InstantDBLogging.root.debug('ReaxStore: Checking entity type: $entityType with key: $entityKey');
        
        final entity = await _db.get(entityKey);
        if (entity != null) {
          InstantDBLogging.root.debug('ReaxStore: Entity found with type: $entityType');
          return entityType;
        }
      }
      
      // If not found in common types, try to find by pattern matching
      InstantDBLogging.root.debug('ReaxStore: Entity not found in common types, searching all data...');
      final allData = await _db.getAll('*');
      
      for (final entry in allData.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // Skip non-entity keys
        if (!key.contains(':')) continue;
        
        final parts = key.split(':');
        if (parts.length != 2) continue;
        
        final entityType = parts[0];
        final keyEntityId = parts[1];
        
        if (keyEntityId == entityId && value is Map<String, dynamic> && value['id'] == entityId) {
          InstantDBLogging.root.debug('ReaxStore: Entity found through search with type: $entityType');
          return entityType;
        }
      }
      
      InstantDBLogging.root.debug('ReaxStore: Entity type resolution failed, returning "unknown"');
      return 'unknown';
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Error resolving entity type for $entityId', e, stackTrace);
      return 'unknown';
    }
  }

  /// Find entity key across all entity types
  Future<String?> _findEntityAcrossTypes(String entityId) async {
    try {
      InstantDBLogging.root.debug('ReaxStore: Searching for entity across all types, ID: $entityId');
      
      final allData = await _db.getAll('*');
      
      for (final entry in allData.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // Skip non-entity keys
        if (!key.contains(':')) continue;
        
        final parts = key.split(':');
        if (parts.length != 2) continue;
        
        final keyEntityId = parts[1];
        
        if (keyEntityId == entityId && value is Map<String, dynamic> && value['id'] == entityId) {
          InstantDBLogging.root.debug('ReaxStore: Entity found with key: $key');
          return key;
        }
      }
      
      InstantDBLogging.root.debug('ReaxStore: Entity not found across any types');
      return null;
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('ReaxStore: Error finding entity across types for $entityId', e, stackTrace);
      return null;
    }
  }

  /// Close the store and clean up resources
  Future<void> close() async {
    try {
      InstantDBLogging.root.debug('ReaxStore: Closing store');
      
      // Cancel all watchers
      for (final subscription in _watchSubscriptions) {
        await subscription.cancel();
      }
      _watchSubscriptions.clear();
      
      // Close change controller
      await _changeController.close();
      
      // Close ReaxDB (if it has a close method)
      // Note: ReaxDB might not need explicit closing, check documentation
      
      InstantDBLogging.root.debug('ReaxStore: Store closed');
    } catch (e) {
      InstantDBLogging.root.severe('ReaxStore: Error closing store', e);
      rethrow;
    }
  }
}