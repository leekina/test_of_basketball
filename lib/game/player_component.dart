import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show FontWeight, TextStyle;

import '../sim/match_sim.dart';
import 'iso_projection.dart';

/// 플레이스홀더 선수 — 팀 컬러 캡슐 + 그림자 + 등번호.
/// 머리 위: 홀더 HP 칸 / 발밑: 현재 상태 라벨.
/// position은 바닥 접지점(발 위치).
class PlayerComponent extends PositionComponent {
  PlayerComponent({
    required this.team,
    required this.number,
    required this.positionName,
  });

  final Team team;
  final int number;

  /// 포지션 약칭 (PG/SG/SF/PF/C) — 유니폼에 표시
  final String positionName;

  /// 현재 볼 소유자 표시용 링 (MatchLayer가 매 프레임 갱신)
  bool hasBall = false;

  /// 발밑에 표시할 상태 라벨
  String stateLabel = '';

  /// 볼 소유 시 남은 HP (압박당하면 깎임)
  int holderHp = MatchSim.maxHolderHp;

  /// 블락 점프 진행도 0..1 (블락 중이 아니면 음수) — 시뮬 상태 기반
  double blockProgress = -1;

  /// 수비 범위(압박 반경) 표시 여부 — 수비중 상태일 때
  bool showDefenseRange = false;

  /// 이 수비수의 범위 안에 볼 홀더가 잡혀 있는가 (압박 진행 중)
  bool pressuring = false;

  static const _bodyWidth = 14.0;
  static const _bodyHeight = 22.0;
  static const _headRadius = 6.0;

  static const double _jumpDuration = 0.5;
  static const double _jumpHeight = 0.55; // 미터
  double _jumpTime = 0;

  /// 슛 릴리즈 점프 연출 (렌더 전용 — 시뮬에 영향 없음)
  void jump() => _jumpTime = _jumpDuration;

  @override
  void update(double dt) {
    if (_jumpTime > 0) {
      _jumpTime = math.max(0, _jumpTime - dt);
    }
  }

  double get _jumpOffsetY {
    // 블락 점프(시뮬 상태)가 우선, 아니면 슛 릴리즈 점프(연출)
    if (blockProgress >= 0) {
      return -math.sin(math.pi * blockProgress) *
          0.7 *
          IsoProjection.heightScale;
    }
    if (_jumpTime <= 0) {
      return 0;
    }
    final t = 1 - _jumpTime / _jumpDuration;
    return -math.sin(math.pi * t) * _jumpHeight * IsoProjection.heightScale;
  }

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
      fontSize: 7,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
    ),
  );
  static final TextPaint _labelPaint = TextPaint(
    style: const TextStyle(
      fontSize: 8,
      color: Color(0xFFFFFFFF),
      shadows: [Shadow(color: Color(0xCC000000), blurRadius: 2)],
    ),
  );

  static final Paint _rangePaint = Paint()
    ..color = const Color(0x334A6AD8)
    ..style = PaintingStyle.fill;
  static final Paint _rangeEdgePaint = Paint()
    ..color = const Color(0x664A6AD8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final Paint _pressurePaint = Paint()
    ..color = const Color(0x44FF3B30)
    ..style = PaintingStyle.fill;
  static final Paint _pressureEdgePaint = Paint()
    ..color = const Color(0x99FF3B30)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void render(Canvas canvas) {
    // 수비 범위: 압박 반경(1m)의 아이소메트릭 투영 타원.
    // 홀더가 범위 안이면(압박 중) 빨간색으로 바뀐다.
    if (showDefenseRange) {
      // 바닥 원 r(m) → 화면 타원: 가로 64√2·r, 세로 32√2·r
      const r = MatchSim.pressureRadius;
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: 64 * math.sqrt2 * r,
        height: 32 * math.sqrt2 * r,
      );
      canvas.drawOval(rect, pressuring ? _pressurePaint : _rangePaint);
      canvas.drawOval(
        rect,
        pressuring ? _pressureEdgePaint : _rangeEdgePaint,
      );
    }
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
    // 점프 중이면 몸만 떠오른다 (그림자·링·라벨은 바닥에 유지)
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
    // 포지션 약칭 (유니폼)
    _numberPaint.render(
      canvas,
      positionName,
      Vector2(0, -_bodyHeight / 2 - 2),
      anchor: Anchor.center,
    );
    if (hasBall) {
      _renderHpPips(canvas);
    }
    canvas.restore();

    // 발밑 상태 라벨
    if (stateLabel.isNotEmpty) {
      _labelPaint.render(
        canvas,
        stateLabel,
        Vector2(0, 6),
        anchor: Anchor.topCenter,
      );
    }
  }

  static final Paint _hpFullPaint = Paint()..color = const Color(0xFFFF5555);
  static final Paint _hpEmptyPaint = Paint()..color = const Color(0x66000000);

  /// 홀더 머리 위 HP 칸 (압박당하면 줄어듦)
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
}
