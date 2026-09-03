import 'dart:math' as math;

import 'package:flame/components.dart';

import '../sim/match_sim.dart';
import 'ball_component.dart';
import 'hoop_component.dart';
import 'iso_projection.dart';
import 'player_component.dart';

/// 시뮬레이션 틱 스트림을 소비해 선수/공 컴포넌트를 재생하는 연출 층.
/// 고정 틱(10/s) 사이는 이전/현재 스냅샷을 보간해 부드럽게 그린다.
/// 렌더는 시뮬 결과에 영향을 주지 않는다 (로직/렌더 분리).
class MatchLayer extends Component {
  MatchLayer({required this.sim, required this.iso});

  final MatchSim sim;
  final IsoProjection iso;

  final List<PlayerComponent> _playerComps = [];
  late final BallComponent _ballComp;

  double _accumulator = 0;
  double _renderClock = 0; // 드리블 바운스 등 연출 전용 시계

  // 보간용 스냅샷 (코트 좌표)
  final List<Vector2> _prevPos = [];
  final List<Vector2> _currPos = [];
  final Vector2 _prevBall = Vector2.zero();
  final Vector2 _currBall = Vector2.zero();
  double _prevBallZ = 0;
  double _currBallZ = 0;

  @override
  Future<void> onLoad() async {
    for (final p in sim.players) {
      final comp = PlayerComponent(
        team: p.team,
        number: p.id % 5 + 1,
        positionName: p.position.shortName,
      );
      _playerComps.add(comp);
      add(comp);
      _prevPos.add(p.pos.clone());
      _currPos.add(p.pos.clone());
    }
    _ballComp = BallComponent();
    add(_ballComp);
    _prevBall.setFrom(sim.ball.pos);
    _currBall.setFrom(sim.ball.pos);

    // 골대 (양쪽) — 선수와 같은 깊이 정렬 공간에 둔다
    for (final leftSide in [true, false]) {
      final hoop = HoopComponent(iso: iso, leftSide: leftSide);
      hoop.position = iso.courtToLocal(
        hoop.floorAnchor.x,
        hoop.floorAnchor.y,
      );
      hoop.priority =
          iso.depthOf(hoop.floorAnchor.x, hoop.floorAnchor.y);
      add(hoop);
    }
  }

  @override
  void update(double dt) {
    _renderClock += dt;
    _accumulator += dt;
    while (_accumulator >= MatchSim.dt) {
      _accumulator -= MatchSim.dt;
      _snapshot(_prevPos, _prevBall);
      _prevBallZ = _currBallZ;
      sim.tick();
      _snapshot(_currPos, _currBall);
      _currBallZ = sim.ball.z;
    }
    final alpha = (_accumulator / MatchSim.dt).clamp(0.0, 1.0);
    _applyInterpolated(alpha);
  }

  /// 발밑 상태 라벨 (한국어)
  String _labelFor(SimPlayer p) {
    switch (p.state) {
      case PlayerState.dribbling:
        return '드리블';
      case PlayerState.windup:
        return p.layupMotion ? '레이업!' : '슛!';
      case PlayerState.faking:
        return '페이크';
      case PlayerState.receiving:
        return '리시브';
      case PlayerState.cutting:
        return '컷';
      case PlayerState.chasing:
        return '볼 추적';
      case PlayerState.moving:
        return '이동';
      case PlayerState.defending:
        return '수비';
      case PlayerState.blocking:
        return '블락!';
      case PlayerState.rebounding:
        return '리바운드!';
      case PlayerState.bodyChecking:
        return '박치기!';
      case PlayerState.driving:
        return '드라이빙!';
      case PlayerState.screening:
        return '스크린!';
      case PlayerState.stunned:
        return '스턴!';
      case PlayerState.idle:
        return '대기';
    }
  }

  void _snapshot(List<Vector2> posOut, Vector2 ballOut) {
    for (var i = 0; i < sim.players.length; i++) {
      posOut[i].setFrom(sim.players[i].pos);
    }
    ballOut.setFrom(sim.ball.pos);
  }

