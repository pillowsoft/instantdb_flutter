import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../core/logging_config.dart';
import '../storage/storage_interface.dart';
import '../auth/auth_manager.dart';
import '../reactive/presence.dart';

// Platform-specific WebSocket imports
import 'web_socket_stub.dart'
    if (dart.library.io) 'web_socket_io.dart'
    if (dart.library.html) 'web_socket_web.dart';

/// Sync engine for real-time communication with InstantDB server
class SyncEngine {
  final String appId;
  final StorageInterface _store;
  final AuthManager _authManager;
  final InstantConfig config;
  final Dio _dio;
  final PresenceManager? _presenceManager;

  // Loggers for different aspects of sync
  static final _logger = InstantDBLogging.syncEngine;
  static final _wsLogger = InstantDBLogging.webSocket;
  static final _txLogger = InstantDBLogging.transaction;

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

  // Track recently created entity IDs to avoid duplicates during refresh-ok
  final Map<String, DateTime> _recentlyCreatedEntities = {};

  // Store session ID from init-ok response
  String? _sessionId;

  // Queue for queries that need to be sent after authentication
  final Queue<Map<String, dynamic>> _pendingQueries =
      Queue<Map<String, dynamic>>();

  // Track last processed data to avoid duplicates
  final Map<String, String> _lastProcessedData = {};
  int _refreshOkCount = 0;

  // Cache for query results from datalog conversion
  final Map<String, List<Map<String, dynamic>>> _queryResultCache = {};

  /// Connection status signal
  ReadonlySignal<bool> get connectionStatus => _connectionStatus.readonly();

  SyncEngine({
    required this.appId,
    required StorageInterface store,
    required AuthManager authManager,
    required this.config,
    PresenceManager? presenceManager,
  }) : _store = store,
       _authManager = authManager,
       _presenceManager = presenceManager,
       _dio = Dio(
         BaseOptions(baseUrl: config.baseUrl!, headers: {'X-App-ID': appId}),
       );

  /// Start the sync engine
  Future<void> start() async {
    // Listen to store changes for outgoing sync
    _storeSubscription = _store.changes.listen(_handleLocalChange);

    // Listen to auth changes to reconnect with new token
    _authSubscription = _authManager.onAuthStateChange.listen(
      _handleAuthChange,
    );

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
    InstantDBLogging.root.debug(
      'SyncEngine: sendQuery called with: ${jsonEncode(query)}',
    );

    if (!_connectionStatus.value || _webSocket == null || !_webSocket.isOpen) {
      InstantDBLogging.root.debug(
        'SyncEngine: Cannot send query - WebSocket not connected, queuing for later (${_pendingQueries.length} already queued)',
      );
      _pendingQueries.add(query);
      return;
    }

    final clientEventId = _generateEventId();
    final queryMessage = {
      'op': 'add-query',
      'q': query,
      'client-event-id': clientEventId,
      if (_sessionId != null) 'session-id': _sessionId,
      // Add subscription flag to ensure real-time updates
      'subscribe': true,
    };

    final queryJson = jsonEncode(queryMessage);
    InstantDBLogging.root.debug(
      'SyncEngine: Sending query to WebSocket - EventId: $clientEventId, SessionId: $_sessionId',
    );
    _wsLogger.fine('🔍 QUERY MESSAGE: $queryJson');
    _webSocket.send(queryJson);
    InstantDBLogging.root.debug('SyncEngine: Query sent successfully');
  }

  void sendJoinRoom(String roomType, String roomId) {
    InstantDBLogging.root.debug(
      'SyncEngine: sendJoinRoom called - roomType: $roomType, roomId: $roomId',
    );

    if (!_connectionStatus.value || _webSocket == null || !_webSocket.isOpen) {
      InstantDBLogging.root.warning(
        'SyncEngine: Cannot send join-room - WebSocket not connected',
      );
      return;
    }

    final joinMessage = {
      'op': 'join-room',
      'room-type': roomType,
      'room-id': roomId,
      'client-event-id': _generateEventId(),
    };

    final joinJson = jsonEncode(joinMessage);
    InstantDBLogging.root.debug(
      'SyncEngine: Sending join-room message to WebSocket - roomType: $roomType, roomId: $roomId',
    );
    _wsLogger.fine('🏠 JOIN ROOM MESSAGE: $joinJson');
    _webSocket.send(joinJson);
    InstantDBLogging.root.debug(
      'SyncEngine: Join room message sent successfully',
    );
  }

  void sendLeaveRoom(String roomType, String roomId) {
    InstantDBLogging.root.debug(
      'SyncEngine: sendLeaveRoom called - roomType: $roomType, roomId: $roomId',
    );

    if (!_connectionStatus.value || _webSocket == null || !_webSocket.isOpen) {
      InstantDBLogging.root.warning(
        'SyncEngine: Cannot send leave-room - WebSocket not connected',
      );
      return;
    }

    final leaveMessage = {
      'op': 'leave-room',
      'room-type': roomType,
      'room-id': roomId,
      'client-event-id': _generateEventId(),
    };

    final leaveJson = jsonEncode(leaveMessage);
    InstantDBLogging.root.debug(
      'SyncEngine: Sending leave-room message to WebSocket - roomType: $roomType, roomId: $roomId',
    );
    _wsLogger.fine('🚪 LEAVE ROOM MESSAGE: $leaveJson');
    _webSocket.send(leaveJson);
    InstantDBLogging.root.debug(
      'SyncEngine: Leave room message sent successfully',
    );
  }

