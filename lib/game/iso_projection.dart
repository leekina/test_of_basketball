import 'package:flame/components.dart';

import 'court_spec.dart';

/// 바닥 좌표(연속) → 아이소메트릭 화면 좌표 투영.
///
/// 기저 벡터를 [IsometricTileMapComponent]의 블록 중심 좌표에서 직접
/// 추출하므로 타일 크기가 바뀌어도 항상 타일맵과 정렬된다.
class IsoProjection {
  IsoProjection(IsometricTileMapComponent map)
      : _origin = map.getBlockCenterPosition(Block(0, 0)),
        _ex = map.getBlockCenterPosition(Block(1, 0)) -
            map.getBlockCenterPosition(Block(0, 0)),
        _ey = map.getBlockCenterPosition(Block(0, 1)) -
            map.getBlockCenterPosition(Block(0, 0));

  final Vector2 _origin;
  final Vector2 _ex;
  final Vector2 _ey;

  /// 높이(z) 1m 당 화면 y 오프셋(px). 픽셀 게임 감성으로 약간 과장.
  static const double heightScale = 28;

  /// 맵 타일 연속 좌표 → 맵 로컬 좌표
  Vector2 tileToLocal(double tx, double ty) =>
      _origin + _ex * tx + _ey * ty;

  /// 코트 바닥 좌표(미터, 코트 좌상단 코너 원점) → 맵 로컬 좌표
  Vector2 courtToLocal(double x, double y) => tileToLocal(
        CourtSpec.courtOrigin.x + x,
        CourtSpec.courtOrigin.y + y,
      );

  /// 깊이 정렬 키 (바닥 기준 x+y, Heeve 패턴)
  int depthOf(double courtX, double courtY) =>
      (((CourtSpec.courtOrigin.x + courtX) +
                  (CourtSpec.courtOrigin.y + courtY)) *
              100)
          .round();
}