  void _applyInterpolated(double alpha) {
    for (var i = 0; i < _playerComps.length; i++) {
      final x = _lerp(_prevPos[i].x, _currPos[i].x, alpha);
      final y = _lerp(_prevPos[i].y, _currPos[i].y, alpha);
      final comp = _playerComps[i];
      comp.position = iso.courtToLocal(x, y);
      comp.priority = iso.depthOf(x, y);
      final p = sim.players[i];
      comp.hasBall = sim.ball.holderId == p.id;
      comp.holderHp = sim.holderHp;
      comp.stateLabel = _labelFor(p);
      // 점프 곡선: 블락/리바운드/슈팅 모션(페이크 포함 — 겉모습 동일해야
      // 낚시가 성립) 모두 시뮬 상태 타이머에서 유도한다
      comp.blockProgress = switch (p.state) {
        PlayerState.blocking =>
          1 - (p.stateTimer / MatchSim.blockDuration).clamp(0.0, 1.0),
        PlayerState.rebounding =>
          1 - (p.stateTimer / MatchSim.reboundJumpDuration).clamp(0.0, 1.0),
        PlayerState.windup => 1 -
            (p.stateTimer /
                    (p.layupMotion
                        ? MatchSim.layupWindupDuration
                        : MatchSim.windupDuration))
                .clamp(0.0, 1.0),
        PlayerState.faking =>
          1 - (p.stateTimer / MatchSim.fakeDuration).clamp(0.0, 1.0),
        _ => -1.0,
      };
      // 몸통박치기 런지: 공(홀더) 방향으로 짧게 들이받는 모션
      if (p.state == PlayerState.bodyChecking) {
        final progress =
            1 - (p.stateTimer / MatchSim.bodyCheckDuration).clamp(0.0, 1.0);
        final ballScreen =
            iso.courtToLocal(sim.ball.pos.x, sim.ball.pos.y);
        final dir = ballScreen - comp.position;
        if (dir.length > 1e-6) {
          dir.normalize();
        }
        comp.lungeProgress = progress;
        comp.lungeDir.setFrom(dir);
      } else {
        comp.lungeProgress = -1;
      }
      comp.stunned = p.state == PlayerState.stunned;
      comp.showDefenseRange = p.state == PlayerState.defending;
      final h = sim.holder;
      comp.pressuring = p.state == PlayerState.defending &&
          h != null &&
          h.state == PlayerState.dribbling &&
          h.team != p.team &&
          p.pos.distanceTo(h.pos) <= MatchSim.pressureRadius;
    }

    final bx = _lerp(_prevBall.x, _currBall.x, alpha);
    final by = _lerp(_prevBall.y, _currBall.y, alpha);
    var bz = _lerp(_prevBallZ, _currBallZ, alpha);
    var spinning = sim.ball.phase != BallPhase.held;
    var spinSpeed = 1.0;
    // 홀더 연출: 슛 모션이면 공을 몸쪽에 고정, 드리블이면 바운스+저속 회전
    if (sim.ball.phase == BallPhase.held) {
      final h = sim.holder;
      if (h != null &&
          (h.state == PlayerState.windup ||
              h.state == PlayerState.faking)) {
        bz = 1.2; // 드리블을 멈추고 몸쪽(가슴 높이)에 가만히 든다
      } else {
        bz = 0.45 * math.sin(_renderClock * 9).abs();
        spinning = true; // 드리블 중엔 공 프레임을 천천히 교체
        spinSpeed = 0.5; // 비행의 절반 속도
      }
    }
    _ballComp
      ..position = iso.courtToLocal(bx, by)
      ..z = bz
      ..spinning = spinning
      ..spinSpeed = spinSpeed
      ..priority = iso.depthOf(bx, by) + 50;
  }

  /// 현재 보간된 공의 코트 좌표 (카메라 추적용)
  Vector2 get ballCourtPos {
    final alpha = (_accumulator / MatchSim.dt).clamp(0.0, 1.0);
    return Vector2(
      _lerp(_prevBall.x, _currBall.x, alpha),
      _lerp(_prevBall.y, _currBall.y, alpha),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
