import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show FontWeight, TextStyle;

import '../sim/match_sim.dart';

/// 플레이스홀더 선수 — 팀 컬러 캡슐 + 그림자 + 등번호.
/// position은 바닥 접지점(발 위치), 스프라이트 교체를 대비해 anchor 개념은
/// "바닥 중심" 고정.
class PlayerComponent extends PositionComponent {
  PlayerComponent({required this.team, required this.number});

  final Team team;
  final int number;

  /// 현재 볼 소유자 표시용 링
  bool hasBall = false;

  static const _bodyWidth = 14.0;
  static const _bodyHeight = 22.0;
  static const _headRadius = 6.0;

  late final Paint _bodyPaint = Paint()
    ..color = team == Team.home
        ? const Color(0xFFD84A4A)
        : const Color(0xFF4A6AD8);
  static final Paint _headPaint = Paint()..color = const Color(0xFFF2C9A0);
  static final Paint _shadowPaint = Paint()..color = const Color(0x55000000);
  static final Paint _ringPaint = Paint()
    ..color = const Color(0xFFFFE066)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  late final TextPaint _numberPaint = TextPaint(
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
    ),
  );

  @override
  void render(Canvas canvas) {
    // 바닥 그림자
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18, height: 8),
      _shadowPaint,
    );
    if (hasBall) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 26, height: 12),
        _ringPaint,
      );
    }
    // 몸통 (바닥에서 위로)
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, -_bodyHeight / 2 - 2),
        width: _bodyWidth,
        height: _bodyHeight,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(body, _bodyPaint);
    // 머리
    canvas.drawCircle(
      Offset(0, -_bodyHeight - _headRadius + 1),
      _headRadius,
      _headPaint,
    );
    // 등번호
    _numberPaint.render(
      canvas,
      '$number',
      Vector2(0, -_bodyHeight / 2 - 2),
      anchor: Anchor.center,
    );
  }
}
