import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_of_basketball/game/basketball_court_game.dart';
import 'package:test_of_basketball/game/court_spec.dart';
import 'package:test_of_basketball/game/court_tileset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getBlock(getBlockCenterPosition(b)) 라운드트립', () async {
    final tileset = await CourtTileset.generate();
    final map = IsometricTileMapComponent(
      tileset,
      CourtSpec.buildMatrix(),
      destTileSize: CourtTileset.srcTileSize,
    );

    for (final block in [
      Block(0, 0),
      Block(CourtSpec.margin, CourtSpec.margin),
      Block(CourtSpec.cols - 1, CourtSpec.rows - 1),
      Block(CourtSpec.cols ~/ 2, CourtSpec.rows ~/ 2),
    ]) {
      final center = map.getBlockCenterPosition(block);
      final result = map.getBlock(center);
      expect(result.x, block.x, reason: 'block $block x');
      expect(result.y, block.y, reason: 'block $block y');
    }
  });

  testWidgets('게임이 로드되고 코트맵·라인이 붙는다', (tester) async {
    final game = BasketballCourtGame();
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();

    expect(game.courtMap.isMounted, isTrue);
    expect(game.courtMap.children.length, greaterThanOrEqualTo(2));
    // 카메라는 맵 중앙에서 시작
    expect(game.camera.viewfinder.position, game.courtMap.size / 2);
  });
}
