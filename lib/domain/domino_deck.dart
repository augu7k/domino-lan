import 'dart:math';

import 'domino_tile.dart';

class DominoDeck {
  DominoDeck._();

  static List<DominoTile> doubleSix() {
    final tiles = <DominoTile>[];
    for (var first = 0; first <= 6; first++) {
      for (var second = first; second <= 6; second++) {
        tiles.add(DominoTile(first, second));
      }
    }
    return tiles;
  }

  static List<DominoTile> shuffled({Random? random}) {
    final tiles = doubleSix();
    tiles.shuffle(random ?? Random.secure());
    return tiles;
  }
}
