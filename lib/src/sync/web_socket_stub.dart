// Stub implementation for non-web platforms
import 'dart:async';

class WebSocketManager {
  static Future<dynamic> connect(String url) {
    throw UnsupportedError('This platform is not supported');
  }
}