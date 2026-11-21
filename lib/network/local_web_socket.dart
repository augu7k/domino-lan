import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalWebSocketHost {
  LocalWebSocketHost({this.port = 40405, this.maxClients = 3});

  final int port;
  final int maxClients;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;
  final Set<WebSocket> _clients = <WebSocket>{};

  void Function(WebSocket client, Object message)? onMessage;
  void Function(WebSocket client)? onClientConnected;
  void Function(WebSocket client)? onClientDisconnected;

  int get connectedClients => _clients.length;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _requests = server.listen((request) async {
      if (request.uri.path != '/ws') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (_clients.length >= maxClients) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      try {
        final client = await WebSocketTransformer.upgrade(request);
        _clients.add(client);
        onClientConnected?.call(client);
        client.listen(
          (message) => onMessage?.call(client, message),
          onDone: () {
            _clients.remove(client);
            onClientDisconnected?.call(client);
          },
          onError: (Object error) {
            _clients.remove(client);
            onClientDisconnected?.call(client);
          },
          cancelOnError: true,
        );
      } on WebSocketException {
        // The request may have disconnected before the upgrade completed.
      } on HttpException {
        // Ignore malformed or interrupted upgrade requests.
      }
    });
  }

  void sendTo(WebSocket client, Map<String, Object?> message) {
    if (_clients.contains(client) && client.readyState == WebSocket.open) {
      client.add(jsonEncode(message));
    }
  }

  void broadcast(Map<String, Object?> message) {
    final encoded = jsonEncode(message);
    for (final client in _clients.toList()) {
      if (client.readyState == WebSocket.open) client.add(encoded);
    }
  }

  Future<void> stop() async {
    await _requests?.cancel();
    _requests = null;
    for (final client in _clients.toList()) {
      await client.close(WebSocketStatus.goingAway, 'Host stopped');
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

class LocalWebSocketClient {
  LocalWebSocketClient._(this._socket);

  final WebSocket _socket;
  Stream<dynamic> get messages => _socket;
  bool get isConnected => _socket.readyState == WebSocket.open;

  static Future<LocalWebSocketClient> connect({
    required String host,
    int port = 40405,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await WebSocket.connect(
      'ws://$host:$port/ws',
    ).timeout(timeout);
    return LocalWebSocketClient._(socket);
  }

  void send(Map<String, Object?> message) {
    if (!isConnected) throw StateError('The local host connection is closed.');
    _socket.add(jsonEncode(message));
  }

  Future<void> close() => _socket.close();
}
