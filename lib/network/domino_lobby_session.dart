import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/domino_lobby.dart';
import '../domain/domino_engine.dart';
import '../domain/domino_tile.dart';
import '../domain/game_state.dart';
import 'local_discovery_host.dart';
import 'local_web_socket.dart';

class DominoLobbyHost {
  DominoLobbyHost({required this.hostName});

  final String hostName;
  final String hostId = 'host';
  late final DominoLobby lobby;
  late final LocalWebSocketHost _server;
  LocalDiscoveryHost? _discovery;
  final Map<WebSocket, String> _connectionPlayers = <WebSocket, String>{};
  int _nextPlayerNumber = 1;
  bool _started = false;
  DominoGameState? _gameState;

  DominoGameState? get gameState => _gameState;
  List<DominoTile> get hostHand => _gameState?.handForSeat(0) ?? const <DominoTile>[];

  void Function()? onChanged;
  void Function(String message)? onError;
  void Function(List<LobbyPlayer> players)? onGameStarted;
  void Function(Map<String, Object?> snapshot, List<DominoTile> hand)? onGameState;

  int get connectedPlayers => _connectionPlayers.length;
  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) return;
    lobby = DominoLobby.create(hostId: hostId, hostName: hostName);
    _server = LocalWebSocketHost(port: 40405, maxClients: 3);
    _server.onMessage = _handleMessage;
    _server.onClientDisconnected = _handleDisconnect;
    await _server.start();
    try {
      _discovery = LocalDiscoveryHost(
        roomId: lobby.roomCode,
        roomName: 'غرفة ${lobby.roomCode} • ${lobby.players.first.name}',
      );
      await _discovery!.start();
    } catch (_) {
      await _server.stop();
      rethrow;
    }
    _started = true;
    onChanged?.call();
  }

  void setHostReady(bool ready) {
    if (!_started || _started == lobby.isGameStarted) return;
    lobby.setReady(playerId: hostId, ready: ready);
    _publish();
  }

  void startGame() {
    if (!_started || !lobby.canStart) {
      throw StateError('لا يمكن بدء المباراة قبل استعداد اللاعبين الأربعة.');
    }
    final players = lobby.startGame();
    final gamePlayers = players
        .map((player) => GamePlayer(
              id: player.id,
              name: player.name,
              seat: player.seat,
            ))
        .toList(growable: false);
    _gameState = DominoEngine.startRound(
      players: gamePlayers,
      teamScores: const <int>[0, 0],
    );
    for (final player in players.where((player) => !player.isHost)) {
      final socket = _connectionPlayers.entries
          .where((entry) => entry.value == player.id)
          .map((entry) => entry.key)
          .firstOrNull;
      if (socket != null) {
        _server.sendTo(socket, <String, Object?>{
          'v': 1,
          'type': 'game_started',
          'seat': player.seat,
          'hand': _tileJson(_gameState!.handForSeat(player.seat)),
        });
      }
    }
    _publishGame();
    onGameStarted?.call(players);
    onChanged?.call();
  }

  void _handleMessage(WebSocket socket, Object rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage.toString());
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
        _sendError(socket, 'صيغة الرسالة غير مدعومة.');
        return;
      }
      switch (decoded['type']) {
        case 'join':
          _handleJoin(socket, decoded);
          return;
        case 'play_tile':
          _handlePlayTile(socket, decoded);
          return;
        case 'pass':
          _handlePass(socket);
          return;
        case 'ready':
          final playerId = _connectionPlayers[socket];
          if (playerId == null) {
            _sendError(socket, 'انضم إلى الغرفة أولاً.');
            return;
          }
          final ready = decoded['ready'];
          if (ready is! bool ||
              !lobby.setReady(playerId: playerId, ready: ready)) {
            _sendError(socket, 'تعذر تحديث حالة الاستعداد.');
            return;
          }
          _publish();
          return;
        default:
          _sendError(socket, 'طلب غير معروف.');
          return;
      }
    } on FormatException {
      _sendError(socket, 'تعذر قراءة الرسالة.');
    } on Object catch (error) {
      onError?.call('خطأ في معالجة طلب لاعب: $error');
      _sendError(socket, 'تعذر تنفيذ الطلب.');
    }
  }

  void _handleJoin(WebSocket socket, Map<String, dynamic> message) {
    if (_connectionPlayers.containsKey(socket)) {
      _sendError(socket, 'هذا الجهاز انضم بالفعل.');
      return;
    }
    if (message['roomCode'] != lobby.roomCode) {
      _sendError(socket, 'رمز الغرفة غير صحيح.');
      return;
    }
    final name = message['name'];
    if (name is! String) {
      _sendError(socket, 'أدخل اسماً صحيحاً.');
      return;
    }

    final playerId = 'guest-${_nextPlayerNumber++}';
    final result = lobby.join(playerId: playerId, playerName: name);
    if (!result.isSuccess) {
      final messageText = switch (result.failure) {
        LobbyJoinFailure.roomFull => 'الغرفة مكتملة.',
        LobbyJoinFailure.duplicateName => 'هذا الاسم مستخدم في الغرفة.',
        LobbyJoinFailure.gameAlreadyStarted => 'المباراة بدأت بالفعل.',
        LobbyJoinFailure.invalidName => 'الاسم غير صالح.',
        null => 'تعذر الانضمام.',
      };
      _sendError(socket, messageText);
      return;
    }

    // The host assigns the seat and player identity; client-supplied IDs
    // are intentionally ignored.
    _connectionPlayers[socket] = playerId;
    _server.sendTo(socket, <String, Object?>{
      'v': 1,
      'type': 'joined',
      'playerId': playerId,
      'seat': result.player!.seat,
    });
    _publish();
  }


  void _handlePlayTile(WebSocket socket, Map<String, dynamic> message) {
    final playerId = _connectionPlayers[socket];
    final state = _gameState;
    if (playerId == null || state == null || !lobby.isGameStarted) {
      _sendError(socket, 'لا توجد مباراة نشطة لهذا اللاعب.');
      return;
    }
    final player = lobby.players.where((item) => item.id == playerId).firstOrNull;
    final first = message['first'];
    final second = message['second'];
    final sideValue = message['side'];
    if (player == null || first is! int || second is! int) {
      _sendError(socket, 'بيانات الحجر غير صالحة.');
      return;
    }
    final side = sideValue == 'left' ? BoardSide.left : BoardSide.right;
    try {
      DominoEngine.playTile(
        state: state,
        playerSeat: player.seat,
        tile: DominoTile(first, second),
        side: side,
      );
      _publishGame();
    } on Object catch (error) {
      _sendError(socket, error.toString());
    }
  }

  void _handlePass(WebSocket socket) {
    final playerId = _connectionPlayers[socket];
    final state = _gameState;
    if (playerId == null || state == null) {
      _sendError(socket, 'لا توجد مباراة نشطة لهذا اللاعب.');
      return;
    }
    final player = lobby.players.where((item) => item.id == playerId).firstOrNull;
    if (player == null) return;
    try {
      DominoEngine.passTurn(state: state, playerSeat: player.seat);
      _publishGame();
    } on Object catch (error) {
      _sendError(socket, error.toString());
    }
  }

  void playHostTile(DominoTile tile, BoardSide side) {
    final state = _gameState;
    if (state == null) throw StateError('لم تبدأ المباراة.');
    DominoEngine.playTile(state: state, playerSeat: 0, tile: tile, side: side);
    _publishGame();
  }

  void passHostTurn() {
    final state = _gameState;
    if (state == null) throw StateError('لم تبدأ المباراة.');
    DominoEngine.passTurn(state: state, playerSeat: 0);
    _publishGame();
  }

  void _publishGame() {
    final state = _gameState;
    if (state == null) return;
    final snapshot = <String, Object?>{
      'currentSeat': state.currentSeat,
      'board': state.board
          .map((placed) => <String, Object?>{
                'first': placed.tile.first,
                'second': placed.tile.second,
                'leftPip': placed.leftPip,
                'rightPip': placed.rightPip,
              })
          .toList(growable: false),
      'teamScores': List<int>.of(state.teamScores),
      'isFinished': state.isFinished,
      'result': state.result == null
          ? null
          : <String, Object?>{
              'winningTeam': state.result!.winningTeam,
              'pointsAwarded': state.result!.pointsAwarded,
              'reason': state.result!.reason.name,
            },
    };
    _server.broadcast(<String, Object?>{
      'v': 1,
      'type': 'game_state',
      'state': snapshot,
    });
    for (final entry in _connectionPlayers.entries) {
      final player = lobby.players.where((item) => item.id == entry.value).firstOrNull;
      if (player != null) {
        _server.sendTo(entry.key, <String, Object?>{
          'v': 1,
          'type': 'your_hand',
          'hand': _tileJson(state.handForSeat(player.seat)),
        });
      }
    }
    onGameState?.call(snapshot, state.handForSeat(0));
  }

  List<Map<String, int>> _tileJson(List<DominoTile> tiles) => tiles
      .map((tile) => <String, int>{'first': tile.first, 'second': tile.second})
      .toList(growable: false);

  void _handleDisconnect(WebSocket socket) {
    final playerId = _connectionPlayers.remove(socket);
    if (playerId == null || !_started || lobby.isGameStarted) return;
    lobby.removePlayer(playerId);
    _publish();
  }

  void _publish() {
    _server.broadcast(<String, Object?>{
      'v': 1,
      'type': 'lobby_snapshot',
      'lobby': lobby.toPublicJson(),
    });
    onChanged?.call();
  }

  void _sendError(WebSocket socket, String message) {
    _server.sendTo(socket, <String, Object?>{
      'v': 1,
      'type': 'error',
      'message': message,
    });
  }

  Map<String, Object?> _playerJson(LobbyPlayer player) => <String, Object?>{
        'id': player.id,
        'name': player.name,
        'seat': player.seat,
        'team': player.team,
        'isHost': player.isHost,
      };

  Future<void> stop() async {
    await _discovery?.stop();
    _discovery = null;
    if (_started) await _server.stop();
    _connectionPlayers.clear();
    _started = false;
  }
}

