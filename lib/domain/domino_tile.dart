enum BoardSide { left, right }

/// A canonical Double-Six domino tile. The lower pip is always stored first.
class DominoTile {
  DominoTile(int first, int second)
      : first = first <= second ? first : second,
        second = first <= second ? second : first {
    if (first < 0 || first > 6 || second < 0 || second > 6) {
      throw ArgumentError('Domino pips must be between 0 and 6.');
    }
  }

  final int first;
  final int second;

  int get points => first + second;
  bool get isDouble => first == second;

  bool matches(int pip) => first == pip || second == pip;

  /// Returns the pip that remains exposed after matching [pip].
  int? otherEnd(int pip) {
    if (first == pip) return second;
    if (second == pip) return first;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DominoTile && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => '$first|$second';
}

/// A tile as it is oriented on the board, from the left side to the right side.
class PlacedTile {
  const PlacedTile({
    required this.tile,
    required this.leftPip,
    required this.rightPip,
  });

  final DominoTile tile;
  final int leftPip;
  final int rightPip;

  factory PlacedTile.start(DominoTile tile) => PlacedTile(
        tile: tile,
        leftPip: tile.first,
        rightPip: tile.second,
      );

  factory PlacedTile.attachLeft(DominoTile tile, int matchingPip) {
    final exposed = tile.otherEnd(matchingPip);
    if (exposed == null) throw ArgumentError('Tile does not match the left end.');
    return PlacedTile(
      tile: tile,
      leftPip: exposed,
      rightPip: matchingPip,
    );
  }

  factory PlacedTile.attachRight(DominoTile tile, int matchingPip) {
    final exposed = tile.otherEnd(matchingPip);
    if (exposed == null) throw ArgumentError('Tile does not match the right end.');
    return PlacedTile(
      tile: tile,
      leftPip: matchingPip,
      rightPip: exposed,
    );
  }
}
