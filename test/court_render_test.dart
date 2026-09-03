import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_of_basketball/game/basketball_court_game.dart';

/// 렌더 골든 테스트 — 코트 타일맵·라인이 실제로 그려지는지 픽셀로 검증한다.
/// 갱신: flutter test --update-goldens test/court_render_test.dart
void main() {
  testWidgets('아이소메트릭 코트 렌더 골든', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 450));
    final game = BasketballCourtGame();
    await tester.pumpWidget(
      RepaintBoundary(child: GameWidget(game: game)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(GameWidget<BasketballCourtGame>),
      matchesGoldenFile('goldens/court_render.png'),
    );
  });
}
