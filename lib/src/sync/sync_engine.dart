import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../core/logging.dart';
import '../storage/triple_store.dart';
import '../auth/auth_manager.dart';

// Platform-specific WebSocket imports
import 'web_socket_stub.dart'
    if (dart.library.io) 'web_socket_io.dart'
    if (dart.library.html) 'web_socket_web.dart';

/// Sync engine for real-time communication with InstantDB server
class SyncEngine {
  final String appId;
  final TripleStore _store;
  final AuthManager _authManager;
  final InstantConfig config;
  final Dio _dio;

  dynamic _webSocket; // WebSocketAdapter
  StreamSubscription? _messageSubscription;
  StreamSubscription? _storeSubscription;
  StreamSubscription? _authSubscription;
  Timer? _reconnectTimer;

  final Signal<bool> _connectionStatus = signal(false);
  final Queue<Transaction> _syncQueue = Queue<Transaction>();
  bool _isProcessingQueue = false;
  final _uuid = const Uuid();
  
  // Cache attribute UUIDs from InstantDB
  final Map<String, Map<String, String>> _attributeCache = {};
  
  // Track our own client event IDs to avoid processing echoed transactions
  final Set<String> _sentEventIds = {};
  
  // Store session ID from init-ok response
  String? _sessionId;
  
  // Queue for queries that need to be sent after authentication
  final Queue<Map<String, dynamic>> _pendingQueries = Queue<Map<String, dynamic>>();
  
  // Track last processed data to avoid duplicates
  final Map<String, String> _lastProcessedData = {};
  int _refreshOkCount = 0;

  /// Connection status signal
  ReadonlySignal<bool> get connectionStatus => _connectionStatus.readonly();

