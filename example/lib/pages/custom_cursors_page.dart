import 'dart:async';
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import '../utils/colors.dart';

class CustomCursorsPage extends StatefulWidget {
  const CustomCursorsPage({super.key});

  @override
  State<CustomCursorsPage> createState() => _CustomCursorsPageState();
}

class _CustomCursorsPageState extends State<CustomCursorsPage> {
  String? _userId;
  String? _userName;
  Color? _userColor;
  Timer? _cursorTimer;
  InstantRoom? _room;
  final _nameController = TextEditingController();
  bool _hasSetName = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
      _joinRoom();
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _nameController.dispose();
    _removeCursor();
    super.dispose();
  }

  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    
    if (currentUser != null) {
      _userId = currentUser.id;
      _userName = currentUser.email.split('@')[0];
      _userColor = UserColors.fromString(currentUser.email);
      _hasSetName = true;
    } else {
      final db = InstantProvider.of(context);
      _userId = db.getAnonymousUserId(); // Use consistent anonymous user ID
      _userName = 'Guest';
      _userColor = UserColors.fromString(_userId!);
    }
  }

  void _joinRoom() {
    final db = InstantProvider.of(context);
    // Join the custom cursors room using the presence API
    _room = db.presence.joinRoom('custom-cursors-room');
  }

  void _setUserName() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      setState(() {
        _userName = name;
        _hasSetName = true;
      });
    }
  }

  void _updateCursor(Offset position) {
    if (_userId == null || !_hasSetName || _room == null) return;
    
    // Cancel existing timer
    _cursorTimer?.cancel();
    
    // Update cursor position using presence system
    _room!.updateCursor(
      x: position.dx,
      y: position.dy,
      userName: _userName,
      userColor: _userColor?.toARGB32().toString(),
      metadata: {
        'color': _userColor!.toARGB32(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
    
    // Set timer to remove cursor after 5 seconds of inactivity
    _cursorTimer = Timer(const Duration(seconds: 5), _removeCursor);
  }

  void _removeCursor() {
    if (_userId == null || _room == null) return;
    
    // Remove cursor using presence system
    _room!.removeCursor();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSetName) {
      return _buildNameSetup();
    }

    return Column(
      children: [
        // Header with user info
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _userColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _userName!.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Your cursor color',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Move your cursor to see others with names!',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        
        // Cursor tracking area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                onHover: (event) {
                  // Get position relative to the tracking area
                  final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final localPosition = renderBox.globalToLocal(event.position);
                    _updateCursor(localPosition);
                  }
                },
                onExit: (_) => _removeCursor(),
                child: GestureDetector(
                  onPanUpdate: (details) {
                    _updateCursor(details.localPosition);
                  },
                  child: Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.deepPurple[50]!,
                          Colors.indigo[50]!,
                        ],
                      ),
                      border: Border.all(
                        color: Colors.deepPurple[200]!,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Instructions
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.gesture_outlined,
                                size: 64,
                                color: Colors.deepPurple[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Move your mouse or touch to track',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.deepPurple[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Cursors using presence system
                        Watch((context) {
                          if (_room == null) return const SizedBox.shrink();
                          
                          final cursors = _room!.getCursors().value;
                          
                          return Stack(
                            children: cursors.entries.map((entry) {
                              final userId = entry.key;
                              final cursor = entry.value;
                              final userName = cursor.userName ?? _userName ?? 'Unknown';
                              // Get color from metadata or use user color
                              final colorValue = cursor.metadata?['color'] as int?;
                              final color = colorValue != null ? Color(colorValue) : _userColor ?? Colors.purple;
                              final x = cursor.x;
                              final y = cursor.y;
                              final isMe = userId == _userId;
                              
                              return _CustomCursorWidget(
                                position: Offset(x, y),
                                userName: userName,
                                color: color,
                                isMe: isMe,
                              );
                            }).toList(),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNameSetup() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 64,
                color: Colors.deepPurple[400],
              ),
              const SizedBox(height: 24),
              Text(
                'Choose Your Name',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick a name to identify your cursor',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  hintText: 'Enter your name',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _setUserName(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _setUserName,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomCursorWidget extends StatelessWidget {
  final Offset position;
  final String userName;
  final Color color;
  final bool isMe;

  const _CustomCursorWidget({
    required this.position,
    required this.userName,
    required this.color,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cursor
              Transform.rotate(
                angle: -0.2,
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _CursorPainter(
                    color: color,
                    isMe: isMe,
                  ),
                ),
              ),
              // Name label
              Container(
                margin: const EdgeInsets.only(left: 16, top: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '(You)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final Color color;
  final bool isMe;

  _CursorPainter({
    required this.color,
    required this.isMe,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    // Cursor path
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height * 0.7)
      ..lineTo(size.width * 0.25, size.height * 0.5)
      ..lineTo(size.width * 0.4, size.height * 0.75)
      ..lineTo(size.width * 0.35, size.height * 0.45)
      ..lineTo(size.width * 0.65, size.height * 0.45)
      ..close();
    
    // Draw white outline
    canvas.drawPath(path, outlinePaint);
    
    // Draw colored fill
    canvas.drawPath(path, paint);
    
    // Add glow effect for current user
    if (isMe) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      
      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) {
    return color != oldDelegate.color || isMe != oldDelegate.isMe;
  }
}