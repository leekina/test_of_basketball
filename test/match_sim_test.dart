import 'package:flutter_test/flutter_test.dart';
import 'package:test_of_basketball/sim/court_dims.dart';
import 'package:test_of_basketball/sim/match_sim.dart';

void main() {
  test('시드가 같으면 결과가 완전히 재현된다', () {
    final a = MatchSim(seed: 7);
    final b = MatchSim(seed: 7);
    for (var i = 0; i < 2000; i++) {
      a.tick();
      b.tick();
    }
    expect(a.homeScore, b.homeScore);
    expect(a.awayScore, b.awayScore);
    expect(a.ball.pos.x, b.ball.pos.x);
    expect(a.ball.pos.y, b.ball.pos.y);
    expect(a.players.map((p) => p.pos.x).toList(),
        b.players.map((p) => p.pos.x).toList());
  });

  test('속성: 선수는 코트 안, 볼 소유자는 항상 1명 이하, 샷클락 상한', () {
    final sim = MatchSim(seed: 42);
    for (var i = 0; i < 3000; i++) {
      sim.tick();
      for (final p in sim.players) {
        expect(p.pos.x, inInclusiveRange(-0.01, CourtDims.length + 0.01),
            reason: 'tick $i player ${p.id} x');
        expect(p.pos.y, inInclusiveRange(-0.01, CourtDims.width + 0.01),
            reason: 'tick $i player ${p.id} y');
      }
      if (sim.ball.holderId != null) {
        expect(sim.ball.holderId, inInclusiveRange(0, 9));
        expect(sim.ball.phase, BallPhase.held);
        // 공은 홀더(id 일치) 위치에 있어야 한다 (인덱스/id 혼동 회귀 방지)
        final holderPlayer =
            sim.players.firstWhere((p) => p.id == sim.ball.holderId);
        expect(sim.ball.pos.distanceTo(holderPlayer.pos), lessThan(0.001),
            reason: 'tick $i: 공이 홀더가 아닌 곳에 있음');
      }
      expect(sim.shotClock, lessThanOrEqualTo(MatchSim.shotClockMax + 0.001),
          reason: 'tick $i shot clock');
    }
  });

  test('5분 시뮬이면 득점과 공수 전환이 발생한다', () {
    final sim = MatchSim(seed: 42);
    for (var i = 0; i < 3000; i++) {
      sim.tick();
    }
    expect(sim.homeScore + sim.awayScore, greaterThan(0));
    expect(sim.offenseChanges, greaterThan(0));
  });

  test('모든 선수가 계속 움직인다 (오프볼 무브 포함)', () {
    final sim = MatchSim(seed: 42);
    final moved = List.filled(10, 0.0);
    final prev = [for (final p in sim.players) p.pos.clone()];
    for (var i = 0; i < 600; i++) {
      // 60초
      sim.tick();
      for (var j = 0; j < 10; j++) {
        moved[j] += sim.players[j].pos.distanceTo(prev[j]);
        prev[j].setFrom(sim.players[j].pos);
      }
    }
    for (var j = 0; j < 10; j++) {
      expect(moved[j], greaterThan(20),
          reason: '선수 $j가 60초 동안 ${moved[j].toStringAsFixed(1)}m만 이동');
    }
  });

  test('핑퐁 패스 금지: 직전 패서에게 즉시 리턴 없음, 패스 간격 보장', () {
    for (final seed in [1, 42, 777]) {
      final sim = MatchSim(seed: seed);
      int? lastPassTick;
      int? lastPasser;
      for (var i = 0; i < 6000; i++) {
        final holderBefore = sim.ball.holderId;
        sim.tick();
        final e = sim.lastEvent;
        if (e == null) {
          continue;
        }
        // 슛/공수 전환이 끼면 시뮬도 리턴 금지를 리셋한다
        if (e.startsWith('shot') || e.startsWith('score') || e == 'turnover') {
          lastPasser = null;
          continue;
        }
        if (!e.startsWith('pass:')) {
          continue;
        }
        final receiver = int.parse(e.split(':')[1]);
        if (lastPasser != null) {
          expect(receiver, isNot(lastPasser),
              reason: 'seed $seed tick $i: 직전 패서에게 즉시 리턴 패스');
        }
        if (lastPassTick != null) {
          expect(i - lastPassTick, greaterThanOrEqualTo(10),
              reason: 'seed $seed tick $i: 패스 간격이 너무 짧음');
        }
        lastPasser = holderBefore;
        lastPassTick = i;
      }
    }
  });

  test('패스와 슛 이벤트가 모두 발생한다', () {
    final sim = MatchSim(seed: 42);
    final seen = <String>{};
    for (var i = 0; i < 3000; i++) {
      sim.tick();
      if (sim.lastEvent != null) {
        seen.add(sim.lastEvent!.split(':').first);
      }
    }
    expect(seen, containsAll(['pass', 'shot']));
  });
}
