import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

class ReactionsPage extends StatefulWidget {
  const ReactionsPage({super.key});

  @override
  State<ReactionsPage> createState() => _ReactionsPageState();
}

class _ReactionsPageState extends State<ReactionsPage> {
  String? _userId;
  final List<_AnimatedReaction> _localReactions = [];
  InstantRoom? _room;

  static const List<String> _emojis = ['❤️', '👍', '😄', '🎉', '🚀', '✨', '🔥', '💯'];

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
    _userId = currentUser?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _joinRoom() {
    final db = InstantProvider.of(context);
    // Join the reactions room using the new room-based API
    _room = db.presence.joinRoom('reactions-room');
  }

  void _sendReaction(String emoji, Offset globalPosition) {
    if (_userId == null || _room == null) return;
    
    final db = InstantProvider.of(context);
    
    // Convert global position to local position relative to the screen
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final localPosition = renderBox?.globalToLocal(globalPosition) ?? globalPosition;
    
    // Create reaction using the new room-based API
    _room!.sendReaction(emoji, metadata: {
      'x': localPosition.dx,
      'y': localPosition.dy,
    });
    
    // Add local reaction for immediate feedback
    final reactionId = db.id();
    setState(() {
      _localReactions.add(_AnimatedReaction(
        id: reactionId,
        emoji: emoji,
        position: localPosition,
        onComplete: () {
          setState(() {
            _localReactions.removeWhere((r) => r.id == reactionId);
          });
        },
      ));
    });
    
    // Auto-delete reaction after animation completes (3 seconds)
    Timer(const Duration(seconds: 3), () {
      db.transact([
        db.delete(reactionId),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.celebration_outlined,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Emoji Reactions',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap anywhere to send a reaction!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            // Emoji selector
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _emojis.map((emoji) {
                  return _EmojiButton(
                    emoji: emoji,
                    onTap: (globalPosition) => _sendReaction(emoji, globalPosition),
                  );
                }).toList(),
              ),
            ),
            
            // Reaction area
            Expanded(
              child: GestureDetector(
                onTapDown: (details) {
                  // Send random emoji on tap
                  final randomEmoji = _emojis[math.Random().nextInt(_emojis.length)];
                  _sendReaction(randomEmoji, details.globalPosition);
                },
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap anywhere or use emojis above',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        
        // Remote reactions from new room-based API
        Watch((context) {
          if (_room == null) return const SizedBox.shrink();
          
          final reactionsData = _room!.getReactions().value;
          
          return Stack(
            children: reactionsData.map((reaction) {
              final id = reaction.id;
              final emoji = reaction.emoji;
              final x = (reaction.metadata?['x'] ?? 0.0).toDouble();
              final y = (reaction.metadata?['y'] ?? 0.0).toDouble();
              final isLocal = _localReactions.any((r) => r.id == id);
              
              // Skip if we're already showing this as a local reaction
              if (isLocal) return const SizedBox.shrink();
              
              return _AnimatedReaction(
                id: id,
                emoji: emoji,
                position: Offset(x, y),
                onComplete: () {},
              );
            }).toList(),
          );
        }),
        
        // Local reactions (for immediate feedback)
        ..._localReactions,
      ],
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final Function(Offset) onTap;

  const _EmojiButton({
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => onTap(details.globalPosition),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ),
    );
  }
}

class _AnimatedReaction extends StatefulWidget {
  final String id;
  final String emoji;
  final Offset position;
  final VoidCallback onComplete;

  const _AnimatedReaction({
    required this.id,
    required this.emoji,
    required this.position,
    required this.onComplete,
  });

  @override
  State<_AnimatedReaction> createState() => _AnimatedReactionState();
}

class _AnimatedReactionState extends State<_AnimatedReaction>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _positionAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    // Scale animation - grow then shrink
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);
    
    // Fade animation
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 30,
      ),
    ]).animate(_controller);
    
    // Position animation - float upward
    _positionAnimation = Tween<Offset>(
      begin: widget.position,
      end: Offset(widget.position.dx, widget.position.dy - 150),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx - 28, // Center the emoji
          top: _positionAnimation.value.dy - 28,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}