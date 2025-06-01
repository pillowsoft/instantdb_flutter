import 'package:flutter/material.dart';

class CustomCursorsPage extends StatelessWidget {
  const CustomCursorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_location_alt_outlined,
            size: 64,
            color: Colors.indigo,
          ),
          SizedBox(height: 16),
          Text(
            'Custom Cursors Example',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Cursors with names and colors coming soon!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}