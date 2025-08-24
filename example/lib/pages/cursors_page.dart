import 'dart:async';
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

class CursorsPage extends StatefulWidget {
  const CursorsPage({super.key});

  @override
  State<CursorsPage> createState() => _CursorsPageState();
}

class _CursorsPageState extends State<CursorsPage> {
  String? _userId;
  Timer? _cursorTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _removeCursor();
    super.dispose();
  }

  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    _userId = currentUser?.id ?? 'cursor_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _updateCursor(Offset position) {
    if (_userId == null) return;
    
    final db = InstantProvider.of(context);
    
    // Cancel existing timer
    _cursorTimer?.cancel();
    
    // Update cursor position using presence API
    db.presence.updateCursor(
      'cursors-room',
      x: position.dx,
      y: position.dy,
    );
    
    // Set timer to remove cursor after 5 seconds of inactivity
    _cursorTimer = Timer(const Duration(seconds: 5), _removeCursor);
  }

  void _removeCursor() {
    if (_userId == null) return;
    
    final db = InstantProvider.of(context);
    
    // Remove cursor using presence API
    db.presence.leaveRoom('cursors-room');
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
                Icons.mouse_outlined,
                size: 48,
                color: Colors.purple,
              ),
              const SizedBox(height: 16),
              Text(
                'Cursor Tracking',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Move your cursor to see others!',
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
                  onPanEnd: (_) {
                    // Keep cursor visible for a bit after touch ends
                  },
                  child: Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border: Border.all(
                        color: Colors.grey[300]!,
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
                                Icons.pan_tool_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Move your mouse or drag to track cursor',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Open in multiple windows to see other cursors',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Cursors
                        Watch((context) {
                          final db = InstantProvider.of(context);
                          final cursors = db.presence.getCursors('cursors-room').value;
                          
                          return Stack(
                            children: cursors.entries.map((entry) {
                              final userId = entry.key;
                              final cursor = entry.value;
                              final x = cursor.x;
                              final y = cursor.y;
                              final isMe = userId == _userId;
                              
                              return _CursorWidget(
                                position: Offset(x, y),
                                isMe: isMe,
                                userId: userId,
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
        
        // Stats
        Container(
          padding: const EdgeInsets.all(16),
          child: Watch((context) {
            final db = InstantProvider.of(context);
            final cursors = db.presence.getCursors('cursors-room').value;
            final activeCursors = cursors.length;
            
            return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mouse_outlined,
                          size: 16,
                          color: Colors.purple[700],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$activeCursors active cursor${activeCursors == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.purple[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            );
          }),
        ),
      ],
    );
  }
}

class _CursorWidget extends StatelessWidget {
  final Offset position;
  final bool isMe;
  final String userId;

  const _CursorWidget({
    required this.position,
    required this.isMe,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    // Generate color from userId
    final hue = (userId.hashCode % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.7, 0.5).toColor();
    
    return Positioned(
      left: position.dx - 12,
      top: position.dy - 12,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          child: Transform.rotate(
            angle: -0.2,
            child: CustomPaint(
              size: const Size(24, 24),
              painter: _CursorPainter(
                color: color,
                isMe: isMe,
              ),
            ),
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
      ..lineTo(size.width * 0.3, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.8)
      ..lineTo(size.width * 0.4, size.height * 0.45)
      ..lineTo(size.width * 0.7, size.height * 0.45)
      ..close();
    
    // Draw white outline
    canvas.drawPath(path, outlinePaint);
    
    // Draw colored fill
    canvas.drawPath(path, paint);
    
    // Add dot for "me" indicator
    if (isMe) {
      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(size.width * 0.7, size.height * 0.2),
        3,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) {
    return color != oldDelegate.color || isMe != oldDelegate.isMe;
  }
}