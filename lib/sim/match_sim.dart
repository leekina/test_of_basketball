import 'dart:math';

import 'package:vector_math/vector_math.dart';

import 'court_dims.dart';

/// 순수 Dart 경기 시뮬레이션 (능력치 없음, 룰 기반 창발 코어의 뼈대).
/// Flame 미의존 — 고정 틱 + 시드 RNG로 완전 재현 가능.
///
/// 룰 요약:
/// - 볼 핸들러: 골대로 드리블, 사거리 안에서 확률적 슛, 샷클락 만료 직전 강제 슛
/// - 오프볼 공격수: 포메이션 앵커로 이동 + 동료 분리
/// - 수비수: 마크 대상↔공격 골대 선분 위로 이동 (맨투맨)
/// - 패스: 압박 시/간헐적으로 가장 오픈된 동료에게 (비행 중 소유자 없음)
/// - 슛: 포물선 비행 후 고정 확률 성공. 실패 시 림 주변 리바운드 → 줍기 경쟁

enum Team { home, away }

enum BallPhase { held, pass, shot, loose }

class SimPlayer {
  SimPlayer(this.id, this.team, double x, double y) : pos = Vector2(x, y);

  final int id;
  final Team team;
  final Vector2 pos;
}

class SimBall {
  final Vector2 pos = Vector2.zero();
  double z = 0;
  int? holderId;
  BallPhase phase = BallPhase.loose;

  // 비행(패스/슛) 상태
  final Vector2 from = Vector2.zero();
  final Vector2 to = Vector2.zero();
  double flightTime = 0;
  double flightDuration = 0;
  double arcPeak = 0;
  int? receiverId;
  bool shotWillScore = false;
  int shotValue = 2;
}

class MatchSim {
  MatchSim({int seed = 42}) : _rng = Random(seed) {
    for (var i = 0; i < 5; i++) {
      players.add(SimPlayer(i, Team.home, 10 + 2.0 * i, 2.5 + 2.5 * i));
      players.add(SimPlayer(5 + i, Team.away, 18 - 2.0 * i, 2.5 + 2.5 * i));
    }
    _giveBallTo(players[0]);
  }

  /// 시뮬레이션 틱 간격 (초) — 10 tick/s
  static const double dt = 0.1;

  static const double playerSpeed = 4.0;
  static const double passSpeed = 7.0;
  static const double shotSpeed = 6.0;
  static const double shootRange = 6.8;
  static const double shotClockMax = 14.0;
  static const double catchRadius = 1.2;
  static const double pickupRadius = 0.7;
  static const double shotMakeProb = 0.5;

  final Random _rng;
  final List<SimPlayer> players = [];
  final SimBall ball = SimBall();

  Team offense = Team.home;
  double shotClock = shotClockMax;
  int homeScore = 0;
  int awayScore = 0;
  int offenseChanges = 0;

  /// 직전 틱에 발생한 이벤트 ('pass:3', 'shot:2', 'score:home:2', 'miss',
  /// 'pickup:7', 'turnover') — 없으면 null
  String? lastEvent;

  /// 공격 팀이 노리는 골대
  Vector2 basketOf(Team team) => team == Team.home
      ? Vector2(CourtDims.length - CourtDims.basketX, CourtDims.centerY)
      : Vector2(CourtDims.basketX, CourtDims.centerY);

  SimPlayer? get holder =>
      ball.holderId == null ? null : players[ball.holderId!];

  Iterable<SimPlayer> teamOf(Team t) => players.where((p) => p.team == t);

  void tick() {
    lastEvent = null;
    shotClock = max(0, shotClock - dt);

    _updateBallFlight();
    _movePlayers();

    final h = holder;
    if (h != null) {
      _handlerDecision(h);
    }
    // 이동 후 소유 중이면 공은 핸들러 위치에
    if (ball.phase == BallPhase.held && holder != null) {
      ball.pos.setFrom(holder!.pos);
      ball.z = 0;
    }
    if (ball.phase == BallPhase.loose) {
      _tryPickup();
    }
  }

  // ---------------- 공 비행 ----------------

