import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_discovery.dart';

class LocalDiscoveryHost {
  LocalDiscoveryHost({
    required this.roomId,
    required this.roomName,
    this.webSocketPort = 40405,
  });

  final String roomId;
  final String roomName;
  final int webSocketPort;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      LocalDiscovery.discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final message = utf8.decode(datagram.data, allowMalformed: true);
      if (message != LocalDiscovery.discoveryRequest) return;

      final response = jsonEncode(<String, Object>{
        'type': 'domino_host',
        'protocolVersion': 1,
        'roomId': roomId,
        'roomName': roomName,
        'port': webSocketPort,
      });
      socket.send(utf8.encode(response), datagram.address, datagram.port);
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}

// End of local host discovery service.
