import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show FontWeight, TextStyle;

import '../sim/match_sim.dart';
import 'iso_projection.dart';

/// 플레이스홀더 선수 — 팀 컬러 캡슐 + 그림자 + 등번호.
/// position은 바닥 접지점(발 위치), 스프라이트 교체를 대비해 anchor 개념은
/// "바닥 중심" 고정.
class PlayerComponent extends PositionComponent {
  PlayerComponent({required this.team, required this.number});

  final Team team;
  final int number;

  /// 현재 볼 소유자 표시용 링
  bool hasBall = false;

  /// 행동 상태 배지 (MatchLayer가 매 프레임 갱신)
  PlayerActivity activity = PlayerActivity.offBall;

  /// 볼 소유 시 남은 HP (압박당하면 깎임)
  int holderHp = MatchSim.maxHolderHp;

  static const double _jumpDuration = 0.5;
  static const double _jumpHeight = 0.55; // 미터
  double _jumpTime = 0;

  /// 점프샷/블록 연출 (렌더 전용 — 시뮬에 영향 없음)
  void jump() => _jumpTime = _jumpDuration;

  @override
  void update(double dt) {
    if (_jumpTime > 0) {
      _jumpTime = math.max(0, _jumpTime - dt);
    }
  }

  double get _jumpOffsetY {
    if (_jumpTime <= 0) {
      return 0;
    }
    final t = 1 - _jumpTime / _jumpDuration;
    return -math.sin(math.pi * t) *
        _jumpHeight *
        IsoProjection.heightScale;
  }

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
    // 점프 중이면 몸만 떠오른다 (그림자·링은 바닥에 유지)
    canvas.save();
    canvas.translate(0, _jumpOffsetY);
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
    _renderActivityBadge(canvas);
    if (hasBall) {
      _renderHpPips(canvas);
    }
    canvas.restore();
  }

  static final Paint _hpFullPaint = Paint()..color = const Color(0xFFFF5555);
  static final Paint _hpEmptyPaint = Paint()
    ..color = const Color(0x66000000);

  /// 홀더 머리 위 HP 칸 (3칸, 압박당하면 줄어듦)
  void _renderHpPips(Canvas canvas) {
    final top = -_bodyHeight - _headRadius * 2 - 8.0;
    for (var i = 0; i < MatchSim.maxHolderHp; i++) {
      final rect = Rect.fromCenter(
        center: Offset((i - 1) * 7.0, top),
        width: 5,
        height: 5,
      );
      canvas.drawRect(rect, i < holderHp ? _hpFullPaint : _hpEmptyPaint);
    }
  }

  static final Paint _receiverPaint = Paint()
    ..color = const Color(0xFFFF9F1C);
  static final Paint _cuttingPaint = Paint()..color = const Color(0xFF4CD964);
  static final Paint _chasingPaint = Paint()..color = const Color(0xFFC96BFF);

  /// 머리 위 상태 배지: ● 리시버(주황) ▲ 컷(초록) ◆ 루즈볼 추적(보라)
  void _renderActivityBadge(Canvas canvas) {
    final top = -_bodyHeight - _headRadius * 2 - 7.0;
    switch (activity) {
      case PlayerActivity.receiver:
        canvas.drawCircle(Offset(0, top), 3.5, _receiverPaint);
      case PlayerActivity.cutting:
        final path = Path()
          ..moveTo(0, top - 4)
          ..lineTo(4, top + 3)
          ..lineTo(-4, top + 3)
          ..close();
        canvas.drawPath(path, _cuttingPaint);
      case PlayerActivity.chasing:
        final path = Path()
          ..moveTo(0, top - 4)
          ..lineTo(4, top)
          ..lineTo(0, top + 4)
          ..lineTo(-4, top)
          ..close();
        canvas.drawPath(path, _chasingPaint);
      case PlayerActivity.handler:
      case PlayerActivity.offBall:
      case PlayerActivity.defending:
        break; // 핸들러는 노란 링으로 이미 표시, 나머지는 배지 없음
    }
  }
}
