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
