import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:domino_lan/domain/domino_deck.dart';
import 'package:domino_lan/domain/domino_engine.dart';
import 'package:domino_lan/domain/domino_tile.dart';
import 'package:domino_lan/domain/game_state.dart';

List<GamePlayer> fourPlayers() => const <GamePlayer>[
      GamePlayer(id: 'p1', name: 'الأول', seat: 0),
      GamePlayer(id: 'p2', name: 'الثاني', seat: 1),
      GamePlayer(id: 'p3', name: 'الثالث', seat: 2),
      GamePlayer(id: 'p4', name: 'الرابع', seat: 3),
    ];

DominoGameState testState({
  required List<List<DominoTile>> hands,
  int currentSeat = 0,
}) {
  final state = DominoGameState(
    players: fourPlayers(),
    hands: hands,
    startingTile: DominoTile(6, 6),
    currentSeat: currentSeat,
    teamScores: const <int>[0, 0],
  );
  state.board.add(PlacedTile.start(DominoTile(6, 6)));
  return state;
}

void main() {
  group('Domino deck', () {
    test('contains exactly 28 unique Double-Six tiles', () {
      final deck = DominoDeck.doubleSix();
      expect(deck, hasLength(28));
      expect(deck.toSet(), hasLength(28));
      expect(deck, contains(DominoTile(0, 0)));
      expect(deck, contains(DominoTile(6, 6)));
    });

    test('deals seven tiles to each of four players', () {
      final state = DominoEngine.startRound(
        players: fourPlayers(),
        random: Random(42),
      );
      expect(state.hands, hasLength(4));
      expect(state.hands.map((hand) => hand.length), everyElement(7));
      expect(state.hands.expand((hand) => hand).toSet(), hasLength(28));
      expect(state.hands.expand((hand) => hand).where((tile) => tile == DominoTile(6, 6)), hasLength(1));
      expect(state.hands[state.currentSeat], contains(DominoTile(6, 6)));
    });
  });

  group('Domino engine', () {
    test('teams are assigned to opposite seats', () {
      expect(fourPlayers().map((player) => player.team), <int>[0, 1, 0, 1]);
    });

    test('requires the highest double as the opening tile', () {
      final state = DominoEngine.startRound(players: fourPlayers(), random: Random(4));
      final seat = state.currentSeat;
      expect(
        () => DominoEngine.playTile(
          state: state,
          playerSeat: seat,
          tile: state.hands[seat].firstWhere((tile) => tile != DominoTile(6, 6)),
        ),
        throwsStateError,
      );
      DominoEngine.playTile(
        state: state,
        playerSeat: seat,
        tile: DominoTile(6, 6),
      );
      expect(state.board, hasLength(1));
      expect(state.hands[seat], isNot(contains(DominoTile(6, 6))));
    });

    test('orients a right-side tile against the matching end', () {
      final state = testState(
        hands: <List<DominoTile>>[
          <DominoTile>[DominoTile(3, 6)],
          <DominoTile>[DominoTile(0, 1)],
          <DominoTile>[DominoTile(2, 2)],
          <DominoTile>[DominoTile(4, 4)],
        ],
      );
      DominoEngine.playTile(
        state: state,
        playerSeat: 0,
        tile: DominoTile(3, 6),
      );
      expect(state.rightEnd, 3);
      expect(state.board.last.leftPip, 6);
    });

    test('does not allow passing when a legal tile exists', () {
      final state = testState(
        hands: <List<DominoTile>>[
          <DominoTile>[DominoTile(1, 6)],
          <DominoTile>[DominoTile(0, 1)],
          <DominoTile>[DominoTile(2, 2)],
          <DominoTile>[DominoTile(4, 4)],
        ],
      );
      expect(
        () => DominoEngine.passTurn(state: state, playerSeat: 0),
        throwsStateError,
      );
    });

    test('ends a blocked round after four consecutive legal passes', () {
      final state = testState(
        hands: <List<DominoTile>>[
          <DominoTile>[DominoTile(0, 0)],
          <DominoTile>[DominoTile(1, 1)],
          <DominoTile>[DominoTile(2, 2)],
          <DominoTile>[DominoTile(3, 3)],
        ],
      );
      for (var seat = 0; seat < 4; seat++) {
        DominoEngine.passTurn(state: state, playerSeat: seat);
      }
      expect(state.isFinished, isTrue);
      expect(state.result?.reason, RoundEndReason.blocked);
      expect(state.result?.winningTeam, 0);
      expect(state.result?.pointsAwarded, 8);
      expect(state.teamScores, <int>[8, 0]);
    });
  });
}