  void sendPresence(Map<String, dynamic> presenceMessage) {
    InstantDBLogging.root.debug(
      'SyncEngine: sendPresence called with: ${jsonEncode(presenceMessage)}',
    );

    if (!_connectionStatus.value || _webSocket == null || !_webSocket.isOpen) {
      InstantDBLogging.root.warning(
        'SyncEngine: Cannot send presence - WebSocket not connected',
      );
      return;
    }

    final presenceJson = jsonEncode(presenceMessage);
    InstantDBLogging.root.debug(
      'SyncEngine: Sending presence message to WebSocket - EventId: ${presenceMessage['clientEventId']}',
    );
    _wsLogger.fine('👥 PRESENCE MESSAGE: $presenceJson');
    _webSocket.send(presenceJson);
    InstantDBLogging.root.debug(
      'SyncEngine: Presence message sent successfully',
    );
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
      _logger.info('Attempting WebSocket connection to $wsUri');
      final connectStopwatch = Stopwatch()..start();

      // Use platform-specific WebSocket implementation
      _webSocket = await WebSocketManager.connect(wsUri.toString());

      connectStopwatch.stop();
      _logger.info(
        'WebSocket connected in ${connectStopwatch.elapsedMilliseconds}ms, sending init message',
      );

      // Send init message according to InstantDB protocol
      // refresh-token can be null for anonymous users
      final clientEventId = _generateEventId();
      final currentUser = _authManager.currentUser.value;
      final initMessage = {
        'op': 'init',
        'app-id': appId,
        if (currentUser?.refreshToken != null)
          'refresh-token': currentUser!.refreshToken,
        'client-event-id': clientEventId,
        'versions': {'@instantdb/flutter': 'v0.1.0'},
      };

      InstantDBLogging.root.debug(
        'SyncEngine: Sending init message - EventId: $clientEventId, HasRefreshToken: ${currentUser?.refreshToken != null}, User: ${currentUser?.email ?? "anonymous"}',
      );
      _webSocket.send(jsonEncode(initMessage));
      InstantDBLogging.root.debug('SyncEngine: Init message sent successfully');

      // Listen for messages with enhanced logging
      _logger.debug('Setting up WebSocket message listeners');
      _messageSubscription = _webSocket.stream.listen(
        (message) {
          final messageStr = message.toString();
          _wsLogger.debug('Received message (${messageStr.length} chars)');
          _handleRemoteMessage(message);
        },
        onError: (error) {
          _wsLogger.severe('Stream error', error);
          _handleWebSocketError(error);
        },
        onDone: () {
          _wsLogger.info('Stream closed');
          _handleWebSocketClose();
        },
        cancelOnError: false,
      );
    } catch (e) {
      InstantDBLogging.root.severe('WebSocket connection error', e);
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
      _wsLogger.fine('Parsing message...');
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final op = data['op'];
      final clientEventId = data['client-event-id']?.toString();

      // COMPREHENSIVE LOGGING: Log ALL incoming messages to detect what we might be missing
      _wsLogger.fine('🔍 RAW MESSAGE ANALYSIS:');
      _wsLogger.fine('   Operation: $op');
      _wsLogger.fine('   Client Event ID: $clientEventId');
      _wsLogger.fine('   All message keys: ${data.keys.toList()}');
      _wsLogger.fine(
        '   Full message (first 500 chars): ${message.toString().substring(0, message.toString().length.clamp(0, 500))}',
      );

      // Enhanced logging with event correlation
      if (op == 'refresh-ok') {
        _refreshOkCount++;
        if (_refreshOkCount <= 3) {
          InstantDBLogging.logWebSocketMessage(
            '<<<',
            op,
            eventId: clientEventId,
          );
          _wsLogger.fine(
            '🔄 REFRESH-OK MESSAGE: This should contain updated query results',
          );
          // Log the computations data specifically for refresh-ok
          if (data['computations'] != null) {
            _wsLogger.fine(
              '   Computations found: ${data['computations'] is List ? (data['computations'] as List).length : 'not a list'}',
            );
          } else {
            _wsLogger.warning('   ❌ NO COMPUTATIONS in refresh-ok message!');
          }
        } else if (_refreshOkCount == 4) {
          _wsLogger.debug('Suppressing further refresh-ok logs...');
        }
      } else {
        InstantDBLogging.logWebSocketMessage('<<<', op, eventId: clientEventId);
        _wsLogger.fine('Message data keys: ${data.keys.toList()}');

        // Special logging for messages that might be related to sync
        if (op == 'refresh' ||
            op == 'transact' ||
            op == 'refresh-query' ||
            op?.toString().contains('query') == true) {
          _wsLogger.info(
            '🚨 SYNC-RELATED MESSAGE: $op - This might be important for real-time updates!',
          );
        }
      }

      switch (data['op']) {
        case 'init-ok':
          InstantDBLogging.root.info('WebSocket authenticated successfully');
          _connectionStatus.value = true;
          // Store session ID for future messages
          _sessionId = data['session-id']?.toString();
          InstantDBLogging.root.debug('Session ID: $_sessionId');

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
                  InstantDBLogging.root.debug(
                    'Cached attribute $namespace.$attrName = $attrId',
                  );
                }
              }
            }

            // Add hardcoded mapping for todos.completed if not present
            // This is a workaround for missing attribute in init-ok response
            if (_attributeCache['todos'] != null &&
                !_attributeCache['todos']!.containsKey('completed')) {
              _attributeCache['todos']!['completed'] =
                  'd4787d60-b7fe-4dbc-a7cb-683cbdd2c0a9';
              InstantDBLogging.root.debug(
                'Added hardcoded mapping for todos.completed',
              );
            }

            // Debug: Log all cached attributes
            InstantDBLogging.root.debug('All cached attributes after init-ok:');
            for (final entry in _attributeCache.entries) {
              InstantDBLogging.root.debug(
                '  Namespace "${entry.key}": ${entry.value.keys.join(', ')}',
              );
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
          InstantDBLogging.root.severe(
            'WebSocket authentication failed: ${data['error']}',
          );
          _connectionStatus.value = false;
          _handleAuthError(data['error']);
          break;

        case 'transaction':
          InstantDBLogging.root.debug(
            'Received transaction message: ${jsonEncode(data)}',
          );
          try {
            // Check various possible data locations
            final txData = data['data'] ?? data['tx'] ?? data;

            // If this looks like a transaction with tx-steps, handle it like transact
            if (txData['tx-steps'] != null) {
              InstantDBLogging.root.debug(
                'Transaction message contains tx-steps, processing as transact',
              );
              _handleRemoteTransact(txData);
            } else if (txData['operations'] != null) {
              // This looks like our Transaction format
              _applyRemoteTransaction(Transaction.fromJson(txData));
            } else {
              InstantDBLogging.root.warning(
                'Transaction message has unexpected format',
              );
              InstantDBLogging.root.debug(
                'Keys in data: ${txData.keys.toList()}',
              );
            }
          } catch (e, stackTrace) {
            InstantDBLogging.root.severe('Error processing transaction: $e');
            InstantDBLogging.root.debug('Stack trace: $stackTrace');
          }
          break;

        case 'transact':
          // Handle incoming transactions from other clients
          _logger.info('Received transact from remote client');
          _wsLogger.fine('Transact keys: ${data.keys.toList()}');
          _wsLogger.fine('Full transact: ${jsonEncode(data)}');
          try {
            _handleRemoteTransact(data);
          } catch (e, stackTrace) {
            _logger.severe('Error processing transact', e, stackTrace);
          }
          break;

        case 'transaction-ack':
          _handleTransactionAck(data['tx-id'] as String);
          break;

        case 'error':
          // Log the full error data for debugging
          InstantDBLogging.root.debug('Error message data: $data');
          final errorMessage = data['message'] ?? data['error'];
          if (errorMessage != null) {
            _handleRemoteError(errorMessage.toString());
          } else {
            InstantDBLogging.root.warning(
              'Received error with no message or error field',
            );
          }
          break;

        case 'transact-ok':
          InstantDBLogging.root.info(
            'Transaction successful: server tx-id=${data['tx-id']}, client-event-id=${data['client-event-id']}',
          );
          // Use client-event-id (which is our transaction ID) to mark as synced
          if (data['client-event-id'] != null) {
            _handleTransactionAck(data['client-event-id'].toString());
          }
          break;

        case 'query-update':
        case 'invalidate-query':
          // Handle query invalidation messages
          InstantDBLogging.root.debug(
            'Received query update/invalidation message: ${jsonEncode(data)}',
          );
          _handleQueryInvalidation(data);
          break;

        case 'refresh':
          // Handle refresh messages which contain updated data
          InstantDBLogging.root.debug(
            'Received refresh message with updated data',
          );
          InstantDBLogging.root.debug(
            'Refresh data keys: ${data.keys.toList()}',
          );
          _handleRefreshMessage(data);
          break;

        case 'add-query-ok':
        case 'query-response':
        case 'query-result':
          // Handle query response with initial data
          InstantDBLogging.root.debug(
            'Received query response: ${jsonEncode(data)}',
          );
          _handleQueryResponse(data);
          break;

        case 'refresh-query':
          // Handle refresh-query message which might contain updated data
          InstantDBLogging.root.debug(
            'Received refresh-query message: ${jsonEncode(data)}',
          );
          _handleRefreshQuery(data);
          break;

        // Note: Since we don't send subscribe or listen-query, we won't receive these

        case 'refresh-ok':
          // Handle refresh-ok messages which contain updated query results
          InstantDBLogging.root.debug('Processing refresh-ok');
          _handleRefreshOk(data);
          break;

        case 'join-room-ok':
          // Handle successful room join
          final roomType = data['room-type']?.toString();
          final roomId = data['room-id']?.toString();
          InstantDBLogging.root.info(
            'Successfully joined room: $roomType/$roomId',
          );
          // TODO: Notify PresenceManager that room is ready
          break;

        case 'join-room-error':
          // Handle failed room join
          final roomType = data['room-type']?.toString();
          final roomId = data['room-id']?.toString();
          final error = data['error']?.toString() ?? 'Unknown error';
          InstantDBLogging.root.severe(
            'Failed to join room $roomType/$roomId: $error',
          );
          break;

        case 'leave-room-ok':
          // Handle successful room leave
          final roomType = data['room-type']?.toString();
          final roomId = data['room-id']?.toString();
          InstantDBLogging.root.info(
            'Successfully left room: $roomType/$roomId',
          );
          break;

        case 'presence':
          // Handle incoming presence messages (reactions, cursors, typing indicators)
          InstantDBLogging.root.debug(
            'Received presence message: ${jsonEncode(data)}',
          );
          _handlePresenceMessage(data);
          break;

        case 'refresh-presence':
          // Handle refresh-presence messages containing all peer presence data
          InstantDBLogging.root.debug(
            'Received refresh-presence message for room: ${data['room-id']}',
          );
          _handleRefreshPresenceMessage(data);
          break;

        case 'set-presence-ok':
          // Handle successful presence update acknowledgment
          final roomId = data['room-id'] as String? ?? 'unknown';
          final clientEventId = data['client-event-id'] as String?;
          InstantDBLogging.root.debug(
            'Presence update acknowledged for room $roomId${clientEventId != null ? ', event-id: $clientEventId' : ''}',
          );
          break;

        default:
          InstantDBLogging.root.warning('🚨 UNHANDLED MESSAGE: ${data['op']}');
          _wsLogger.warning('   Message keys: ${data.keys.toList()}');
          _wsLogger.warning('   Full message: ${jsonEncode(data)}');
          InstantDBLogging.root.warning(
            '   ❗ This message might be important for sync - consider adding a handler!',
          );
      }
    } catch (e) {
      InstantDBLogging.root.severe('Error parsing message', e);
      InstantDBLogging.root.debug('Raw message was: $message');
    }
  }

  void _handleAuthError(dynamic error) {
    InstantDBLogging.root.severe('Authentication error: $error');
    _connectionStatus.value = false;
    // Could implement retry logic or user notification here
  }

  void _handleWebSocketError(Object error) {
    InstantDBLogging.root.severe('WebSocket error: $error');
    _connectionStatus.value = false;
    _scheduleReconnect();
  }

  void _handleWebSocketClose() {
    InstantDBLogging.root.info('WebSocket connection closed');
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
        InstantDBLogging.root.debug(
          'Applying remote transaction ${transaction.id} with ${transaction.operations.length} operations',
        );
      }

      // Apply the transaction with already-synced status to avoid re-sending
      await _store.applyTransaction(transaction);
      // No need to mark as synced separately since remote transactions have synced status
    } catch (e) {
      // Handle conflict resolution here
      // For now, just log the error
      InstantDBLogging.root.severe('Error applying remote transaction', e);
    }
  }

  void _handleRemoteTransact(Map<String, dynamic> data) async {
    // InstantDB sends remote transactions as 'transact' messages with tx-steps
    // We need to convert these to our Transaction format
    try {
      // Check if this is our own transaction echoed back
      final clientEventId = data['client-event-id'];
      if (clientEventId != null && _sentEventIds.contains(clientEventId)) {
        InstantDBLogging.root.debug(
          'Ignoring our own echoed transaction: $clientEventId',
        );
        return;
      }

      final txSteps = data['tx-steps'] as List?;
      if (txSteps == null) {
        InstantDBLogging.root.warning('No tx-steps in transact message');
        return;
      }

      // Generate a transaction ID from the event ID if available
      final txId = data['client-event-id']?.toString() ?? _uuid.v4();
      final timestamp = data['created'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['created'] as int)
          : DateTime.now();

      // Convert tx-steps to operations
      final operations = <Operation>[];

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
                    break;
                  }
                }
                if (attrName != null) break;
              }

              if (attrName != null) {
                // Check if this is a type declaration
                if (attrName == '__type') {
                  // Type declaration processed
                }

                operations.add(
                  Operation.legacy(
                    type: OperationType.add,
                    entityId: entityId,
                    attribute: attrName,
                    value: value,
                  ),
                );
              } else {
                // If we don't have the attribute cached, try to use common attribute names
                // This is a workaround for when we receive updates before the attribute cache is fully populated
                InstantDBLogging.root.debug(
                  'Unknown attribute ID: $attrId, trying to infer attribute name',
                );

                // Common attributes we might expect
                if (value is String && (value == 'todos' || value == 'users')) {
                  // This is likely a __type attribute
                  operations.add(
                    Operation.legacy(
                      type: OperationType.add,
                      entityId: entityId,
                      attribute: '__type',
                      value: value,
                    ),
                  );
                } else {
                  // For now, skip unknown attributes but log them
                  InstantDBLogging.root.debug(
                    'Skipping unknown attribute ID: $attrId with value: $value',
                  );
                }
              }
            }
            break;

          case 'delete-entity':
            if (step.length >= 2) {
              final entityId = step[1].toString();
              operations.add(
                Operation.legacy(
                  type: OperationType.delete,
                  entityId: entityId,
                ),
              );
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

        InstantDBLogging.logTransaction(
          'APPLY_REMOTE',
          txId,
          operationCount: operations.length,
          status: 'synced',
        );
        await _applyRemoteTransaction(transaction);
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling remote transact: $e');
      InstantDBLogging.root.debug('Stack trace: $stackTrace');
    }
  }

  void _handleTransactionAck(String txId) async {
    InstantDBLogging.logTransaction('ACK', txId, status: 'synced');
    await _store.markTransactionSynced(txId);
  }

  void _handleRemoteError(String error) {
    InstantDBLogging.root.severe('Remote error: $error');
    // Handle specific error types if needed
    // For now, just log the error
  }

  void _handleQueryInvalidation(Map<String, dynamic> data) async {
    // When a query is invalidated, we need to re-fetch the data
    InstantDBLogging.root.debug('Query invalidation received');

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
          Operation.legacy(
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
    InstantDBLogging.root.debug('Processing refresh-query message');

    // Check if this message contains updated data
    final result = data['result'] ?? data['data'] ?? data['r'];
    if (result != null) {
      InstantDBLogging.root.debug(
        'refresh-query contains data, processing as query response',
      );
      _handleQueryResponse(data);
    } else {
      // Otherwise treat it as an invalidation
      InstantDBLogging.root.debug(
        'refresh-query has no data, treating as invalidation',
      );
      _handleQueryInvalidation(data);
    }
  }

  void _handleRefreshMessage(Map<String, dynamic> data) async {
    _wsLogger.info('🔄 Processing refresh message');
    _wsLogger.fine('   Message keys: ${data.keys.toList()}');

    // Refresh messages typically contain the full updated dataset
    // Check various possible data locations
    final result = data['data'] ?? data['result'] ?? data['r'] ?? data;

    if (result != null && result is Map) {
      // Process the refresh data similar to a query response
      _wsLogger.info('   ✅ Refresh contains data, processing updates');
      _handleQueryResponse({'result': result});
    } else {
      // If no data, trigger a query invalidation
      _wsLogger.info('   ⚠️  Refresh has no data, triggering invalidation');
      _handleQueryInvalidation(data);
    }
  }

  void _processPendingQueries() {
    InstantDBLogging.root.debug('Processing pending queries');
    while (_pendingQueries.isNotEmpty) {
      final query = _pendingQueries.removeFirst();
      sendQuery(query);
    }
  }

  void _handleRefreshOk(Map<String, dynamic> data) {
    // refresh-ok contains updated query results
    _wsLogger.info('🔄 Processing refresh-ok message...');

    if (data['computations'] is List) {
      final computations = data['computations'] as List;
      _wsLogger.info('   Found ${computations.length} computations to process');

      // Generate a hash of the computations to detect duplicates
      final dataHash = computations.toString().hashCode.toString();
      _wsLogger.fine('   Data hash: $dataHash');
      _wsLogger.fine(
        '   Last processed hash: ${_lastProcessedData['refresh-ok']}',
      );

      if (_lastProcessedData['refresh-ok'] == dataHash) {
        _wsLogger.warning(
          '   ⏭️  SKIPPING: Duplicate refresh-ok data detected',
        );
        return;
      }
      _lastProcessedData['refresh-ok'] = dataHash;

      for (int i = 0; i < computations.length; i++) {
        final computation = computations[i];
        _wsLogger.fine(
          '   Processing computation ${i + 1}/${computations.length}',
        );

        if (computation is Map && computation['instaql-result'] != null) {
          _wsLogger.info(
            '   ✅ Found instaql-result in computation ${i + 1}, processing...',
          );
          // Process the query result
          _handleQueryResponse({
            'result': computation['instaql-result'],
          }, skipDuplicateCheck: true);
        } else {
          _wsLogger.warning(
            '   ❌ Computation ${i + 1} has no instaql-result: ${computation.runtimeType}',
          );
          if (computation is Map) {
            _wsLogger.warning(
              '      Computation keys: ${computation.keys.toList()}',
            );
          }
        }
      }

      _wsLogger.info('   ✅ Finished processing refresh-ok computations');

      // Periodic cleanup of recently created entities
      _cleanupRecentlyCreatedEntities();
    } else {
      _wsLogger.warning('   ❌ refresh-ok has no computations array');
      _wsLogger.warning('   Message keys: ${data.keys.toList()}');
    }
  }

  /// Clean up old entries from recently created entities map
  void _cleanupRecentlyCreatedEntities() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _recentlyCreatedEntities.entries) {
      final age = now.difference(entry.value);
      if (age.inSeconds > 30) {
        // Remove entries older than 30 seconds
        toRemove.add(entry.key);
      }
    }

    for (final key in toRemove) {
      _recentlyCreatedEntities.remove(key);
    }

    if (toRemove.isNotEmpty) {
      InstantDBLogging.root.debug(
        'Cleaned up ${toRemove.length} old recently-created entity entries',
      );
    }
  }

  /// Send a transaction to the server
  Future<TransactionResult> sendTransaction(Transaction transaction) async {
    InstantDBLogging.logTransaction(
      'SEND',
      transaction.id,
      operationCount: transaction.operations.length,
    );

    // Log operation details
    for (int i = 0; i < transaction.operations.length; i++) {
      final op = transaction.operations[i];
      _txLogger.fine(
        'Op ${i + 1}: ${op.type} ${op.entityType}:${op.entityId} | Data: ${op.data}',
      );
    }

    // Clear cache for affected collections when a local transaction is sent
    final affectedCollections = <String>{};
    for (final operation in transaction.operations) {
      final entityType = operation.entityType;
      affectedCollections.add(entityType);
    }

    for (final collection in affectedCollections) {
      clearCachedQueryResult(collection);
    }

    // Add to sync queue
    InstantDBLogging.root.debug(
      'SyncEngine: Adding transaction ${transaction.id} to sync queue (current queue size: ${_syncQueue.length})',
    );
    _syncQueue.add(transaction);

    // Process queue if not already processing
    if (!_isProcessingQueue) {
      InstantDBLogging.root.debug(
        'SyncEngine: Starting queue processing for transaction ${transaction.id}',
      );
      _processQueue();
    } else {
      InstantDBLogging.root.debug(
        'SyncEngine: Queue processing already in progress, transaction ${transaction.id} queued',
      );
    }

    InstantDBLogging.root.debug(
      'SyncEngine: sendTransaction returning pending result for ${transaction.id}',
    );
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

        if (_connectionStatus.value &&
            _webSocket != null &&
            _webSocket.isOpen) {
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
                // Handle new Operation format with data map
                if (op.data != null && op.data!.isNotEmpty) {
                  final ns = op.entityType.isNotEmpty
                      ? op.entityType
                      : (namespace ?? 'todos');
                  InstantDBLogging.root.debug(
                    'Processing add operation for entity ${op.entityId} in namespace $ns',
                  );
                  InstantDBLogging.root.debug('Operation data: ${op.data}');

                  // Convert each attribute in the data map to a tx-step
                  for (final entry in op.data!.entries) {
                    final attrName = entry.key;
                    final attrValue = entry.value;

                    // Skip __type attribute for now - we'll handle it separately
                    if (attrName == '__type') continue;

                    // Look up the attribute ID from cache
                    String? attrId = _attributeCache[ns]?[attrName];

                    if (attrId != null) {
                      // Use known attribute UUID
                      txSteps.add([
                        'add-triple',
                        op.entityId,
                        attrId,
                        attrValue,
                      ]);
                      InstantDBLogging.root.debug(
                        'Added tx-step for $ns.$attrName = $attrValue (UUID: $attrId)',
                      );
                    } else {
                      // Skip unknown attributes for now
                      InstantDBLogging.root.warning(
                        'Skipping unknown attribute $ns.$attrName - not registered with server',
                      );
                    }
                  }
                }
                // Legacy format support (for backwards compatibility)
                else if (op.attribute != null && op.attribute != '__type') {
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
                    // Skip unknown attributes for now
                    InstantDBLogging.root.warning(
                      'Skipping unknown attribute ${op.attribute} for namespace $ns - not registered with server',
                    );
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
                    // Skip unknown attributes for now
                    InstantDBLogging.root.warning(
                      'Skipping unknown attribute ${op.attribute} for namespace $ns in update - not registered with server',
                    );
                  }
                }
              } else if (op.type == OperationType.delete) {
                // For deletes, we need to ensure entity ID is a proper string
                // Sometimes entity IDs come as stringified arrays from corrupted data
                String cleanEntityId = op.entityId;

                // Check if entity ID looks like a stringified array
                if (cleanEntityId.startsWith('[') &&
                    cleanEntityId.endsWith(']')) {
                  try {
                    // Try to parse it as JSON array and extract first element
                    final parsed = jsonDecode(cleanEntityId);
                    if (parsed is List && parsed.isNotEmpty) {
                      cleanEntityId = parsed[0].toString();
                      InstantDBLogging.root.debug(
                        'Fixed corrupted entity ID from "$op.entityId" to "$cleanEntityId"',
                      );
                    }
                  } catch (e) {
                    // If parsing fails, try to extract first UUID-like string
                    final uuidPattern = RegExp(
                      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                    );
                    final match = uuidPattern.firstMatch(cleanEntityId);
                    if (match != null) {
                      cleanEntityId = match.group(0)!;
                      InstantDBLogging.root.debug(
                        'Extracted entity ID "$cleanEntityId" from corrupted string',
                      );
                    }
                  }
                }

                // Resolve entity type if it's 'unknown'
                String entityType = op.entityType;
                if (entityType == 'unknown' || entityType.isEmpty) {
                  // Try to resolve from store, fallback to namespace or default
                  final resolvedType = await _store.getEntityType(
                    cleanEntityId,
                  );
                  entityType = resolvedType ?? namespace ?? 'todos';

                  if (resolvedType != null) {
                    InstantDBLogging.root.debug(
                      'Resolved entity type for $cleanEntityId: $resolvedType',
                    );
                  } else {
                    InstantDBLogging.root.debug(
                      'Could not resolve entity type for $cleanEntityId, using fallback: $entityType',
                    );
                  }
                }

                txSteps.add(['delete-entity', cleanEntityId, entityType]);
              }
            }

            final clientEventId =
                transaction.id; // Use transaction ID as client-event-id
            _sentEventIds.add(clientEventId); // Track for deduplication

            // Track entity IDs from add operations for deduplication
            final now = DateTime.now();
            for (final op in transaction.operations) {
              if (op.type == OperationType.add) {
                _recentlyCreatedEntities[op.entityId] = now;
                InstantDBLogging.root.debug(
                  'Tracking recently created entity: ${op.entityId}',
                );
              }
            }

            final transactionMessage = {
              'op': 'transact',
              'tx-steps': txSteps,
              'created': DateTime.now().millisecondsSinceEpoch,
              'order': 1,
              'client-event-id': clientEventId,
            };

            // Debug log transaction details
            InstantDBLogging.root.debug(
              'Sending transaction ${transaction.id} with ${txSteps.length} steps',
            );
            if (txSteps.isNotEmpty) {
              InstantDBLogging.root.debug(
                'First tx-step: ${jsonEncode(txSteps.first)}',
              );
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
    InstantDBLogging.root.info(
      'Found ${pendingTransactions.length} pending transactions to sync',
    );

    for (final transaction in pendingTransactions) {
      _syncQueue.add(transaction);
      InstantDBLogging.root.debug(
        'Queued transaction ${transaction.id} with ${transaction.operations.length} operations',
      );
    }

    if (_syncQueue.isNotEmpty) {
      _processQueue();
    }
  }

  // Note: InstantDB automatically subscribes to queries when they are sent.
  // There's no need for explicit subscribe or listen-query operations.
  // Real-time updates are received as 'transact' messages from other clients.

  void _handleQueryResponse(
    Map<String, dynamic> data, {
    bool skipDuplicateCheck = false,
  }) async {
    // Only log if not from refresh-ok or if it's one of the first few
    if (!skipDuplicateCheck || _refreshOkCount <= 3) {
      InstantDBLogging.root.debug('Processing query response');
    }

    // Extract the query to determine entity type
    String? queryEntityType;
    if (data['q'] is Map) {
      final query = data['q'] as Map<String, dynamic>;
      // Get the first (and usually only) entity type from the query
      if (query.isNotEmpty) {
        queryEntityType = query.keys.first;
        _wsLogger.debug('Query is for entity type: $queryEntityType');
      }
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
      InstantDBLogging.root.warning('Query response has no result data');
      return;
    }

    // Enhanced datalog detection and conversion
    final convertedData = _tryConvertDatalogToCollectionFormat(
      resultData,
      queryEntityType: queryEntityType,
    );
    if (convertedData.isNotEmpty) {
      await _processCollectionData(convertedData, skipDuplicateCheck);
      return;
    }

    // Explicit warning for unhandled formats
    _wsLogger.warning(
      'Query response in unrecognized format. Keys: ${resultData is Map ? resultData.keys.toList() : 'not a map'}',
    );
    _wsLogger.debug('Raw unhandled data: ${jsonEncode(resultData)}');
  }

  /// Enhanced datalog conversion method that handles multiple format variations
  Map<String, List<Map<String, dynamic>>> _tryConvertDatalogToCollectionFormat(
    dynamic resultData, {
    String? queryEntityType,
  }) {
    final convertedData = <String, List<Map<String, dynamic>>>{};

    if (resultData is! Map<String, dynamic>) {
      _wsLogger.debug('ResultData is not a Map, cannot process');
      return convertedData;
    }

    final resultMap = resultData;

    // Try multiple datalog format variations
    final possibleDatalogPaths = [
      resultMap['datalog-result'],
      resultMap['datalog'],
      (resultMap['result'] as Map<String, dynamic>?)?['datalog-result'],
      (resultMap['data'] as Map<String, dynamic>?)?['datalog-result'],
    ];

    for (final datalogCandidate in possibleDatalogPaths) {
      if (datalogCandidate == null) continue;

      final joinRows = _extractJoinRows(datalogCandidate);
      if (joinRows.isNotEmpty) {
        final entities = _parseJoinRowsToEntities(joinRows);
        _groupEntitiesByType(
          entities,
          convertedData,
          defaultType: queryEntityType,
        );
        _wsLogger.debug(
          'Successfully converted datalog format to ${convertedData.length} entity types',
        );
        return convertedData;
      }
    }

    // Try simple collection format as fallback - check for the query entity type first
    if (queryEntityType != null && resultMap[queryEntityType] is List) {
      convertedData[queryEntityType] = List<Map<String, dynamic>>.from(
        resultMap[queryEntityType] as List,
      );
      _wsLogger.debug('Using simple $queryEntityType format fallback');
      return convertedData;
    }

    // Legacy fallback for todos
    if (resultMap['todos'] is List) {
      convertedData['todos'] = List<Map<String, dynamic>>.from(
        resultMap['todos'] as List,
      );
      _wsLogger.debug('Using simple todos format fallback');
      return convertedData;
    }

    // Try any other collection-like arrays
    for (final entry in resultMap.entries) {
      if (entry.value is List && (entry.value as List).isNotEmpty) {
        final list = entry.value as List;
        if (list.first is Map) {
          convertedData[entry.key] = List<Map<String, dynamic>>.from(list);
          _wsLogger.debug(
            'Found collection format for entity type: ${entry.key}',
          );
        }
      }
    }

    return convertedData;
  }

  /// Robust join-rows extraction that handles multiple format variations
  List<List<dynamic>> _extractJoinRows(dynamic datalogCandidate) {
    if (datalogCandidate is! Map<String, dynamic>) {
      _wsLogger.debug(
        'Datalog candidate is not a Map: ${datalogCandidate.runtimeType}',
      );
      return [];
    }

    final joinRowsCandidates = [
      datalogCandidate['join-rows'],
      datalogCandidate['joinRows'],
      datalogCandidate['rows'],
    ];

    for (final candidate in joinRowsCandidates) {
      if (candidate is List) {
        // Handle nested array structures: [[[row1], [row2]]] vs [[row1], [row2]]
        if (candidate.isNotEmpty &&
            candidate[0] is List &&
            candidate[0].isNotEmpty &&
            candidate[0][0] is List) {
          _wsLogger.debug(
            'Found nested join-rows structure with ${candidate[0].length} rows',
          );
          return List<List<dynamic>>.from(candidate[0]);
        }
        _wsLogger.debug(
          'Found direct join-rows structure with ${candidate.length} rows',
        );
        return List<List<dynamic>>.from(candidate);
      }
    }

    _wsLogger.debug('No valid join-rows found in datalog candidate');
    return [];
  }

  /// Parse join-rows into entity objects
  List<Map<String, dynamic>> _parseJoinRowsToEntities(
    List<List<dynamic>> joinRows,
  ) {
    final entityMap = <String, Map<String, dynamic>>{};
    _wsLogger.info('Parsing ${joinRows.length} join-rows into entities');

    for (final row in joinRows) {
      if (row.length >= 3) {
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
            _wsLogger.debug(
              'Inferred attribute "completed" for unknown ID: $attributeId',
            );
          } else {
            _wsLogger.debug(
              'Unknown attribute ID in query response: $attributeId with value: $value',
            );
          }
        }
      }
    }

    final entities = entityMap.values.toList();
    _wsLogger.info('Reconstructed ${entities.length} entities from join-rows');
    return entities;
  }

  /// Group entities by type for collection format
  void _groupEntitiesByType(
    List<Map<String, dynamic>> entities,
    Map<String, List<Map<String, dynamic>>> convertedData, {
    String? defaultType,
  }) {
    final typeCount = <String, int>{};
    for (final entity in entities) {
      // Use __type field if present, otherwise use the query's entity type, fallback to 'todos'
      final entityType = entity['__type'] as String? ?? defaultType ?? 'todos';
      convertedData.putIfAbsent(entityType, () => []);
      convertedData[entityType]!.add(entity);
      typeCount[entityType] = (typeCount[entityType] ?? 0) + 1;
    }

    if (typeCount.isNotEmpty) {
      _wsLogger.info(
        '📊 Grouped entities by type: ${typeCount.entries.map((e) => '${e.key}(${e.value})').join(', ')}',
      );
    }
  }

  /// Process collection data with enhanced delete detection
  Future<void> _processCollectionData(
    Map<String, List<Map<String, dynamic>>> collectionData,
    bool skipDuplicateCheck,
  ) async {
    if (!skipDuplicateCheck || _refreshOkCount <= 3) {
      final totalEntities = collectionData.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      _wsLogger.debug(
        'Processing $totalEntities entities across ${collectionData.length} entity types',
      );
    }

    // Check for duplicate data processing
    final dataHash = collectionData.toString().hashCode.toString();
    if (!skipDuplicateCheck &&
        _lastProcessedData['collection-data'] == dataHash) {
      _wsLogger.debug('Skipping duplicate collection data');
      return;
    }
    _lastProcessedData['collection-data'] = dataHash;

    // Cache the converted collection data for immediate query access
    _cacheQueryResults(collectionData);

    final allOperations = <Operation>[];

    // Process each entity type separately for better delete detection
    for (final entry in collectionData.entries) {
      final entityType = entry.key;
      final entities = entry.value;

      _wsLogger.debug(
        'Processing ${entities.length} entities of type: $entityType',
      );

      // Get current local entities of this type for delete detection
      Set<String> localEntityIds = {};
      try {
        final localEntities = await _store.queryEntities(
          entityType: entityType,
        );
        localEntityIds = localEntities.map((e) => e['id'] as String).toSet();
        _wsLogger.debug(
          'Found ${localEntityIds.length} existing local $entityType entities',
        );
      } catch (e) {
        _wsLogger.warning('Failed to query local $entityType entities: $e');
      }

      // Track server entity IDs for this type
      final serverEntityIds = <String>{};

      // Process entities from server
      for (final entity in entities) {
        final entityId = entity['id']?.toString();
        if (entityId == null) {
          _wsLogger.warning('Entity missing ID, skipping: $entity');
          continue;
        }

        serverEntityIds.add(entityId);

        // Skip system entities
        if (entityId.startsWith('__')) continue;

        // Skip recently created entities to avoid duplicates
        if (_recentlyCreatedEntities.containsKey(entityId)) {
          final createdTime = _recentlyCreatedEntities[entityId]!;
          final age = DateTime.now().difference(createdTime);
          if (age.inSeconds < 10) {
            _wsLogger.debug(
              'Skipping recently created entity: $entityId (age: ${age.inMilliseconds}ms)',
            );
            continue;
          }
          _recentlyCreatedEntities.remove(entityId);
        }

        // Ensure entity has type information
        final entityData = Map<String, dynamic>.from(entity);
        entityData['__type'] = entityType;

        allOperations.add(
          Operation(
            type: OperationType.add,
            entityType: entityType,
            entityId: entityId,
            data: entityData,
          ),
        );
      }

      // Generate delete operations for missing entities
      final deletedEntityIds = localEntityIds.difference(serverEntityIds);
      if (deletedEntityIds.isNotEmpty) {
        _wsLogger.debug(
          'Detected ${deletedEntityIds.length} deleted $entityType entities: ${deletedEntityIds.take(3).join(', ')}${deletedEntityIds.length > 3 ? '...' : ''}',
        );

        for (final deletedId in deletedEntityIds) {
          if (!_recentlyCreatedEntities.containsKey(deletedId)) {
            allOperations.add(
              Operation(
                type: OperationType.delete,
                entityType: entityType,
                entityId: deletedId,
              ),
            );
          }
        }
      }
    }

    // Apply all operations as a single transaction
    if (allOperations.isNotEmpty) {
      final transaction = Transaction(
        id: _generateEventId(),
        operations: allOperations,
        timestamp: DateTime.now(),
        status: TransactionStatus.synced,
      );

      _wsLogger.debug(
        'Applying transaction with ${allOperations.length} operations',
      );
      await _applyRemoteTransaction(transaction);
    } else {
      _wsLogger.debug('No operations to apply from collection data');
    }
  }

  void _handlePresenceMessage(Map<String, dynamic> data) {
    try {
      InstantDBLogging.root.debug(
        'SyncEngine: Processing presence message - type: ${data['type']}, roomId: ${data['roomId']}',
      );

      // Forward to PresenceManager when available
      if (_presenceManager != null) {
        _presenceManager.handlePresenceMessage(data);
      } else {
        InstantDBLogging.root.info(
          'Received presence update: ${data['type']} in room ${data['roomId']} (no PresenceManager)',
        );
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe(
        'Error handling presence message',
        e,
        stackTrace,
      );
    }
  }

  void _handleRefreshPresenceMessage(Map<String, dynamic> data) {
    try {
      final roomId = data['room-id']?.toString() ?? 'unknown';
      final presenceData = data['data'] as Map<String, dynamic>? ?? {};

      InstantDBLogging.root.debug(
        'SyncEngine: Processing refresh-presence for room $roomId with ${presenceData.length} peers',
      );

      // Forward to PresenceManager when available
      if (_presenceManager != null) {
        _presenceManager.handleRefreshPresenceMessage(roomId, presenceData);
      } else {
        InstantDBLogging.root.info(
          'Received refresh-presence for room $roomId with ${presenceData.length} peers (no PresenceManager)',
        );
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe(
        'Error handling refresh-presence message',
        e,
        stackTrace,
      );
    }
  }

  /// Cache query results from datalog conversion for immediate access
  void _cacheQueryResults(Map<String, List<Map<String, dynamic>>> data) {
    for (final entry in data.entries) {
      final collection = entry.key;
      final documents = entry.value;

      _queryResultCache[collection] = documents;
      _wsLogger.info(
        '✅ Cached ${documents.length} documents for collection: $collection - Cache now available for queries',
      );
    }
    if (data.isNotEmpty) {
      _wsLogger.info(
        '📦 Total cached collections: ${data.length} with ${data.values.fold(0, (sum, list) => sum + list.length)} total documents',
      );
    }
  }

  /// Get cached query results for a collection
  List<Map<String, dynamic>>? getCachedQueryResult(String collection) {
    final cached = _queryResultCache[collection];
    if (cached != null) {
      _wsLogger.debug(
        '🎯 Cache hit for collection: $collection - returning ${cached.length} documents',
      );
    } else {
      _wsLogger.debug('❌ Cache miss for collection: $collection');
    }
    return cached;
  }

  /// Clear cached query results for a collection
  void clearCachedQueryResult(String collection) {
    _queryResultCache.remove(collection);
    _wsLogger.debug('Cleared cache for collection: $collection');
  }

  /// Clear all cached query results
  void clearAllCachedResults() {
    _queryResultCache.clear();
    _wsLogger.debug('Cleared all cached query results');
  }
}
