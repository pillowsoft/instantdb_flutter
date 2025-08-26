import 'dart:async';
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import '../utils/colors.dart';

class TypingPage extends StatefulWidget {
  const TypingPage({super.key});

  @override
  State<TypingPage> createState() => _TypingPageState();
}

class _TypingPageState extends State<TypingPage> {
  final _messageController = TextEditingController();
  final _messages = <ChatMessage>[];
  Timer? _typingTimer;
  String? _userId;
  InstantRoom? _room;

  @override
  void initState() {
    super.initState();
    // Initialize user in didChangeDependencies to access context
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
      _joinRoom();
    }
  }

  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    
    // Use authenticated user ID or generate a temporary one
    _userId = currentUser?.id ?? db.id(); // Generate proper UUID
  }

  void _joinRoom() {
    final db = InstantProvider.of(context);
    // Join the chat room using the new room-based API with initial presence
    _room = db.presence.joinRoom('chat-room', initialPresence: {
      'userName': _getUserName(),
      'status': 'online',
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _stopTyping();
    super.dispose();
  }

  void _startTyping() {
    if (_userId == null || _room == null) return;
    
    // Cancel existing timer
    _typingTimer?.cancel();
    
    // Create typing indicator using new room-based API
    _room!.setTyping(true);
    
    // Set timer to remove typing indicator after 3 seconds of inactivity
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    if (_userId == null || _room == null) return;
    
    // Remove typing indicator using new room-based API
    _room!.setTyping(false);
  }

  String _getUserName() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    return currentUser?.email ?? 'Anonymous $_userId';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _userId == null) return;
    
    final db = InstantProvider.of(context);
    
    // Add message
    final message = ChatMessage(
      id: db.id(),
      userId: _userId!,
      userName: _getUserName(),
      text: text,
      timestamp: DateTime.now(),
    );
    
    db.transact([
      ...db.create('messages', {
        'id': message.id,
        'userId': message.userId,
        'userName': message.userName,
        'text': message.text,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
      }),
    ]);
    
    // Clear input and stop typing
    _messageController.clear();
    _stopTyping();
    
    // Add to local messages for immediate feedback
    setState(() {
      _messages.add(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Messages list
        Expanded(
          child: InstantBuilder(
            query: {'messages': {}},
            loadingBuilder: (context) => const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error) => Center(
              child: Text('Error: $error'),
            ),
            builder: (context, data) {
              final messages = (data['messages'] as List? ?? [])
                  .map((msg) => ChatMessage(
                        id: msg['id'],
                        userId: msg['userId'],
                        userName: msg['userName'] ?? 'Unknown',
                        text: msg['text'] ?? '',
                        timestamp: DateTime.fromMillisecondsSinceEpoch(
                          msg['timestamp'] ?? 0,
                        ),
                      ))
                  .toList()
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
              
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isMe = message.userId == _userId;
                  
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      child: Card(
                        color: isMe ? Colors.teal : Colors.grey[200],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.userName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isMe ? Colors.teal[100] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(message.timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe ? Colors.teal[100] : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        
        // Typing indicators using new room-based API
        Watch((context) {
          if (_room == null) return const SizedBox.shrink();
          
          final typingData = _room!.getTyping().value;
          
          // Filter out current user (typing data is Map<String, DateTime>)
          final indicators = typingData.entries
              .where((entry) => entry.key != _userId)
              .toList();
            
            if (indicators.isEmpty) return const SizedBox.shrink();
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  // Avatar stack
                  SizedBox(
                    width: indicators.length * 20.0 + 20,
                    height: 30,
                    child: Stack(
                      children: indicators.asMap().entries.map((mapEntry) {
                        final index = mapEntry.key;
                        final indicatorEntry = mapEntry.value;
                        final userId = indicatorEntry.key;
                        final userName = userId.startsWith('user_') ? userId.substring(5, 9) : userId.substring(0, 4);
                        
                        return Positioned(
                          left: index * 20.0,
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: UserColors.fromString(userName),
                            child: Text(
                              userName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Typing text
                  Text(
                    _buildTypingText(indicators),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Animated dots
                  const _TypingDots(),
                ],
              ),
            );
        }),
        
        // Message input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) => _startTyping(),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildTypingText(List<MapEntry<String, DateTime>> indicators) {
    if (indicators.isEmpty) return '';
    if (_room == null) return 'Someone is typing...';

    // Get presence data to look up user names
    final presenceData = _room!.getPresence().value;
    
    // Map typing user IDs to their names
    final typingUsers = indicators.map((entry) {
      final userId = entry.key;
      final presence = presenceData[userId];
      final userName = presence?.data['userName'] as String?;
      // Fallback to user ID fragment if no userName found
      return userName ?? (userId.length > 4 ? userId.substring(userId.length - 4) : userId);
    }).toList();

    if (typingUsers.length == 1) {
      return '${typingUsers[0]} is typing...';
    } else if (typingUsers.length == 2) {
      return '${typingUsers[0]} and ${typingUsers[1]} are typing...';
    } else {
      return '${typingUsers[0]} and ${typingUsers.length - 1} others are typing...';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

class ChatMessage {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.3;
            final value = (_animation.value + delay) % 1.0;
            final opacity = value < 0.5 ? value * 2 : 2 - value * 2;
            
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.grey[600]!.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}