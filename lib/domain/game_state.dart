import 'domino_tile.dart';

enum RoundEndReason { playerEmptiedHand, blocked }

class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.name,
    required this.seat,
  });

  final String id;
  final String name;
  final int seat;

  /// Seats 0 and 2 form team 0; seats 1 and 3 form team 1.
  int get team => seat.isEven ? 0 : 1;
}

class RoundResult {
  const RoundResult({
    required this.reason,
    required this.winningTeam,
    required this.pointsAwarded,
    required this.teamRemainingPips,
  });

  final RoundEndReason reason;
  final int? winningTeam;
  final int pointsAwarded;
  final List<int> teamRemainingPips;
}

class DominoGameState {
  DominoGameState({
    required this.players,
    required this.hands,
    required this.startingTile,
    required this.currentSeat,
    required List<int> teamScores,
  }) : teamScores = List<int>.of(teamScores);

  final List<GamePlayer> players;
  final List<List<DominoTile>> hands;
  final DominoTile startingTile;
  final List<PlacedTile> board = <PlacedTile>[];
  final List<int> teamScores;
  int currentSeat;
  int consecutivePasses = 0;
  bool isFinished = false;
  RoundResult? result;

  int get leftEnd => board.first.leftPip;
  int get rightEnd => board.last.rightPip;

  List<DominoTile> handForSeat(int seat) => List.unmodifiable(hands[seat]);

  int remainingPipsForTeam(int team) {
    var total = 0;
    for (final player in players.where((player) => player.team == team)) {
      total += hands[player.seat].fold<int>(0, (sum, tile) => sum + tile.points);
    }
    return total;
  }
}
