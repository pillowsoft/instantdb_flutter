// Web implementation
import 'dart:async';
import 'dart:html' as html;
import '../core/logging_config.dart';

class WebSocketManager {
  static final _logger = InstantDBLogging.webSocket;
  
  static Future<WebSocketAdapter> connect(String url) async {
    final completer = Completer<WebSocketAdapter>();

    _logger.fine('WebSocket Web: Connecting to $url');
    final ws = html.WebSocket(url);

    ws.onOpen.listen((_) {
      _logger.fine('WebSocket Web: Connection opened');
      completer.complete(WebSocketAdapter(ws));
    });

    ws.onError.listen((event) {
      _logger.warning('WebSocket Web: Connection error: $event');
      if (!completer.isCompleted) {
        completer.completeError('WebSocket connection failed');
      }
    });

    return completer.future;
  }
}

class WebSocketAdapter {
  final html.WebSocket _webSocket;
  late final StreamController<dynamic> _streamController;

  WebSocketAdapter(this._webSocket) {
    _streamController = StreamController<dynamic>.broadcast();

    _webSocket.onMessage.listen((event) {
      _streamController.add(event.data);
    });

    _webSocket.onClose.listen((_) {
      _streamController.close();
    });

    _webSocket.onError.listen((event) {
      _streamController.addError(event);
    });
  }

  Stream<dynamic> get stream => _streamController.stream;

  void send(String data) {
    if (_webSocket.readyState == html.WebSocket.OPEN) {
      _webSocket.send(data);
    }
  }

  Future<void> close() async {
    _webSocket.close();
    await _streamController.close();
  }

  bool get isOpen => _webSocket.readyState == html.WebSocket.OPEN;
}
