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

/// 농구 포지션 — 팀 내 인덱스(id % 5) 순서로 배정된다.
enum CourtPosition {
  pointGuard,
  shootingGuard,
  smallForward,
  powerForward,
  center;

  String get shortName =>
      const ['PG', 'SG', 'SF', 'PF', 'C'][index];
}

/// 포지션별 행동 파라미터 (능력치가 아니라 역할 성향).
/// 데이터 테이블로 분리 — AI 튜닝 루프가 수치만 바꿀 수 있게.
class PositionProfile {
  const PositionProfile({
    required this.anchor,
    this.shootMul = 1,
    this.passMul = 1,
    this.layupChance = 0.3,
    this.maxShotDist = 7.4,
    this.cutChance = 0.03,
    this.reboundWeight = 1,
    this.blockProb = 0.35,
    this.defenseStandoff = 0.6,
    this.crashesBoards = false,
    this.arcRelocate = false,
    this.wanderIntervalMin = 1.5,
    this.wanderIntervalMax = 4.0,
  });

  /// 공격 앵커 (u: 공격 골대 베이스라인에서의 거리, y)
  final (double, double) anchor;

  /// 슛 시도 확률 배율
  final double shootMul;

  /// 패스 시도 확률 배율
  final double passMul;

  /// 림 근처 레이업 시도 확률 (틱당)
  final double layupChance;

  /// 이 거리 밖에서는 (강제 상황 제외) 슛을 쏘지 않는다
  final double maxShotDist;

  /// 골밑 컷 발동 확률 (틱당)
  final double cutChance;

  /// 루즈볼 추격 거리 가중치 — 낮을수록 리바운드에 적극적
  final double reboundWeight;

  /// 슈팅 모션에 대한 블락 점프 반응 확률 (틱당)
  final double blockProb;

  /// 오프볼 수비 시 마크와의 간격 (크면 골밑 사그/드롭 커버리지)
  final double defenseStandoff;

  /// 슛이 뜨면 림으로 리바운드 진입하는가 (PF/C)
  final bool crashesBoards;

  /// 3점 라인을 따라 오픈 지점으로 계속 이동하는가 (SG)
  final bool arcRelocate;

  /// 배회 지점 재추첨 주기 — 짧을수록 쉬지 않고 움직인다
  final double wanderIntervalMin;
  final double wanderIntervalMax;
}

/// 선수 상태 머신. 렌더 표시와 상호작용 판정 양쪽이 사용한다.
/// - dribbling: 볼 소유, 드리블 (수비 밀착 시 HP 깎임)
/// - windup: 슈팅 준비 모션 (0.5초 후 릴리즈, 수비 블락 유발)
/// - faking: 슈팅 페이크 (windup과 겉모습 동일, 릴리즈 없음)
/// - blocking: 블락 시도 점프 (진행 중엔 HP 못 깎고 이동 불가)
enum PlayerState {
  idle,
  moving,
  dribbling,
  windup,
  faking,
  receiving,
  cutting,
  chasing,
  defending,
  blocking,
  rebounding, // 리바운드 점프 (공중 볼 잡기)
}

class SimPlayer {
  SimPlayer(this.id, this.team, double x, double y) : pos = Vector2(x, y);

  final int id;
  final Team team;
  final Vector2 pos;

  /// 팀 내 인덱스로 결정되는 포지션 (0=PG .. 4=C)
  CourtPosition get position => CourtPosition.values[id % 5];

  // 오프볼 무브 상태 (공격 시)
  final Vector2 wander = Vector2.zero(); // 앵커 주변 배회 오프셋
  double wanderTimer = 0; // 배회 지점 재추첨까지 남은 시간
  double cutTime = 0; // 골밑 컷 진행 중 남은 시간
  double cutCooldown = 0; // 다음 컷까지 남은 시간

  // 수비 반응 지연: 마크의 위치를 주기적으로만 인식한다 (설계 문서 §3-3)
  final Vector2 perceivedMarkPos = Vector2.zero();
  double markSnapTimer = 0;

  // 상태 머신
  PlayerState state = PlayerState.idle;
  double stateTimer = 0; // windup/faking/blocking 같은 시한부 상태의 남은 시간
  double fakeCooldown = 0; // 페이크 연속 사용 방지

  bool get inTimedState =>
      (state == PlayerState.windup ||
          state == PlayerState.faking ||
          state == PlayerState.blocking ||
          state == PlayerState.rebounding) &&
      stateTimer > 0;
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

  /// 루즈볼을 특정 팀만 주울 수 있는 경우 (득점 후 인바운드)
  Team? looseFor;

  /// 이번 패스 비행에서 이미 인터셉트 판정을 굴린 수비수들
  final Set<int> interceptTried = {};
}

