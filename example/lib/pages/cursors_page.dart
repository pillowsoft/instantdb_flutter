import 'package:flutter/material.dart';

class CursorsPage extends StatelessWidget {
  const CursorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mouse_outlined,
            size: 64,
            color: Colors.purple,
          ),
          SizedBox(height: 16),
          Text(
            'Cursors Example',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Real-time cursor tracking coming soon!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}