import 'package:flutter_test/flutter_test.dart';
import 'package:test_of_basketball/game/court_spec.dart';

void main() {
  group('CourtSpec.buildMatrix', () {
    final matrix = CourtSpec.buildMatrix();

    test('행렬 크기는 rows x cols', () {
      expect(matrix.length, CourtSpec.rows);
      for (final row in matrix) {
        expect(row.length, CourtSpec.cols);
      }
    });

    test('코트 영역은 마루 타일, 바깥은 바닥 타일', () {
      const m = CourtSpec.margin;
      expect(matrix[m][m], isNot(CourtSpec.tileFloor)); // 코트 코너
      expect(
        matrix[m + CourtSpec.widthTiles - 1][m + CourtSpec.lengthTiles - 1],
        isNot(CourtSpec.tileFloor),
      );
      expect(matrix[m - 1][m], CourtSpec.tileFloor); // 코트 바로 밖
      expect(matrix[0][0], CourtSpec.tileFloor);
    });

    test('코트 마루는 체커 패턴', () {
      const m = CourtSpec.margin;
      expect(matrix[m][m], isNot(matrix[m][m + 1]));
    });
  });

  test('3점 코너 교차점은 코트 안쪽', () {
    expect(CourtSpec.threeCornerX, greaterThan(CourtSpec.basketX));
    expect(CourtSpec.threeCornerX, lessThan(CourtSpec.length / 2));
  });
}