class MatchSim {
  MatchSim({int seed = 42}) : _rng = Random(seed) {
    // 주의: players[i].id == i 불변식을 코드 전체가 의존한다 (holder 조회 등)
    for (var i = 0; i < 5; i++) {
      players.add(SimPlayer(i, Team.home, 10 + 2.0 * i, 2.5 + 2.5 * i));
    }
    for (var i = 0; i < 5; i++) {
      players.add(SimPlayer(5 + i, Team.away, 18 - 2.0 * i, 2.5 + 2.5 * i));
    }
    assert(
      players.every((p) => players[p.id] == p),
      'players 리스트는 index == id 여야 한다',
    );
    _giveBallTo(players[0]);
  }

  /// 시뮬레이션 틱 간격 (초) — 10 tick/s
  static const double dt = 0.1;

  static const double playerSpeed = 2.8;
  static const double passSpeed = 7.0;
  static const double shotSpeed = 6.0;
  static const double shootRange = 7.4; // 윙/탑 3점까지 사거리
  static const double shotClockMax = 14.0;
  static const double catchRadius = 1.2;
  static const double pickupRadius = 0.7;

  // 슛/레이업/블락 상호작용 (공 물리와 무관한 판정 파라미터)
  static const double windupDuration = 0.5; // 슈팅 준비 유지 시간
  static const double layupWindupDuration = 0.3;
  static const double fakeDuration = 0.4;
  static const double blockDuration = 1.0; // 블락 점프 전체 시간
  static const double blockRadius = 1.5; // 블락 반응 거리
  static const double layupRange = 2.3; // 이 거리 안에서는 레이업
  static const double interceptRadius = 0.45; // 패스 인터셉트 몸 판정
  static const double interceptProb = 0.5;

  // 거리별 슛 성공률 곡선: base - falloff*거리, 블락 컨테스트 시 배율 적용
  // (림 근처 ~70%, 미드레인지 ~50%, 3점 ~36% — 실제 농구 근사)
  static const double shotBaseProb = 0.74;
  static const double shotDistFalloff = 0.05;
  static const double shotProbFloor = 0.25;
  static const double contestedMultiplier = 0.45;

  /// 거리·컨테스트에 따른 슛 성공 확률
  static double makeProb(double dist, {required bool contested}) {
    final open =
        (shotBaseProb - shotDistFalloff * dist).clamp(shotProbFloor, 1.0);
    return contested ? open * contestedMultiplier : open;
  }

  final Random _rng;
  final List<SimPlayer> players = [];
  final SimBall ball = SimBall();

  Team offense = Team.home;
  double shotClock = shotClockMax;

  /// 현재 홀더가 공을 잡은 뒤 경과 시간 — 이만큼은 패스하지 않고 버틴다
  double holdTime = 0;
  static const double minHoldBeforePass = 0.4; // 압박(1초/HP) 전에 탈출 가능

  /// 홀더 HP: 수비가 [pressureRadius] 안에 붙어 있으면 1초마다 1씩 깎이고
  /// 0이 되면 그 수비수에게 스틸당한다. 공이 새 홀더에게 갈 때마다 초기화.
  static const int maxHolderHp = 3;
  static const double pressureRadius = 1.0;
  int holderHp = maxHolderHp;
  double _pressureTime = 0;

  /// 진행 중인 슈팅 모션의 길이 (레이업이면 짧음) — 컨테스트 판정에 사용
  double _currentWindup = windupDuration;

  /// 직전 패서 — 핑퐁 방지를 위해 바로 되돌려주는 패스는 금지
  int? lastPasserId;

  /// 직전 슛의 슈터 (점프샷 연출용)
  int? lastShooterId;
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

  // ---------------- 상태 머신 ----------------

  /// 시한부 상태(windup/faking/blocking) 타이머 진행 및 만료 처리
  void _updateTimedStates() {
    for (final p in players) {
      if (p.fakeCooldown > 0) {
        p.fakeCooldown -= dt;
      }
      if (!p.inTimedState) {
        continue;
      }
      p.stateTimer -= dt;
      if (p.stateTimer > 0) {
        continue;
      }
      switch (p.state) {
        case PlayerState.windup:
          if (ball.holderId == p.id) {
            _releaseShot(p);
          }
          p.state = PlayerState.idle;
        case PlayerState.faking:
          p.state = PlayerState.idle;
          // 페이크에 수비가 떴으면 착지 전에 바로 진짜 슛 (오픈 찬스)
          if (ball.holderId == p.id &&
              players.any(
                (d) =>
                    d.team != p.team &&
                    d.state == PlayerState.blocking &&
                    d.pos.distanceTo(p.pos) < blockRadius,
              )) {
            _startWindup(p, p.pos.distanceTo(basketOf(offense)));
          }
        case PlayerState.blocking:
          p.state = PlayerState.idle;
        case PlayerState.rebounding:
          p.state = PlayerState.idle;
        default:
          break;
      }
    }
  }

