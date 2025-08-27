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
  InstantRoom? _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
      _joinRoom();
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
      final db = InstantProvider.of(context);
      _userId = db.getAnonymousUserId(); // Use consistent anonymous user ID
      _userName = 'Guest ${_userId!.substring(_userId!.length - 4)}';
    }
  }

  void _joinRoom() {
    final db = InstantProvider.of(context);
    // Join the avatars room using the new room-based API
    _room = db.presence.joinRoom('avatars-room', initialPresence: {
      'userName': _userName,
      'status': 'online',
    });
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
    if (_userId == null || _room == null) return;
    
    // Update presence using new room-based API
    _room!.setPresence({
      'userName': _userName,
      'status': 'online',
    });
  }

  void _removePresence() {
    if (_userId == null) return;
    
    final db = InstantProvider.of(context);
    
    // Remove presence using presence API
    db.presence.leaveRoom('avatars-room');
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
        
        // User list using new room-based API
        Expanded(
          child: Watch((context) {
            if (_room == null) return const SizedBox.shrink();
            
            final presenceData = _room!.getPresence().value;
            
            final presenceList = presenceData.entries
                .where((entry) => entry.value.data['status'] == 'online')
                .toList();
              
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
                          final presenceEntry = entry.value;
                          final userId = presenceEntry.key;
                          final presence = presenceEntry.value;
                          final userName = presence.data['userName'] ?? 'Unknown';
                          final isMe = userId == _userId;
                          
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
                        final presenceEntry = presenceList[index];
                        final userId = presenceEntry.key;
                        final presence = presenceEntry.value;
                        final userName = presence.data['userName'] ?? 'Unknown';
                        final isMe = userId == _userId;
                        
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
                            subtitle: Text('Online'),
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
          }),
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
}