import 'package:flutter/material.dart';

/// Generates a color based on a string (e.g., user ID or email)
class UserColors {
  static const List<Color> _palette = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFF97316), // Orange
    Color(0xFF14B8A6), // Teal
    Color(0xFFEC4899), // Pink
    Color(0xFF84CC16), // Lime
  ];

  static Color fromString(String str) {
    // Generate a hash from the string
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash = hash & hash; // Convert to 32-bit integer
    }
    
    // Use the hash to pick a color from the palette
    final index = hash.abs() % _palette.length;
    return _palette[index];
  }

  static String getInitials(String str) {
    final parts = str.split('@')[0].split(RegExp(r'[._-]'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return str.substring(0, 2).toUpperCase();
  }
}