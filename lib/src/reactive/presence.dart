import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../core/logging.dart';
import '../core/logging_config.dart';
// SyncEngine will be injected to avoid circular imports
import '../auth/auth_manager.dart';

/// Represents a user's presence data in a room
class PresenceData {
  final String userId;
  final Map<String, dynamic> data;
  final DateTime lastSeen;

  PresenceData({
    required this.userId,
    required this.data,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'data': data,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
  };

  factory PresenceData.fromJson(Map<String, dynamic> json) {
    return PresenceData(
      userId: json['userId'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresenceData &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          _deepEquals(data, other.data);

  @override
  int get hashCode => userId.hashCode ^ data.hashCode;

  bool _deepEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

/// Represents a cursor position in a collaborative environment
class CursorData {
  final String userId;
  final String? userName;
  final String? userColor;
  final double x;
  final double y;
  final Map<String, dynamic>? metadata;
  final DateTime lastUpdated;

  CursorData({
    required this.userId,
    this.userName,
    this.userColor,
    required this.x,
    required this.y,
    this.metadata,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    if (userName != null) 'userName': userName,
    if (userColor != null) 'userColor': userColor,
    'x': x,
    'y': y,
    if (metadata != null) 'metadata': metadata,
    'lastUpdated': lastUpdated.millisecondsSinceEpoch,
  };

  factory CursorData.fromJson(Map<String, dynamic> json) {
    return CursorData(
      userId: json['userId'] as String,
      userName: json['userName'] as String?,
      userColor: json['userColor'] as String?,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'] as int),
    );
  }

  CursorData copyWith({
    String? userId,
    String? userName,
    String? userColor,
    double? x,
    double? y,
    Map<String, dynamic>? metadata,
    DateTime? lastUpdated,
  }) {
    return CursorData(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userColor: userColor ?? this.userColor,
      x: x ?? this.x,
      y: y ?? this.y,
      metadata: metadata ?? this.metadata,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorData &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => userId.hashCode ^ x.hashCode ^ y.hashCode;
}

/// Manages presence and collaboration features for InstantDB
class PresenceManager {
  dynamic _syncEngine; // SyncEngine? - using dynamic to avoid circular imports
  final AuthManager _authManager;
  final dynamic _db; // InstantDB instance to get consistent anonymous user ID
  final _uuid = const Uuid();

  // Room-based presence data
  final Map<String, Map<String, PresenceData>> _roomPresence = {};
  final Map<String, Signal<Map<String, PresenceData>>> _presenceSignals = {};

  // Cursor tracking
  final Map<String, Map<String, CursorData>> _roomCursors = {};
  final Map<String, Signal<Map<String, CursorData>>> _cursorSignals = {};

  // Typing indicators
  final Map<String, Map<String, DateTime>> _roomTyping = {};
  final Map<String, Signal<Map<String, DateTime>>> _typingSignals = {};

  // Reactions
  final Map<String, List<ReactionData>> _roomReactions = {};
  final Map<String, Signal<List<ReactionData>>> _reactionSignals = {};

  // Topic pub/sub system
  final Map<String, Map<String, StreamController<Map<String, dynamic>>>> _roomTopics = {};
  final Map<String, Map<String, Stream<Map<String, dynamic>>>> _topicStreams = {};

  // Cleanup timers
  final Map<String, Timer> _cleanupTimers = {};
  
  // Track joined rooms - key format: "roomType:roomId"
  final Set<String> _joinedRooms = {};
  // Track rooms that should be active (persist across reconnections)
  final Set<String> _activeRooms = {};
  final Map<String, Completer<void>> _roomJoinCompleters = {};

  PresenceManager({
    required dynamic syncEngine, // SyncEngine? - using dynamic to avoid circular imports
    required AuthManager authManager,
    required dynamic db, // InstantDB instance
  })  : _syncEngine = syncEngine,
        _authManager = authManager,
        _db = db;

  /// Get user ID (authenticated or anonymous)
  String _getUserId() {
    final user = _authManager.currentUser.value;
    if (user != null) {
      return user.id;
    }
    
    // For anonymous users, use consistent UUID from InstantDB instance
    return _db.getAnonymousUserId();
  }

  /// Set user's presence data in a room
  Future<void> setPresence(String roomId, Map<String, dynamic> data) async {
    final userId = _getUserId();

    final presenceData = PresenceData(
      userId: userId,
      data: data,
      lastSeen: DateTime.now(),
    );

    // Update local state
    _roomPresence.putIfAbsent(roomId, () => {});
    _roomPresence[roomId]![userId] = presenceData;

    // Notify signal listeners
    _getPresenceSignal(roomId).value = Map.from(_roomPresence[roomId]!);

    // Send to server if sync engine is available
    if (_syncEngine != null) {
      await _ensureRoomJoined(roomId);
      await _sendPresenceMessageWithRetry(roomId, 'set', presenceData.toJson());
    }

    InstantDBLogging.root.debug('Set presence for user $userId in room $roomId');
  }

  /// Get presence data for a room
  Signal<Map<String, PresenceData>> getPresence(String roomId) {
    return _getPresenceSignal(roomId);
  }

  /// Update cursor position in a room
  Future<void> updateCursor(
    String roomId, {
    required double x,
    required double y,
    String? userName,
    String? userColor,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _getUserId();

    final cursorData = CursorData(
      userId: userId,
      userName: userName,
      userColor: userColor,
      x: x,
      y: y,
      metadata: metadata,
      lastUpdated: DateTime.now(),
    );

    // Update local state
    _roomCursors.putIfAbsent(roomId, () => {});
    _roomCursors[roomId]![userId] = cursorData;

    // Notify signal listeners
    _getCursorSignal(roomId).value = Map.from(_roomCursors[roomId]!);

    // Send to server with throttling
    if (_syncEngine != null) {
      await _ensureRoomJoined(roomId);
      await _sendPresenceMessageWithRetry(roomId, 'cursor', cursorData.toJson());
    }
  }

  /// Get cursor positions for a room
  Signal<Map<String, CursorData>> getCursors(String roomId) {
    return _getCursorSignal(roomId);
  }

  /// Set typing status for a user in a room
  Future<void> setTyping(String roomId, bool isTyping) async {
    final userId = _getUserId();
    
    // Update local typing state
    _roomTyping.putIfAbsent(roomId, () => {});
    if (isTyping) {
      _roomTyping[roomId]![userId] = DateTime.now();
    } else {
      _roomTyping[roomId]!.remove(userId);
    }
    
    // Notify signal listeners
    _getTypingSignal(roomId).value = Map.from(_roomTyping[roomId]!);
    
    // Send to server
    if (_syncEngine != null) {
      await _ensureRoomJoined(roomId);
      await _sendPresenceMessageWithRetry(roomId, 'typing', {
        'userId': userId,
        'isTyping': isTyping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    
    // Auto-clear typing after 3 seconds
    if (isTyping) {
      Timer(const Duration(seconds: 3), () {
        setTyping(roomId, false);
      });
    }
  }

  /// Get typing indicators for a room
  Signal<Map<String, DateTime>> getTyping(String roomId) {
    return _getTypingSignal(roomId);
  }

  /// Send a reaction in a room
  Future<void> sendReaction(String roomId, String emoji, {
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _getUserId();

    final reaction = ReactionData(
      id: _uuid.v4(),
      userId: userId,
      roomId: roomId,
      emoji: emoji,
      messageId: messageId,
      metadata: metadata,
      timestamp: DateTime.now(),
    );

    // Update local state
    _roomReactions.putIfAbsent(roomId, () => []);
    _roomReactions[roomId]!.add(reaction);

    // Keep only the last 50 reactions
    if (_roomReactions[roomId]!.length > 50) {
      _roomReactions[roomId]!.removeAt(0);
    }

    // Notify signal listeners
    _getReactionSignal(roomId).value = List.from(_roomReactions[roomId]!);

    // Ensure room is joined before sending presence message - use simplified data format
    if (_syncEngine != null) {
      await _ensureRoomJoined(roomId);
      final simplifiedData = {
        'emoji': emoji,
        'x': metadata?['x'] ?? 0,
        'y': metadata?['y'] ?? 0,
        'userId': userId,
      };
      await _sendPresenceMessageWithRetry(roomId, 'reaction', simplifiedData);
    }

    // Auto-remove reaction after 5 seconds
    Timer(const Duration(seconds: 5), () {
      _roomReactions[roomId]?.removeWhere((r) => r.id == reaction.id);
      if (_roomReactions[roomId] != null) {
        _getReactionSignal(roomId).value = List.from(_roomReactions[roomId]!);
      }
    });
  }

  /// Get reactions for a room
  Signal<List<ReactionData>> getReactions(String roomId) {
    return _getReactionSignal(roomId);
  }

  /// Join a room and return a room-specific API
  InstantRoom joinRoom(String roomId, {Map<String, dynamic>? initialPresence}) {
    // For now, we'll assume roomType is the same as roomId for backwards compatibility
    // In a full implementation, this should accept roomType as a parameter
    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';
    
    // Initialize room data if needed
    _roomPresence.putIfAbsent(roomKey, () => {});
    _roomCursors.putIfAbsent(roomKey, () => {});
    _roomTyping.putIfAbsent(roomKey, () => {});
    _roomReactions.putIfAbsent(roomKey, () => []);
    _roomTopics.putIfAbsent(roomKey, () => {});

    // Track this room as active so it gets rejoined on reconnect
    _activeRooms.add(roomKey);
    
    // Send proper join-room message to server first
    if (_syncEngine != null && !_joinedRooms.contains(roomKey)) {
      InstantDBLogging.root.debug('PresenceManager: Sending join-room for $roomKey');
      _syncEngine!.sendJoinRoom(roomType, roomId);
      
      // Add to joined rooms after a small delay to ensure message was sent
      Future.delayed(const Duration(milliseconds: 50), () {
        _joinedRooms.add(roomKey);
        InstantDBLogging.root.debug('PresenceManager: Room $roomKey marked as joined');
      });
    }

    // Set initial presence if provided (after joining room)
    if (initialPresence != null) {
      setPresence(roomKey, initialPresence);
    }

    InstantDBLogging.root.debug('Joined room $roomKey');
    
    return InstantRoom._(this, roomKey);
  }

  /// Leave a room (clear presence)
  Future<void> leaveRoom(String roomId) async {
    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';
    final user = _authManager.currentUser.value;
    String userId;
    
    if (user == null) {
      // For anonymous users, we need to clear all anonymous data
      // This is a simplified approach for testing
      _roomPresence[roomId]?.clear();
      _roomCursors[roomId]?.clear();
      _roomTyping[roomId]?.clear();
    } else {
      userId = user.id;
      // Remove from local state
      _roomPresence[roomId]?.remove(userId);
      _roomCursors[roomId]?.remove(userId);
      _roomTyping[roomId]?.remove(userId);
    }

    // Update signals
    if (_presenceSignals.containsKey(roomId)) {
      _presenceSignals[roomId]!.value = Map.from(_roomPresence[roomId] ?? {});
    }
    if (_cursorSignals.containsKey(roomId)) {
      _cursorSignals[roomId]!.value = Map.from(_roomCursors[roomId] ?? {});
    }
    if (_typingSignals.containsKey(roomId)) {
      _typingSignals[roomId]!.value = Map.from(_roomTyping[roomId] ?? {});
    }

    // Send leave message to server (no need to ensure room joined for leave)
    if (_syncEngine != null && user != null) {
      await _sendPresenceMessage(roomId, 'leave', {'userId': user.id});
    }

    // Remove from active and joined rooms
    _activeRooms.remove(roomKey);
    _joinedRooms.remove(roomKey);
    
    InstantDBLogging.root.debug('Left room $roomId');
  }


  void _handlePresenceSet(String roomId, Map<String, dynamic> data) {
    try {
      final presenceData = PresenceData.fromJson(data);
      
      _roomPresence.putIfAbsent(roomId, () => {});
      _roomPresence[roomId]![presenceData.userId] = presenceData;
      
      _getPresenceSignal(roomId).value = Map.from(_roomPresence[roomId]!);
    } catch (e) {
      InstantDBLogging.root.severe('Error handling presence set', e);
    }
  }

  void _handleCursorUpdate(String roomId, Map<String, dynamic> data) {
    try {
      final cursorData = CursorData.fromJson(data);
      
      _roomCursors.putIfAbsent(roomId, () => {});
      _roomCursors[roomId]![cursorData.userId] = cursorData;
      
      _getCursorSignal(roomId).value = Map.from(_roomCursors[roomId]!);
    } catch (e) {
      InstantDBLogging.root.severe('Error handling cursor update', e);
    }
  }

  void _handleTypingUpdate(String roomId, Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String;
      final isTyping = data['isTyping'] as bool;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
      
      _roomTyping.putIfAbsent(roomId, () => {});
      
      if (isTyping) {
        _roomTyping[roomId]![userId] = timestamp;
      } else {
        _roomTyping[roomId]!.remove(userId);
      }
      
      _getTypingSignal(roomId).value = Map.from(_roomTyping[roomId]!);
    } catch (e) {
      InstantDBLogging.root.severe('Error handling typing update', e);
    }
  }

  void _handleReactionUpdate(String roomId, Map<String, dynamic> data) {
    try {
      final reaction = ReactionData.fromJson(data);
      
      _roomReactions.putIfAbsent(roomId, () => []);
      _roomReactions[roomId]!.add(reaction);
      
      // Keep only the last 50 reactions
      if (_roomReactions[roomId]!.length > 50) {
        _roomReactions[roomId]!.removeAt(0);
      }
      
      _getReactionSignal(roomId).value = List.from(_roomReactions[roomId]!);
    } catch (e) {
      InstantDBLogging.root.severe('Error handling reaction update', e);
    }
  }

  void _handleUserLeave(String roomId, Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String;
      
      _roomPresence[roomId]?.remove(userId);
      _roomCursors[roomId]?.remove(userId);
      _roomTyping[roomId]?.remove(userId);
      
      // Update signals
      if (_presenceSignals.containsKey(roomId)) {
        _presenceSignals[roomId]!.value = Map.from(_roomPresence[roomId] ?? {});
      }
      if (_cursorSignals.containsKey(roomId)) {
        _cursorSignals[roomId]!.value = Map.from(_roomCursors[roomId] ?? {});
      }
      if (_typingSignals.containsKey(roomId)) {
        _typingSignals[roomId]!.value = Map.from(_roomTyping[roomId] ?? {});
      }
    } catch (e) {
      InstantDBLogging.root.severe('Error handling user leave', e);
    }
  }

  /// Handle WebSocket connection status changes
  void _handleConnectionStatusChange(bool isConnected) {
    if (isConnected) {
      InstantDBLogging.root.info('PresenceManager: WebSocket connected, rejoining active rooms');
      _rejoinActiveRooms();
    } else {
      InstantDBLogging.root.info('PresenceManager: WebSocket disconnected, clearing joined rooms state');
      // Clear joined rooms but keep active rooms for rejoining
      _joinedRooms.clear();
    }
  }

  /// Rejoin all active rooms after reconnection
  Future<void> _rejoinActiveRooms() async {
    if (_activeRooms.isEmpty) {
      InstantDBLogging.root.debug('PresenceManager: No active rooms to rejoin');
      return;
    }

    InstantDBLogging.root.info('PresenceManager: Rejoining ${_activeRooms.length} active rooms');
    for (final roomKey in _activeRooms.toList()) {
      try {
        final parts = roomKey.split(':');
        if (parts.length == 2) {
          final roomType = parts[0];
          final roomId = parts[1];
          
          InstantDBLogging.root.info('PresenceManager: Rejoining room $roomKey');
          _syncEngine!.sendJoinRoom(roomType, roomId);
          _joinedRooms.add(roomKey);
          
          // Small delay between room joins to avoid overwhelming the server
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        InstantDBLogging.root.severe('PresenceManager: Failed to rejoin room $roomKey', e);
      }
    }
    
    InstantDBLogging.root.info('PresenceManager: Room rejoin process completed');
  }

  /// Ensure a room is properly joined before sending presence messages
  Future<void> _ensureRoomJoined(String roomId) async {
    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';
    
    InstantDBLogging.root.debug('PresenceManager: _ensureRoomJoined called for roomKey: $roomKey');
    InstantDBLogging.root.debug('PresenceManager: Currently joined rooms: ${_joinedRooms.toList()}');
    InstantDBLogging.root.debug('PresenceManager: Currently active rooms: ${_activeRooms.toList()}');
    
    if (!_joinedRooms.contains(roomKey)) {
      InstantDBLogging.root.info('PresenceManager: JOIN ROOM MESSAGE - Joining room $roomKey before sending presence');
      InstantDBLogging.root.info('PresenceManager: SyncEngine available: ${_syncEngine != null}');
      
      if (_syncEngine != null) {
        // Add to active rooms if not already there
        _activeRooms.add(roomKey);
        
        _syncEngine!.sendJoinRoom(roomType, roomId);
        
        // Add to joined rooms after a short delay to ensure message was sent
        await Future.delayed(const Duration(milliseconds: 100));
        _joinedRooms.add(roomKey);
        
        InstantDBLogging.root.info('PresenceManager: Room $roomKey join message sent and marked as joined');
      } else {
        InstantDBLogging.root.severe('PresenceManager: Cannot join room - sync engine is null');
        throw InstantException(message: 'Cannot join room - sync engine is null');
      }
    } else {
      InstantDBLogging.root.debug('PresenceManager: Room $roomKey already joined, skipping join');
    }
  }

  /// Force rejoin a room (used when presence messages fail)
  Future<void> _forceRejoinRoom(String roomId) async {
    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';
    
    InstantDBLogging.root.warning('PresenceManager: Force rejoining room $roomKey due to server error');
    
    // Remove from joined rooms to force rejoin
    _joinedRooms.remove(roomKey);
    
    // Ensure it's in active rooms
    _activeRooms.add(roomKey);
    
    // Rejoin the room
    await _ensureRoomJoined(roomId);
  }

  /// Send presence message with preventive room join check
  Future<void> _sendPresenceMessageWithRetry(String roomId, String type, Map<String, dynamic> data, {int retryCount = 0}) async {
    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';
    
    // If room is not in active rooms, add it
    if (!_activeRooms.contains(roomKey)) {
      _activeRooms.add(roomKey);
      InstantDBLogging.root.info('PresenceManager: Added $roomKey to active rooms');
    }
    
    // If we're not confident the room is joined (especially after reconnect), force rejoin
    if (!_joinedRooms.contains(roomKey)) {
      InstantDBLogging.root.info('PresenceManager: Room $roomKey not in joined set, ensuring join before sending $type');
      await _ensureRoomJoined(roomId);
    }
    
    // Send the presence message
    await _sendPresenceMessage(roomId, type, data);
  }

  Future<void> _sendPresenceMessage(String roomId, String type, Map<String, dynamic> data) async {
    if (_syncEngine == null) {
      InstantDBLogging.root.warning('PresenceManager: Cannot send presence message - sync engine not available');
      return;
    }

    const roomType = 'presence-room';
    final roomKey = '$roomType:$roomId';

    // Try simpler message format matching React SDK
    final message = {
      'op': 'set-presence',
      'room-type': roomType,
      'room-id': roomId,
      'data': data,
      'client-event-id': _uuid.v4(),
    };

    InstantDBLogging.root.debug('PresenceManager: Sending set-presence message - room: $roomKey, type: $type');
    _syncEngine!.sendPresence(message);
  }

  Signal<Map<String, PresenceData>> _getPresenceSignal(String roomId) {
    if (!_presenceSignals.containsKey(roomId)) {
      _presenceSignals[roomId] = signal<Map<String, PresenceData>>({});
      _startCleanupTimer(roomId);
    }
    return _presenceSignals[roomId]!;
  }

  Signal<Map<String, CursorData>> _getCursorSignal(String roomId) {
    if (!_cursorSignals.containsKey(roomId)) {
      _cursorSignals[roomId] = signal<Map<String, CursorData>>({});
    }
    return _cursorSignals[roomId]!;
  }

  Signal<Map<String, DateTime>> _getTypingSignal(String roomId) {
    if (!_typingSignals.containsKey(roomId)) {
      _typingSignals[roomId] = signal<Map<String, DateTime>>({});
    }
    return _typingSignals[roomId]!;
  }

  Signal<List<ReactionData>> _getReactionSignal(String roomId) {
    if (!_reactionSignals.containsKey(roomId)) {
      _reactionSignals[roomId] = signal<List<ReactionData>>([]);
    }
    return _reactionSignals[roomId]!;
  }

  void _startCleanupTimer(String roomId) {
    _cleanupTimers[roomId]?.cancel();
    _cleanupTimers[roomId] = Timer.periodic(const Duration(seconds: 30), (timer) {
      _cleanupStaleData(roomId);
    });
  }

  void _cleanupStaleData(String roomId) {
    final now = DateTime.now();
    final staleThreshold = now.subtract(const Duration(seconds: 60));

    // Clean up stale presence data
    _roomPresence[roomId]?.removeWhere((userId, presence) => 
        presence.lastSeen.isBefore(staleThreshold));

    // Clean up stale cursors
    _roomCursors[roomId]?.removeWhere((userId, cursor) => 
        cursor.lastUpdated.isBefore(staleThreshold));

    // Clean up stale typing indicators
    _roomTyping[roomId]?.removeWhere((userId, timestamp) => 
        timestamp.isBefore(staleThreshold));

    // Update signals
    if (_presenceSignals.containsKey(roomId)) {
      _presenceSignals[roomId]!.value = Map.from(_roomPresence[roomId] ?? {});
    }
    if (_cursorSignals.containsKey(roomId)) {
      _cursorSignals[roomId]!.value = Map.from(_roomCursors[roomId] ?? {});
    }
    if (_typingSignals.containsKey(roomId)) {
      _typingSignals[roomId]!.value = Map.from(_roomTyping[roomId] ?? {});
    }
  }

  /// Publish a message to a topic in a room
  Future<void> publishTopic(String roomId, String topic, Map<String, dynamic> data) async {
    // Send to server
    if (_syncEngine != null) {
      await _ensureRoomJoined(roomId);
      await _sendPresenceMessageWithRetry(roomId, 'topic', {
        'topic': topic,
        'data': data,
        'userId': _getUserId(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // Emit to local subscribers
    final topicController = _getRoomTopicController(roomId, topic);
    topicController.add(data);
  }

  /// Subscribe to a topic in a room
  Stream<Map<String, dynamic>> subscribeTopic(String roomId, String topic) {
    return _getRoomTopicStream(roomId, topic);
  }

  /// Get or create topic controller for room/topic
  StreamController<Map<String, dynamic>> _getRoomTopicController(String roomId, String topic) {
    _roomTopics.putIfAbsent(roomId, () => {});
    
    if (!_roomTopics[roomId]!.containsKey(topic)) {
      _roomTopics[roomId]![topic] = StreamController<Map<String, dynamic>>.broadcast();
      _topicStreams.putIfAbsent(roomId, () => {});
      _topicStreams[roomId]![topic] = _roomTopics[roomId]![topic]!.stream;
    }
    
    return _roomTopics[roomId]![topic]!;
  }

  /// Get or create topic stream for room/topic
  Stream<Map<String, dynamic>> _getRoomTopicStream(String roomId, String topic) {
    _getRoomTopicController(roomId, topic); // Ensure controller exists
    return _topicStreams[roomId]![topic]!;
  }

  /// Handle incoming topic messages
  void _handleTopicMessage(String roomId, String topic, Map<String, dynamic> data) {
    final controller = _getRoomTopicController(roomId, topic);
    controller.add(data);
  }

  /// Set the sync engine after initialization (used to resolve circular dependency)
  void setSyncEngine(dynamic syncEngine) {
    _syncEngine = syncEngine;
    
    // Set up connection status listener if not already done
    if (_syncEngine != null) {
      effect(() {
        final isConnected = _syncEngine!.connectionStatus.value;
        _handleConnectionStatusChange(isConnected);
      });
    }
  }

  /// Handle incoming presence messages from the server
  void handlePresenceMessage(Map<String, dynamic> data) {
    try {
      final type = data['type'] as String?;
      final roomId = data['room-id'] as String? ?? data['roomId'] as String?;
      final presenceData = data['data'] as Map<String, dynamic>?;
      
      if (type == null || roomId == null || presenceData == null) {
        InstantDBLogging.root.warning('PresenceManager: Invalid presence message format: $data');
        return;
      }

      InstantDBLogging.root.debug('PresenceManager: Processing presence message - type: $type, roomId: $roomId');
      
      switch (type) {
        case 'reaction':
          _handleIncomingReaction(roomId, presenceData);
          break;
        case 'cursor':
          _handleIncomingCursor(roomId, presenceData);
          break;
        case 'typing':
          _handleIncomingTyping(roomId, presenceData);
          break;
        case 'set':
          _handleIncomingPresenceSet(roomId, presenceData);
          break;
        default:
          InstantDBLogging.root.debug('PresenceManager: Unknown presence type: $type');
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling presence message', e, stackTrace);
    }
  }

  /// Handle refresh-presence messages containing all peer data
  void handleRefreshPresenceMessage(String roomId, Map<String, dynamic> peersData) {
    try {
      InstantDBLogging.root.debug('PresenceManager: Processing refresh-presence for room $roomId with ${peersData.length} peers');
      
      // CRITICAL: Save local user's presence before processing peers
      // The server only sends peer data, not the local user's data
      final localUserId = _getUserId();
      final localPresence = _roomPresence[roomId]?[localUserId];
      
      // Update local presence state for all peers
      for (final entry in peersData.entries) {
        final peerId = entry.key;
        final peerData = entry.value as Map<String, dynamic>;
        final presenceDataWrapper = peerData['data'] as Map<String, dynamic>? ?? {};
        
        // Extract user ID
        final peerUserId = presenceDataWrapper['userId'] as String?;
        
        // Try to get data - first check if it's directly in presenceDataWrapper (typing data),
        // then check nested structure (other presence data)
        Map<String, dynamic> userData;
        if (presenceDataWrapper.containsKey('isTyping')) {
          // Typing data comes directly in presenceDataWrapper
          userData = Map<String, dynamic>.from(presenceDataWrapper);
        } else {
          // Other data is nested under 'data' key
          userData = presenceDataWrapper['data'] as Map<String, dynamic>? ?? {};
        }
        
        InstantDBLogging.root.debug('PresenceManager: Processing peer $peerId with userId $peerUserId, userData: $userData');
        
        if (userData.isNotEmpty) {
          // Detect and route different types of presence data based on contents
          if (userData.containsKey('emoji') && userData.containsKey('x') && userData.containsKey('y')) {
            // This is reaction data - convert it to a visible reaction
            InstantDBLogging.root.debug('PresenceManager: Converting refresh-presence data to visible reaction: $userData');
            _handleIncomingReaction(roomId, userData);
            
          } else if (userData.containsKey('x') && userData.containsKey('y') && !userData.containsKey('emoji')) {
            // This is cursor data (has coordinates but no emoji)
            InstantDBLogging.root.debug('PresenceManager: Converting refresh-presence data to cursor: $userData');
            final cursorData = Map<String, dynamic>.from(userData);
            cursorData['userId'] = peerUserId ?? peerId; // Use actual userId, fallback to peer ID
            _handleIncomingCursor(roomId, cursorData);
            
          } else if (userData.containsKey('isTyping')) {
            // This is typing data
            InstantDBLogging.root.debug('PresenceManager: Converting refresh-presence data to typing indicator: $userData');
            final typingData = Map<String, dynamic>.from(userData);
            // Keep the userId from the data itself, it should already be there
            _handleIncomingTyping(roomId, typingData);
            
          } else if (userData.containsKey('userName') || userData.containsKey('status')) {
            // This is avatar presence data (has userName or status)
            InstantDBLogging.root.debug('PresenceManager: Converting refresh-presence data to presence: $userData');
            final presenceDataMap = {
              'userId': peerUserId ?? peerId, // Use the actual userId, not peer ID
              'data': userData,
            };
            _handleIncomingPresenceSet(roomId, presenceDataMap);
            
          } else {
            // Generic presence data - store directly
            final actualUserId = peerUserId ?? peerId;
            final presenceData = PresenceData(
              userId: actualUserId,
              data: userData,
              lastSeen: DateTime.now(),
            );
            
            _roomPresence.putIfAbsent(roomId, () => {});
            _roomPresence[roomId]![actualUserId] = presenceData;
          }
        }
      }
      
      // CRITICAL: Re-add local user's presence after processing peers
      // This ensures the local user always appears in their own presence list
      if (localPresence != null) {
        _roomPresence.putIfAbsent(roomId, () => {});
        _roomPresence[roomId]![localUserId] = localPresence;
        InstantDBLogging.root.debug('PresenceManager: Preserved local user $localUserId in presence list after refresh');
      }
      
      // Notify presence signal listeners with complete data (local + peers)
      if (_presenceSignals.containsKey(roomId)) {
        _presenceSignals[roomId]!.value = Map.from(_roomPresence[roomId] ?? {});
      }
      
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling refresh-presence message', e, stackTrace);
    }
  }

  void _handleIncomingReaction(String roomId, Map<String, dynamic> data) {
    try {
      final emoji = data['emoji'] as String?;
      final userId = data['userId'] as String?;
      final x = data['x'] as num? ?? 0;
      final y = data['y'] as num? ?? 0;
      
      if (emoji != null && userId != null) {
        final reaction = ReactionData(
          id: _uuid.v4(),
          userId: userId,
          roomId: roomId,
          emoji: emoji,
          metadata: {'x': x.toDouble(), 'y': y.toDouble()},
          timestamp: DateTime.now(),
        );
        
        _roomReactions.putIfAbsent(roomId, () => []);
        _roomReactions[roomId]!.add(reaction);
        
        // Keep only the last 50 reactions
        if (_roomReactions[roomId]!.length > 50) {
          _roomReactions[roomId]!.removeAt(0);
        }
        
        // Notify signal listeners
        _getReactionSignal(roomId).value = List.from(_roomReactions[roomId]!);
        
        InstantDBLogging.root.debug('PresenceManager: Added remote reaction $emoji from user $userId in room $roomId');
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling incoming reaction', e, stackTrace);
    }
  }

  void _handleIncomingCursor(String roomId, Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String?;
      final x = data['x'] as num? ?? 0;
      final y = data['y'] as num? ?? 0;
      final userName = data['userName'] as String?;
      final userColor = data['userColor'] as String?;
      final metadata = data['metadata'] as Map<String, dynamic>?;
      
      if (userId != null) {
        final cursorData = CursorData(
          userId: userId,
          userName: userName,
          userColor: userColor,
          x: x.toDouble(),
          y: y.toDouble(),
          metadata: metadata,
          lastUpdated: DateTime.now(),
        );
        
        _roomCursors.putIfAbsent(roomId, () => {});
        _roomCursors[roomId]![userId] = cursorData;
        
        // Notify signal listeners
        _getCursorSignal(roomId).value = Map.from(_roomCursors[roomId]!);
        
        InstantDBLogging.root.debug('PresenceManager: Added remote cursor from user $userId at ($x, $y) in room $roomId');
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling incoming cursor', e, stackTrace);
    }
  }

  void _handleIncomingTyping(String roomId, Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String?;
      final isTyping = data['isTyping'] as bool?;
      final timestamp = data['timestamp'] as int?;
      
      if (userId != null && isTyping != null) {
        // Skip our own typing data - we don't want to see our own typing indicator
        final currentUserId = _getUserId();
        if (userId == currentUserId) {
          InstantDBLogging.root.debug('PresenceManager: Skipping own typing data for user $userId in room $roomId');
          return;
        }
        
        _roomTyping.putIfAbsent(roomId, () => {});
        
        if (isTyping && timestamp != null) {
          _roomTyping[roomId]![userId] = DateTime.fromMillisecondsSinceEpoch(timestamp);
        } else {
          _roomTyping[roomId]!.remove(userId);
        }
        
        // Notify signal listeners
        _getTypingSignal(roomId).value = Map.from(_roomTyping[roomId]!);
        
        InstantDBLogging.root.debug('PresenceManager: Updated remote typing for user $userId in room $roomId - isTyping: $isTyping');
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling incoming typing', e, stackTrace);
    }
  }

  void _handleIncomingPresenceSet(String roomId, Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String?;
      final presenceData = data['data'] as Map<String, dynamic>?;
      
      if (userId != null && presenceData != null) {
        final presence = PresenceData(
          userId: userId,
          data: presenceData,
          lastSeen: DateTime.now(),
        );
        
        _roomPresence.putIfAbsent(roomId, () => {});
        _roomPresence[roomId]![userId] = presence;
        
        // Notify signal listeners
        _getPresenceSignal(roomId).value = Map.from(_roomPresence[roomId]!);
        
        InstantDBLogging.root.debug('PresenceManager: Updated remote presence for user $userId in room $roomId');
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling incoming presence set', e, stackTrace);
    }
  }

  /// Dispose of the presence manager and cleanup resources
  void dispose() {
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    _cleanupTimers.clear();

    // Dispose topic controllers
    for (final roomTopics in _roomTopics.values) {
      for (final controller in roomTopics.values) {
        controller.close();
      }
    }
    _roomTopics.clear();
    _topicStreams.clear();
    
    _presenceSignals.clear();
    _cursorSignals.clear();
    _typingSignals.clear();
    _reactionSignals.clear();
    
    _roomPresence.clear();
    _roomCursors.clear();
    _roomTyping.clear();
    _roomReactions.clear();
  }
}

/// Represents a reaction in a room
class ReactionData {
  final String id;
  final String userId;
  final String roomId;
  final String emoji;
  final String? messageId;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  ReactionData({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.emoji,
    this.messageId,
    this.metadata,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'roomId': roomId,
    'emoji': emoji,
    if (messageId != null) 'messageId': messageId,
    if (metadata != null) 'metadata': metadata,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory ReactionData.fromJson(Map<String, dynamic> json) {
    return ReactionData(
      id: json['id'] as String,
      userId: json['userId'] as String,
      roomId: json['roomId'] as String,
      emoji: json['emoji'] as String,
      messageId: json['messageId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionData &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Room-specific API for InstantDB presence and collaboration features
/// This class provides a scoped interface for a specific room
class InstantRoom {
  final PresenceManager _presenceManager;
  final String roomId;

  InstantRoom._(this._presenceManager, this.roomId);

  /// Set presence data for the current user in this room
  Future<void> setPresence(Map<String, dynamic> data) async {
    return _presenceManager.setPresence(roomId, data);
  }

  /// Get presence data for all users in this room
  Signal<Map<String, PresenceData>> getPresence() {
    return _presenceManager.getPresence(roomId);
  }

  /// Update cursor position in this room
  Future<void> updateCursor({
    required double x,
    required double y,
    String? userName,
    String? userColor,
    Map<String, dynamic>? metadata,
  }) async {
    return _presenceManager.updateCursor(
      roomId,
      x: x,
      y: y,
      userName: userName,
      userColor: userColor,
      metadata: metadata,
    );
  }

  /// Get cursor positions for all users in this room
  Signal<Map<String, CursorData>> getCursors() {
    return _presenceManager.getCursors(roomId);
  }

  /// Set typing status for the current user in this room
  Future<void> setTyping(bool isTyping) async {
    return _presenceManager.setTyping(roomId, isTyping);
  }

  /// Get typing indicators for all users in this room
  Signal<Map<String, DateTime>> getTyping() {
    return _presenceManager.getTyping(roomId);
  }

  /// Send a reaction in this room
  Future<void> sendReaction(String emoji, {
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    return _presenceManager.sendReaction(
      roomId,
      emoji,
      messageId: messageId,
      metadata: metadata,
    );
  }

  /// Get reactions for this room
  Signal<List<ReactionData>> getReactions() {
    return _presenceManager.getReactions(roomId);
  }

  /// Publish a message to a topic in this room
  Future<void> publishTopic(String topic, Map<String, dynamic> data) async {
    return _presenceManager.publishTopic(roomId, topic, data);
  }

  /// Subscribe to a topic in this room
  Stream<Map<String, dynamic>> subscribeTopic(String topic) {
    return _presenceManager.subscribeTopic(roomId, topic);
  }

  /// Leave this room
  Future<void> leave() async {
    return _presenceManager.leaveRoom(roomId);
  }

  /// Get the room ID
  String get id => roomId;
}