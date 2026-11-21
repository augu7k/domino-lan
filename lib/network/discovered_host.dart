class DiscoveredHost {
  const DiscoveredHost({
    required this.address,
    required this.port,
    required this.roomId,
    required this.roomName,
    required this.protocolVersion,
  });

  final String address;
  final int port;
  final String roomId;
  final String roomName;
  final int protocolVersion;

  String get websocketUrl => 'ws://$address:$port/ws';
}
