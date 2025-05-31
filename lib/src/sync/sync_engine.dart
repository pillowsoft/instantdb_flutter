import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';
import '../storage/triple_store.dart';
import '../auth/auth_manager.dart';

/// Sync engine for real-time communication with InstantDB server
class SyncEngine {
  final String appId;
  final TripleStore _store;
  final AuthManager _authManager;
  final InstantConfig config;
  final Dio _dio;

  WebSocketChannel? _channel;
  StreamSubscription? _storeSubscription;
  StreamSubscription? _authSubscription;
  Timer? _reconnectTimer;

  final Signal<bool> _connectionStatus = signal(false);
  final Queue<Transaction> _syncQueue = Queue<Transaction>();
  bool _isProcessingQueue = false;

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
    await _channel?.sink.close();
    _connectionStatus.value = false;
  }

  Future<void> _connectWebSocket() async {
    try {
      // Parse the base URL to extract components
      final baseUri = Uri.parse(config.baseUrl!);
      
      // Construct WebSocket URL with proper scheme and default port
      final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri(
        scheme: wsScheme,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null, // Let WebSocket use default ports
        path: '/v1/sync',
      );
      
      // Log connection attempt for debugging
      print('InstantDB: Connecting to WebSocket at $wsUri');
      
      _channel = WebSocketChannel.connect(wsUri);

      // Send authentication
      final authData = {
        'type': 'auth',
        'appId': appId,
        'token': _authManager.authToken,
      };
      _channel!.sink.add(jsonEncode(authData));

      // Listen for messages
      _channel!.stream.listen(
        _handleRemoteMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketClose,
      );

      _connectionStatus.value = true;
    } catch (e) {
      print('InstantDB: WebSocket connection error: $e');
      _connectionStatus.value = false;
      _scheduleReconnect();
    }
  }

  void _handleRemoteMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      switch (data['type']) {
        case 'auth_success':
          _connectionStatus.value = true;
          break;
        case 'auth_error':
          _connectionStatus.value = false;
          break;
        case 'transaction':
          _applyRemoteTransaction(Transaction.fromJson(data['data']));
          break;
        case 'transaction_ack':
          _handleTransactionAck(data['txId'] as String);
          break;
        case 'error':
          _handleRemoteError(data['error'] as String);
          break;
      }
    } catch (e) {
      // Handle JSON parsing errors
    }
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
    if (user != null && _channel != null) {
      // Re-authenticate with new token
      final authData = {
        'type': 'auth',
        'appId': appId,
        'token': _authManager.authToken,
      };
      _channel!.sink.add(jsonEncode(authData));
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
    // Handle remote errors
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

        if (_connectionStatus.value && _channel != null) {
          // Send via WebSocket
          try {
            _channel!.sink.add(jsonEncode({
              'type': 'transaction',
              'data': transaction.toJson(),
            }));
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