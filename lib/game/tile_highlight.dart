import 'dart:ui';

import 'package:flame/components.dart';

/// 탭으로 선택된 타일 위에 다이아몬드 외곽선을 그린다.
class TileHighlightComponent extends PositionComponent {
  TileHighlightComponent({required Vector2 tileSize})
      : super(size: tileSize);

  final Paint _paint = Paint()
    ..color = const Color(0xFFFFE066)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  bool visible = false;

  @override
  void render(Canvas canvas) {
    if (!visible) {
      return;
    }
    final path = Path()
      ..moveTo(size.x / 2, 0)
      ..lineTo(size.x, size.y / 2)
      ..lineTo(size.x / 2, size.y)
      ..lineTo(0, size.y / 2)
      ..close();
    canvas.drawPath(path, _paint);
  }
}