  void _updateBallFlight() {
    if (ball.phase != BallPhase.pass && ball.phase != BallPhase.shot) {
      return;
    }
    ball.flightTime += dt;
    final u = min(1.0, ball.flightTime / ball.flightDuration);
    ball.pos
      ..setFrom(ball.to)
      ..sub(ball.from)
      ..scale(u)
      ..add(ball.from);
    final baseZ = ball.phase == BallPhase.shot
        ? _lerpDouble(1.8, CourtDims.rimHeight, u)
        : 1.2;
    ball.z = baseZ + 4 * ball.arcPeak * u * (1 - u);
    if (u < 1.0) {
      return;
    }
    // 도착
    if (ball.phase == BallPhase.pass) {
      final receiver = players[ball.receiverId!];
      if (receiver.pos.distanceTo(ball.to) <= catchRadius) {
        _giveBallTo(receiver);
      } else {
        _dropLooseAt(ball.to);
      }
      return;
    }
    // 슛 도착
    if (ball.shotWillScore) {
      if (offense == Team.home) {
        homeScore += ball.shotValue;
      } else {
        awayScore += ball.shotValue;
      }
      lastEvent = 'score:${offense.name}:${ball.shotValue}';
      _switchOffense();
      // 인바운드: 새 공격팀에서 골대에 가장 가까운 선수에게
      final inbounder = _nearestOf(teamOf(offense), ball.to);
      _giveBallTo(inbounder);
    } else {
      lastEvent = 'miss';
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = 1.0 + _rng.nextDouble() * 2.0;
      final spot = ball.to + Vector2(cos(angle), sin(angle)) * dist;
      _dropLooseAt(spot);
    }
  }

  void _dropLooseAt(Vector2 spot) {
    ball.phase = BallPhase.loose;
    ball.holderId = null;
    ball.receiverId = null;
    ball.pos.setFrom(_clampToCourt(spot));
    ball.z = 0;
  }

  void _tryPickup() {
    final nearest = _nearestOf(players, ball.pos);
    if (nearest.pos.distanceTo(ball.pos) > pickupRadius) {
      return;
    }
    final wasOffense = offense;
    _giveBallTo(nearest);
    lastEvent = 'pickup:${nearest.id}';
    if (nearest.team != wasOffense) {
      _switchOffense(to: nearest.team);
      lastEvent = 'turnover';
    } else {
      shotClock = shotClockMax; // 공격 리바운드도 리셋 (단순화)
    }
  }

  void _giveBallTo(SimPlayer p) {
    ball.holderId = p.id;
    ball.receiverId = null;
    ball.phase = BallPhase.held;
    ball.pos.setFrom(p.pos);
    ball.z = 0;
    if (p.team != offense) {
      _switchOffense(to: p.team);
    }
  }

  void _switchOffense({Team? to}) {
    final next =
        to ?? (offense == Team.home ? Team.away : Team.home);
    if (next == offense) {
      return;
    }
    offense = next;
    offenseChanges++;
    shotClock = shotClockMax;
  }

  // ---------------- 핸들러 판단 ----------------

  void _handlerDecision(SimPlayer h) {
    final basket = basketOf(offense);
    final distToBasket = h.pos.distanceTo(basket);
    final nearestDef = _nearestOf(
      teamOf(offense == Team.home ? Team.away : Team.home),
      h.pos,
    );
    final pressure = nearestDef.pos.distanceTo(h.pos);

    if (shotClock <= 0.3) {
      _shoot(h, basket, distToBasket);
    } else if (distToBasket < shootRange && _rng.nextDouble() < 0.08) {
      _shoot(h, basket, distToBasket);
    } else if (pressure < 1.3 && _rng.nextDouble() < 0.08) {
      _pass(h);
    } else if (_rng.nextDouble() < 0.008) {
      _pass(h);
    }
  }

  void _shoot(SimPlayer h, Vector2 basket, double dist) {
    ball.from.setFrom(h.pos);
    ball.to.setFrom(basket);
    ball.flightTime = 0;
    ball.flightDuration = max(0.9, dist / shotSpeed);
    ball.arcPeak = 1.0 + dist * 0.15;
    ball.shotWillScore = _rng.nextDouble() < shotMakeProb;
    ball.shotValue = dist > CourtDims.threeRadius ? 3 : 2;
    ball.holderId = null;
    ball.phase = BallPhase.shot;
    lastEvent = 'shot:${ball.shotValue}';
  }

