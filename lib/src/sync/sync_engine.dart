import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
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

    // Process any pending transactions
    await _processPendingTransactions();

    // Connect WebSocket
    await _connectWebSocket();
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
      print('InstantDB: Connecting to WebSocket at $wsUri');
      
      // Use platform-specific WebSocket implementation
      _webSocket = await WebSocketManager.connect(wsUri.toString());
      
      print('InstantDB: WebSocket connected, sending init message');
      
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
      print('InstantDB: Sent init message: ${initMessage['op']}');

      // Listen for messages
      _messageSubscription = _webSocket.stream.listen(
        _handleRemoteMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketClose,
        cancelOnError: false,
      );
    } catch (e) {
      print('InstantDB: WebSocket connection error: $e');
      _connectionStatus.value = false;
      _scheduleReconnect();
    }
  }
  
  String _generateEventId() {
    return _uuid.v4();
  }

  void _handleRemoteMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      print('InstantDB: Received message: ${data['op']}');

      switch (data['op']) {
        case 'init-ok':
          print('InstantDB: WebSocket authenticated successfully');
          _connectionStatus.value = true;
          // Store session ID if needed
          final sessionId = data['session-id'];
          print('InstantDB: Session ID: $sessionId');
          
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
                
                print('InstantDB: Cached attribute $namespace.$attrName = $attrId');
              }
            }
          }
          break;
          
        case 'init-error':
          print('InstantDB: WebSocket authentication failed: ${data['error']}');
          _connectionStatus.value = false;
          _handleAuthError(data['error']);
          break;
          
        case 'transaction':
          _applyRemoteTransaction(Transaction.fromJson(data['data']));
          break;
          
        case 'transaction-ack':
          _handleTransactionAck(data['tx-id'] as String);
          break;
          
        case 'error':
          // Log the full error data for debugging
          print('InstantDB: Error message data: $data');
          final errorMessage = data['message'] ?? data['error'];
          if (errorMessage != null) {
            _handleRemoteError(errorMessage.toString());
          } else {
            print('InstantDB: Received error with no message or error field');
          }
          break;
          
        case 'transact-ok':
          print('InstantDB: Transaction successful: ${data['tx-id']}');
          if (data['tx-id'] != null) {
            _handleTransactionAck(data['tx-id'].toString());
          }
          break;
          
        default:
          print('InstantDB: Unknown message op: ${data['op']}');
      }
    } catch (e) {
      print('InstantDB: Error parsing message: $e');
      print('InstantDB: Raw message was: $message');
    }
  }
  
  void _handleAuthError(dynamic error) {
    print('InstantDB: Authentication error: $error');
    _connectionStatus.value = false;
    // Could implement retry logic or user notification here
  }

  void _handleWebSocketError(error) {
    print('InstantDB: WebSocket error: $error');
    _connectionStatus.value = false;
    _scheduleReconnect();
  }

  void _handleWebSocketClose() {
    print('InstantDB: WebSocket connection closed');
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
      await _store.applyTransaction(transaction);
      await _store.markTransactionSynced(transaction.id);
    } catch (e) {
      // Handle conflict resolution here
      // For now, just log the error
    }
  }

  void _handleTransactionAck(String txId) async {
    await _store.markTransactionSynced(txId);
  }

  void _handleRemoteError(String error) {
    print('InstantDB: Remote error: $error');
    // Handle specific error types if needed
    // For now, just log the error
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
            
            // Track namespace and attributes we need to register
            String? namespace;
            final attributesToRegister = <String, Map<String, dynamic>>{};
            
            // First pass: collect unique attributes and namespace
            for (final op in transaction.operations) {
              if (op.attribute == '__type' && op.value is String) {
                namespace = op.value as String;
              }
              
              if (op.attribute != null && op.attribute != '__type') {
                final ns = namespace ?? 'todos';
                
                // Check if we already have this attribute cached
                if (_attributeCache[ns]?.containsKey(op.attribute) == true) {
                  // Use cached UUID
                  attributesToRegister[op.attribute!] = {
                    'id': _attributeCache[ns]![op.attribute!],
                    'namespace': ns,
                    'cached': true,
                  };
                } else if (!attributesToRegister.containsKey(op.attribute)) {
                  // Generate a new UUID for unknown attributes
                  final attrId = _uuid.v4();
                  attributesToRegister[op.attribute!] = {
                    'id': attrId,
                    'namespace': ns,
                    'cached': false,
                  };
                }
              }
            }
            
            // Add attribute registration steps only for uncached attributes
            attributesToRegister.forEach((attrName, attrInfo) {
              if (attrInfo['cached'] != true) {
                txSteps.add([
                  'add-attr',
                  {
                    'id': attrInfo['id'],
                    'forward-identity': [
                      _uuid.v4(), // Random UUID for the forward identity
                      attrInfo['namespace'],
                      attrName,
                    ],
                    'value-type': 'blob',
                    'cardinality': 'one',
                    'unique?': attrName == 'id',
                    'index?': false,
                    'isUnsynced': true,
                  }
                ]);
                
                // Cache the new attribute
                _attributeCache.putIfAbsent(attrInfo['namespace'], () => {});
                _attributeCache[attrInfo['namespace']]![attrName] = attrInfo['id'];
              }
            });
            
            // Second pass: add the actual operations using attribute UUIDs
            for (final op in transaction.operations) {
              if (op.type == OperationType.add) {
                if (op.attribute != null && op.attribute != '__type') {
                  final attrId = attributesToRegister[op.attribute]?['id'];
                  if (attrId != null) {
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  }
                }
              } else if (op.type == OperationType.update) {
                if (op.attribute != null) {
                  final attrId = attributesToRegister[op.attribute]?['id'];
                  if (attrId != null) {
                    // For updates, just add the new triple
                    // InstantDB will handle replacing the old value
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  }
                }
              } else if (op.type == OperationType.delete) {
                // For deletes, we still use entity ID and namespace
                txSteps.add([
                  'delete-entity',
                  op.entityId,
                  namespace ?? 'todos',
                ]);
              }
            }
            
            final transactionMessage = {
              'op': 'transact',
              'tx-steps': txSteps,
              'created': DateTime.now().millisecondsSinceEpoch,
              'order': 1,
              'client-event-id': _generateEventId(),
            };
            
            print('InstantDB: Sending transaction: ${jsonEncode(transactionMessage)}');
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
    for (final transaction in pendingTransactions) {
      _syncQueue.add(transaction);
    }

    if (_syncQueue.isNotEmpty) {
      _processQueue();
    }
  }
}