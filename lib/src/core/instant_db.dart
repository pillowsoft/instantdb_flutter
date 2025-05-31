import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import 'types.dart';
import '../storage/triple_store.dart';
import '../query/query_engine.dart';
import '../sync/sync_engine.dart';
import '../auth/auth_manager.dart';
import '../schema/schema.dart';

/// Main InstantDB client
class InstantDB {
  final String appId;
  final InstantConfig config;
  final InstantSchema? schema;

  late final TripleStore _store;
  late final QueryEngine _queryEngine;
  late final SyncEngine _syncEngine;
  late final AuthManager _authManager;

  final Signal<bool> _isReady = signal(false);
  final Signal<bool> _isOnline = signal(false);
  final _uuid = const Uuid();

  /// Whether the database is ready for use
  ReadonlySignal<bool> get isReady => _isReady.readonly();

  /// Whether the database is online and syncing
  ReadonlySignal<bool> get isOnline => _isOnline.readonly();

  /// Authentication manager
  AuthManager get auth => _authManager;

  /// Query engine for reactive queries
  QueryEngine get queries => _queryEngine;

  InstantDB._({
    required this.appId,
    required this.config,
    this.schema,
  });

  /// Initialize a new InstantDB instance
  static Future<InstantDB> init({
    required String appId,
    InstantConfig? config,
    InstantSchema? schema,
  }) async {
    final db = InstantDB._(
      appId: appId,
      config: config ?? const InstantConfig(),
      schema: schema,
    );

    await db._initialize();
    return db;
  }

  Future<void> _initialize() async {
    try {
      // Initialize triple store
      _store = await TripleStore.init(
        appId: appId,
        persistenceDir: config.persistenceDir,
      );

      // Initialize query engine
      _queryEngine = QueryEngine(_store);

      // Initialize auth manager
      _authManager = AuthManager(
        appId: appId,
        baseUrl: config.baseUrl!,
      );

      // Initialize sync engine
      _syncEngine = SyncEngine(
        appId: appId,
        store: _store,
        authManager: _authManager,
        config: config,
      );

      // Connect sync engine events
      effect(() {
        _isOnline.value = _syncEngine.connectionStatus.value;
      });

      // Start sync if enabled
      if (config.syncEnabled) {
        await _syncEngine.start();
      }

      _isReady.value = true;
    } catch (e) {
      throw InstantException(
        message: 'Failed to initialize InstantDB: $e',
        originalError: e,
      );
    }
  }

  /// Generate a new unique ID
  String id() => _uuid.v4();

  /// Execute a query and return a reactive signal
  Signal<QueryResult> query(Map<String, dynamic> query) {
    if (!_isReady.value) {
      throw InstantException(message: 'InstantDB not ready. Call init() first.');
    }
    return _queryEngine.query(query);
  }

  /// Execute a transaction with multiple operations
  Future<TransactionResult> transact(List<Operation> operations) async {
    if (!_isReady.value) {
      throw InstantException(message: 'InstantDB not ready. Call init() first.');
    }

    final txId = id();
    final transaction = Transaction(
      id: txId,
      operations: operations,
      timestamp: DateTime.now(),
    );

    try {
      // Apply optimistically to local store
      await _store.applyTransaction(transaction);

      // Send to sync engine
      final result = await _syncEngine.sendTransaction(transaction);

      return result;
    } catch (e) {
      // Rollback on error
      await _store.rollbackTransaction(txId);
      rethrow;
    }
  }

  /// Create a new entity
  List<Operation> create(String entityType, Map<String, dynamic> data) {
    final entityId = data['id'] as String? ?? id();
    final operations = <Operation>[];

    // Add entity type as __type attribute
    operations.add(Operation(
      type: OperationType.add,
      entityId: entityId,
      attribute: '__type',
      value: entityType,
    ));

    // Add all attributes
    for (final entry in data.entries) {
      operations.add(Operation(
        type: OperationType.add,
        entityId: entityId,
        attribute: entry.key,
        value: entry.value,
      ));
    }

    return operations;
  }

  /// Update an entity
  Operation update(String entityId, Map<String, dynamic> data) {
    // For simplicity, return single operation (real implementation would handle multiple attributes)
    final firstEntry = data.entries.first;
    return Operation(
      type: OperationType.update,
      entityId: entityId,
      attribute: firstEntry.key,
      value: firstEntry.value,
    );
  }

  /// Delete an entity
  Operation delete(String entityId) {
    return Operation(
      type: OperationType.delete,
      entityId: entityId,
    );
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _syncEngine.stop();
    await _store.close();
    _isReady.value = false;
    _isOnline.value = false;
  }
}

/// Transaction builder for fluent API
class TransactionBuilder {
  final InstantDB _db;
  final List<Operation> _operations = [];

  TransactionBuilder(this._db);

  /// Add an operation
  TransactionBuilder add(Operation operation) {
    _operations.add(operation);
    return this;
  }

  /// Create a new entity
  TransactionBuilder create(String entityType, Map<String, dynamic> data) {
    _operations.addAll(_db.create(entityType, data));
    return this;
  }

  /// Update an entity
  TransactionBuilder update(String entityId, Map<String, dynamic> data) {
    _operations.add(_db.update(entityId, data));
    return this;
  }

  /// Delete an entity
  TransactionBuilder delete(String entityId) {
    _operations.add(_db.delete(entityId));
    return this;
  }

  /// Execute the transaction
  Future<TransactionResult> commit() async {
    return await _db.transact(_operations);
  }
}