class DominoLobbyClient {
  DominoLobbyClient();

  LocalWebSocketClient? _client;
  StreamSubscription<dynamic>? _subscription;

  void Function(Map<String, dynamic> lobby)? onLobby;
  void Function(String playerId, int seat)? onJoined;
  void Function(String message)? onError;
  void Function(List<dynamic> players)? onGameStarted;
  void Function(Map<String, dynamic> state)? onGameState;
  void Function(List<DominoTile> hand)? onHand;

  List<DominoTile> hand = const <DominoTile>[];
  void Function()? onDisconnected;

  bool get isConnected => _client?.isConnected == true;

  Future<void> connect({
    required String address,
    required String roomCode,
    required String playerName,
  }) async {
    final client = await LocalWebSocketClient.connect(host: address);
    _client = client;
    _subscription = client.messages.listen(
      _handleMessage,
      onDone: () => onDisconnected?.call(),
      onError: (Object error) => onError?.call('انقطع الاتصال: $error'),
    );
    client.send(<String, Object?>{
      'v': 1,
      'type': 'join',
      'roomCode': roomCode.trim(),
      'name': playerName.trim(),
    });
  }

  void setReady(bool ready) {
    _client?.send(<String, Object?>{
      'v': 1,
      'type': 'ready',
      'ready': ready,
    });
  }

