import 'dart:ui';

import 'package:flame/components.dart';

import '../sim/court_dims.dart';
import 'iso_projection.dart';

/// 골대 — 스탠션(기둥) + 백보드 + 림 + 네트를 z축 투영으로 세워 그린다.
/// position 은 백보드 바닥 지점, 깊이 정렬은 그 바닥 좌표를 따른다.
class HoopComponent extends PositionComponent {
  HoopComponent({required this.iso, required this.leftSide});

  final IsoProjection iso;

  /// 왼쪽(홈 진영) 골대인가 — 코트 x 좌표를 미러링
  final bool leftSide;

  static const double _boardBottomZ = 2.9;
  static const double _boardTopZ = 4.05;
  static const double _rimZ = CourtDims.rimHeight;

  double get _boardX =>
      leftSide ? CourtDims.backboardX : CourtDims.length - CourtDims.backboardX;

  double get _rimX =>
      leftSide ? CourtDims.basketX : CourtDims.length - CourtDims.basketX;

  /// 바닥 앵커 (백보드 아래)
  Vector2 get floorAnchor => Vector2(_boardX, CourtDims.centerY);

  static final Paint _boardFill = Paint()..color = const Color(0x55E8F0F8);
  static final Paint _boardEdge = Paint()
    ..color = const Color(0xFFE8F0F8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _innerBox = Paint()
    ..color = const Color(0xCCE8F0F8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _rimPaint = Paint()
    ..color = const Color(0xFFFF6B35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  static final Paint _netPaint = Paint()
    ..color = const Color(0xAAFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final Paint _polePaint = Paint()
    ..color = const Color(0xFF666E78)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  /// 코트 좌표(x, y, 높이 z) → 이 컴포넌트 로컬 좌표
  Vector2 _pt(double x, double y, double z) =>
      iso.courtToLocal(x, y) -
      position +
      Vector2(0, -z * IsoProjection.heightScale);

  @override
  void render(Canvas canvas) {
    const cy = CourtDims.centerY;
    const half = CourtDims.backboardHalf;
    final poleX = leftSide ? -0.9 : CourtDims.length + 0.9;

    // 스탠션: 베이스라인 뒤 기둥 → 백보드 상단 연결
    final poleBase = _pt(poleX, cy, 0);
    final poleTop = _pt(poleX, cy, _boardBottomZ + 0.4);
    final boardMid = _pt(_boardX, cy, _boardBottomZ + 0.4);
    canvas.drawLine(poleBase.toOffset(), poleTop.toOffset(), _polePaint);
    canvas.drawLine(poleTop.toOffset(), boardMid.toOffset(), _polePaint);

    // 백보드 (세로 평면 사각형)
    final b1 = _pt(_boardX, cy - half, _boardBottomZ);
    final b2 = _pt(_boardX, cy + half, _boardBottomZ);
    final b3 = _pt(_boardX, cy + half, _boardTopZ);
    final b4 = _pt(_boardX, cy - half, _boardTopZ);
    final board = Path()
      ..moveTo(b1.x, b1.y)
      ..lineTo(b2.x, b2.y)
      ..lineTo(b3.x, b3.y)
      ..lineTo(b4.x, b4.y)
      ..close();
    canvas.drawPath(board, _boardFill);
    canvas.drawPath(board, _boardEdge);
    // 백보드 안쪽 사각형 (슛 타겟)
    final i1 = _pt(_boardX, cy - 0.3, _rimZ);
    final i2 = _pt(_boardX, cy + 0.3, _rimZ);
    final i3 = _pt(_boardX, cy + 0.3, _rimZ + 0.45);
    final i4 = _pt(_boardX, cy - 0.3, _rimZ + 0.45);
    canvas.drawPath(
      Path()
        ..moveTo(i1.x, i1.y)
        ..lineTo(i2.x, i2.y)
        ..lineTo(i3.x, i3.y)
        ..lineTo(i4.x, i4.y)
        ..close(),
      _innerBox,
    );

    // 림: 높이 3.05m 의 바닥 평행 원 → 화면상 타원
    final rimCenter = _pt(_rimX, cy, _rimZ);
    const rimR = CourtDims.rimRadius;
    final rimRect = Rect.fromCenter(
      center: rimCenter.toOffset(),
      width: 90.5 * rimR, // 바닥 원 투영 폭 (64√2·r)
      height: 45.25 * rimR,
    );
    canvas.drawOval(rimRect, _rimPaint);

    // 네트: 림 가장자리에서 아래로 좁아지는 선들
    final netBottom = _pt(_rimX, cy, _rimZ - 0.45);
    for (final t in const [-0.9, -0.45, 0.0, 0.45, 0.9]) {
      final topX = rimCenter.x + rimRect.width / 2 * t;
      final bottomX = rimCenter.x + (topX - rimCenter.x) * 0.4;
      canvas.drawLine(
        Offset(topX, rimCenter.y),
        Offset(bottomX, netBottom.y),
        _netPaint,
      );
    }
  }
}
