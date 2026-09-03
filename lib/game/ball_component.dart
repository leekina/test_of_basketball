import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/sprite.dart';

import 'iso_projection.dart';

/// 농구공 — 9프레임 회전 픽셀아트 + 바닥 그림자 + z(높이) 투영.
/// position은 바닥 접지점, [z]는 미터 단위 높이.
class BallComponent extends PositionComponent with HasGameReference {
  /// 공 높이 (미터) — MatchLayer가 매 프레임 갱신
  double z = 0;

  /// 회전 애니메이션 재생 여부와 속도 배율 (드리블은 비행의 절반 속도)
  bool spinning = false;
  double spinSpeed = 1.0;

  static const double _renderSize = 18;

  late final SpriteAnimationTicker _ticker;

  static final Paint _shadowPaint = Paint()..color = const Color(0x55000000);

  @override
  Future<void> onLoad() async {
    final sprites = <Sprite>[];
    for (var i = 1; i <= 9; i++) {
      sprites.add(Sprite(await game.images.load('balls/ball_${i}_32_x4.png')));
    }
    final animation = SpriteAnimation.spriteList(sprites, stepTime: 0.06);
    _ticker = animation.createTicker();
  }

  @override
  void update(double dt) {
    if (spinning) {
      _ticker.update(dt * spinSpeed);
    }
  }

  @override
  void render(Canvas canvas) {
    // 그림자: 높이 올라갈수록 작고 옅게
    final shrink = (1 - z / 10).clamp(0.4, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 14 * shrink,
        height: 6 * shrink,
      ),
      _shadowPaint,
    );
    final screenY = -z * IsoProjection.heightScale - _renderSize / 2 - 2;
    _ticker.getSprite().render(
          canvas,
          position: Vector2(0, screenY),
          size: Vector2.all(_renderSize),
          anchor: Anchor.center,
        );
  }
}
