import 'dart:math' as math;

import 'package:flame/components.dart';

import '../sim/match_sim.dart';
import 'ball_component.dart';
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
      final comp = PlayerComponent(team: p.team, number: p.id % 5 + 1);
      _playerComps.add(comp);
      add(comp);
      _prevPos.add(p.pos.clone());
      _currPos.add(p.pos.clone());
    }
    _ballComp = BallComponent();
    add(_ballComp);
    _prevBall.setFrom(sim.ball.pos);
    _currBall.setFrom(sim.ball.pos);
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
      comp.hasBall = sim.ball.holderId == sim.players[i].id;
      comp.activity = sim.activityOf(sim.players[i]);
    }

    final bx = _lerp(_prevBall.x, _currBall.x, alpha);
    final by = _lerp(_prevBall.y, _currBall.y, alpha);
    var bz = _lerp(_prevBallZ, _currBallZ, alpha);
    // 드리블 바운스는 연출 전용 (시뮬 z는 0)
    if (sim.ball.phase == BallPhase.held) {
      bz = 0.45 * math.sin(_renderClock * 9).abs();
    }
    _ballComp
      ..position = iso.courtToLocal(bx, by)
      ..z = bz
      ..spinning = sim.ball.phase != BallPhase.held
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
