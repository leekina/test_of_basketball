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

/// 지역방어 대형
enum ZoneScheme { twoThree, threeTwo }

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
  bodyChecking, // 몸통박치기 (드리블러 접촉 시 HP 깎는 모션)
  driving, // 림을 향한 드라이브 (1.1배 가속, 도착하면 레이업)
  screening, // 스크린 세팅 (제자리 — 부딪힌 상대 수비는 스턴)
  stunned, // 스턴 (1초 제자리 고정 — 스크린/리바운드 패배/스틸·블락 피해)
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
  double checkCooldown = 0; // 몸통박치기 쿨타임
  double driveTime = 0; // 드라이브 잔여 시간 (홀더 전용)
  bool layupMotion = false; // 현재 windup 이 레이업(활공)인가
  double stunImmunity = 0; // 스턴 직후 재스턴 방지

  bool get inTimedState =>
      (state == PlayerState.windup ||
          state == PlayerState.faking ||
          state == PlayerState.blocking ||
          state == PlayerState.rebounding ||
          state == PlayerState.bodyChecking ||
          state == PlayerState.screening ||
          state == PlayerState.stunned) &&
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
    // 팁오프 대형: 양팀 C 가 센터서클, 나머지는 자기 진영
    const homeSpots = [(10.0, 7.5), (8.0, 3.5), (8.0, 11.5), (5.0, 5.5), (13.2, 7.5)];
    for (var i = 0; i < 5; i++) {
      final (x, y) = homeSpots[i];
      players.add(SimPlayer(i, Team.home, x, y));
    }
    for (var i = 0; i < 5; i++) {
      final (x, y) = homeSpots[i];
      players.add(SimPlayer(5 + i, Team.away, CourtDims.length - x, y));
    }
    assert(
      players.every((p) => players[p.id] == p),
      'players 리스트는 index == id 여야 한다',
    );
    // 팁오프: 센터서클에서 공을 띄우고 리바운드 경쟁으로 첫 소유 결정
    _dropLooseAt(
      Vector2(
        CourtDims.length / 2 + (_rng.nextDouble() - 0.5) * 1.2,
        CourtDims.centerY + (_rng.nextDouble() - 0.5) * 1.2,
      ),
      bounceFrom: Vector2(CourtDims.length / 2, CourtDims.centerY),
    );
  }

  /// 시뮬레이션 틱 간격 (초) — 10 tick/s
  static const double dt = 0.1;

  static const double playerSpeed = 2.6;
  static const double dribbleSpeedFactor = 0.8; // 볼 소유 시 이동속도 배율
  static const double passSpeed = 7.0;
  static const double shotSpeed = 5.0;
  static const double shootRange = 7.4; // 윙/탑 3점까지 사거리
  static const double shotClockMax = 14.0;
  static const double catchRadius = 1.2;
  static const double pickupRadius = 0.7;
  static const double heldBallHeight = 1.2; // 소유 중 공 높이 (몸쪽)
  static const double shotReleaseHeight = 1.8; // 슛 릴리즈 높이

  // 슛/레이업/블락 상호작용 (공 물리와 무관한 판정 파라미터)
  static const double windupDuration = 0.7; // 슈팅 준비 유지 시간
  static const double layupWindupDuration = 0.45;
  static const double fakeDuration = 0.4;
  static const double blockDuration = 1.0; // 블락 점프 전체 시간
  static const double blockRadius = 1.5; // 블락 반응 거리
  static const double layupRange = 2.3; // 이 거리 안에서는 레이업
  static const double interceptRadius = 0.45; // 패스 인터셉트 몸 판정
  static const double interceptProb = 0.5;

  // 거리별 슛 성공률 곡선: base - falloff*거리, 블락 컨테스트 시 배율 적용
  // (림 근처 ~70%, 미드레인지 ~50%, 3점 ~36% — 실제 농구 근사)
  static const double shotBaseProb = 0.78;
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
  static const double minHoldBeforePass = 0.6; // 압박(1초/HP) 전에 탈출 가능

  /// 홀더 HP: 수비가 [pressureRadius] 안에 붙어 있으면 1초마다 1씩 깎이고
  /// 0이 되면 그 수비수에게 스틸당한다. 공이 새 홀더에게 갈 때마다 초기화.
  static const int maxHolderHp = 3;
  static const double pressureRadius = 1.0;
  int holderHp = maxHolderHp;

  // 몸통박치기 파라미터
  static const double bodyCheckRadius = 0.75; // 접촉 판정 거리
  static const double bodyCheckCooldown = 1.0; // 수비수별 쿨타임
  static const double bodyCheckDuration = 0.35; // 박치기 모션/경직 시간

  /// 더블팀: 홀더 근처(2.5m)에 수비수가 둘이면 확률적으로 두 번째
  /// 수비수가 존을 버리고 협공에 가담한다
  int? doubleTeamerId;
  double _doubleTeamTime = 0;

  /// 현재 doubleTeamerId 가 협공(더블팀)이 아니라 헬프 디펜스인가
  bool doubleTeamIsHelp = false;
  static const double doubleTeamRadius = 2.5;
  static const double doubleTeamDuration = 1.6;

  // 스턴: 스크린 충돌 / 리바운드 경합 패배 / 스틸·블락 피해 시 1초 고정
  static const double stunDuration = 1.0;
  static const double stunImmunityDuration = 2.0;

  // 스크린 플레이 (픽앤롤 / 핀다운)
  int? screenerId; // 스크린 세터
  int? screenTargetId; // 스크린 수혜자 (온볼=홀더, 핀다운=SG)
  bool screenSet = false; // 세터가 자리를 잡았는가
  bool _screenOnBall = true;
  double _screenTime = 0; // 세팅 유지 잔여 시간
  double _screenCooldown = 3.0;

  // 속공: 라이브볼 턴오버 직후 몇 초간 발동
  double fastBreakTime = 0;
  static const double fastBreakDuration = 4.0;

  // 클로즈아웃: 오픈 캐치에 가장 가까운 수비수가 달려나간다
  int? closeoutId;
  double _closeoutTime = 0;

  // 마지막으로 공을 만진 팀 (아웃오브바운드 소유권 판정)
  Team lastTouchTeam = Team.home;

  // 득점 후 인바운드 시퀀스
  static const double netDropDuration = 1.0; // 림 통과 낙하 모션
  double _netDropTime = 0;
  int? inbounderId; // 공 주우러 가는 선수 (골대 최근접)
  int? inboundReceiverId; // 4~5m 에서 받아주는 선수 (2순위)
  final Vector2 _inboundSpot = Vector2.zero();

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

  /// 디버그/UI 표시용 getter
  double get netDropTime => _netDropTime;
  double get doubleTeamTime => _doubleTeamTime;
  double get closeoutTime => _closeoutTime;

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
      if (p.stunImmunity > 0) {
        p.stunImmunity -= dt;
      }
      if (p.checkCooldown > 0) {
        p.checkCooldown -= dt;
      }
      if (p.driveTime > 0) {
        p.driveTime -= dt;
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
        case PlayerState.blocking:
          p.state = PlayerState.idle;
        case PlayerState.rebounding:
          p.state = PlayerState.idle;
        case PlayerState.bodyChecking:
          p.state = PlayerState.idle;
        case PlayerState.screening:
          p.state = PlayerState.idle;
        case PlayerState.stunned:
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
      if (p.driveTime > 0) {
        return PlayerState.driving;
      }
      return PlayerState.dribbling;
    }
    p.driveTime = 0; // 공을 놓으면 드라이브 해제
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
    // 0.7 배: 슈팅 모션이 길어진 만큼(0.5→0.7초) 틱당 확률을 정규화
    if (nearest != null &&
        nearestDist < blockRadius &&
        _rng.nextDouble() < profileOf(nearest).blockProb * 0.7) {
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
    _updateNetDrop();
    _updateLooseAir();
    _updateTimedStates();
    _deriveStates();
    _tryBlockReactions();
    _updateDoubleTeam();
    _updateScreenPlay();
    if (fastBreakTime > 0) {
      fastBreakTime -= dt;
    }
    if (_closeoutTime > 0) {
      _closeoutTime -= dt;
      if (_closeoutTime <= 0) {
        closeoutId = null;
      }
    }
    _movePlayers();

    final h = holder;
    if (h != null &&
        (h.state == PlayerState.dribbling ||
            h.state == PlayerState.driving)) {
      _handlerDecision(h);
    }
    // 박치기(넉백 포함) 처리 후, 여전히 소유 중이면 공은 핸들러 위치에
    if (ball.phase == BallPhase.held && holder != null) {
      holdTime += dt;
      _applyDefensivePressure(holder!);
      if (ball.phase == BallPhase.held && holder != null) {
        ball.pos.setFrom(holder!.pos);
        ball.z = heldBallHeight; // 몸 높이 — 릴리즈 순간 바닥 출발 방지
      }
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
        ? _lerpDouble(shotReleaseHeight, CourtDims.rimHeight, u)
        : heldBallHeight;
    ball.z = baseZ + 4 * ball.arcPeak * u * (1 - u);
    // 리시버가 마중 나와 조기 캐치 — 수비가 레인에 닿기 전에 받는다
    if (ball.phase == BallPhase.pass && u < 1.0 && ball.z < 2.2) {
      final receiver = players[ball.receiverId!];
      if (receiver.pos.distanceTo(ball.pos) <= 1.0) {
        _giveBallTo(receiver);
        return;
      }
    }
    // 패스 인터셉트: 공이 수비수 몸(0.45m)과 겹치면 50% 확률로 스틸
    // (수비수당 비행마다 1회만 판정). 점프 리치보다 높이 나는 로브는
    // 몸에 닿지 않으므로 스틸 불가.
    if (ball.phase == BallPhase.pass && u < 1.0 && ball.z < 2.2) {
      final defense = offense == Team.home ? Team.away : Team.home;
      for (final d in teamOf(defense)) {
        if (ball.interceptTried.contains(d.id) ||
            d.pos.distanceTo(ball.pos) > interceptRadius) {
          continue;
        }
        ball.interceptTried.add(d.id);
        if (_rng.nextDouble() < interceptProb) {
          _giveBallTo(d);
          fastBreakTime = fastBreakDuration; // 인터셉트 → 속공
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
      final rim = ball.to.clone();
      _switchOffense();
      // 득점 시퀀스: ① 공이 림을 통과해 1초 동안 떨어지고
      // ② 림 좌측 라인 바로 밖에 공이 놓이면 ③ 최근접이 주워
      // ④ 4~5m 근처로 온 두 번째 선수에게 인바운드 패스로 재개.
      // 그동안 양팀 나머지는 존/앵커를 따라 각자 진영으로 복귀한다.
      ball.phase = BallPhase.loose;
      ball.holderId = null;
      ball.receiverId = null;
      ball.looseFor = offense;
      ball.flightTime = 0;
      ball.flightDuration = 0;
      ball.pos.setFrom(rim);
      ball.z = CourtDims.rimHeight;
      _netDropTime = netDropDuration;
      final sorted = teamOf(offense).toList()
        ..sort(
          (a, b) => a.pos.distanceTo(rim).compareTo(b.pos.distanceTo(rim)),
        );
      inbounderId = sorted[0].id;
      inboundReceiverId = sorted[1].id;
      final outX = rim.x < CourtDims.length / 2 ? -0.35 : CourtDims.length + 0.35;
      _inboundSpot.setValues(outX, CourtDims.centerY - 2.5); // 림 좌측 라인 밖
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
      // 착지점은 클램프하지 않는다 — 라인을 넘으면 아웃오브바운드
      ball.from.setFrom(bounceFrom);
      ball.to.setFrom(spot);
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

  /// 득점 후 림 통과 낙하 모션 (1초) — 끝나면 라인 밖 인바운드 스팟으로
  void _updateNetDrop() {
    if (_netDropTime <= 0) {
      return;
    }
    _netDropTime -= dt;
    ball.z = max(
      0,
      CourtDims.rimHeight * (_netDropTime / netDropDuration),
    );
    if (_netDropTime <= 0) {
      ball.pos.setFrom(_inboundSpot); // 라인 바로 밖에 공 놓기
      ball.z = 0;
    }
  }

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
      _checkOutOfBounds();
    }
  }

  /// 루즈볼이 라인을 넘었으면 마지막 터치 상대팀의 스로인으로 재개
  void _checkOutOfBounds() {
    final pos = ball.pos;
    final out = pos.x < 0 ||
        pos.x > CourtDims.length ||
        pos.y < 0 ||
        pos.y > CourtDims.width;
    if (!out || inbounderId != null) {
      return;
    }
    final award =
        lastTouchTeam == Team.home ? Team.away : Team.home;
    lastEvent = 'outofbounds:${award.name}';
    if (award != offense) {
      _switchOffense(to: award);
    }
    // 스로인 지점: 넘어간 라인 바로 밖
    final sx = pos.x < 0
        ? -0.35
        : pos.x > CourtDims.length
            ? CourtDims.length + 0.35
            : pos.x.clamp(0.5, CourtDims.length - 0.5);
    final sy = pos.x < 0 || pos.x > CourtDims.length
        ? pos.y.clamp(0.5, CourtDims.width - 0.5)
        : (pos.y < 0 ? -0.35 : CourtDims.width + 0.35);
    _inboundSpot.setValues(sx.toDouble(), sy.toDouble());
    ball.pos.setFrom(_inboundSpot);
    ball.z = 0;
    ball.looseFor = award;
    final sorted = teamOf(award).toList()
      ..sort(
        (a, b) => a.pos
            .distanceTo(_inboundSpot)
            .compareTo(b.pos.distanceTo(_inboundSpot)),
      );
    inbounderId = sorted[0].id;
    inboundReceiverId = sorted[1].id;
  }

  /// 점프해서 공을 잡을 수 있는 최대 높이
  static const double reboundReach = 2.5;

  /// 리바운드 점프 지속 시간 (렌더 점프 곡선과 공유)
  static const double reboundJumpDuration = 0.5;

  void _tryPickup() {
    // 림 통과 낙하 연출 중에는 잡을 수 없다
    if (_netDropTime > 0) {
      return;
    }
    // 너무 높이 떠 있으면 아직 아무도 못 잡는다
    if (ball.z > reboundReach) {
      return;
    }
    final airborne = ball.z > 0.3;
    // 인바운드 상황: 지정된 인바운더만 주울 수 있다
    final candidates = inbounderId != null
        ? [players[inbounderId!]]
        : ball.looseFor == null
            ? players
            : teamOf(ball.looseFor!).toList();
    final nearest = _nearestOf(candidates, ball.pos);
    final grabRadius = airborne ? 0.9 : pickupRadius;
    if (nearest.pos.distanceTo(ball.pos) > grabRadius) {
      return;
    }
    if (airborne) {
      // 리바운드 점프로 공중에서 낚아챈다 — 착지 동안 잠깐 멈춘다
      nearest.state = PlayerState.rebounding;
      nearest.stateTimer = reboundJumpDuration;
      // 리바운드 경합에서 밀린 근처 선수들은 스턴
      for (final other in players) {
        if (other.id != nearest.id &&
            !other.inTimedState &&
            other.pos.distanceTo(ball.pos) < 1.3) {
          _stun(other);
        }
      }
    }
    final wasOffense = offense;
    _giveBallTo(nearest);
    lastEvent = airborne ? 'rebound:${nearest.id}' : 'pickup:${nearest.id}';
    if (nearest.team != wasOffense) {
      _switchOffense(to: nearest.team);
      fastBreakTime = fastBreakDuration; // 라이브볼 턴오버 → 속공
      lastEvent = 'turnover';
    } else {
      shotClock = shotClockMax; // 공격 리바운드도 리셋 (단순화)
    }
  }

  /// 스턴: 1초 제자리 고정 (재스턴 방지 면역 포함)
  void _stun(SimPlayer p) {
    if (p.stunImmunity > 0 || p.state == PlayerState.stunned) {
      return;
    }
    p.state = PlayerState.stunned;
    p.stateTimer = stunDuration;
    p.stunImmunity = stunDuration + stunImmunityDuration;
    p.driveTime = 0;
    lastEvent = 'stun:${p.id}';
  }

  /// 스크린 플레이 오케스트레이션 — 픽앤롤(온볼) / 핀다운(오프볼).
  /// 세터가 자리를 잡으면(screening) 부딪힌 상대 수비는 스턴된다.
  void _updateScreenPlay() {
    final h = holder;
    // 진행 중 관리
    if (screenerId != null) {
      final screener = players[screenerId!];
      final target =
          screenTargetId == null ? null : players[screenTargetId!];
      final invalid = h == null ||
          target == null ||
          screener.team != offense ||
          screener.state == PlayerState.stunned;
      if (invalid) {
        _clearScreen();
        return;
      }
      if (!screenSet) {
        // 세팅 지점 도착 판정
        if (screener.pos.distanceTo(_screenSpot(target)) < 0.7) {
          screenSet = true;
          screener.state = PlayerState.screening;
          screener.stateTimer = 1.5;
          _screenTime = 1.5;
          if (_screenOnBall) {
            h.driveTime = 1.6; // 스크린을 타고 드라이브
          } else {
            // 핀다운: 수혜자(SG)가 스크린을 돌아 오픈 지점으로 튀어나온다
            target.wanderTimer = 1.2;
            target.wander.setValues(2.5, target.pos.y < CourtDims.centerY ? 1.5 : -1.5);
          }
        }
        return;
      }
      _screenTime -= dt;
      if (_screenTime <= 0 || screener.state != PlayerState.screening) {
        // 롤: 세터가 림으로 파고든다 (픽앤"롤")
        screener.cutTime = 1.4;
        _clearScreen(cooldown: 6 + _rng.nextDouble() * 4);
      }
      return;
    }
    // 새 스크린 시작 판단
    _screenCooldown -= dt;
    if (_screenCooldown > 0 ||
        h == null ||
        ball.phase != BallPhase.held ||
        h.pos.distanceTo(basketOf(offense)) > 11 ||
        _rng.nextDouble() > 0.08) {
      return;
    }
    // 세터: 홀더가 아닌 빅맨 (C 우선)
    final bigs = teamOf(offense)
        .where(
          (p) =>
              p.id != h.id &&
              !p.inTimedState &&
              profileOf(p).crashesBoards,
        )
        .toList();
    if (bigs.isEmpty) {
      return;
    }
    bigs.sort((a, b) => b.position.index.compareTo(a.position.index));
    final setter = bigs.first;
    _screenOnBall = _rng.nextDouble() < 0.6;
    final sg = teamOf(offense).firstWhere(
      (p) => p.position == CourtPosition.shootingGuard,
    );
    final beneficiary = _screenOnBall || sg.id == h.id ? h : sg;
    _screenOnBall = beneficiary.id == h.id;
    screenerId = setter.id;
    screenTargetId = beneficiary.id;
    screenSet = false;
    lastEvent = _screenOnBall ? 'screen:onball' : 'screen:pindown';
  }

  /// 스크린 세팅 지점: 수혜자의 최근접 수비수 바로 앞
  Vector2 _screenSpot(SimPlayer target) {
    final defense = offense == Team.home ? Team.away : Team.home;
    final defender = _nearestOf(teamOf(defense), target.pos);
    final dir = defender.pos - target.pos;
    if (dir.length < 1e-6) {
      return defender.pos.clone();
    }
    return _clampToCourt(target.pos + dir.normalized().scaled(0.9));
  }

  void _clearScreen({double cooldown = 3.0}) {
    screenerId = null;
    screenTargetId = null;
    screenSet = false;
    _screenTime = 0;
    _screenCooldown = cooldown;
  }

  /// 더블팀 판단: 홀더 근처에 수비수 둘 → 확률적으로 협공 개시.
  /// 협공 중인 수비수는 존을 버리고 홀더를 직접 압박한다.
  void _updateDoubleTeam() {
    final h = holder;
    // 진행 중인 더블팀 유지/해제
    if (doubleTeamerId != null) {
      _doubleTeamTime -= dt;
      if (_doubleTeamTime <= 0 || h == null) {
        doubleTeamerId = null;
      }
      return;
    }
    if (h == null || h.pos.distanceTo(basketOf(offense)) > 10) {
      return;
    }
    final near = teamOf(h.team == Team.home ? Team.away : Team.home)
        .where(
          (d) =>
              d.state == PlayerState.defending &&
              d.pos.distanceTo(h.pos) < doubleTeamRadius,
        )
        .toList()
      ..sort(
        (a, b) =>
            a.pos.distanceTo(h.pos).compareTo(b.pos.distanceTo(h.pos)),
      );
    if (near.length >= 2 && _rng.nextDouble() < 0.06) {
      doubleTeamerId = near[1].id; // 두 번째로 가까운 수비수가 협공
      doubleTeamIsHelp = false;
      _doubleTeamTime = doubleTeamDuration;
      lastEvent = 'doubleteam:${near[1].id}';
      return;
    }
    // 헬프 디펜스: 홀더가 골밑(5m)까지 뚫고 들어왔는데 앞에 수비가 없으면
    // 가장 가까운 수비수가 존을 버리고 막으러 나온다 (코너가 비는 대가)
    if (h.pos.distanceTo(basketOf(offense)) < 5 && near.isEmpty) {
      final defenders = teamOf(h.team == Team.home ? Team.away : Team.home)
          .where((d) => d.state == PlayerState.defending)
          .toList();
      if (defenders.isNotEmpty) {
        final helper = _nearestOf(defenders, h.pos);
        doubleTeamerId = helper.id;
        doubleTeamIsHelp = true;
        _doubleTeamTime = 1.2;
        lastEvent = 'help:${helper.id}';
      }
    }
  }

  /// 몸통박치기: 수비수가 드리블러와 닿으면(0.75m) 박치기 모션과 함께
  /// HP 1을 깎고 홀더를 살짝 밀어낸다. 수비수별 쿨타임 1초.
  /// HP 0이 되는 박치기는 그대로 스틸.
  void _applyDefensivePressure(SimPlayer h) {
    // 드리블/드라이브 중에만 박치기 대상 (슈팅 모션 등은 제외)
    if (h.state != PlayerState.dribbling &&
        h.state != PlayerState.driving) {
      return;
    }
    // 박치기는 공격 존(골대 10m 이내)에서만 — 운반 구간 보호
    if (h.pos.distanceTo(basketOf(offense)) > 10) {
      return;
    }
    for (final d in teamOf(h.team == Team.home ? Team.away : Team.home)) {
      if (d.state != PlayerState.defending ||
          d.checkCooldown > 0 ||
          d.pos.distanceTo(h.pos) > bodyCheckRadius) {
        continue;
      }
      // 박치기 성립
      d.checkCooldown = bodyCheckCooldown;
      d.state = PlayerState.bodyChecking;
      d.stateTimer = bodyCheckDuration;
      holderHp--;
      // 넉백: 홀더가 반대 방향으로 살짝 밀려난다
      final push = h.pos - d.pos;
      if (push.length > 1e-6) {
        h.pos.setFrom(_clampToCourt(h.pos + push.normalized().scaled(0.35)));
      }
      if (holderHp <= 0) {
        final victim = h;
        _giveBallTo(d);
        fastBreakTime = fastBreakDuration; // 라이브볼 스틸 → 속공
        _stun(victim);
        lastEvent = 'steal:${d.id}';
      } else {
        lastEvent = 'bodycheck:${d.id}:$holderHp';
      }
      return; // 틱당 한 명만
    }
  }

  void _giveBallTo(SimPlayer p) {
    ball.holderId = p.id;
    ball.receiverId = null;
    ball.looseFor = null;
    holdTime = 0;
    holderHp = maxHolderHp;
    doubleTeamerId = null; // 홀더가 바뀌면 협공 해제
    lastTouchTeam = p.team;
    // 클로즈아웃: 오픈 캐치면 가장 가까운 수비수가 전력으로 달려나간다
    final opponents = teamOf(p.team == Team.home ? Team.away : Team.home)
        .where((d) => d.state == PlayerState.defending)
        .toList();
    if (opponents.isNotEmpty &&
        p.pos.distanceTo(basketOf(p.team)) < shootRange) {
      final nearestDef = _nearestOf(opponents, p.pos);
      if (nearestDef.pos.distanceTo(p.pos) > 2.2) {
        closeoutId = nearestDef.id;
        _closeoutTime = 1.2;
      }
    }
    ball.phase = BallPhase.held;
    ball.pos.setFrom(p.pos);
    ball.z = heldBallHeight;
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
    // 공수가 바뀌면 진행 중이던 인바운드/협공/스크린/속공은 무효
    inbounderId = null;
    inboundReceiverId = null;
    _netDropTime = 0;
    doubleTeamerId = null;
    _clearScreen();
    fastBreakTime = 0;
    closeoutId = null;
    _closeoutTime = 0;
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

    // 인바운더: 리시버가 자리 잡을 시간을 주고 인바운드 패스로 재개
    if (h.id == inbounderId && inboundReceiverId != null) {
      if (holdTime < 0.3) {
        return;
      }
      final receiver = players[inboundReceiverId!];
      ball.from.setFrom(h.pos);
      ball.to.setFrom(receiver.pos);
      ball.flightTime = 0;
      ball.flightDuration =
          max(0.4, h.pos.distanceTo(receiver.pos) / passSpeed);
      ball.arcPeak = 0.5;
      ball.receiverId = receiver.id;
      ball.interceptTried.clear();
      lastPasserId = h.id;
      ball.holderId = null;
      ball.z = heldBallHeight; // 몸 높이에서 출발
      ball.phase = BallPhase.pass;
      lastTouchTeam = h.team;
      shotClock = shotClockMax; // 인바운드부터 새 공격 시작
      lastEvent = 'inbound:${receiver.id}';
      inbounderId = null;
      inboundReceiverId = null;
      return;
    }
    // 샷클락 임박: 릴리즈까지 걸리는 시간을 감안해 강제 슈팅 모션
    if (shotClock <= 0.8) {
      _startWindup(h, distToBasket);
      return;
    }
    // 드라이브 중: 림에 도달하면 레이업, 아니면 계속 질주
    if (h.state == PlayerState.driving) {
      if (distToBasket <= layupRange) {
        h.driveTime = 0;
        _startWindup(h, distToBasket);
      }
      return;
    }
    // HP 마지막 칸: 골밑 근처면 뺏기느니 쏜다 (필사 슛).
    // 샷클락도 얼마 없으면 거리 불문 던진다.
    if (holderHp <= 1 &&
        (distToBasket < 5.5 ||
            (shotClock < 5 && distToBasket < shootRange))) {
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
    // 드라이빙: 3점 라인 안이면 확률적으로 림을 향해 가속 돌파
    if (distToBasket < CourtDims.threeRadius &&
        distToBasket > layupRange &&
        _rng.nextDouble() < 0.09) {
      h.driveTime = 2.2;
      lastEvent = 'drive:${h.id}';
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
      // 3점은 신중하게 — 아크 밖에서는 시도 확률을 크게 낮춘다
      final rangeMul =
          distToBasket > CourtDims.threeRadius ? 0.4 : 1.0;
      if (pressure > 1.2 &&
          _rng.nextDouble() < 0.45 * profile.shootMul * rangeMul) {
        _startWindup(h, distToBasket); // 오픈 슛
        return;
      }
      if (pressure > 0.8 &&
          _rng.nextDouble() < 0.10 * profile.shootMul * rangeMul) {
        _startWindup(h, distToBasket); // 세미오픈
        return;
      }
    }
    // 잡은 직후에는 패스하지 않는다 (핑퐁 방지)
    if (holdTime < minHoldBeforePass) {
      return;
    }
    // 오픈 찬스가 난 동료(수비 2.2m 밖 + 사거리 안)에게 적극적으로 피드
    final defendersList =
        teamOf(offense == Team.home ? Team.away : Team.home).toList();
    final hasOpenMate = teamOf(offense).any((m) {
      if (m.id == h.id || m.id == lastPasserId) {
        return false;
      }
      if (m.pos.distanceTo(basket) >= shootRange) {
        return false;
      }
      final nearestToMate =
          defendersList.map((d) => d.pos.distanceTo(m.pos)).reduce(min);
      return nearestToMate >= 2.2;
    });
    if (hasOpenMate && _rng.nextDouble() < 0.3) {
      _pass(h);
      return;
    }
    // 압박당하면(HP 깎이는 중) 적극적으로 탈출 패스, 아니어도 종종 볼 순환.
    // PG 는 배급 역할이라 더 자주 돌리고, HP 가 깎일수록 급해진다.
    final hpUrgency = 1.0 + (maxHolderHp - holderHp) * 0.8;
    if (pressure < pressureRadius &&
        _rng.nextDouble() <
            (0.3 * profile.passMul * hpUrgency).clamp(0.0, 0.95)) {
      _pass(h);
    } else if (_rng.nextDouble() <
        (0.03 * profile.passMul * hpUrgency).clamp(0.0, 0.5)) {
      _pass(h);
    }
  }

  /// 슈팅 준비 모션 시작 (레이업은 짧은 모션 + 림으로 활공)
  void _startWindup(SimPlayer h, double distToBasket) {
    h.layupMotion = distToBasket <= layupRange;
    _currentWindup =
        h.layupMotion ? layupWindupDuration : windupDuration;
    h.state = PlayerState.windup;
    h.stateTimer = _currentWindup;
    lastEvent = 'windup:${h.id}';
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
    ball.flightDuration = max(1.0, dist / shotSpeed);
    ball.arcPeak = 1.0 + dist * 0.15;
    ball.shotWillScore =
        _rng.nextDouble() < makeProb(dist, contested: contested);
    ball.shotValue = dist > CourtDims.threeRadius ? 3 : 2;
    lastPasserId = null;
    lastShooterId = h.id;
    ball.holderId = null;
    ball.z = shotReleaseHeight; // 손끝에서 출발
    ball.phase = BallPhase.shot;
    lastTouchTeam = h.team;
    if (contested && !ball.shotWillScore) {
      _stun(h); // 블락당함 — 슈터 스턴
    }
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
      // 아웃렛(빅맨 운반 → 가드) 패스인가 — 머리 위로 넘기는 패스라
      // 오픈 요구치를 완화한다
      final isGuardOutlet =
          h.position.index >= CourtPosition.smallForward.index &&
              h.pos.distanceTo(basket) > 9 &&
              mate.position.index <= CourtPosition.shootingGuard.index;
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
        if (d.pos.distanceTo(h.pos + ab * t) < 0.8) {
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
      final requiredOpenness =
          (0.75 + 0.11 * passDist) * (isGuardOutlet ? 0.8 : 1.0);
      if (openness < requiredOpenness) {
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
      // 백도어: 림으로 컷 중인 동료에게 찔러주면 레이업으로 직결
      final backdoorBonus = mate.cutTime > 0 ? 1.5 : 0.0;
      // 빅맨이 운반 중이면 올라와 준 가드에게 넘긴다 (아웃렛)
      final guardOutletBonus =
          h.position.index >= CourtPosition.smallForward.index &&
                  h.pos.distanceTo(basket) > 9 &&
                  mate.position.index <= CourtPosition.shootingGuard.index
              ? 2.0
              : 0.0;
      // 속공: 골대 쪽으로 3m 이상 앞서 달리는 동료에게 몰아준다
      final fastBreakBonus = fastBreakTime > 0 &&
              mate.pos.distanceTo(basket) < h.pos.distanceTo(basket) - 3
          ? 2.5
          : 0.0;
      // 짧은 패스 선호 — 비행 시간이 길수록 레인 점프에 노출된다
      final score = fastBreakBonus +
          openness -
          mate.pos.distanceTo(basket) * 0.15 -
          passDist * 0.12 +
          pgCarryBonus +
          postEntryBonus +
          backdoorBonus +
          guardOutletBonus;
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
    // 로브 패스(높은 궤적): 빅맨 아웃렛, 또는 속공 롱패스
    final lob = (h.position.index >= CourtPosition.smallForward.index &&
            h.pos.distanceTo(basket) > 9 &&
            best.position.index <= CourtPosition.shootingGuard.index) ||
        (fastBreakTime > 0 && h.pos.distanceTo(target) > 6);
    ball.arcPeak = lob ? 1.2 : 0.5;
    ball.receiverId = best.id;
    ball.interceptTried.clear();
    lastPasserId = h.id;
    ball.holderId = null;
    ball.z = heldBallHeight; // 몸 높이에서 출발
    ball.phase = BallPhase.pass;
    lastTouchTeam = h.team;
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
        // 볼 소유자는 드리블 때문에 80% 속도, 드라이브 중엔 110% 가속
        final speed = p.state == PlayerState.driving
            ? playerSpeed * 1.1
            : ball.holderId == p.id
                ? playerSpeed * dribbleSpeedFactor
                : playerSpeed;
        final step = min(distance, speed * dt);
        p.pos.add(delta..scale(step / distance));
      }
      _separate(p);
      p.pos.setFrom(_clampToCourt(p.pos));
    }
  }

  Vector2 _targetFor(SimPlayer p) {
    // 슈팅 모션/페이크/블락 점프 중에는 제자리.
    // 단 레이업 모션은 림으로 계속 활공한다 (러닝 레이업)
    if (p.inTimedState) {
      if (p.state == PlayerState.windup && p.layupMotion) {
        return basketOf(offense);
      }
      return p.pos.clone();
    }
    // 드라이브 중인 홀더: 림으로 직진 (가속은 _movePlayers 에서)
    if (p.state == PlayerState.driving && ball.holderId == p.id) {
      return basketOf(offense);
    }
    // 패스 받을 사람은 캐치 지점으로
    if (ball.phase == BallPhase.pass && ball.receiverId == p.id) {
      return ball.to.clone();
    }
    // 득점 후 인바운드: 지정 인바운더는 공으로, 리시버는 받을 지점으로,
    // 나머지는 아래 일반 로직(존/앵커)을 따라 각자 진영으로 복귀한다
    if (ball.phase == BallPhase.loose && inbounderId != null) {
      if (p.id == inbounderId) {
        return _clampToCourt(ball.pos.clone());
      }
      if (p.id == inboundReceiverId) {
        final inDir = Vector2(_inboundSpot.x < 0 ? 1 : -1, 0.35)
          ..normalize();
        return _clampToCourt(_inboundSpot + inDir.scaled(4.5));
      }
    }
    // 루즈볼: 리바운드 가중치(PF/C 우선)로 뽑힌 선수가 공으로.
    // 공중에 떠 있으면 낙하 지점으로 미리 달려간다
    if (ball.phase == BallPhase.loose &&
        inbounderId == null &&
        (ball.looseFor == null || ball.looseFor == p.team)) {
      if (_looseChaserOf(p.team).id == p.id) {
        return looseAirborne ? ball.to.clone() : ball.pos.clone();
      }
    }
    // 슛이 뜨거나 리바운드가 공중에 있으면 PF/C 는 양팀 모두
    // 림으로 리바운드 진입 (박스아웃 자리)
    if ((ball.phase == BallPhase.shot ||
            (looseAirborne && inbounderId == null)) &&
        profileOf(p).crashesBoards) {
      final rim = basketOf(offense);
      final toCenter = rim.x < CourtDims.length / 2 ? 1.0 : -1.0;
      final side = p.position == CourtPosition.center ? 1.0 : -1.0;
      return _clampToCourt(
        Vector2(rim.x + toCenter * 1.4, rim.y + side * 1.2),
      );
    }
    // 패스 비행 중, 리시버 근처의 수비수는 공 궤적 위로 뛰어들어
    // 인터셉트를 노린다 — 단, 자기 존을 벗어나면서까지 쫓지는 않는다
    if (ball.phase == BallPhase.pass &&
        p.team != offense &&
        ball.receiverId != null &&
        p.pos.distanceTo(players[ball.receiverId!].pos) < 2.5) {
      final ab = ball.to - ball.pos;
      final len2 = ab.length2;
      if (len2 > 1e-9) {
        final t = ((p.pos - ball.pos).dot(ab) / len2).clamp(0.0, 1.0);
        final jumpSpot = ball.pos + ab * t;
        if (jumpSpot.distanceTo(_zoneAnchorFor(p)) <= zoneRadius + 0.8) {
          return jumpSpot;
        }
      }
    }
    if (p.team == offense) {
      if (ball.holderId == p.id) {
        // 인바운더는 패스할 때까지 라인 밖 자리에서 대기
        if (p.id == inbounderId) {
          return p.pos.clone();
        }
        final defender = _nearestOf(
          teamOf(p.team == Team.home ? Team.away : Team.home),
          p.pos,
        );
        final toDefender = defender.pos - p.pos;
        // 드리블이 느려(80%) 정면 돌파가 어렵다 — HP가 깎이기 시작하면
        // 옆으로 흘러나가며 볼 무브먼트로 풀어간다 (측면 회피).
        // 뒤로 빠지면 하프라인까지 밀리므로 후퇴 성분은 최소화한다.
        if (holderHp <= 2 &&
            toDefender.length < 1.3 &&
            toDefender.length > 1e-6) {
          final away = -toDefender.normalized();
          // HP 1: 최후 수단 — 뒤로 빠져 접촉을 끊되, 하프라인 뒤로
          // 도망가지는 않는다 (프론트코트 안에서만 후퇴)
          if (holderHp <= 1) {
            final escape = _clampToCourt(p.pos + away.scaled(2.5));
            if (escape.distanceTo(basketOf(offense)) <= 13) {
              return escape;
            }
            // 더 물러날 곳이 없으면 측면 회피로 전환
          }
          // HP 2 (또는 후퇴 공간 없음): 측면 회피 — 전진 자세 유지
          final basket = basketOf(offense);
          final toBasketDir = (basket - p.pos)..normalize();
          final perpA = Vector2(away.y, -away.x);
          final perpB = Vector2(-away.y, away.x);
          final perp =
              perpA.dot(toBasketDir) >= perpB.dot(toBasketDir) ? perpA : perpB;
          return _clampToCourt(
            p.pos + perp.scaled(2.2) + away.scaled(0.5),
          );
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
      // 스크린 세터: 세팅 지점으로 이동 (도착하면 screening 상태로 고정)
      if (p.id == screenerId && !screenSet && screenTargetId != null) {
        return _screenSpot(players[screenTargetId!]);
      }
      // 속공: 가드/포워드는 앞선으로 질주 (leak out)
      if (fastBreakTime > 0 &&
          p.position.index <= CourtPosition.smallForward.index) {
        final basket = basketOf(offense);
        final u = 3.5;
        final x = basket.x < CourtDims.length / 2
            ? basket.x - CourtDims.basketX + u
            : basket.x + CourtDims.basketX - u;
        final y = switch (p.position) {
          CourtPosition.shootingGuard => 3.0,
          CourtPosition.smallForward => 12.0,
          _ => 7.5,
        };
        return Vector2(x, y);
      }
      // 빅맨(비가드)이 볼을 "운반 중"(아직 공격 진영 밖)이면
      // 가드는 탑으로 올라가 받아준다 — 세트 오펜스 진입 후엔 평소 무브
      final h = holder;
      if (h != null &&
          h.team == p.team &&
          h.position.index >= CourtPosition.smallForward.index &&
          h.pos.distanceTo(basketOf(offense)) > 9 &&
          p.position.index <= CourtPosition.shootingGuard.index) {
        // 받으러 올라가되 배회/저크는 유지해 마크를 떨어뜨린다
        final anchor = _anchorFor(p);
        return _clampToCourt(
          anchor + (h.pos - anchor) * 0.3 + p.wander,
        );
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
      // 스페이싱: 3m 안의 동료에게서 멀어지는 방향으로 목표를 민다
      // (오프볼끼리 몰려 있으면 패스 레인과 컷 공간이 죽는다)
      for (final mate in teamOf(p.team)) {
        if (mate.id == p.id) {
          continue;
        }
        final d = p.pos.distanceTo(mate.pos);
        if (d < 3.0 && d > 1e-6) {
          target.add(
            (p.pos - mate.pos).normalized()..scale((3.0 - d) * 0.8),
          );
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

  /// 지역방어 존 앵커 프리셋 — 수비 골대 기준 (u: 베이스라인 거리, y)
  static const Map<ZoneScheme, Map<CourtPosition, (double, double)>>
      zoneAnchorPresets = {
    // 2-3: 가드 둘이 위, 포워드·센터 셋이 아래
    ZoneScheme.twoThree: {
      CourtPosition.pointGuard: (6.8, 5.2),
      CourtPosition.shootingGuard: (6.8, 9.8),
      CourtPosition.smallForward: (2.4, 3.6),
      CourtPosition.powerForward: (2.4, 11.4),
      CourtPosition.center: (2.4, 7.5),
    },
    // 3-2: 셋이 위(외곽 압박), 빅맨 둘이 아래
    ZoneScheme.threeTwo: {
      CourtPosition.pointGuard: (7.6, 7.5),
      CourtPosition.shootingGuard: (6.6, 3.5),
      CourtPosition.smallForward: (6.6, 11.5),
      CourtPosition.powerForward: (2.3, 5.3),
      CourtPosition.center: (2.3, 9.7),
    },
  };

  /// 현재 지역방어 대형 — 런타임에 전환 가능 (감독 지시)
  ZoneScheme zoneScheme = ZoneScheme.twoThree;

  /// 존 담당 반경 — 이 안에 들어온 공격수를 따라붙고, 나가면 놓아준다
  static const double zoneRadius = 3.8;

  Vector2 _zoneAnchorFor(SimPlayer p) {
    final (u, y) = zoneAnchorPresets[zoneScheme]![p.position]!;
    final basket = basketOf(offense); // 지키는 골대
    final x = basket.x < CourtDims.length / 2
        ? basket.x - CourtDims.basketX + u
        : basket.x + CourtDims.basketX - u;
    return Vector2(x, y);
  }

  /// 지역방어: 기본은 존 앵커를 지키고(볼 쪽으로 살짝 쉐이드),
  /// 존에 들어온 공격수(볼 홀더 최우선)는 존 안에서 맨투맨처럼 따라붙는다.
  Vector2 _defenseTargetFor(SimPlayer p) {
    final basket = basketOf(offense);
    // 클로즈아웃: 오픈 캐치한 홀더에게 지연 없이 직행
    if (p.id == closeoutId && holder != null) {
      final h = holder!;
      final toBasket = basket - h.pos;
      if (toBasket.length > 1e-6) {
        return _clampToCourt(h.pos + toBasket.normalized().scaled(0.6));
      }
      return h.pos.clone();
    }
    // 더블팀 가담자: 존을 버리고 홀더를 직접 압박
    if (p.id == doubleTeamerId && holder != null) {
      final h = holder!;
      final toBasket = basket - h.pos;
      if (toBasket.length > 1e-6) {
        return _clampToCourt(
          h.pos + toBasket.normalized().scaled(0.6),
        );
      }
      return h.pos.clone();
    }
    final zoneCenter = _zoneAnchorFor(p);

    SimPlayer? mark;
    var bestScore = double.infinity;
    for (final o in teamOf(offense)) {
      final dist = o.pos.distanceTo(zoneCenter);
      if (dist > zoneRadius) {
        continue;
      }
      // 볼 홀더가 내 존에 있으면 무조건 그를 막는다
      final score = ball.holderId == o.id ? dist - 100 : dist;
      if (score < bestScore) {
        bestScore = score;
        mark = o;
      }
    }

    if (mark == null) {
      // 빈 존: 자리를 지키며 공 방향으로 반 발짝 쉐이드
      return _clampToCourt(
        zoneCenter + (ball.pos - zoneCenter).scaled(0.15),
      );
    }

    // 지연된 인식: 0.3초마다만 마크의 실제 위치를 확인
    p.markSnapTimer -= dt;
    if (p.markSnapTimer <= 0) {
      p.markSnapTimer = defenseReactionDelay;
      p.perceivedMarkPos.setFrom(mark.pos);
    }
    final markPos = p.perceivedMarkPos;
    final toBasket = basket - markPos;
    final len = toBasket.length;
    if (len < 1e-6) {
      return markPos.clone();
    }
    // 항상 마크와 림 사이. 볼 핸들러는 바짝(압박), 오프볼은 성향대로
    final standOff = ball.holderId == mark.id
        ? 0.6
        : profileOf(p).defenseStandoff;
    return _clampToCourt(markPos + toBasket.scaled(standOff / len));
  }

  void _separate(SimPlayer p) {
    for (final other in players) {
      if (other.id == p.id) {
        continue;
      }
      // 같은 팀: 스페이싱 유지(1.1m), 상대 팀: 몸싸움 충돌(0.5m).
      // 상대와 겹쳐 지나갈 수 없으므로 컷/리바운드 진입 무브가
      // 자연스럽게 스크린처럼 수비의 추격 경로를 막는다.
      final minDist = other.team == p.team ? 1.1 : 0.5;
      final delta = p.pos - other.pos;
      final distance = delta.length;
      if (distance > 1e-6 && distance < minDist) {
        // 스크린에 걸림: 세팅된 상대 스크리너와 부딪히면 스턴
        if (other.team != p.team &&
            other.state == PlayerState.screening &&
            !p.inTimedState) {
          _stun(p);
        }
        p.pos.add(delta.scaled((minDist - distance) / distance * 0.5));
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
