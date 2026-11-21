import 'package:flutter_test/flutter_test.dart';
import 'package:domino_lan/domain/domino_tile.dart';

void main() {
  group('DominoTile', () {
    test('normalizes pip order so identity is stable', () {
      expect(DominoTile(2, 5), equals(DominoTile(5, 2)));
      expect(DominoTile(2, 5).hashCode, equals(DominoTile(5, 2).hashCode));
    });

    test('rejects pips outside the Double-Six range', () {
      expect(() => DominoTile(-1, 2), throwsArgumentError);
      expect(() => DominoTile(2, 7), throwsArgumentError);
    });

    test('returns the opposite pip when matching', () {
      expect(DominoTile(2, 5).otherEnd(2), 5);
      expect(DominoTile(2, 5).otherEnd(5), 2);
      expect(DominoTile(2, 5).otherEnd(4), isNull);
    });

    test('identifies doubles and calculates pip totals', () {
      expect(DominoTile(4, 4).isDouble, isTrue);
      expect(DominoTile(4, 4).points, 8);
      expect(DominoTile(1, 6).isDouble, isFalse);
      expect(DominoTile(1, 6).points, 7);
    });
  });
}