  /// 시한부 상태가 아닌 선수들의 상태를 상황에서 유도
  void _deriveStates() {
    for (final p in players) {
      if (p.inTimedState) {
        continue;
      }
      p.state = _derivedState(p);
    }
  }

  PlayerState _derivedState(SimPlayer p) {
    if (ball.holderId == p.id) {
      return PlayerState.dribbling;
    }
    if (ball.phase == BallPhase.pass && ball.receiverId == p.id) {
      return PlayerState.receiving;
    }
    if (ball.phase == BallPhase.loose &&
        (ball.looseFor == null || ball.looseFor == p.team) &&
        _looseChaserOf(p.team).id == p.id) {
      return PlayerState.chasing;
    }
    if (p.team == offense) {
      return p.cutTime > 0 ? PlayerState.cutting : PlayerState.moving;
    }
    return PlayerState.defending;
  }

  /// 슈팅 준비(또는 페이크) 모션에 가장 가까운 수비수가 블락 점프로 반응.
  /// 슈터와 림 사이(앞쪽)에 있는 수비수만 반응한다 — 등 뒤 블락은 없다.
  /// 페이크에 낚인 수비수는 점프 후반이라 진짜 슛 릴리즈를 컨테스트 못 한다.
  void _tryBlockReactions() {
    final shooter = holder;
    if (shooter == null ||
        (shooter.state != PlayerState.windup &&
            shooter.state != PlayerState.faking)) {
      return;
    }
    final toBasket = basketOf(offense) - shooter.pos;
    SimPlayer? nearest;
    var nearestDist = double.infinity;
    for (final d in teamOf(
      shooter.team == Team.home ? Team.away : Team.home,
    )) {
      if (d.state != PlayerState.defending) {
        continue;
      }
      // 림과 슈터 사이에 있는 수비수만 (등 뒤에서는 블락 불가)
      if (toBasket.dot(d.pos - shooter.pos) <= 0) {
        continue;
      }
      final dist = d.pos.distanceTo(shooter.pos);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = d;
      }
    }
    if (nearest != null &&
        nearestDist < blockRadius &&
        _rng.nextDouble() < profileOf(nearest).blockProb) {
      nearest.state = PlayerState.blocking;
      nearest.stateTimer = blockDuration;
      lastEvent = 'block:${nearest.id}';
    }
  }

  /// 리바운드 가중치를 적용한 루즈볼 추격자 선정 (PF/C 가 우선)
  SimPlayer _looseChaserOf(Team t) {
    late SimPlayer best;
    var bestScore = double.infinity;
    for (final p in teamOf(t)) {
      final score =
          p.pos.distanceTo(ball.pos) * profileOf(p).reboundWeight;
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return best;
  }

  void tick() {
    lastEvent = null;
    shotClock = max(0, shotClock - dt);

    _updateBallFlight();
    _updateLooseAir();
    _updateTimedStates();
    _deriveStates();
    _tryBlockReactions();
    _movePlayers();

    final h = holder;
    if (h != null && h.state == PlayerState.dribbling) {
      _handlerDecision(h);
    }
    // 이동 후 소유 중이면 공은 핸들러 위치에
    if (ball.phase == BallPhase.held && holder != null) {
      holdTime += dt;
      ball.pos.setFrom(holder!.pos);
      ball.z = 0;
      _applyDefensivePressure(holder!);
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
    // 패스 인터셉트: 공이 수비수 몸(0.45m)과 겹치면 50% 확률로 스틸
    // (수비수당 비행마다 1회만 판정)
    if (ball.phase == BallPhase.pass && u < 1.0) {
      final defense = offense == Team.home ? Team.away : Team.home;
      for (final d in teamOf(defense)) {
        if (ball.interceptTried.contains(d.id) ||
            d.pos.distanceTo(ball.pos) > interceptRadius) {
          continue;
        }
        ball.interceptTried.add(d.id);
        if (_rng.nextDouble() < interceptProb) {
          _giveBallTo(d);
          lastEvent = 'intercept:${d.id}';
          return;
        }
      }
    }
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
      // 인바운드: 골대 뒤 베이스라인에 루즈볼로 떨어뜨려
      // 새 공격팀 선수가 걸어가서 줍는다 (순간이동 방지)
      final baselineX = ball.to.x < CourtDims.length / 2 ? 0.4 : CourtDims.length - 0.4;
      _dropLooseAt(
        Vector2(baselineX, CourtDims.centerY + (_rng.nextDouble() - 0.5) * 4),
        forTeam: offense,
      );
    } else {
      lastEvent = 'miss';
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = 1.0 + _rng.nextDouble() * 2.0;
      final rim = ball.to.clone();
      final spot = ball.to + Vector2(cos(angle), sin(angle)) * dist;
      // 림에서 튕겨 공중으로 — 낙하 동안 리바운드 점프 경쟁이 벌어진다
      _dropLooseAt(spot, bounceFrom: rim);
    }
  }

  void _dropLooseAt(Vector2 spot, {Team? forTeam, Vector2? bounceFrom}) {
    ball.phase = BallPhase.loose;
    ball.holderId = null;
    ball.receiverId = null;
    ball.looseFor = forTeam;
    if (bounceFrom != null) {
      // 림 높이에서 리바운드 지점으로 포물선 낙하 (0.55초)
      ball.from.setFrom(bounceFrom);
      ball.to.setFrom(_clampToCourt(spot));
      ball.flightTime = 0;
      ball.flightDuration = 0.55;
      ball.pos.setFrom(bounceFrom);
      ball.z = CourtDims.rimHeight;
      return;
    }
    ball.flightTime = 0;
    ball.flightDuration = 0;
    ball.pos.setFrom(_clampToCourt(spot));
    ball.z = 0;
  }

  /// 루즈볼이 아직 공중에 떠 있는가 (림 리바운드 낙하 중)
  bool get looseAirborne =>
      ball.phase == BallPhase.loose && ball.z > 0.05;

  /// 리바운드 낙하 진행 — 림에서 튕긴 공이 포물선으로 떨어진다
  void _updateLooseAir() {
    if (ball.phase != BallPhase.loose ||
        ball.flightTime >= ball.flightDuration) {
      return;
    }
    ball.flightTime += dt;
    final u = min(1.0, ball.flightTime / ball.flightDuration);
    ball.pos
      ..setFrom(ball.to)
      ..sub(ball.from)
      ..scale(u)
      ..add(ball.from);
    ball.z = (1 - u) * CourtDims.rimHeight + sin(pi * u) * 0.4;
    if (u >= 1.0) {
      ball.z = 0;
    }
  }

  /// 점프해서 공을 잡을 수 있는 최대 높이
  static const double reboundReach = 2.5;

  /// 리바운드 점프 지속 시간 (렌더 점프 곡선과 공유)
  static const double reboundJumpDuration = 0.5;

  void _tryPickup() {
    // 너무 높이 떠 있으면 아직 아무도 못 잡는다
    if (ball.z > reboundReach) {
      return;
    }
    final airborne = ball.z > 0.3;
    final candidates =
        ball.looseFor == null ? players : teamOf(ball.looseFor!).toList();
    final nearest = _nearestOf(candidates, ball.pos);
    final grabRadius = airborne ? 0.9 : pickupRadius;
    if (nearest.pos.distanceTo(ball.pos) > grabRadius) {
      return;
    }
    if (airborne) {
      // 리바운드 점프로 공중에서 낚아챈다 — 착지 동안 잠깐 멈춘다
      nearest.state = PlayerState.rebounding;
      nearest.stateTimer = reboundJumpDuration;
      // 경합하던 근처 선수들도 같이 뛰어오른다
      for (final other in players) {
        if (other.id != nearest.id &&
            !other.inTimedState &&
            other.pos.distanceTo(ball.pos) < 1.3) {
          other.state = PlayerState.rebounding;
          other.stateTimer = reboundJumpDuration;
        }
      }
    }
    final wasOffense = offense;
    _giveBallTo(nearest);
    lastEvent = airborne ? 'rebound:${nearest.id}' : 'pickup:${nearest.id}';
    if (nearest.team != wasOffense) {
      _switchOffense(to: nearest.team);
      lastEvent = 'turnover';
    } else {
      shotClock = shotClockMax; // 공격 리바운드도 리셋 (단순화)
    }
  }

  /// 수비 압박: 홀더가 드리블 중 + '수비중' 상태의 수비수가 붙어 있는 동안
  /// 1초마다 HP 1 감소, 0이면 스틸
  void _applyDefensivePressure(SimPlayer h) {
    if (h.state != PlayerState.dribbling) {
      _pressureTime = 0;
      return;
    }
    SimPlayer? defender;
    var defenderDist = double.infinity;
    for (final d in teamOf(h.team == Team.home ? Team.away : Team.home)) {
      if (d.state != PlayerState.defending) {
        continue;
      }
      final dist = d.pos.distanceTo(h.pos);
      if (dist < defenderDist) {
        defenderDist = dist;
        defender = d;
      }
    }
    if (defender == null || defenderDist > pressureRadius) {
      _pressureTime = 0;
      return;
    }
    _pressureTime += dt;
    if (_pressureTime < 1.0) {
      return;
    }
    _pressureTime -= 1.0;
    holderHp--;
    if (holderHp > 0) {
      lastEvent = 'pressure:$holderHp';
      return;
    }
    _giveBallTo(defender);
    lastEvent = 'steal:${defender.id}';
  }

  void _giveBallTo(SimPlayer p) {
    ball.holderId = p.id;
    ball.receiverId = null;
    ball.looseFor = null;
    holdTime = 0;
    holderHp = maxHolderHp;
    _pressureTime = 0;
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
    lastPasserId = null;
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

    // 샷클락 임박: 릴리즈까지 걸리는 시간을 감안해 강제 슈팅 모션
    if (shotClock <= 0.8) {
      _startWindup(h, distToBasket);
      return;
    }
    // HP 마지막 칸: 골밑 근처면 뺏기느니 쏜다 (필사 슛).
    // 멀면 무리슛 대신 리트리트/패스로 버틴다 — 가끔은 스틸당한다.
    if (holderHp <= 1 && distToBasket < 5.5) {
      _startWindup(h, distToBasket);
      return;
    }
    final profile = profileOf(h);
    // 림 근처: 레이업 적극 시도 (빅맨일수록 적극)
    if (distToBasket <= layupRange &&
        _rng.nextDouble() < profile.layupChance) {
      _startWindup(h, distToBasket);
      return;
    }
    // 드라이브&킥: 수비가 2명 이상 붙으면 오픈 동료에게 킥아웃
    final collapsers = teamOf(offense == Team.home ? Team.away : Team.home)
        .where((d) => d.pos.distanceTo(h.pos) < 1.8)
        .length;
    if (collapsers >= 2 &&
        holdTime >= minHoldBeforePass &&
        _rng.nextDouble() < 0.3) {
      _pass(h);
      return;
    }
    // 슛 셀렉션: 오픈이면 적극적으로 쏘고(캐치&슛),
    // 밀착당했으면 무리슛 대신 페이크로 공간을 만든다.
    // 포지션 성향: SG 는 자주 쏘고, PG 는 아끼고, 빅맨은 사거리 제한.
    if (distToBasket < shootRange && distToBasket <= profile.maxShotDist) {
      if (pressure > 1.5 &&
          _rng.nextDouble() < 0.45 * profile.shootMul) {
        _startWindup(h, distToBasket); // 오픈 슛
        return;
      }
      if (pressure > 1.0 &&
          _rng.nextDouble() < 0.08 * profile.shootMul) {
        _startWindup(h, distToBasket); // 세미오픈
        return;
      }
      if (pressure <= blockRadius &&
          h.fakeCooldown <= 0 &&
          _rng.nextDouble() < 0.15) {
        _startFake(h); // 밀착 — 페이크로 수비를 띄운다
        return;
      }
    }
    // 잡은 직후에는 패스하지 않는다 (핑퐁 방지)
    if (holdTime < minHoldBeforePass) {
      return;
    }
    // 압박당하면(HP 깎이는 중) 적극적으로 탈출 패스, 아니어도 종종 볼 순환.
    // PG 는 배급 역할이라 더 자주 돌리고, HP 가 깎일수록 급해진다.
    final hpUrgency = 1.0 + (maxHolderHp - holderHp) * 0.8;
    if (pressure < pressureRadius &&
        _rng.nextDouble() <
            (0.4 * profile.passMul * hpUrgency).clamp(0.0, 0.95)) {
      _pass(h);
    } else if (_rng.nextDouble() <
        (0.05 * profile.passMul * hpUrgency).clamp(0.0, 0.5)) {
      _pass(h);
    }
  }

  /// 슈팅 준비 모션 시작 (레이업은 더 짧은 모션)
  void _startWindup(SimPlayer h, double distToBasket) {
    _currentWindup = distToBasket <= layupRange
        ? layupWindupDuration
        : windupDuration;
    h.state = PlayerState.windup;
    h.stateTimer = _currentWindup;
    lastEvent = 'windup:${h.id}';
  }

  void _startFake(SimPlayer h) {
    h.state = PlayerState.faking;
    h.stateTimer = fakeDuration;
    h.fakeCooldown = 2.5;
    lastEvent = 'fake:${h.id}';
  }

  /// windup 종료 시점의 실제 릴리즈. 이번 모션 중에 뛴 블락만 컨테스트로 친다.
  void _releaseShot(SimPlayer h) {
    final basket = basketOf(offense);
    final dist = h.pos.distanceTo(basket);
    // 이번 모션 중에 뛴, 슈터와 림 사이의 블락만 컨테스트로 친다
    final contested = players.any(
      (d) =>
          d.team != h.team &&
          d.state == PlayerState.blocking &&
          d.stateTimer >= blockDuration - _currentWindup &&
          d.pos.distanceTo(h.pos) < blockRadius &&
          (basket - h.pos).dot(d.pos - h.pos) > 0,
    );
    final layup = dist <= layupRange;
    ball.from.setFrom(h.pos);
    ball.to.setFrom(basket);
    ball.flightTime = 0;
    ball.flightDuration = max(0.9, dist / shotSpeed);
    ball.arcPeak = 1.0 + dist * 0.15;
    ball.shotWillScore =
        _rng.nextDouble() < makeProb(dist, contested: contested);
    ball.shotValue = dist > CourtDims.threeRadius ? 3 : 2;
    lastPasserId = null;
    lastShooterId = h.id;
    ball.holderId = null;
    ball.phase = BallPhase.shot;
    final kind = layup ? 'layup' : 'shot';
    lastEvent = '$kind:${ball.shotValue}${contested ? ':c' : ''}';
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
      // 방금 나에게 패스한 선수에게 곧장 되돌려주지 않는다
      if (mate.id == lastPasserId) {
        continue;
      }
      // 패스 레인 중간에 수비수 몸이 걸리면 인터셉트 위험 — 그 레인은 버린다.
      // 패서 바로 옆(t<=0.15) 수비수는 릴리즈로 제칠 수 있으므로 제외.
      var laneRisky = false;
      final ab = mate.pos - h.pos;
      final len2 = ab.length2;
      for (final d in defenders) {
        if (len2 < 1e-9) {
          break;
        }
        final t = ((d.pos - h.pos).dot(ab) / len2).clamp(0.0, 1.0);
        if (t <= 0.15) {
          continue;
        }
        if (d.pos.distanceTo(h.pos + ab * t) < 0.55) {
          laneRisky = true;
          break;
        }
      }
      if (laneRisky) {
        continue;
      }
      final openness = defenders
          .map((d) => d.pos.distanceTo(mate.pos))
          .reduce(min);
      // 롱패스일수록 수비가 궤적에 뛰어들 시간이 길다 —
      // 패스 거리에 비례한 분리(오픈) 요구치를 못 넘기면 그 패스는 버린다
      final passDist = h.pos.distanceTo(mate.pos);
      if (openness < 0.75 + 0.11 * passDist) {
        continue;
      }
      // 오픈 정도 우선 + 골대에 가까울수록 약간 가산.
      // 백코트(볼 운반 구간)에서는 PG 에게 우선적으로 맡긴다.
      final pgCarryBonus = h.pos.distanceTo(basket) > 14 &&
              mate.position == CourtPosition.pointGuard
          ? 3.0
          : 0.0;
      // 포스트 엔트리: 골밑에서 오픈된 빅맨에게 우선 투입 (레이업 찬스)
      final postEntryBonus =
          profileOf(mate).crashesBoards && mate.pos.distanceTo(basket) < 5
              ? 1.2
              : 0.0;
      final score = openness -
          mate.pos.distanceTo(basket) * 0.15 +
          pgCarryBonus +
          postEntryBonus;
      if (score > bestScore) {
        bestScore = score;
        best = mate;
      }
    }
    if (best == null) {
      return;
    }
    ball.from.setFrom(h.pos);
    // 리드 패스: 리시버의 수비수 반대쪽으로 공간을 주고 던진다
    final bestDefender = _nearestOf(defenders, best.pos);
    final lead = best.pos - bestDefender.pos;
    final target = lead.length > 1e-6
        ? _clampToCourt(best.pos + lead.normalized().scaled(1.2))
        : best.pos.clone();
    ball.to.setFrom(target);
    ball.flightTime = 0;
    ball.flightDuration = max(0.4, h.pos.distanceTo(target) / passSpeed);
    ball.arcPeak = 0.5;
    ball.receiverId = best.id;
    ball.interceptTried.clear();
    lastPasserId = h.id;
    ball.holderId = null;
    ball.phase = BallPhase.pass;
    lastEvent = 'pass:${best.id}';
  }

  // ---------------- 이동 ----------------

  /// 포지션별 역할 프로파일 (앵커·성향).
  /// PG: 탑에서 볼 운반·배급 / SG: 3점 라인 오픈 이동 /
  /// SF: 미드레인지에서 수비 흔들기 / PF·C: 골밑·리바운드.
  static const Map<CourtPosition, PositionProfile> positionProfiles = {
    CourtPosition.pointGuard: PositionProfile(
      anchor: (8.7, 7.5), // 탑
      shootMul: 0.7,
      passMul: 1.6,
      cutChance: 0.012,
      reboundWeight: 1.15,
      blockProb: 0.25,
    ),
    CourtPosition.shootingGuard: PositionProfile(
      anchor: (7.3, 3.0), // 윙 3점
      shootMul: 1.3,
      passMul: 0.9,
      cutChance: 0.015,
      reboundWeight: 1.1,
      blockProb: 0.25,
      arcRelocate: true,
      wanderIntervalMin: 0.8,
      wanderIntervalMax: 2.0,
    ),
    CourtPosition.smallForward: PositionProfile(
      anchor: (5.0, 12.0), // 미드레인지 윙
      shootMul: 1.1,
      maxShotDist: 6.6,
      cutChance: 0.05,
      wanderIntervalMin: 1.0,
      wanderIntervalMax: 2.5,
    ),
    CourtPosition.powerForward: PositionProfile(
      anchor: (1.5, 4.2), // 덩커 스팟
      shootMul: 0.9,
      layupChance: 0.4,
      maxShotDist: 5.0,
      cutChance: 0.04,
      reboundWeight: 0.8,
      blockProb: 0.45,
      crashesBoards: true,
    ),
    CourtPosition.center: PositionProfile(
      anchor: (1.5, 10.8), // 로우포스트
      shootMul: 0.8,
      layupChance: 0.45,
      maxShotDist: 4.2,
      cutChance: 0.035,
      reboundWeight: 0.7,
      blockProb: 0.5,
      defenseStandoff: 1.5, // 드롭 커버리지
      crashesBoards: true,
    ),
  };

  PositionProfile profileOf(SimPlayer p) => positionProfiles[p.position]!;

  /// 오프볼 공격수의 배회/컷 상태 갱신 (매 틱, 시드 RNG)
  void _updateOffBallState() {
    for (final p in players) {
      final offBallOffense = p.team == offense && ball.holderId != p.id;
      if (!offBallOffense) {
        p.cutTime = 0;
        continue;
      }
      // 앵커 주변 배회 지점을 주기적으로 재추첨 (주기·컷은 포지션 성향)
      final profile = profileOf(p);
      p.wanderTimer -= dt;
      if (p.wanderTimer <= 0) {
        p.wanderTimer = profile.wanderIntervalMin +
            _rng.nextDouble() *
                (profile.wanderIntervalMax - profile.wanderIntervalMin);
        final angle = _rng.nextDouble() * 2 * pi;
        final radius = 0.5 + _rng.nextDouble() * 1.8;
        p.wander.setValues(cos(angle) * radius, sin(angle) * radius);
      }
      // V-컷 저크: 밀착 마크당하면 즉시 급격한 방향 전환으로 분리 창출
      // (수비는 0.4초 반응 지연이 있어 이 순간 오픈이 된다)
      final closestDef = _nearestOf(
        teamOf(p.team == Team.home ? Team.away : Team.home),
        p.pos,
      );
      if (closestDef.pos.distanceTo(p.pos) < 0.9 && p.wanderTimer > 0.6) {
        p.wanderTimer = 0.5 + _rng.nextDouble() * 0.6;
        final angle = _rng.nextDouble() * 2 * pi;
        final radius = 2.0 + _rng.nextDouble() * 2.0;
        p.wander.setValues(cos(angle) * radius, sin(angle) * radius);
      }
      // 골밑 컷: 쿨다운이 돌면 낮은 확률로 발동
      if (p.cutTime > 0) {
        p.cutTime -= dt;
      } else {
        p.cutCooldown -= dt;
        if (p.cutCooldown <= 0 && _rng.nextDouble() < profile.cutChance) {
          p.cutTime = 1.6;
          p.cutCooldown = 4 + _rng.nextDouble() * 5;
        }
      }
    }
  }

  void _movePlayers() {
    _updateOffBallState();
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
    // 슈팅 모션/페이크/블락 점프 중에는 제자리
    if (p.inTimedState) {
      return p.pos.clone();
    }
    // 패스 받을 사람은 캐치 지점으로
    if (ball.phase == BallPhase.pass && ball.receiverId == p.id) {
      return ball.to.clone();
    }
    // 루즈볼: 리바운드 가중치(PF/C 우선)로 뽑힌 선수가 공으로.
    // 공중에 떠 있으면 낙하 지점으로 미리 달려간다
    if (ball.phase == BallPhase.loose &&
        (ball.looseFor == null || ball.looseFor == p.team)) {
      if (_looseChaserOf(p.team).id == p.id) {
        return looseAirborne ? ball.to.clone() : ball.pos.clone();
      }
    }
    // 슛이 뜨거나 리바운드가 공중에 있으면 PF/C 는 양팀 모두
    // 림으로 리바운드 진입 (박스아웃 자리)
    if ((ball.phase == BallPhase.shot || looseAirborne) &&
        profileOf(p).crashesBoards) {
      final rim = basketOf(offense);
      final toCenter = rim.x < CourtDims.length / 2 ? 1.0 : -1.0;
      final side = p.position == CourtPosition.center ? 1.0 : -1.0;
      return _clampToCourt(
        Vector2(rim.x + toCenter * 1.4, rim.y + side * 1.2),
      );
    }
    // 패스 비행 중, 리시버 근처의 수비수는 공 궤적 위로 뛰어들어
    // 인터셉트를 노린다 (롱패스일수록 도달 시간이 길어 위험해짐)
    if (ball.phase == BallPhase.pass &&
        p.team != offense &&
        ball.receiverId != null &&
        p.pos.distanceTo(players[ball.receiverId!].pos) < 2.5) {
      final ab = ball.to - ball.pos;
      final len2 = ab.length2;
      if (len2 > 1e-9) {
        final t = ((p.pos - ball.pos).dot(ab) / len2).clamp(0.0, 1.0);
        return ball.pos + ab * t;
      }
      return ball.pos.clone();
    }
    if (p.team == offense) {
      if (ball.holderId == p.id) {
        final defender = _nearestOf(
          teamOf(p.team == Team.home ? Team.away : Team.home),
          p.pos,
        );
        final toDefender = defender.pos - p.pos;
        // HP 마지막 칸이면 리트리트 드리블로 스틸 회피 시도
        if (holderHp <= 1 &&
            toDefender.length < 1.3 &&
            toDefender.length > 1e-6) {
          return _clampToCourt(p.pos - toDefender.normalized().scaled(2.5));
        }
        // 크로스오버 돌파: 수비가 돌파 경로를 막고 있으면 사선으로 제친다
        // (수비 반응 지연 0.4초 동안 블로바이 창이 열린다)
        final basket = basketOf(offense);
        final toBasket = basket - p.pos;
        if (toDefender.length < 1.2 &&
            toBasket.length > layupRange &&
            toDefender.dot(toBasket) > 0) {
          final cross =
              toBasket.x * toDefender.y - toBasket.y * toDefender.x;
          final dir = toBasket.normalized();
          final perp = cross >= 0
              ? Vector2(dir.y, -dir.x) // 수비 반대측으로
              : Vector2(-dir.y, dir.x);
          return _clampToCourt(p.pos + dir.scaled(1.2) + perp.scaled(1.6));
        }
        return basket;
      }
      if (p.cutTime > 0) {
        // 골밑 컷: 림 방향으로 파고들기 (선수마다 살짝 다른 각도)
        final basket = basketOf(offense);
        return Vector2(
          basket.x,
          (basket.y + (p.id % 5 - 2) * 1.2)
              .clamp(1.0, CourtDims.width - 1.0),
        );
      }
      // 수비를 떨어뜨리는 방향으로 도망치며 오픈 만들기
      final target = _anchorFor(p)..add(p.wander);
      final defender = _nearestOf(
        teamOf(p.team == Team.home ? Team.away : Team.home),
        p.pos,
      );
      final defDist = defender.pos.distanceTo(p.pos);
      if (defDist < 2.0) {
        final escape = p.pos - defender.pos;
        if (escape.length > 1e-6) {
          target.add(escape.normalized()..scale(2.0 - defDist));
        }
      }
      // SG: 항상 3점 라인 근처에 머문다 — 목표 지점을 아크 반경으로 보정
      if (profileOf(p).arcRelocate) {
        final basket = basketOf(offense);
        final radial = target - basket;
        if (radial.length > 1e-6) {
          final clamped = radial.length.clamp(6.9, 7.6);
          return _clampToCourt(basket + radial.normalized().scaled(clamped));
        }
      }
      return target;
    }
    return _defenseTargetFor(p);
  }

  Vector2 _anchorFor(SimPlayer p) {
    final (u, y) = profileOf(p).anchor;
    final x = offense == Team.home ? CourtDims.length - u : u;
    return Vector2(x, y);
  }

  /// 수비 반응 지연 시간 — 이 간격으로만 마크 위치를 갱신해 쫓는다.
  /// 공격의 방향 전환/컷이 실제 분리를 만드는 근거.
  static const double defenseReactionDelay = 0.3;

  Vector2 _defenseTargetFor(SimPlayer p) {
    final mark = players.firstWhere(
      (o) => o.team != p.team && o.id % 5 == p.id % 5,
    );
    // 지연된 인식: 0.3초마다만 마크의 실제 위치를 확인
    p.markSnapTimer -= dt;
    if (p.markSnapTimer <= 0) {
      p.markSnapTimer = defenseReactionDelay;
      p.perceivedMarkPos.setFrom(mark.pos);
    }
    final markPos = p.perceivedMarkPos;
    final basket = basketOf(offense);
    // 하프코트 디펜스: 마크가 백코트에 있으면 풀코트 프레스 대신
    // 자기 진영으로 물러나 마크가 오는 길목에서 대기한다
    final markToBasket = markPos.distanceTo(basket);
    if (markToBasket > 13) {
      final dir = markPos - basket;
      if (dir.length > 1e-6) {
        return _clampToCourt(basket + dir.normalized().scaled(11));
      }
    }
    final toBasket = basket - markPos;
    final len = toBasket.length;
    if (len < 1e-6) {
      return markPos.clone();
    }
    // 항상 마크와 림 사이에 선다. 볼 핸들러 마크는 바짝(압박),
    // 오프볼은 포지션 성향대로 (C 는 드롭 커버리지로 골밑 사그)
    final standOff = ball.holderId == mark.id
        ? 0.45
        : profileOf(p).defenseStandoff;
    return markPos + toBasket.scaled(standOff / len);
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
