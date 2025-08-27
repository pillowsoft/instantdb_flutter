import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:logging/logging.dart';

import 'types.dart';
import 'logging_config.dart';
import 'transaction_builder.dart';
import '../storage/storage_interface.dart';
import '../storage/triple_store.dart';
import '../query/query_engine.dart';
import '../sync/sync_engine.dart';
import '../auth/auth_manager.dart';
import '../schema/schema.dart';
import '../reactive/presence.dart';

/// Main InstantDB client
class InstantDB {
  final String appId;
  final InstantConfig config;
  final InstantSchema? schema;

  late final StorageInterface _store;
  late final QueryEngine _queryEngine;
  late final SyncEngine _syncEngine;
  late final AuthManager _authManager;
  late final PresenceManager _presenceManager;

  final Signal<bool> _isReady = signal(false);
  final Signal<bool> _isOnline = signal(false);
  final _uuid = const Uuid();
  String? _anonymousUserId;

  // Transaction namespace for fluent API
  late final TransactionBuilder _txBuilder;

  /// Whether the database is ready for use
  ReadonlySignal<bool> get isReady => _isReady.readonly();

  /// Whether the database is online and syncing
  ReadonlySignal<bool> get isOnline => _isOnline.readonly();

  /// Authentication manager
  AuthManager get auth => _authManager;

  /// Query engine for reactive queries
  QueryEngine get queries => _queryEngine;

  /// Presence manager for collaboration features
  PresenceManager get presence => _presenceManager;

  /// Transaction builder for fluent API (e.g., tx.goals[goalId].update(...))
  TransactionBuilder get tx => _txBuilder;

  InstantDB._({required this.appId, required this.config, this.schema});

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
      // Configure the new hierarchical logging system
      InstantDBLogging.configure(
        level: config.verboseLogging ? Level.FINE : Level.INFO,
        enableHierarchical: true,
        instanceId: 'Instance-${DateTime.now().millisecondsSinceEpoch % 10000}',
      );

      // Initialize SQLite storage backend
      InstantDBLogging.root.debug('Initializing SQLite storage backend');
      _store = await TripleStore.init(
        appId: appId,
        persistenceDir: config.persistenceDir,
      );

      // Initialize query engine
      _queryEngine = QueryEngine(_store);

      // Initialize auth manager
      _authManager = AuthManager(appId: appId, baseUrl: config.baseUrl!);

      // Initialize presence manager first (without sync engine)
      _presenceManager = PresenceManager(
        syncEngine: null, // Will be set later
        authManager: _authManager,
        db: this, // Pass this InstantDB instance
      );

      // Initialize sync engine with presence manager
      _syncEngine = SyncEngine(
        appId: appId,
        store: _store,
        authManager: _authManager,
        config: config,
        presenceManager: config.syncEnabled ? _presenceManager : null,
      );

      // Now wire up the presence manager to sync engine
      if (config.syncEnabled) {
        _presenceManager.setSyncEngine(_syncEngine);
      }

      // Initialize transaction builder
      _txBuilder = TransactionBuilder();

      // Wire up sync engine to query engine
      _queryEngine.setSyncEngine(_syncEngine);

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

  /// Get the consistent anonymous user ID for this database instance
  String getAnonymousUserId() {
    _anonymousUserId ??= _uuid.v4();
    return _anonymousUserId!;
  }

