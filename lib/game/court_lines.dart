import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import 'court_spec.dart';
import 'iso_projection.dart';

/// 코트 라인(경계·센터 서클·페인트존·3점 라인·림)을
/// 바닥 좌표(미터) → 아이소메트릭 투영으로 그린다.
class CourtLinesComponent extends Component {
  CourtLinesComponent({required this.iso});

  final IsoProjection iso;

  late final Path _linePath;

  final Paint _linePaint = Paint()
    ..color = const Color(0xFFF5F0E8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  Future<void> onLoad() async {
    _linePath = _buildPath();
  }

  Vector2 courtToLocal(double x, double y) => iso.courtToLocal(x, y);

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_linePath, _linePaint);
  }

  Path _buildPath() {
    final path = Path();

    void polyline(List<Vector2> pts, {bool close = false}) {
      final first = courtToLocal(pts.first.x, pts.first.y);
      path.moveTo(first.x, first.y);
      for (final p in pts.skip(1)) {
        final v = courtToLocal(p.x, p.y);
        path.lineTo(v.x, v.y);
      }
      if (close) {
        path.close();
      }
    }

    void circle(double cx, double cy, double r, {int segments = 48}) {
      final pts = List<Vector2>.generate(segments, (k) {
        final a = 2 * math.pi * k / segments;
        return Vector2(cx + r * math.cos(a), cy + r * math.sin(a));
      });
      polyline(pts, close: true);
    }

    const len = CourtSpec.length;
    const w = CourtSpec.width;
    const cy = CourtSpec.centerY;

    // 경계 + 센터 라인 + 센터 서클
    polyline(
      [Vector2(0, 0), Vector2(len, 0), Vector2(len, w), Vector2(0, w)],
      close: true,
    );
    polyline([Vector2(len / 2, 0), Vector2(len / 2, w)]);
    circle(len / 2, cy, CourtSpec.centerCircleRadius);

    // 양쪽 하프코트 (왼쪽 기준 x → 오른쪽은 미러)
    for (final mirror in [false, true]) {
      double mx(double x) => mirror ? len - x : x;

      // 페인트존
      polyline([
        Vector2(mx(0), cy - CourtSpec.keyHalfWidth),
        Vector2(mx(CourtSpec.keyLength), cy - CourtSpec.keyHalfWidth),
        Vector2(mx(CourtSpec.keyLength), cy + CourtSpec.keyHalfWidth),
        Vector2(mx(0), cy + CourtSpec.keyHalfWidth),
      ]);
      circle(mx(CourtSpec.keyLength), cy, CourtSpec.ftCircleRadius);

      // 3점 라인: 코너 직선 + 아크 + 코너 직선
      final cornerX = CourtSpec.threeCornerX;
      final r = CourtSpec.threeRadius;
      final bx = CourtSpec.basketX;
      final a1 = math.atan2(CourtSpec.threeSideOffset - cy, cornerX - bx);
      final a2 = math.atan2(w - CourtSpec.threeSideOffset - cy, cornerX - bx);
      const arcSegments = 40;
      final pts = <Vector2>[
        Vector2(mx(0), CourtSpec.threeSideOffset),
        for (var k = 0; k <= arcSegments; k++)
          () {
            final a = a1 + (a2 - a1) * k / arcSegments;
            return Vector2(mx(bx + r * math.cos(a)), cy + r * math.sin(a));
          }(),
        Vector2(mx(0), w - CourtSpec.threeSideOffset),
      ];
      polyline(pts);

      // 백보드 + 림
      polyline([
        Vector2(mx(CourtSpec.backboardX), cy - CourtSpec.backboardHalf),
        Vector2(mx(CourtSpec.backboardX), cy + CourtSpec.backboardHalf),
      ]);
      circle(mx(bx), cy, CourtSpec.rimRadius, segments: 16);
    }

    return path;
  }
}
