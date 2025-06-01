import 'package:flutter/material.dart';

class TypingPage extends StatelessWidget {
  const TypingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.keyboard_outlined,
            size: 64,
            color: Colors.teal,
          ),
          SizedBox(height: 16),
          Text(
            'Typing Indicator Example',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '"User is typing..." indicators coming soon!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}