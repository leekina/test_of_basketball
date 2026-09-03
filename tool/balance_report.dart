// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps
// 밸런스 리포트: 헤드리스 대량 시뮬로 공격 효율/수비 효과를 측정한다.
// 실행: dart tool/balance_report.dart
//
// 참고 지표(실제 농구): PPP ~1.0-1.15, FG% ~44-48%, 레이업 비중 ~30-40%
import 'package:test_of_basketball/sim/match_sim.dart';

void main() {
  const seeds = [1, 7, 42, 99, 777];
  const ticks = 6000; // 10분
  var totalPoints = 0;
  var possessions = 0;
  var shots = 0, layups = 0, threes = 0, contested = 0;
  var makes = 0, fakes = 0, blocks = 0, steals = 0, turnovers = 0, passes = 0;
  var intercepts = 0;

  for (final seed in seeds) {
    final sim = MatchSim(seed: seed);
    for (var i = 0; i < ticks; i++) {
      sim.tick();
      final e = sim.lastEvent;
      if (e == null) continue;
      final parts = e.split(':');
      switch (parts.first) {
        case 'shot':
          shots++;
          if (parts[1] == '3') threes++;
          if (parts.length > 2) contested++;
        case 'layup':
          shots++;
          layups++;
          if (parts.length > 2) contested++;
        case 'score':
          makes++;
        case 'fake':
          fakes++;
        case 'block':
          blocks++;
        case 'intercept':
          intercepts++;
        case 'steal':
          steals++;
        case 'turnover':
          turnovers++;
        case 'pass':
          passes++;
      }
    }
    totalPoints += sim.homeScore + sim.awayScore;
    possessions += sim.offenseChanges;
  }

  final n = seeds.length;
  String f(num v) => v.toStringAsFixed(2);
  print('=== 10분 x ${n}시드 평균 ===');
  print('득점 합: ${f(totalPoints / n)} | 포제션: ${f(possessions / n)} '
      '| PPP: ${f(totalPoints / possessions)}');
  print('슛 시도: ${f(shots / n)} (레이업 ${f(layups / n)}, 3점 ${f(threes / n)}, '
      '컨테스트 ${f(contested / n)})');
  print('FG%: ${f(makes * 100 / shots)}% | 레이업 비중: ${f(layups * 100 / shots)}% '
      '| 컨테스트율: ${f(contested * 100 / shots)}%');
  print('페이크: ${f(fakes / n)} | 블락시도: ${f(blocks / n)} '
      '| HP스틸: ${f(steals / n)} | 인터셉트: ${f(intercepts / n)} '
      '| 턴오버: ${f(turnovers / n)} | 패스: ${f(passes / n)}');
}
