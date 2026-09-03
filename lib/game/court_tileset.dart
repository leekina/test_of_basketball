import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/painting.dart';

/// 플레이스홀더 타일셋을 런타임에 생성한다.
/// 진짜 픽셀아트 에셋이 생기면 이 파일만 이미지 로드로 교체하면 된다.
///
/// Flame의 IsometricTileMapComponent 규약: 소스 타일은 정사각형이고
/// 그 위쪽 절반이 바닥 다이아몬드 표면이다 (아래쪽은 블록 측면/투명).
/// 이 규약을 지켜야 getBlock(탭 판정)과 렌더 위치가 일치한다.
class CourtTileset {
  /// 정사각 타일 한 변 (px)
  static const double tileSide = 64;

  /// 타일 스프라이트 크기 (64x64)
  static final Vector2 srcTileSize = Vector2.all(tileSide);

  /// 바닥 다이아몬드 크기 (64x32) — 하이라이트 등 표면 오버레이용
  static final Vector2 diamondSize = Vector2(tileSide, tileSide / 2);

  static const _floorFill = Color(0xFF4A5D6B);
  static const _floorEdge = Color(0xFF3D4E5A);
  static const _courtFill = Color(0xFFD9A05B);
  static const _courtAltFill = Color(0xFFD1974F);
  static const _courtEdge = Color(0xFFC08A45);

  /// [tileId 0: 바깥 바닥, 1: 코트 마루, 2: 코트 마루 변형] 순서의 시트 생성
  static Future<SpriteSheet> generate() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    _drawDiamond(canvas, 0, _floorFill, _floorEdge);
    _drawDiamond(canvas, 1, _courtFill, _courtEdge);
    _drawDiamond(canvas, 2, _courtAltFill, _courtEdge);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (tileSide * 3).toInt(),
      tileSide.toInt(),
    );
    return SpriteSheet(image: image, srcSize: srcTileSize);
  }

  static void _drawDiamond(
    Canvas canvas,
    int index,
    Color fill,
    Color edge,
  ) {
    final left = index * tileSide;
    final h = tileSide / 2; // 다이아몬드는 타일 위쪽 절반
    final path = Path()
      ..moveTo(left + tileSide / 2, 0)
      ..lineTo(left + tileSide, h / 2)
      ..lineTo(left + tileSide / 2, h)
      ..lineTo(left, h / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
}
