import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovered_host.dart';

class LocalDiscovery {
  LocalDiscovery._();

  static const int discoveryPort = 40406;
  static const String discoveryRequest = 'DOMINO_DISCOVER_V1';

  /// Listens for local hosts for [timeout]. UDP broadcast can be blocked by
  /// some hotspot implementations; manual IP entry remains the fallback.
  static Future<List<DiscoveredHost>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final found = <String, DiscoveredHost>{};
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is! Map<String, dynamic> ||
            decoded['type'] != 'domino_host' ||
            decoded['protocolVersion'] != 1) {
          return;
        }
        final host = DiscoveredHost(
          address: datagram.address.address,
          port: decoded['port'] as int,
          roomId: decoded['roomId'] as String,
          roomName: decoded['roomName'] as String,
          protocolVersion: decoded['protocolVersion'] as int,
        );
        found['${host.address}:${host.port}:${host.roomId}'] = host;
      } on FormatException {
        // Ignore malformed discovery packets from unrelated local devices.
      } on TypeError {
        // Ignore packets that do not match this protocol version's schema.
      }
    });

    socket.broadcastEnabled = true;
    socket.send(
      utf8.encode(discoveryRequest),
      InternetAddress('255.255.255.255'),
      discoveryPort,
    );

    await Future<void>.delayed(timeout);
    await subscription.cancel();
    socket.close();
    return List<DiscoveredHost>.unmodifiable(found.values);
  }
}
