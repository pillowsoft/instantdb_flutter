import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import '../utils/colors.dart';

class AvatarsPage extends StatefulWidget {
  const AvatarsPage({super.key});

  @override
  State<AvatarsPage> createState() => _AvatarsPageState();
}

class _AvatarsPageState extends State<AvatarsPage> {
  String? _userId;
  String? _userName;
  Timer? _presenceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
      _startPresence();
    }
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _removePresence();
    super.dispose();
  }

  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    
    // Use authenticated user or generate temporary identity
    if (currentUser != null) {
      _userId = currentUser.id;
      _userName = currentUser.email;
    } else {
      _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = 'Guest ${_userId!.substring(_userId!.length - 4)}';
    }
  }

  void _startPresence() {
    if (_userId == null) return;
    
    // Update presence immediately
    _updatePresence();
    
    // Update presence every 10 seconds
    _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updatePresence();
    });
  }

  void _updatePresence() {
    if (_userId == null) return;
    
    final db = InstantProvider.of(context);
    
    db.transact([
      ...db.create('presence', {
        'id': _userId,
        'userId': _userId,
        'userName': _userName,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'status': 'online',
      }),
    ]);
  }

  void _removePresence() {
    if (_userId == null) return;
    
    final db = InstantProvider.of(context);
    
    db.transact([
      db.delete(_userId!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.people_outline,
                size: 48,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                'Connected Users',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'See who else is online right now',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        
        // User list
        Expanded(
          child: InstantBuilder(
            query: {'presence': {}},
            builder: (context, data) {
              final presenceList = (data['presence'] as List? ?? [])
                  .where((p) {
                    // Filter out stale presence (older than 30 seconds)
                    final lastSeen = p['lastSeen'] ?? 0;
                    final age = DateTime.now().millisecondsSinceEpoch - lastSeen;
                    return age < 30000;
                  })
                  .toList()
                  ..sort((a, b) {
                    // Sort by last seen, most recent first
                    final aTime = a['lastSeen'] ?? 0;
                    final bTime = b['lastSeen'] ?? 0;
                    return bTime.compareTo(aTime);
                  });
              
              if (presenceList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No one else is online',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open this page in another window to see presence!',
                        style: TextStyle(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              return Column(
                children: [
                  // Avatar stack
                  Container(
                    height: 120,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background circle
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                        ),
                        // Avatar stack
                        ...presenceList.take(5).toList().asMap().entries.map((entry) {
                          final index = entry.key;
                          final presence = entry.value;
                          final userName = presence['userName'] ?? 'Unknown';
                          final isMe = presence['userId'] == _userId;
                          
                          // Calculate position in circle
                          final angle = (index * 2 * 3.14159) / presenceList.length;
                          final radius = 40.0;
                          final x = radius * math.cos(angle);
                          final y = radius * math.sin(angle);
                          
                          return Transform.translate(
                            offset: Offset(x, y),
                            child: _buildAvatar(
                              userName: userName,
                              isMe: isMe,
                              size: 48,
                            ),
                          );
                        }),
                        // Count indicator if more than 5
                        if (presenceList.length > 5)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '+${presenceList.length - 5}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // User count
                  Text(
                    '${presenceList.length} ${presenceList.length == 1 ? 'person' : 'people'} online',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // User list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: presenceList.length,
                      itemBuilder: (context, index) {
                        final presence = presenceList[index];
                        final userName = presence['userName'] ?? 'Unknown';
                        final lastSeen = presence['lastSeen'] ?? 0;
                        final isMe = presence['userId'] == _userId;
                        
                        return Card(
                          child: ListTile(
                            leading: _buildAvatar(
                              userName: userName,
                              isMe: isMe,
                              size: 40,
                            ),
                            title: Row(
                              children: [
                                Text(userName),
                                if (isMe) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(_formatLastSeen(lastSeen)),
                            trailing: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar({
    required String userName,
    required bool isMe,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UserColors.fromString(userName),
        shape: BoxShape.circle,
        border: Border.all(
          color: isMe ? Colors.green : Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          UserColors.getInitials(userName),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }

  String _formatLastSeen(int timestamp) {
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inSeconds < 5) {
      return 'Active now';
    } else if (difference.inSeconds < 30) {
      return 'Active ${difference.inSeconds}s ago';
    } else {
      return 'Active recently';
    }
  }
}