  void _handleMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) return;
      switch (decoded['type']) {
        case 'joined':
          if (decoded['playerId'] is String && decoded['seat'] is int) {
            onJoined?.call(decoded['playerId'] as String, decoded['seat'] as int);
          }
          return;
        case 'lobby_snapshot':
          final lobby = decoded['lobby'];
          if (lobby is Map<String, dynamic>) onLobby?.call(lobby);
          return;
        case 'error':
          if (decoded['message'] is String) {
            onError?.call(decoded['message'] as String);
          }
          return;
        case 'game_started':
          final rawHand = decoded['hand'];
          if (rawHand is List) {
            hand = _parseHand(rawHand);
            onHand?.call(hand);
          }
          final players = decoded['players'];
          if (players is List) onGameStarted?.call(players);
          return;
        case 'game_state':
          final state = decoded['state'];
          if (state is Map<String, dynamic>) onGameState?.call(state);
          return;
        case 'your_hand':
          final rawHand = decoded['hand'];
          if (rawHand is List) {
            hand = _parseHand(rawHand);
            onHand?.call(hand);
          }
          return;
      }
    } on FormatException {
      onError?.call('وصلت رسالة غير صالحة من المضيف.');
    }
  }

  List<DominoTile> _parseHand(List<dynamic> values) => values
      .whereType<Map<String, dynamic>>()
      .where((item) => item['first'] is int && item['second'] is int)
      .map((item) => DominoTile(item['first'] as int, item['second'] as int))
      .toList(growable: false);

  void playTile(DominoTile tile, BoardSide side) {
    _client?.send(<String, Object?>{
      'v': 1,
      'type': 'play_tile',
      'first': tile.first,
      'second': tile.second,
      'side': side.name,
    });
  }

  void passTurn() {
    _client?.send(<String, Object?>{'v': 1, 'type': 'pass'});
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _client?.close();
    _client = null;
  }
}
