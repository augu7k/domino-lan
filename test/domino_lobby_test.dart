import 'dart:math';

import 'package:domino_lan/domain/domino_lobby.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DominoLobby', () {
    late DominoLobby lobby;

    setUp(() {
      lobby = DominoLobby.create(
        hostId: 'host',
        hostName: 'المضيف',
        random: Random(7),
      );
    });

    test('creates a six-digit room code and reserves the first seat for host', () {
      expect(lobby.roomCode, matches(RegExp(r'^\d{6}$')));
      expect(lobby.occupiedSeats, 1);
      expect(lobby.players.single.seat, 0);
      expect(lobby.players.single.isReady, isTrue);
    });

    test('assigns four seats and alternates two teams', () {
      final second = lobby.join(playerId: 'p2', playerName: 'لاعب 2');
      final third = lobby.join(playerId: 'p3', playerName: 'لاعب 3');
      final fourth = lobby.join(playerId: 'p4', playerName: 'لاعب 4');

      expect(second.player?.seat, 1);
      expect(third.player?.seat, 2);
      expect(fourth.player?.seat, 3);
      expect(lobby.players.map((player) => player.team), <int>[0, 1, 0, 1]);
      expect(lobby.isFull, isTrue);
      expect(lobby.canStart, isFalse);
    });

    test('rejects duplicate names without consuming a seat', () {
      final result = lobby.join(playerId: 'p2', playerName: '  المضيف  ');
      expect(result.failure, LobbyJoinFailure.duplicateName);
      expect(lobby.occupiedSeats, 1);
    });

    test('requires all four players to be ready before starting', () {
      for (var seat = 1; seat <= 3; seat++) {
        lobby.join(playerId: 'p$seat', playerName: 'لاعب $seat');
      }
      expect(() => lobby.startGame(), throwsStateError);

      for (var seat = 1; seat <= 3; seat++) {
        expect(lobby.setReady(playerId: 'p$seat', ready: true), isTrue);
      }
      expect(lobby.canStart, isTrue);
      expect(lobby.startGame(), hasLength(4));
      expect(lobby.isGameStarted, isTrue);
    });

    test('allows a disconnected player seat to be reused before game starts', () {
      lobby.join(playerId: 'p2', playerName: 'لاعب 2');
      expect(lobby.removePlayer('p2'), isTrue);
      final replacement = lobby.join(
        playerId: 'p3',
        playerName: 'لاعب 3',
      );
      expect(replacement.player?.seat, 1);
    });

    test('does not allow the host to leave through player removal', () {
      expect(lobby.removePlayer('host'), isFalse);
      expect(lobby.occupiedSeats, 1);
    });
  });
}
