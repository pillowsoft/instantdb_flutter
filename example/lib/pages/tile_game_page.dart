import 'package:flutter/material.dart';

class TileGamePage extends StatelessWidget {
  const TileGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.grid_on_outlined,
            size: 64,
            color: Colors.red,
          ),
          SizedBox(height: 16),
          Text(
            'Merge Tile Game',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Collaborative tile coloring coming soon!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}