  void _pass(SimPlayer h) {
    final defenders =
        teamOf(offense == Team.home ? Team.away : Team.home).toList();
    final basket = basketOf(offense);
    SimPlayer? best;
    var bestScore = double.negativeInfinity;
    for (final mate in teamOf(offense)) {
      if (mate.id == h.id) {
        continue;
      }
      final openness = defenders
          .map((d) => d.pos.distanceTo(mate.pos))
          .reduce(min);
      // 오픈 정도 우선 + 골대에 가까울수록 약간 가산
      final score = openness - mate.pos.distanceTo(basket) * 0.15;
      if (score > bestScore) {
        bestScore = score;
        best = mate;
      }
    }
    if (best == null) {
      return;
    }
    ball.from.setFrom(h.pos);
    ball.to.setFrom(best.pos);
    ball.flightTime = 0;
    ball.flightDuration =
        max(0.4, h.pos.distanceTo(best.pos) / passSpeed);
    ball.arcPeak = 0.5;
    ball.receiverId = best.id;
    ball.holderId = null;
    ball.phase = BallPhase.pass;
    lastEvent = 'pass:${best.id}';
  }

  // ---------------- 이동 ----------------

  /// 공격 포메이션 앵커 (공격 골대 기준 u = 베이스라인에서의 거리)
  static const List<(double, double)> _anchors = [
    (6.5, 2.0),
    (6.5, 13.0),
    (8.5, 7.5),
    (2.0, 4.0),
    (2.0, 11.0),
  ];

  void _movePlayers() {
    for (final p in players) {
      final target = _targetFor(p);
      final delta = target - p.pos;
      final distance = delta.length;
      if (distance > 1e-6) {
        final step = min(distance, playerSpeed * dt);
        p.pos.add(delta..scale(step / distance));
      }
      _separate(p);
      p.pos.setFrom(_clampToCourt(p.pos));
    }
  }

  Vector2 _targetFor(SimPlayer p) {
    // 패스 받을 사람은 캐치 지점으로
    if (ball.phase == BallPhase.pass && ball.receiverId == p.id) {
      return ball.to.clone();
    }
    // 루즈볼: 각 팀에서 가장 가까운 선수가 공으로
    if (ball.phase == BallPhase.loose) {
      final chaser = _nearestOf(teamOf(p.team), ball.pos);
      if (chaser.id == p.id) {
        return ball.pos.clone();
      }
    }
    if (p.team == offense) {
      if (ball.holderId == p.id) {
        return basketOf(offense);
      }
      return _anchorFor(p);
    }
    return _defenseTargetFor(p);
  }

  Vector2 _anchorFor(SimPlayer p) {
    final indexInTeam = p.id % 5;
    final (u, y) = _anchors[indexInTeam];
    final x = offense == Team.home ? CourtDims.length - u : u;
    return Vector2(x, y);
  }

  Vector2 _defenseTargetFor(SimPlayer p) {
    final mark = players.firstWhere(
      (o) => o.team != p.team && o.id % 5 == p.id % 5,
    );
    final basket = basketOf(offense);
    final toBasket = basket - mark.pos;
    final len = toBasket.length;
    if (len < 1e-6) {
      return mark.pos.clone();
    }
    final standOff = min(1.2, len * 0.3);
    return mark.pos + toBasket.scaled(standOff / len);
  }

  void _separate(SimPlayer p) {
    for (final mate in teamOf(p.team)) {
      if (mate.id == p.id) {
        continue;
      }
      final delta = p.pos - mate.pos;
      final distance = delta.length;
      if (distance > 1e-6 && distance < 0.9) {
        p.pos.add(delta.scaled((0.9 - distance) / distance * 0.5));
      }
    }
  }

  // ---------------- 유틸 ----------------

  SimPlayer _nearestOf(Iterable<SimPlayer> group, Vector2 point) {
    late SimPlayer best;
    var bestDist = double.infinity;
    for (final p in group) {
      final d = p.pos.distanceTo(point);
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    return best;
  }

  Vector2 _clampToCourt(Vector2 v) => Vector2(
        v.x.clamp(0.2, CourtDims.length - 0.2),
        v.y.clamp(0.2, CourtDims.width - 0.2),
      );

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