  /// Execute a query and return a reactive signal
  Signal<QueryResult> query(Map<String, dynamic> query) {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }
    return _queryEngine.query(query);
  }

  /// Execute a query once and return the current result
  Future<QueryResult> queryOnce(Map<String, dynamic> query) async {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }

    // Execute the query and get the current value
    final querySignal = _queryEngine.query(query);

    // Wait a bit for the query to execute if it's loading
    if (querySignal.value.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return querySignal.value;
  }

  /// Execute a transaction with operations or transaction chunk
  /// Accepts either List<Operation> or TransactionChunk for React API compatibility
  Future<TransactionResult> transact(dynamic transaction) async {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }

    // Handle both List<Operation> and TransactionChunk
    final List<Operation> operations;
    if (transaction is TransactionChunk) {
      operations = transaction.operations;
    } else if (transaction is List<Operation>) {
      operations = transaction;
    } else {
      throw InstantException(
        message:
            'transact() expects either List<Operation> or TransactionChunk, got ${transaction.runtimeType}',
      );
    }

    final txId = id();
    InstantDBLogging.root.debug(
      'InstantDB: Creating transaction $txId with ${operations.length} operations - StorageBackend: SQLite',
    );

    final tx = Transaction(
      id: txId,
      operations: operations,
      timestamp: DateTime.now(),
    );

    try {
      // Apply optimistically to local store
      InstantDBLogging.root.debug(
        'InstantDB: Applying transaction $txId to local storage (${_store.runtimeType})',
      );
      final applyStopwatch = Stopwatch()..start();
      await _store.applyTransaction(tx);
      applyStopwatch.stop();
      InstantDBLogging.root.debug(
        'InstantDB: Local storage apply completed in ${applyStopwatch.elapsedMilliseconds}ms',
      );

      // Send to sync engine
      InstantDBLogging.root.debug(
        'InstantDB: Sending transaction $txId to sync engine',
      );
      final syncStopwatch = Stopwatch()..start();
      final result = await _syncEngine.sendTransaction(tx);
      syncStopwatch.stop();
      InstantDBLogging.root.debug(
        'InstantDB: Sync engine send completed in ${syncStopwatch.elapsedMilliseconds}ms - Status: ${result.status}',
      );

      return result;
    } catch (e, stackTrace) {
      // Rollback on error
      InstantDBLogging.root.severe(
        'InstantDB: Transaction $txId failed, performing rollback',
        e,
        stackTrace,
      );
      await _store.rollbackTransaction(txId);
      rethrow;
    }
  }

  /// @Deprecated - Use transact() instead
  /// Kept for backward compatibility
  @Deprecated(
    'Use transact() instead - it now accepts TransactionChunk directly',
  )
  Future<TransactionResult> transactChunk(TransactionChunk chunk) async {
    return transact(chunk);
  }

  /// Alias for query - for API compatibility
  Signal<QueryResult> subscribeQuery(Map<String, dynamic> query) {
    return this.query(query);
  }

  /// Get current auth state
  AuthUser? getAuth() {
    return _authManager.currentUser.value;
  }

  /// Subscribe to auth state changes
  Stream<AuthUser?> subscribeAuth() {
    return _authManager.onAuthStateChange;
  }

  /// Create a new entity (legacy API - use tx namespace for new code)
  List<Operation> create(String entityType, Map<String, dynamic> data) {
    final entityId = data['id'] as String? ?? id();

    // Ensure __type is in the data
    final fullData = Map<String, dynamic>.from(data);
    fullData['__type'] = entityType;

    return [
      Operation(
        type: OperationType.add,
        entityType: entityType,
        entityId: entityId,
        data: fullData,
      ),
    ];
  }

  /// Update an entity (legacy API - use tx namespace for new code)
  List<Operation> update(String entityId, Map<String, dynamic> data) {
    return [
      Operation(
        type: OperationType.update,
        entityType: 'unknown', // Will be resolved by store
        entityId: entityId,
        data: data,
      ),
    ];
  }

  /// Delete an entity (legacy API - use tx namespace for new code)
  Operation delete(String entityId) {
    InstantDBLogging.root.debug(
      'InstantDB: Creating delete operation for entity "$entityId"',
    );
    InstantDBLogging.root.debug(
      'InstantDB: Original entity ID type: ${entityId.runtimeType}, length: ${entityId.length}',
    );

    // Validate entity ID to prevent corrupted IDs
    String cleanEntityId = entityId;

    // Check if entity ID looks like a stringified array
    if (cleanEntityId.startsWith('[') && cleanEntityId.endsWith(']')) {
      InstantDBLogging.root.debug(
        'InstantDB: Detected array-like entity ID, attempting to clean',
      );
      try {
        // Try to parse it as JSON array and extract first element
        final parsed = jsonDecode(cleanEntityId);
        if (parsed is List && parsed.isNotEmpty) {
          cleanEntityId = parsed[0].toString();
          InstantDBLogging.root.debug(
            'InstantDB: Fixed corrupted entity ID in delete from "$entityId" to "$cleanEntityId"',
          );
        }
      } catch (e) {
        InstantDBLogging.root.debug(
          'InstantDB: Failed to parse array-like entity ID, trying UUID extraction: $e',
        );
        // If parsing fails, try to extract first UUID-like string
        final uuidPattern = RegExp(
          r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        );
        final match = uuidPattern.firstMatch(cleanEntityId);
        if (match != null) {
          cleanEntityId = match.group(0)!;
          InstantDBLogging.root.debug(
            'InstantDB: Extracted entity ID "$cleanEntityId" from corrupted string in delete',
          );
        } else {
          InstantDBLogging.root.debug(
            'InstantDB: No UUID pattern found in corrupted entity ID',
          );
        }
      }
    }

    final operation = Operation(
      type: OperationType.delete,
      entityType: 'unknown', // Will be resolved by store
      entityId: cleanEntityId,
    );

    InstantDBLogging.root.debug(
      'InstantDB: Delete operation created - Type: ${operation.type}, EntityType: ${operation.entityType}, EntityId: ${operation.entityId}',
    );
    InstantDBLogging.root.debug(
      'InstantDB: Final cleaned entity ID: "$cleanEntityId" (original: "$entityId")',
    );

    return operation;
  }

  /// Clear all local data (useful for development/debugging)
  Future<void> clearLocalDatabase() async {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }

    await _store.clearAll();
    InstantDBLogging.root.debug('Local database cleared');
  }

  /// Clean up resources
  Future<void> dispose() async {
    _presenceManager.dispose();
    await _syncEngine.stop();
    await _store.close();
    _isReady.value = false;
    _isOnline.value = false;
  }
}
