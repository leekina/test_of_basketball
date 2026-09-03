import 'dart:math' as math;

import 'package:flame/extensions.dart';

/// FIBA 규격(미터) 기반 코트 치수. 1 타일 = 1m.
/// 순수 데이터 — Flame 렌더링에 의존하지 않는다.
class CourtSpec {
  static const double length = 28; // 코트 장축 (x)
  static const double width = 15; // 코트 단축 (y)
  static const int lengthTiles = 28;
  static const int widthTiles = 15;

  /// 코트 바깥 여백 타일 수 (관중석/바닥 자리)
  static const int margin = 6;

  static const int cols = lengthTiles + margin * 2;
  static const int rows = widthTiles + margin * 2;

  static const double centerY = width / 2;

  // 골대/페인트존 (양쪽 대칭 — 아래는 왼쪽 기준 x값)
  static const double basketX = 1.575; // 림 중심, 베이스라인에서
  static const double backboardX = 1.2;
  static const double backboardHalf = 0.9; // 백보드 폭 1.8m
  static const double rimRadius = 0.225;
  static const double keyLength = 5.8; // 자유투 라인까지
  static const double keyHalfWidth = 2.45; // 페인트존 폭 4.9m
  static const double ftCircleRadius = 1.8;
  static const double centerCircleRadius = 1.8;
  static const double threeRadius = 6.75;
  static const double threeSideOffset = 0.9; // 사이드라인에서 코너 3점 라인까지

  /// 코너 3점 직선이 아크와 만나는 x (베이스라인 기준)
  static double get threeCornerX {
    final dy = centerY - threeSideOffset;
    return basketX + math.sqrt(threeRadius * threeRadius - dy * dy);
  }

  /// 코트 좌상단 코너의 맵 타일 연속 좌표.
  /// 타일 (i, j)의 중심 = 연속 좌표 (i, j)이므로 코너는 -0.5 보정.
  static Vector2 get courtOrigin => Vector2(margin - 0.5, margin - 0.5);

  /// 타일 id
  static const int tileFloor = 0; // 코트 밖 바닥
  static const int tileCourt = 1; // 코트 마루
  static const int tileCourtAlt = 2; // 코트 마루 (체커 변형)

  /// 맵 행렬 생성: rows x cols, 코트 영역은 마루 체커
  static List<List<int>> buildMatrix() {
    return List.generate(rows, (j) {
      return List.generate(cols, (i) {
        final inCourt = i >= margin &&
            i < margin + lengthTiles &&
            j >= margin &&
            j < margin + widthTiles;
        if (!inCourt) {
          return tileFloor;
        }
        return (i + j).isEven ? tileCourt : tileCourtAlt;
      });
    });
  }
}
