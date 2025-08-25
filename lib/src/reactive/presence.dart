import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../core/logging.dart';
import '../sync/sync_engine.dart';
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
  final SyncEngine? _syncEngine;
  final AuthManager _authManager;
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
  
  // Anonymous user ID for testing (consistent per session)
  String? _anonymousUserId;

  PresenceManager({
    required SyncEngine? syncEngine,
    required AuthManager authManager,
  })  : _syncEngine = syncEngine,
        _authManager = authManager;

  /// Get user ID (authenticated or anonymous)
  String _getUserId() {
    final user = _authManager.currentUser.value;
    if (user != null) {
      return user.id;
    }
    
    // For anonymous users, use consistent ID per session
    _anonymousUserId ??= 'anonymous-${DateTime.now().millisecondsSinceEpoch}';
    return _anonymousUserId!;
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
      await _sendPresenceMessage(roomId, 'set', presenceData.toJson());
    }

    InstantLogger.debug('Set presence for user $userId in room $roomId');
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
      await _sendPresenceMessage(roomId, 'cursor', cursorData.toJson());
    }
  }

  /// Get cursor positions for a room
  Signal<Map<String, CursorData>> getCursors(String roomId) {
    return _getCursorSignal(roomId);
  }

  /// Set typing status for a user in a room
  Future<void> setTyping(String roomId, bool isTyping) async {
    final userId = _getUserId();

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
      await _sendPresenceMessage(roomId, 'typing', {
        'userId': userId,
        'isTyping': isTyping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // Auto-clear typing after 3 seconds
    if (isTyping) {
      Timer(const Duration(seconds: 3), () {
        if (_roomTyping[roomId]?[userId] != null) {
          setTyping(roomId, false);
        }
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

    // Send to server
    if (_syncEngine != null) {
      await _sendPresenceMessage(roomId, 'reaction', reaction.toJson());
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
    // Initialize room data if needed
    _roomPresence.putIfAbsent(roomId, () => {});
    _roomCursors.putIfAbsent(roomId, () => {});
    _roomTyping.putIfAbsent(roomId, () => {});
    _roomReactions.putIfAbsent(roomId, () => []);
    _roomTopics.putIfAbsent(roomId, () => {});

    // Set initial presence if provided
    if (initialPresence != null) {
      setPresence(roomId, initialPresence);
    }

    // Send join message to server
    if (_syncEngine != null) {
      _sendPresenceMessage(roomId, 'join', {
        'userId': _getUserId(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    InstantLogger.debug('Joined room $roomId');
    
    return InstantRoom._(this, roomId);
  }

  /// Leave a room (clear presence)
  Future<void> leaveRoom(String roomId) async {
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

    // Send leave message to server
    if (_syncEngine != null && user != null) {
      await _sendPresenceMessage(roomId, 'leave', {'userId': user.id});
    }

    InstantLogger.debug('Left room $roomId');
  }

  /// Handle incoming presence messages from the sync engine
  void handlePresenceMessage(Map<String, dynamic> message) {
    try {
      final roomId = message['roomId'] as String?;
      final type = message['type'] as String?;
      final data = message['data'] as Map<String, dynamic>?;

      if (roomId == null || type == null || data == null) return;

      switch (type) {
        case 'set':
          _handlePresenceSet(roomId, data);
          break;
        case 'cursor':
          _handleCursorUpdate(roomId, data);
          break;
        case 'typing':
          _handleTypingUpdate(roomId, data);
          break;
        case 'reaction':
          _handleReactionUpdate(roomId, data);
          break;
        case 'leave':
          _handleUserLeave(roomId, data);
          break;
        case 'topic':
          final topic = data['topic'] as String;
          final messageData = data['data'] as Map<String, dynamic>;
          _handleTopicMessage(roomId, topic, messageData);
          break;
      }
    } catch (e) {
      InstantLogger.error('Error handling presence message', e);
    }
  }

  void _handlePresenceSet(String roomId, Map<String, dynamic> data) {
    try {
      final presenceData = PresenceData.fromJson(data);
      
      _roomPresence.putIfAbsent(roomId, () => {});
      _roomPresence[roomId]![presenceData.userId] = presenceData;
      
      _getPresenceSignal(roomId).value = Map.from(_roomPresence[roomId]!);
    } catch (e) {
      InstantLogger.error('Error handling presence set', e);
    }
  }

  void _handleCursorUpdate(String roomId, Map<String, dynamic> data) {
    try {
      final cursorData = CursorData.fromJson(data);
      
      _roomCursors.putIfAbsent(roomId, () => {});
      _roomCursors[roomId]![cursorData.userId] = cursorData;
      
      _getCursorSignal(roomId).value = Map.from(_roomCursors[roomId]!);
    } catch (e) {
      InstantLogger.error('Error handling cursor update', e);
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
      InstantLogger.error('Error handling typing update', e);
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
      InstantLogger.error('Error handling reaction update', e);
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
      InstantLogger.error('Error handling user leave', e);
    }
  }

  Future<void> _sendPresenceMessage(String roomId, String type, Map<String, dynamic> data) async {
    if (_syncEngine == null) return;

    final message = {
      'op': 'presence',
      'roomId': roomId,
      'type': type,
      'data': data,
      'clientEventId': _uuid.v4(),
    };

    // In a real implementation, you would send this via the sync engine
    // For now, we'll just log it
    InstantLogger.debug('Would send presence message: ${jsonEncode(message)}');
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
      await _sendPresenceMessage(roomId, 'topic', {
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