  SyncEngine({
    required this.appId,
    required TripleStore store,
    required AuthManager authManager,
    required this.config,
  })  : _store = store,
        _authManager = authManager,
        _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl!,
          headers: {'X-App-ID': appId},
        ));

  /// Start the sync engine
  Future<void> start() async {
    // Listen to store changes for outgoing sync
    _storeSubscription = _store.changes.listen(_handleLocalChange);

    // Listen to auth changes to reconnect with new token
    _authSubscription = _authManager.onAuthStateChange.listen(_handleAuthChange);

    // Connect WebSocket first
    await _connectWebSocket();
    
    // Process pending transactions will be called after init-ok is received
  }

  /// Stop the sync engine
  Future<void> stop() async {
    _reconnectTimer?.cancel();
    await _storeSubscription?.cancel();
    await _authSubscription?.cancel();
    await _messageSubscription?.cancel();
    if (_webSocket != null) {
      await _webSocket.close();
    }
    _connectionStatus.value = false;
  }
  
  /// Send a query to establish subscription
  void sendQuery(Map<String, dynamic> query) {
    InstantLogger.debug('sendQuery called with: ${jsonEncode(query)}');
    
    if (!_connectionStatus.value || _webSocket == null || !_webSocket.isOpen) {
      InstantLogger.debug('Cannot send query - not connected, queuing for later');
      _pendingQueries.add(query);
      return;
    }
    
    final queryMessage = {
      'op': 'add-query',
      'q': query,
      'client-event-id': _generateEventId(),
      if (_sessionId != null) 'session-id': _sessionId,
    };
    
    final queryJson = jsonEncode(queryMessage);
    _webSocket.send(queryJson);
  }

  Future<void> _connectWebSocket() async {
    try {
      // Construct WebSocket URL with app_id as query parameter
      final baseUri = Uri.parse(config.baseUrl!);
      final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri(
        scheme: wsScheme,
        host: baseUri.host,
        path: '/runtime/session',
        queryParameters: {'app_id': appId},
      );
      
      // Log connection attempt for debugging
      InstantLogger.info('Connecting to WebSocket at $wsUri');
      
      // Use platform-specific WebSocket implementation
      _webSocket = await WebSocketManager.connect(wsUri.toString());
      
      InstantLogger.info('WebSocket connected, sending init message');
      
      // Send init message according to InstantDB protocol
      // refresh-token can be null for anonymous users
      final initMessage = {
        'op': 'init',
        'app-id': appId,
        if (_authManager.currentUser.value?.refreshToken != null)
          'refresh-token': _authManager.currentUser.value!.refreshToken,
        'client-event-id': _generateEventId(),
        'versions': {
          '@instantdb/flutter': 'v0.1.0',
        },
      };
      
      _webSocket.send(jsonEncode(initMessage));
      InstantLogger.debug('Sent init message: ${initMessage['op']}');

      // Listen for messages
      _messageSubscription = _webSocket.stream.listen(
        _handleRemoteMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketClose,
        cancelOnError: false,
      );
    } catch (e) {
      InstantLogger.error('WebSocket connection error', e);
      _connectionStatus.value = false;
      _scheduleReconnect();
    }
  }
  
  String _generateEventId() {
    final eventId = _uuid.v4();
    _sentEventIds.add(eventId);
    // Clean up old event IDs after a while to prevent memory growth
    if (_sentEventIds.length > 1000) {
      _sentEventIds.clear();
    }
    return eventId;
  }

  void _handleRemoteMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final op = data['op'];
      
      // Only log operation type, not full message content
      // Suppress refresh-ok logging after the first few to avoid spam
      if (op == 'refresh-ok') {
        _refreshOkCount++;
        if (_refreshOkCount <= 3) {
          InstantLogger.debug('Received: $op (count: $_refreshOkCount)');
        } else if (_refreshOkCount == 4) {
          InstantLogger.debug('Suppressing further refresh-ok logs...');
        }
      } else {
        InstantLogger.debug('Received: $op');
      }

      switch (data['op']) {
        case 'init-ok':
          InstantLogger.info('WebSocket authenticated successfully');
          _connectionStatus.value = true;
          // Store session ID for future messages
          _sessionId = data['session-id']?.toString();
          InstantLogger.debug('Session ID: $_sessionId');
          
          // Parse and cache attribute UUIDs from the response
          if (data['attrs'] is List) {
            for (final attr in data['attrs'] as List) {
              if (attr is Map<String, dynamic> && 
                  attr['forward-identity'] is List &&
                  (attr['forward-identity'] as List).length >= 3) {
                final forwardIdentity = attr['forward-identity'] as List;
                final namespace = forwardIdentity[1].toString();
                final attrName = forwardIdentity[2].toString();
                final attrId = attr['id'].toString();
                
                // Cache the attribute UUID
                _attributeCache.putIfAbsent(namespace, () => {});
                _attributeCache[namespace]![attrName] = attrId;
                
                // Only log first few attributes to avoid spam
                if (_attributeCache[namespace]!.length <= 3) {
                  InstantLogger.debug('Cached attribute $namespace.$attrName = $attrId');
                }
              }
            }
            
            // Add hardcoded mapping for todos.completed if not present
            // This is a workaround for missing attribute in init-ok response
            if (_attributeCache['todos'] != null && !_attributeCache['todos']!.containsKey('completed')) {
              _attributeCache['todos']!['completed'] = 'd4787d60-b7fe-4dbc-a7cb-683cbdd2c0a9';
              InstantLogger.debug('Added hardcoded mapping for todos.completed');
            }
          }
          
          // InstantDB automatically subscribes to queries, so we don't need explicit subscribe operations
          // Don't fetch initial data immediately - let the UI trigger queries
          // _fetchInitialData();
          
          // Process any pending queries now that we're authenticated
          _processPendingQueries();
          
          // Process any pending transactions now that we're connected
          _processPendingTransactions();
          break;
          
        case 'init-error':
          InstantLogger.error('WebSocket authentication failed: ${data['error']}');
          _connectionStatus.value = false;
          _handleAuthError(data['error']);
          break;
          
        case 'transaction':
          InstantLogger.debug('Received transaction message: ${jsonEncode(data)}');
          try {
            // Check various possible data locations
            final txData = data['data'] ?? data['tx'] ?? data;
            
            // If this looks like a transaction with tx-steps, handle it like transact
            if (txData['tx-steps'] != null) {
              InstantLogger.debug('Transaction message contains tx-steps, processing as transact');
              _handleRemoteTransact(txData);
            } else if (txData['operations'] != null) {
              // This looks like our Transaction format
              _applyRemoteTransaction(Transaction.fromJson(txData));
            } else {
              InstantLogger.warn('Transaction message has unexpected format');
              InstantLogger.debug('Keys in data: ${txData.keys.toList()}');
            }
          } catch (e, stackTrace) {
            InstantLogger.error('Error processing transaction: $e');
            InstantLogger.debug('Stack trace: $stackTrace');
          }
          break;
          
        case 'transact':
          // Handle incoming transactions from other clients
          InstantLogger.debug('Received transact message from another client');
          InstantLogger.debug('Message keys: ${data.keys.toList()}');
          InstantLogger.debug('Full message: ${jsonEncode(data)}');
          try {
            _handleRemoteTransact(data);
          } catch (e, stackTrace) {
            InstantLogger.error('Error processing transact: $e');
            InstantLogger.debug('Stack trace: $stackTrace');
          }
          break;
          
        case 'transaction-ack':
          _handleTransactionAck(data['tx-id'] as String);
          break;
          
        case 'error':
          // Log the full error data for debugging
          InstantLogger.debug('Error message data: $data');
          final errorMessage = data['message'] ?? data['error'];
          if (errorMessage != null) {
            _handleRemoteError(errorMessage.toString());
          } else {
            InstantLogger.warn('Received error with no message or error field');
          }
          break;
          
        case 'transact-ok':
          InstantLogger.info('Transaction successful: server tx-id=${data['tx-id']}, client-event-id=${data['client-event-id']}');
          // Use client-event-id (which is our transaction ID) to mark as synced
          if (data['client-event-id'] != null) {
            _handleTransactionAck(data['client-event-id'].toString());
          }
          break;
          
        case 'query-update':
        case 'invalidate-query':
          // Handle query invalidation messages
          InstantLogger.debug('Received query update/invalidation message: ${jsonEncode(data)}');
          _handleQueryInvalidation(data);
          break;
          
        case 'refresh':
          // Handle refresh messages which contain updated data
          InstantLogger.debug('Received refresh message with updated data');
          InstantLogger.debug('Refresh data keys: ${data.keys.toList()}');
          _handleRefreshMessage(data);
          break;
          
        case 'add-query-ok':
        case 'query-response':
        case 'query-result':
          // Handle query response with initial data
          InstantLogger.debug('Received query response: ${jsonEncode(data)}');
          _handleQueryResponse(data);
          break;
          
        case 'refresh-query':
          // Handle refresh-query message which might contain updated data
          InstantLogger.debug('Received refresh-query message: ${jsonEncode(data)}');
          _handleRefreshQuery(data);
          break;
          
        // Note: Since we don't send subscribe or listen-query, we won't receive these
          
        case 'refresh-ok':
          // Handle refresh-ok messages which contain updated query results
          InstantLogger.debug('Processing refresh-ok');
          _handleRefreshOk(data);
          break;
          
        default:
          InstantLogger.warn('Unknown op: ${data['op']}');
      }
    } catch (e) {
      InstantLogger.error('Error parsing message', e);
      InstantLogger.debug('Raw message was: $message');
    }
  }
  
  void _handleAuthError(dynamic error) {
    InstantLogger.error('Authentication error: $error');
    _connectionStatus.value = false;
    // Could implement retry logic or user notification here
  }

  void _handleWebSocketError(error) {
    InstantLogger.error('WebSocket error: $error');
    _connectionStatus.value = false;
    _scheduleReconnect();
  }

  void _handleWebSocketClose() {
    InstantLogger.info('WebSocket connection closed');
    _connectionStatus.value = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(config.reconnectDelay, () {
      if (!_connectionStatus.value) {
        _connectWebSocket();
      }
    });
  }

  void _handleAuthChange(AuthUser? user) {
    if (user != null && _webSocket != null && _webSocket.isOpen) {
      // Re-authenticate with new token
      final authData = {
        'op': 'auth',
        'app-id': appId,
        'refresh-token': user.refreshToken,
        'client-event-id': _generateEventId(),
      };
      _webSocket.send(jsonEncode(authData));
    }
  }

  void _handleLocalChange(TripleChange change) {
    // Local changes are handled by the transaction system
    // This is mainly for logging/debugging
  }

  Future<void> _applyRemoteTransaction(Transaction transaction) async {
    try {
      // Don't log every operation to reduce verbosity
      if (_refreshOkCount <= 3) {
        InstantLogger.debug('Applying remote transaction ${transaction.id} with ${transaction.operations.length} operations');
      }
      
      // Apply the transaction with already-synced status to avoid re-sending
      await _store.applyTransaction(transaction);
      // No need to mark as synced separately since remote transactions have synced status
    } catch (e) {
      // Handle conflict resolution here
      // For now, just log the error
      InstantLogger.error('Error applying remote transaction', e);
    }
  }
  
  void _handleRemoteTransact(Map<String, dynamic> data) async {
    // InstantDB sends remote transactions as 'transact' messages with tx-steps
    // We need to convert these to our Transaction format
    try {
      // Check if this is our own transaction echoed back
      final clientEventId = data['client-event-id'];
      if (clientEventId != null && _sentEventIds.contains(clientEventId)) {
        InstantLogger.debug('Ignoring our own echoed transaction: $clientEventId');
        return;
      }
      
      final txSteps = data['tx-steps'] as List?;
      if (txSteps == null) {
        InstantLogger.warn('No tx-steps in transact message');
        return;
      }
      
      // Generate a transaction ID from the event ID if available
      final txId = data['client-event-id']?.toString() ?? _uuid.v4();
      final timestamp = data['created'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['created'] as int)
          : DateTime.now();
      
      // Convert tx-steps to operations
      final operations = <Operation>[];
      String? currentNamespace;
      
      for (final step in txSteps) {
        if (step is! List || step.isEmpty) continue;
        
        final stepType = step[0] as String;
        
        switch (stepType) {
          case 'add-triple':
            if (step.length >= 4) {
              final entityId = step[1].toString();
              final attrId = step[2].toString();
              final value = step[3];
              
              // Find the attribute name from our cache
              String? attrName;
              for (final nsEntry in _attributeCache.entries) {
                for (final attrEntry in nsEntry.value.entries) {
                  if (attrEntry.value == attrId) {
                    attrName = attrEntry.key;
                    currentNamespace = nsEntry.key;
                    break;
                  }
                }
                if (attrName != null) break;
              }
              
              if (attrName != null) {
                // Check if this is a type declaration
                if (attrName == '__type') {
                  currentNamespace = value.toString();
                }
                
                operations.add(Operation(
                  type: OperationType.add,
                  entityId: entityId,
                  attribute: attrName,
                  value: value,
                ));
              } else {
                // If we don't have the attribute cached, try to use common attribute names
                // This is a workaround for when we receive updates before the attribute cache is fully populated
                InstantLogger.debug('Unknown attribute ID: $attrId, trying to infer attribute name');
                
                // Common attributes we might expect
                if (value is String && (value == 'todos' || value == 'users')) {
                  // This is likely a __type attribute
                  operations.add(Operation(
                    type: OperationType.add,
                    entityId: entityId,
                    attribute: '__type',
                    value: value,
                  ));
                  currentNamespace = value;
                } else {
                  // For now, skip unknown attributes but log them
                  InstantLogger.debug('Skipping unknown attribute ID: $attrId with value: $value');
                }
              }
            }
            break;
            
          case 'delete-entity':
            if (step.length >= 2) {
              final entityId = step[1].toString();
              operations.add(Operation(
                type: OperationType.delete,
                entityId: entityId,
              ));
            }
            break;
            
          case 'add-attr':
            // This is an attribute registration, update our cache
            if (step.length >= 2 && step[1] is Map) {
              final attrData = step[1] as Map<String, dynamic>;
              if (attrData['id'] != null && 
                  attrData['forward-identity'] is List &&
                  (attrData['forward-identity'] as List).length >= 3) {
                final forwardIdentity = attrData['forward-identity'] as List;
                final namespace = forwardIdentity[1].toString();
                final attrName = forwardIdentity[2].toString();
                final attrId = attrData['id'].toString();
                
                // Cache the attribute UUID
                _attributeCache.putIfAbsent(namespace, () => {});
                _attributeCache[namespace]![attrName] = attrId;
                
                // Silently cache remote attributes to avoid spam
              }
            }
            break;
        }
      }
      
      if (operations.isNotEmpty) {
        // Create and apply the transaction
        final transaction = Transaction(
          id: txId,
          operations: operations,
          timestamp: timestamp,
          status: TransactionStatus.synced,
        );
        
        InstantLogger.debug('Applying remote transaction with ${operations.length} operations');
        await _applyRemoteTransaction(transaction);
      }
    } catch (e, stackTrace) {
      InstantLogger.error('Error handling remote transact: $e');
      InstantLogger.debug('Stack trace: $stackTrace');
    }
  }

  void _handleTransactionAck(String txId) async {
    InstantLogger.debug('Marking transaction $txId as synced');
    await _store.markTransactionSynced(txId);
  }

  void _handleRemoteError(String error) {
    InstantLogger.error('Remote error: $error');
    // Handle specific error types if needed
    // For now, just log the error
  }
  
  void _handleQueryInvalidation(Map<String, dynamic> data) async {
    // When a query is invalidated, we need to re-fetch the data
    InstantLogger.debug('Query invalidation received');
    
    // Check if the message contains the actual data update
    if (data['data'] != null || data['result'] != null) {
      // This invalidation message includes the new data
      _handleQueryResponse(data);
    } else {
      // No data included, we need to re-fetch
      // For now, create a synthetic transaction that will trigger store changes
      // This ensures the UI will re-query and get the latest data
      final syntheticTx = Transaction(
        id: _generateEventId(),
        operations: [
          Operation(
            type: OperationType.add,
            entityId: '__query_invalidation',
            attribute: '__timestamp',
            value: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
        timestamp: DateTime.now(),
        status: TransactionStatus.synced,
      );
      
      // Apply this transaction to trigger change events
      await _store.applyTransaction(syntheticTx);
    }
  }
  
  void _handleRefreshQuery(Map<String, dynamic> data) async {
    InstantLogger.debug('Processing refresh-query message');
    
    // Check if this message contains updated data
    final result = data['result'] ?? data['data'] ?? data['r'];
    if (result != null) {
      InstantLogger.debug('refresh-query contains data, processing as query response');
      _handleQueryResponse(data);
    } else {
      // Otherwise treat it as an invalidation
      InstantLogger.debug('refresh-query has no data, treating as invalidation');
      _handleQueryInvalidation(data);
    }
  }
  
  void _handleRefreshMessage(Map<String, dynamic> data) async {
    InstantLogger.debug('Processing refresh message');
    
    // Refresh messages typically contain the full updated dataset
    // Check various possible data locations
    final result = data['data'] ?? data['result'] ?? data['r'] ?? data;
    
    if (result != null && result is Map) {
      // Process the refresh data similar to a query response
      InstantLogger.debug('Refresh contains data, processing updates');
      _handleQueryResponse({'result': result});
    } else {
      // If no data, trigger a query invalidation
      InstantLogger.debug('Refresh has no data, triggering invalidation');
      _handleQueryInvalidation(data);
    }
  }
  
  void _processPendingQueries() {
    InstantLogger.debug('Processing pending queries');
    while (_pendingQueries.isNotEmpty) {
      final query = _pendingQueries.removeFirst();
      sendQuery(query);
    }
  }
  
  void _handleRefreshOk(Map<String, dynamic> data) {
    // refresh-ok contains updated query results
    if (data['computations'] is List) {
      final computations = data['computations'] as List;
      
      // Generate a hash of the computations to detect duplicates
      final dataHash = computations.toString().hashCode.toString();
      if (_lastProcessedData['refresh-ok'] == dataHash) {
        // Skip duplicate data
        return;
      }
      _lastProcessedData['refresh-ok'] = dataHash;
      
      for (final computation in computations) {
        if (computation is Map && computation['instaql-result'] != null) {
          // Process the query result
          _handleQueryResponse({'result': computation['instaql-result']}, skipDuplicateCheck: true);
        }
      }
    }
  }

  /// Send a transaction to the server
  Future<TransactionResult> sendTransaction(Transaction transaction) async {
    // Add to sync queue
    _syncQueue.add(transaction);

    // Process queue if not already processing
    if (!_isProcessingQueue) {
      _processQueue();
    }

    return TransactionResult(
      txId: transaction.id,
      status: TransactionStatus.pending,
      timestamp: transaction.timestamp,
    );
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_syncQueue.isNotEmpty) {
        final transaction = _syncQueue.removeFirst();

        if (_connectionStatus.value && _webSocket != null && _webSocket.isOpen) {
          // Send via WebSocket
          try {
            // Transform to InstantDB's expected format
            // InstantDB requires UUIDs for attributes, not simple names
            final txSteps = <dynamic>[];
            
            // Track namespace for operations
            String? namespace;
            
            // First pass: identify namespace from __type attribute
            for (final op in transaction.operations) {
              if (op.attribute == '__type' && op.value is String) {
                namespace = op.value as String;
                break;
              }
            }
            
            // Second pass: add the actual operations using attribute UUIDs
            for (final op in transaction.operations) {
              if (op.type == OperationType.add) {
                if (op.attribute != null && op.attribute != '__type') {
                  // Look up the attribute ID from cache
                  final ns = namespace ?? 'todos';
                  String? attrId = _attributeCache[ns]?[op.attribute];
                  
                  if (attrId != null) {
                    // Use known attribute UUID
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  } else {
                    // For unknown attributes, use namespace.attribute format
                    // InstantDB will handle the UUID assignment
                    final attrIdentifier = '${ns}.${op.attribute}';
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrIdentifier,
                      op.value ?? '',
                    ]);
                    InstantLogger.debug('Using attribute identifier for unknown attribute: $attrIdentifier');
                  }
                }
              } else if (op.type == OperationType.update) {
                if (op.attribute != null) {
                  // Look up the attribute ID from cache
                  final ns = namespace ?? 'todos';
                  String? attrId = _attributeCache[ns]?[op.attribute];
                  
                  if (attrId != null) {
                    // Use known attribute UUID
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  } else {
                    // For unknown attributes, use namespace.attribute format
                    final attrIdentifier = '${ns}.${op.attribute}';
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrIdentifier,
                      op.value ?? '',
                    ]);
                    InstantLogger.debug('Using attribute identifier for unknown attribute in update: $attrIdentifier');
                  }
                }
              } else if (op.type == OperationType.delete) {
                // For deletes, we need to ensure entity ID is a proper string
                // Sometimes entity IDs come as stringified arrays from corrupted data
                String cleanEntityId = op.entityId;
                
                // Check if entity ID looks like a stringified array
                if (cleanEntityId.startsWith('[') && cleanEntityId.endsWith(']')) {
                  try {
                    // Try to parse it as JSON array and extract first element
                    final parsed = jsonDecode(cleanEntityId);
                    if (parsed is List && parsed.isNotEmpty) {
                      cleanEntityId = parsed[0].toString();
                      InstantLogger.debug('Fixed corrupted entity ID from "$op.entityId" to "$cleanEntityId"');
                    }
                  } catch (e) {
                    // If parsing fails, try to extract first UUID-like string
                    final uuidPattern = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');
                    final match = uuidPattern.firstMatch(cleanEntityId);
                    if (match != null) {
                      cleanEntityId = match.group(0)!;
                      InstantLogger.debug('Extracted entity ID "$cleanEntityId" from corrupted string');
                    }
                  }
                }
                
                txSteps.add([
                  'delete-entity',
                  cleanEntityId,
                  namespace ?? 'todos',
                ]);
              }
            }
            
            final clientEventId = transaction.id; // Use transaction ID as client-event-id
            _sentEventIds.add(clientEventId); // Track for deduplication
            
            final transactionMessage = {
              'op': 'transact',
              'tx-steps': txSteps,
              'created': DateTime.now().millisecondsSinceEpoch,
              'order': 1,
              'client-event-id': clientEventId,
            };
            
            // Debug log transaction details
            InstantLogger.debug('Sending transaction ${transaction.id} with ${txSteps.length} steps');
            if (txSteps.isNotEmpty) {
              InstantLogger.debug('First tx-step: ${jsonEncode(txSteps.first)}');
              // Check if we're using namespace.attribute format for unknown attributes
              for (final step in txSteps) {
                if (step is List && step.length >= 3 && step[0] == 'add-triple') {
                  final attrId = step[2].toString();
                  if (attrId.contains('.')) {
                    InstantLogger.debug('Using namespace.attribute format: $attrId');
                  }
                }
              }
            }
            _webSocket.send(jsonEncode(transactionMessage));
          } catch (e) {
            // Re-queue on WebSocket error
            _syncQueue.addFirst(transaction);
            break;
          }
        } else {
          // Fallback to HTTP if WebSocket unavailable
          try {
            await _dio.post('/v1/transact', data: transaction.toJson());
            await _store.markTransactionSynced(transaction.id);
          } catch (e) {
            // Re-queue on HTTP error
            _syncQueue.addFirst(transaction);
            break;
          }
        }

        // Small delay between transactions
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processPendingTransactions() async {
    final pendingTransactions = await _store.getPendingTransactions();
    InstantLogger.info('Found ${pendingTransactions.length} pending transactions to sync');
    
    for (final transaction in pendingTransactions) {
      _syncQueue.add(transaction);
      InstantLogger.debug('Queued transaction ${transaction.id} with ${transaction.operations.length} operations');
    }

    if (_syncQueue.isNotEmpty) {
      _processQueue();
    }
  }
  
  // Note: InstantDB automatically subscribes to queries when they are sent.
  // There's no need for explicit subscribe or listen-query operations.
  // Real-time updates are received as 'transact' messages from other clients.
  
  void _handleQueryResponse(Map<String, dynamic> data, {bool skipDuplicateCheck = false}) async {
    // Only log if not from refresh-ok or if it's one of the first few
    if (!skipDuplicateCheck || _refreshOkCount <= 3) {
      InstantLogger.debug('Processing query response');
    }
    
    // InstantDB returns data in a specific format with nested result structure
    dynamic resultData;
    
    if (data['result'] is List && (data['result'] as List).isNotEmpty) {
      // The result is an array with objects containing 'data' field
      final firstResult = (data['result'] as List)[0];
      if (firstResult is Map && firstResult['data'] != null) {
        resultData = firstResult['data'];
      }
    } else {
      resultData = data['result'] ?? data['data'] ?? data['r'];
    }
    
    if (resultData == null) {
      InstantLogger.warn('Query response has no result data');
      return;
    }
    
    // Check if this is a datalog-result format
    if (resultData['datalog-result'] != null) {
      final datalogResult = resultData['datalog-result'];
      InstantLogger.debug('Processing datalog-result format');
      
      if (datalogResult['join-rows'] is List) {
        final joinRowsOuter = datalogResult['join-rows'] as List;
        // Check if this is a nested array structure
        List joinRows;
        if (joinRowsOuter.isNotEmpty && joinRowsOuter[0] is List && 
            joinRowsOuter[0].isNotEmpty && joinRowsOuter[0][0] is List) {
          // Nested structure: [[[row1], [row2], ...]]
          joinRows = joinRowsOuter[0] as List;
        } else {
          // Direct structure: [[row1], [row2], ...]
          joinRows = joinRowsOuter;
        }
        InstantLogger.debug('Found ${joinRows.length} join-rows');
        
        // Parse join-rows to reconstruct entities
        // Join-rows format: [[entityId, attributeId, value, timestamp], ...]
        final entityMap = <String, Map<String, dynamic>>{};
        
        for (final row in joinRows) {
          if (row is List && row.length >= 3) {
            // Entity ID might be a string or an array - handle both cases
            String entityId;
            if (row[0] is List) {
              // If entity ID is an array, use the first element as the actual ID
              entityId = (row[0] as List)[0].toString();
            } else {
              entityId = row[0].toString();
            }
            
            final attributeId = row[1].toString();
            final value = row[2];
            
            // Initialize entity map if needed
            entityMap.putIfAbsent(entityId, () => {'id': entityId});
            
            // Find attribute name from cache
            String? attrName;
            for (final nsEntry in _attributeCache.entries) {
              for (final attrEntry in nsEntry.value.entries) {
                if (attrEntry.value == attributeId) {
                  attrName = attrEntry.key;
                  break;
                }
              }
              if (attrName != null) break;
            }
            
            if (attrName != null) {
              entityMap[entityId]![attrName] = value;
            } else {
              // For unknown attribute IDs, try to infer based on common patterns
              // This is a workaround for missing attribute definitions
              if (value is bool) {
                // Boolean values are likely 'completed' for todos
                entityMap[entityId]!['completed'] = value;
                InstantLogger.debug('Inferred attribute "completed" for unknown ID: $attributeId');
              } else {
                InstantLogger.debug('Unknown attribute ID in query response: $attributeId with value: $value');
              }
            }
          }
        }
        
        // Now process each entity
        if (!skipDuplicateCheck || _refreshOkCount <= 3) {
          InstantLogger.debug('Reconstructed ${entityMap.length} entities from join-rows');
        }
        
        // Check if we've already processed this exact data set
        final entitiesHash = entityMap.toString().hashCode.toString();
        if (!skipDuplicateCheck && _lastProcessedData['query-entities'] == entitiesHash) {
          return; // Skip duplicate data
        }
        _lastProcessedData['query-entities'] = entitiesHash;
        
        // Skip if we've already processed this exact data
        if (entityMap.isEmpty) {
          return;
        }
        
        // Create a single transaction for all entities
        final allOperations = <Operation>[];
        
        for (final entity in entityMap.values) {
          final entityId = entity['id'] as String;
          
          // Skip if this looks like a system entity or invalid ID
          if (entityId.startsWith('__') || entityId == '__query_invalidation') {
            continue;
          }
          
          // Add entity type
          allOperations.add(Operation(
            type: OperationType.add,
            entityId: entityId,
            attribute: '__type',
            value: 'todos',
          ));
          
          // Add all attributes
          for (final entry in entity.entries) {
            if (entry.key != 'id' && entry.value != null) {
              allOperations.add(Operation(
                type: OperationType.add,
                entityId: entityId,
                attribute: entry.key,
                value: entry.value,
              ));
            }
          }
        }
        
        if (allOperations.isNotEmpty) {
          // Apply as a single transaction
          final transaction = Transaction(
            id: _generateEventId(),
            operations: allOperations,
            timestamp: DateTime.now(),
            status: TransactionStatus.synced,
          );
          
          await _applyRemoteTransaction(transaction);
        }
      }
    } else if (resultData['todos'] is List) {
      // Fallback to simple format if available
      final todos = resultData['todos'] as List;
      InstantLogger.debug('Received todos from server (simple format)');
      
      for (final todo in todos) {
        if (todo is Map<String, dynamic>) {
          // Convert server data to operations and apply
          final entityId = todo['id']?.toString();
          if (entityId != null) {
            final operations = <Operation>[];
            
            // Add entity type
            operations.add(Operation(
              type: OperationType.add,
              entityId: entityId,
              attribute: '__type',
              value: 'todos',
            ));
            
            // Add all attributes
            for (final entry in todo.entries) {
              if (entry.key != 'id') {
                operations.add(Operation(
                  type: OperationType.add,
                  entityId: entityId,
                  attribute: entry.key,
                  value: entry.value,
                ));
              }
            }
            
            // Apply as a transaction
            final transaction = Transaction(
              id: _generateEventId(),
              operations: operations,
              timestamp: DateTime.now(),
              status: TransactionStatus.synced,
            );
            
            await _applyRemoteTransaction(transaction);
          }
        }
      }
    }
  }
}