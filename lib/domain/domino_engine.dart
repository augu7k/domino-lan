import 'dart:math';

import 'domino_deck.dart';
import 'domino_tile.dart';
import 'game_state.dart';

class DominoEngine {
  DominoEngine._();

  static DominoGameState startRound({
    required List<GamePlayer> players,
    Random? random,
    List<int> teamScores = const <int>[0, 0],
  }) {
    _validatePlayers(players);
    if (teamScores.length != 2 || teamScores.any((score) => score < 0)) {
      throw ArgumentError('Exactly two non-negative team scores are required.');
    }

    final deck = DominoDeck.shuffled(random: random);
    final hands = List<List<DominoTile>>.generate(4, (_) => <DominoTile>[]);
    for (var index = 0; index < deck.length; index++) {
      hands[index % 4].add(deck[index]);
    }

    final openingTile = DominoTile(6, 6);
    final startingSeat = hands.indexWhere((hand) => hand.contains(openingTile));
    if (startingSeat < 0) {
      throw StateError('The 6-6 tile was not dealt.');
    }

    final playersBySeat = List<GamePlayer>.of(players)
      ..sort((first, second) => first.seat.compareTo(second.seat));

    return DominoGameState(
      players: List<GamePlayer>.unmodifiable(playersBySeat),
      hands: hands,
      startingTile: openingTile,
      currentSeat: startingSeat,
      teamScores: teamScores,
    );
  }

  static List<BoardSide> legalSides(DominoGameState state, DominoTile tile) {
    if (state.isFinished) return const <BoardSide>[];
    if (state.board.isEmpty) {
      return tile == state.startingTile
          ? const <BoardSide>[BoardSide.right]
          : const <BoardSide>[];
    }

    final sides = <BoardSide>[];
    if (tile.matches(state.leftEnd)) sides.add(BoardSide.left);
    if (tile.matches(state.rightEnd)) sides.add(BoardSide.right);
    return sides;
  }

  static bool hasLegalMove(DominoGameState state, int seat) {
    if (seat < 0 || seat > 3 || state.isFinished) return false;
    return state.hands[seat].any((tile) => legalSides(state, tile).isNotEmpty);
  }

  static void playTile({
    required DominoGameState state,
    required int playerSeat,
    required DominoTile tile,
    BoardSide side = BoardSide.right,
  }) {
    _ensureActiveTurn(state, playerSeat);
    final hand = state.hands[playerSeat];
    final tileIndex = hand.indexOf(tile);
    if (tileIndex < 0) throw StateError('This tile is not in the player hand.');

    if (state.board.isEmpty) {
      if (tile != state.startingTile) {
        throw StateError('The opening move must be the 6-6 tile.');
      }
      if (side != BoardSide.right) {
        throw StateError('The opening tile is placed at the start of the chain.');
      }
      state.board.add(PlacedTile.start(tile));
    } else if (side == BoardSide.left) {
      if (!tile.matches(state.leftEnd)) {
        throw StateError('The tile does not match the left end.');
      }
      state.board.insert(0, PlacedTile.attachLeft(tile, state.leftEnd));
    } else {
      if (!tile.matches(state.rightEnd)) {
        throw StateError('The tile does not match the right end.');
      }
      state.board.add(PlacedTile.attachRight(tile, state.rightEnd));
    }

    hand.removeAt(tileIndex);
    state.consecutivePasses = 0;

    if (hand.isEmpty) {
      _finishWithEmptyHand(state, state.players[playerSeat].team);
      return;
    }
    state.currentSeat = (state.currentSeat + 1) % 4;
  }

  static void passTurn({
    required DominoGameState state,
    required int playerSeat,
  }) {
    _ensureActiveTurn(state, playerSeat);
    if (hasLegalMove(state, playerSeat)) {
      throw StateError('Passing is not allowed while a legal move exists.');
    }

    state.consecutivePasses++;
    if (state.consecutivePasses >= 4) {
      _finishBlocked(state);
      return;
    }
    state.currentSeat = (state.currentSeat + 1) % 4;
  }

  static void _finishWithEmptyHand(DominoGameState state, int winningTeam) {
    final opposingTeam = 1 - winningTeam;
    final points = state.remainingPipsForTeam(opposingTeam);
    state.teamScores[winningTeam] += points;
    state.result = RoundResult(
      reason: RoundEndReason.playerEmptiedHand,
      winningTeam: winningTeam,
      pointsAwarded: points,
      teamRemainingPips: <int>[
        state.remainingPipsForTeam(0),
        state.remainingPipsForTeam(1),
      ],
    );
    state.isFinished = true;
  }

  static void _finishBlocked(DominoGameState state) {
    final remaining = <int>[
      state.remainingPipsForTeam(0),
      state.remainingPipsForTeam(1),
    ];
    if (remaining[0] == remaining[1]) {
      state.result = RoundResult(
        reason: RoundEndReason.blocked,
        winningTeam: null,
        pointsAwarded: 0,
        teamRemainingPips: remaining,
      );
      state.isFinished = true;
      return;
    }

    final winningTeam = remaining[0] < remaining[1] ? 0 : 1;
    final points = remaining[1 - winningTeam];
    state.teamScores[winningTeam] += points;
    state.result = RoundResult(
      reason: RoundEndReason.blocked,
      winningTeam: winningTeam,
      pointsAwarded: points,
      teamRemainingPips: remaining,
    );
    state.isFinished = true;
  }

  static void _ensureActiveTurn(DominoGameState state, int playerSeat) {
    if (state.isFinished) throw StateError('The round is already finished.');
    if (playerSeat != state.currentSeat) throw StateError('It is not this player turn.');
    if (playerSeat < 0 || playerSeat > 3) throw ArgumentError.value(playerSeat, 'playerSeat');
  }

  static void _validatePlayers(List<GamePlayer> players) {
    if (players.length != 4) throw ArgumentError('Exactly four players are required.');
    final seats = players.map((player) => player.seat).toSet();
    final ids = players.map((player) => player.id).toSet();
    if (seats.length != 4 || !seats.containsAll(<int>{0, 1, 2, 3})) {
      throw ArgumentError('Player seats must be unique and range from 0 to 3.');
    }
    if (ids.length != 4 || players.any((player) => player.id.trim().isEmpty)) {
      throw ArgumentError('Player IDs must be unique and non-empty.');
    }
  }
}
