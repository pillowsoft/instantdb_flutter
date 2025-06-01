import 'dart:async';
import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import '../utils/colors.dart';

class TileGamePage extends StatefulWidget {
  const TileGamePage({super.key});

  @override
  State<TileGamePage> createState() => _TileGamePageState();
}

class _TileGamePageState extends State<TileGamePage> {
  static const int gridSize = 16;
  static const double tileSize = 20.0;
  
  String? _userId;
  String? _userName;
  Color? _userColor;
  
  // Track tiles being painted in current drag
  final Set<String> _currentDragTiles = {};
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
    }
  }
  
  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    
    if (currentUser != null) {
      _userId = currentUser.id;
      _userName = currentUser.email.split('@')[0];
      _userColor = UserColors.fromString(currentUser.email);
    } else {
      _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = 'Player ${_userId!.substring(_userId!.length - 4)}';
      _userColor = UserColors.fromString(_userId!);
    }
  }
  
  void _paintTile(int row, int col) {
    if (_userId == null) return;
    
    final tileId = 'tile_${row}_$col';
    
    // Skip if already painted in this drag
    if (_currentDragTiles.contains(tileId)) return;
    
    _currentDragTiles.add(tileId);
    
    final db = InstantProvider.of(context);
    
    db.transact([
      ...db.create('tiles', {
        'id': tileId,
        'row': row,
        'col': col,
        'userId': _userId,
        'userName': _userName,
        'color': _userColor!.toARGB32(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    ]);
  }
  
  void _clearGrid() {
    final db = InstantProvider.of(context);
    
    // Get all tiles
    db.query({'tiles': {}});
    Future(() async {
      // Wait a bit for query to update
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Get tiles from signal
      final result = db.query({'tiles': {}}).value;
      final tiles = result.data?['tiles'] as List? ?? [];
      final transactions = tiles.map((tile) => db.delete(tile['id'])).toList();
      
      if (transactions.isNotEmpty) {
        db.transact(transactions);
      }
    });
  }
  
  Offset? _getTilePosition(Offset localPosition, Size bounds) {
    if (localPosition.dx < 0 || localPosition.dy < 0) return null;
    if (localPosition.dx > bounds.width || localPosition.dy > bounds.height) return null;
    
    final col = (localPosition.dx / tileSize).floor();
    final row = (localPosition.dy / tileSize).floor();
    
    if (row >= 0 && row < gridSize && col >= 0 && col < gridSize) {
      return Offset(col.toDouble(), row.toDouble());
    }
    
    return null;
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
                Icons.grid_on_outlined,
                size: 48,
                color: Colors.indigo,
              ),
              const SizedBox(height: 16),
              Text(
                'Merge Tile Game',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Paint the grid collaboratively!',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // User info
              if (_userName != null && _userColor != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _userColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _userName!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        
        // Grid
        Expanded(
          child: Center(
            child: Container(
              width: gridSize * tileSize,
              height: gridSize * tileSize,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(
                  color: Colors.grey[400]!,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GestureDetector(
                onPanStart: (details) {
                  _currentDragTiles.clear();
                  final tile = _getTilePosition(details.localPosition, Size(gridSize * tileSize, gridSize * tileSize));
                  if (tile != null) {
                    _paintTile(tile.dy.toInt(), tile.dx.toInt());
                  }
                },
                onPanUpdate: (details) {
                  final tile = _getTilePosition(details.localPosition, Size(gridSize * tileSize, gridSize * tileSize));
                  if (tile != null) {
                    _paintTile(tile.dy.toInt(), tile.dx.toInt());
                  }
                },
                onPanEnd: (_) {
                  _currentDragTiles.clear();
                },
                onTapDown: (details) {
                  final tile = _getTilePosition(details.localPosition, Size(gridSize * tileSize, gridSize * tileSize));
                  if (tile != null) {
                    _paintTile(tile.dy.toInt(), tile.dx.toInt());
                  }
                },
                child: Stack(
                  children: [
                    // Grid lines
                    CustomPaint(
                      size: Size(gridSize * tileSize, gridSize * tileSize),
                      painter: _GridPainter(),
                    ),
                    
                    // Tiles
                    InstantBuilder(
                      query: {'tiles': {}},
                      builder: (context, data) {
                        final tiles = data['tiles'] as List? ?? [];
                        
                        return Stack(
                          children: tiles.map((tile) {
                            final row = tile['row'] ?? 0;
                            final col = tile['col'] ?? 0;
                            final color = Color(tile['color'] ?? Colors.blue.toARGB32());
                            final userName = tile['userName'] ?? 'Unknown';
                            
                            return Positioned(
                              left: col * tileSize,
                              top: row * tileSize,
                              child: _TileWidget(
                                size: tileSize,
                                color: color,
                                userName: userName,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Controls and stats
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Stats
              InstantBuilder(
                query: {'tiles': {}},
                builder: (context, data) {
                  final tiles = data['tiles'] as List? ?? [];
                  
                  // Count tiles by user
                  final tileCounts = <String, int>{};
                  for (final tile in tiles) {
                    final userName = tile['userName'] ?? 'Unknown';
                    tileCounts[userName] = (tileCounts[userName] ?? 0) + 1;
                  }
                  
                  // Sort by count
                  final sortedUsers = tileCounts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  
                  return Column(
                    children: [
                      // Total tiles
                      Text(
                        '${tiles.length} / ${gridSize * gridSize} tiles painted',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      
                      // Top painters
                      if (sortedUsers.isNotEmpty) ...[
                        const Text(
                          'Top Painters:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 16,
                          children: sortedUsers.take(3).map((entry) {
                            return Text(
                              '${entry.key}: ${entry.value}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Clear button
              FilledButton.icon(
                onPressed: _clearGrid,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Grid'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    // Draw vertical lines
    for (int i = 0; i <= _TileGamePageState.gridSize; i++) {
      final x = i * _TileGamePageState.tileSize;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Draw horizontal lines
    for (int i = 0; i <= _TileGamePageState.gridSize; i++) {
      final y = i * _TileGamePageState.tileSize;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TileWidget extends StatelessWidget {
  final double size;
  final Color color;
  final String userName;
  
  const _TileWidget({
    required this.size,
    required this.color,
    required this.userName,
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: color.withValues(alpha: 0.8),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Show tooltip with painter info
            final overlay = Overlay.of(context);
            late OverlayEntry entry;
            
            entry = OverlayEntry(
              builder: (context) => Positioned(
                left: 0,
                right: 0,
                bottom: 100,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Painted by $userName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            
            overlay.insert(entry);
            
            // Remove after 2 seconds
            Future.delayed(const Duration(seconds: 2), () {
              entry.remove();
            });
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}