import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_of_basketball/game/basketball_court_game.dart';

/// 렌더 골든 테스트 — 코트·선수·공이 실제로 그려지는지 픽셀로 검증한다.
/// 갱신: flutter test --update-goldens test/court_render_test.dart
void main() {
  testWidgets('아이소메트릭 코트+경기 렌더 골든', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 450));
    final game = BasketballCourtGame();

    // 공 스프라이트 등 실제 이미지 디코딩은 FakeAsync에서 완료되지 않으므로
    // runAsync 안에서 로드를 끝낸다.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(child: GameWidget(game: game)),
      );
      await tester.pump();
      // 모든 컴포넌트(공 애니메이션 로드 포함)가 마운트될 때까지 대기
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        game.update(0.016);
      }
      await tester.pump();
    });
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(GameWidget<BasketballCourtGame>),
      matchesGoldenFile('goldens/court_render.png'),
    );
  });
}
