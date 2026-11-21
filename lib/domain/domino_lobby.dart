import 'dart:math';

class LobbyPlayer {
  const LobbyPlayer({
    required this.id,
    required this.name,
    required this.seat,
    required this.isHost,
    required this.isReady,
  });

  final String id;
  final String name;
  final int seat;
  final bool isHost;
  final bool isReady;

  int get team => seat.isEven ? 0 : 1;

  LobbyPlayer copyWith({bool? isReady}) => LobbyPlayer(
        id: id,
        name: name,
        seat: seat,
        isHost: isHost,
        isReady: isReady ?? this.isReady,
      );
}

enum LobbyJoinFailure { roomFull, duplicateName, gameAlreadyStarted, invalidName }

class LobbyJoinResult {
  const LobbyJoinResult.success(this.player)
      : failure = null;

  const LobbyJoinResult.failure(this.failure) : player = null;

  final LobbyPlayer? player;
  final LobbyJoinFailure? failure;

  bool get isSuccess => player != null;
}

/// Authoritative waiting-room state. The host owns this object and applies
/// every join/readiness request before broadcasting a new lobby snapshot.
class DominoLobby {
  DominoLobby._({
    required this.roomCode,
    required List<LobbyPlayer?> seats,
  }) : _seats = seats;

  factory DominoLobby.create({
    required String hostId,
    required String hostName,
    Random? random,
  }) {
    final normalizedName = hostName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(hostName, 'hostName', 'Name is required.');
    }

    final source = random ?? Random.secure();
    final code = (100000 + source.nextInt(900000)).toString();
    return DominoLobby._(
      roomCode: code,
      seats: <LobbyPlayer?>[
        LobbyPlayer(
          id: hostId,
          name: normalizedName,
          seat: 0,
          isHost: true,
          isReady: true,
        ),
        null,
        null,
        null,
      ],
    );
  }

  final String roomCode;
  final List<LobbyPlayer?> _seats;
  bool _gameStarted = false;

  List<LobbyPlayer> get players => List<LobbyPlayer>.unmodifiable(
        _seats.whereType<LobbyPlayer>(),
      );

  int get occupiedSeats => _seats.whereType<LobbyPlayer>().length;
  int get openSeats => 4 - occupiedSeats;
  bool get isFull => openSeats == 0;
  bool get isGameStarted => _gameStarted;
  bool get canStart =>
      isFull && !_gameStarted && _seats.every((player) => player?.isReady == true);

  LobbyJoinResult join({required String playerId, required String playerName}) {
    if (_gameStarted) {
      return const LobbyJoinResult.failure(LobbyJoinFailure.gameAlreadyStarted);
    }
    final normalizedName = playerName.trim();
    if (normalizedName.isEmpty || playerId.trim().isEmpty) {
      return const LobbyJoinResult.failure(LobbyJoinFailure.invalidName);
    }
    if (_seats.whereType<LobbyPlayer>().any(
          (player) => player.name.toLowerCase() == normalizedName.toLowerCase(),
        )) {
      return const LobbyJoinResult.failure(LobbyJoinFailure.duplicateName);
    }
    final seat = _seats.indexWhere((player) => player == null);
    if (seat < 0) {
      return const LobbyJoinResult.failure(LobbyJoinFailure.roomFull);
    }

    final player = LobbyPlayer(
      id: playerId,
      name: normalizedName,
      seat: seat,
      isHost: false,
      isReady: false,
    );
    _seats[seat] = player;
    return LobbyJoinResult.success(player);
  }

  bool setReady({required String playerId, required bool ready}) {
    if (_gameStarted) return false;
    final seat = _seats.indexWhere((player) => player?.id == playerId);
    if (seat < 0) return false;
    _seats[seat] = _seats[seat]!.copyWith(isReady: ready);
    return true;
  }

  bool removePlayer(String playerId) {
    if (_gameStarted) return false;
    final seat = _seats.indexWhere(
      (player) => player?.id == playerId && player?.isHost == false,
    );
    if (seat < 0) return false;
    _seats[seat] = null;
    return true;
  }

  List<LobbyPlayer> startGame() {
    if (!canStart) {
      throw StateError('All four players must join and be ready before starting.');
    }
    _gameStarted = true;
    return players;
  }

  Map<String, Object?> toPublicJson() => <String, Object?>{
        'roomCode': roomCode,
        'gameStarted': _gameStarted,
        'players': _seats
            .map((player) => player == null
                ? null
                : <String, Object?>{
                    'id': player.id,
                    'name': player.name,
                    'seat': player.seat,
                    'team': player.team,
                    'isHost': player.isHost,
                    'isReady': player.isReady,
                  })
            .toList(growable: false),
      };
}
