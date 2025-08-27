// IO implementation (mobile, desktop)
import 'dart:async';
import 'dart:io';

class WebSocketManager {
  static Future<WebSocketAdapter> connect(String url) async {
    print('WebSocket IO: Connecting to $url');
    final ws = await WebSocket.connect(url);
    print('WebSocket IO: Connected successfully');
    return WebSocketAdapter(ws);
  }
}

class WebSocketAdapter {
  final WebSocket _webSocket;

  WebSocketAdapter(this._webSocket);

  Stream<dynamic> get stream => _webSocket;

  void send(String data) {
    _webSocket.add(data);
  }

  Future<void> close() async {
    await _webSocket.close();
  }

  bool get isOpen => _webSocket.readyState == WebSocket.open;
}
