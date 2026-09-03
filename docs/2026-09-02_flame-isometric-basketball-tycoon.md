# Flame 기반 아이소메트릭 픽셀 농구 타이쿤 — 기술 타당성 검토
조사일: 2026-09-02 | 조사 범위: Flame 1.38.x 아이소메트릭·픽셀아트·깊이 정렬 검증 + z축(높이) 설계 방안
프로젝트 전제: 카이로소프트(『농구클럽 이야기』)풍 아이소메트릭 픽셀 그래픽 농구 팀 경영 타이쿤. Flutter 개발자, 코드 온리 선호, AI 코딩 에이전트 적극 활용.

> 선행 문서: [2026-08-31 엔진 비교 리서치](2026-08-31_flutter-flame-vs-godot-2d-game.md) (Flame 채택 근거)
> 상세 원자료: `_workspace/04_researcher_flame-isometric-tycoon.md` (출처 204개)

---

## 종합 판정: 조건부 GO

**기술적으로 실현 가능하다. 성능·픽셀아트·깊이 정렬은 해결된 문제이고, 유일한 실질 리스크는 "아이소메트릭 선례 부재"다** — 막히면 검색으로 해답을 못 찾고 직접 풀어야 하는 개척 프로젝트다. 단 농구 타이쿤이라는 장르 특성(평평한 코트, 낮은 엔티티 수, UI 중심, 물리 불필요)이 Flame의 약점 대부분을 비켜간다.

| 영역 | 판정 | 근거 |
|---|---|---|
| 성능 (캐릭터 수십~수백) | 🟢 여유 | 검증 벤치마크 한계: 웹 2,500 / iOS 5,900 엔티티 — 요구량의 10배+ |
| 깊이 정렬 (y-sort) | 🟢 해결됨 | Flame 팀 공식 벤치마크 채택·최적화 + Heeve 레퍼런스 구현 존재 |
| 픽셀아트 렌더링 | 🟡 주의 | 공식 해법 있음, 단 줌은 정수 배율 제한 권장 |
| z축(높이·슛 궤적) | 🟢 표준 기법 | 물리/렌더 분리 — 아래 §3 |
| 아이소메트릭 맵 시스템 | 🔴 개척 필요 | 높이 스택·레이어 미지원, flame_tiled iso는 experimental, 선례 0건 |

---

## 1. 검증된 사실 (2026-09-02 조사 기준)

### 1-1. 아이소메트릭 지원 — 얕지만 타이쿤 루프에는 충분
- `IsometricTileMapComponent`는 Flame 1.38.x에 현존. **클릭 판정(`getBlock`)과 런타임 타일 편집(`setBlockValue`)** 지원 — "건물/시설 짓기" 루프에 부합.
- 한계: **높이 스택·다중 레이어 미지원**(매트릭스 1장), 컬링·배칭 없이 매 프레임 전체 순회(대형 맵 렌더 비용 미측정).
- Tiled 에디터 경로: `flame_tiled`의 isometric orientation은 **구현 기여자 본인이 "잘해야 experimental"이라고 명시**([flame#1882](https://github.com/flame-engine/flame/issues/1882)), 배치 오프셋 버그 [#3794](https://github.com/flame-engine/flame/issues/3794)가 2025-12부터 open.
- `flame_isometric` 서드파티 패키지는 2023년 이후 방치 — 사용 불가.

### 1-2. 선례 부재 — 최대 리스크
- awesome-flame 등재 게임 66건 전수 조사: **아이소메트릭 0건, 타이쿤/경영 0건.**
- 카이로소프트풍 Dart 저장소 검색 0건. 아이소메트릭×Flame 저장소 9건 전부 ⭐10 미만.

### 1-3. 유일한 레퍼런스: Heeve
- **[bluefireteam/heeve](https://github.com/bluefireteam/heeve)** — Flame 제작팀이 GameOff 2021 잼용으로 만든 아이소메트릭 RTS (⭐20, 2021-12 이후 중단, [플레이](https://spydon.itch.io/heeve)).
- 확인된 유일한 "Flame + 아이소메트릭 + 다수 유닛 깊이 정렬" 구현체. 핵심 파일: [`lib/ordered_map_component.dart`](https://github.com/bluefireteam/heeve/blob/main/lib/ordered_map_component.dart)
  - 정렬 키 = 화면 y가 아니라 **격자 좌표 `block.x + block.y`**
  - Flame 기본 `priority` 대신 별도 `OrderedSet` + `renderTree` 오버라이드로 렌더 순서 직접 제어
  - 작성자(spydon) 본인의 성능 경고 주석 존재(`//TODO(spydon): This will be very heavy`) → 그대로 복사 금지, 패턴 참고용
- 2021년 코드이므로 현행 1.38.x API로 포팅 필요.

### 1-4. 픽셀아트
- 문제: float 정밀도로 인한 타일 경계 ghost line / texture bleeding.
- 공식 해법 2종 문서화됨: `bleed` 옵션, `RasterSpriteComponent`. `flame_tiled`는 기본값이 이미 `FilterQuality.none`.
- 미해결: 전역 픽셀아트 스위치 없음, 정수배율 뷰포트([flame#2810](https://github.com/flame-engine/flame/issues/2810)) 3년째 미구현. → **카메라 줌을 정수 배율(1x/2x/3x)로 제한**하는 설계 권장.

### 1-5. 성능
- filiph.net 벤치마크(2024-09, Flame 1.18) **원본 그래프 직접 판독 검증값**: 60FPS 한계 웹 2,500 / iOS 5,900 엔티티. 카이로소프트풍 요구량(수십~수백)의 10배 이상 여유.
- Flame 팀이 "자식 1,000개 매 틱 y-sort"를 공식 벤치마크로 채택해 3.6배 개선. 이후 `ComponentPool`(1.36.0)·`HasAutoBatchedChildren`(1.37.0) 추가.
- 전역 z-index 부재([flame#1938](https://github.com/flame-engine/flame/issues/1938))는 이 장르에선 비쟁점.

---

## 2. 농구 타이쿤이 Flame 약점을 비켜가는 이유

1. **코트가 평평하다** — 타일 높이 스택 미지원(§1-1)은 지형이 울퉁불퉁할 때의 문제. 코트는 z=0 평면 하나라 미발동. 림·백보드는 바닥 앵커를 가진 키 큰 스프라이트로 처리.
2. **물리 엔진 불필요** — 슛·패스·점프는 포물선 수식이면 충분. forge2d 미사용.
3. **경영 로직은 순수 Dart** — 선수 능력치·재정·훈련·경기 시뮬을 Flame 미의존 순수 Dart 코어로 분리 → 단위 테스트 가능. AI 에이전트 활용에 최적(13개 게임 출시 개발자의 검증된 구조, [선행 리서치](2026-08-31_flutter-flame-vs-godot-2d-game.md) 참조).
4. **UI 비중이 크다** — 메뉴·스탯·계약·다이얼로그는 Flutter 위젯 그대로. Flame의 최대 강점 영역.
5. **장르 원조가 같은 기법으로 성립을 증명** — 카이로소프트 『농구클럽 이야기(Basketball Club Story)』가 아이소메트릭 픽셀 + 공중 슛 궤적 조합. (모델 지식, 미검증 — 연출 상세는 게임 직접 참고)

---

## 3. z축(높이) 설계 — 물리/렌더 분리

2D 아이소메트릭의 공중 표현 표준 기법. 실제 3D가 아니라 투영 트릭이다. (기법 자체는 모델 지식 기반이나, Flame이 컴포넌트 위치를 전부 코드로 제어하는 구조라는 점은 §1에서 검증됨)

### 3-1. 원칙
- **시뮬레이션은 3D**: 공·선수 상태를 `(x, y, z)`로 유지. 슛 궤적은 `z = v₀t − ½gt²` 포물선 물리. 순수 Dart — 렌더링과 무관, 단위 테스트 대상.
- **렌더링은 투영**: 화면 위치 = 아이소메트릭 투영(x, y) − z 오프셋.

```dart
// (x, y) = 코트 바닥 좌표, z = 높이
Vector2 toScreen(double x, double y, double z) =>
    isoProject(x, y) - Vector2(0, z * heightScale);
```

- **그림자 분리**: 공의 `(x, y)` 바닥 위치에 그림자 스프라이트. 높이 가독성은 z 오프셋보다 그림자가 만든다.
- **깊이 정렬은 바닥 기준**: 공이 떠 있어도 정렬 키는 그림자 위치의 `block.x + block.y`. 높이는 화면 오프셋에만 관여 → Heeve 정렬 패턴이 그대로 확장됨.

### 3-2. 설계 시 결정 사항
- **가림(occlusion) 규칙**: 공이 림/백보드 뒤·앞을 지날 때의 앞뒤 관계는 바닥 기준 정렬로 대부분 풀리나, "공이 백보드보다 높은 경우" 예외 처리 필요 가능성. → 스파이크에서 슛 장면 1개로 조기 검증.
- **`heightScale` 상수**: 높이 1m = 화면 몇 px. 게임의 "공중 느낌"을 결정. 실측 비율보다 과장이 픽셀 게임에서 보기 좋은 것이 보통 — 튜닝 파라미터로 유지.

---

## 4. 권장 진행 계획

### 스파이크 (2~3일)
1. [Heeve 소스](https://github.com/bluefireteam/heeve) 정독 → `OrderedMapComponent`를 Flame 1.38.x API로 포팅
2. 실사용 코트+관중석 규모 맵에서 `IsometricTileMapComponent` 렌더 비용 측정 (컬링 없음 주의)
3. 캐릭터 수백 개 y-sort 프레임타임 측정
4. **슛 장면 1개 구현** — z 투영 + 그림자 + 가림 규칙 + `heightScale` 감 잡기
5. 픽셀아트 줌(정수 배율) 품질 확인
6. `leak_tracker` 메모리 프로파일 (장시간 구동 타이쿤 특성상 필수 — [선행 리서치](2026-08-31_flutter-flame-vs-godot-2d-game.md) §7)

### 아키텍처 방침
- **로직/렌더 분리**: 경영·경기 시뮬 = 순수 Dart 코어 / Flame = 렌더+입력만
- **맵 데이터 자체 포맷(JSON) + 코드 로드**: flame_tiled의 experimental 아이소메트릭에 의존하지 않음. 타이쿤은 건물 배치가 런타임 로직이라 외부 에디터 의존도가 원래 낮음
- **AI 하네스**: `claude plugin install dart-flutter@dart-flutter` + `flame_test` 골든 테스트를 CI 루프에 포함
- 오디오는 `audioplayers` 대신 `flutter_soloud` 검토 (선행 리서치의 실무 고통 지점)

---

## 상충/불확실 정보

| 쟁점 | 내용 | 판정 |
|---|---|---|
| Flame 엔티티 한계 수치 | 검증 에이전트 보고(웹 3,200/iOS 4,000) vs 원본 그래프 직접 판독(웹 2,500/iOS 5,900) | **그래프 판독값 채택** (2026-08-31 image8/9 직접 검증). 어느 쪽이든 결론 동일 |
| `IsometricTileMapComponent` 대형 맵 렌더 비용 | 컬링·배칭 없이 전체 순회 — 실측 자료 없음 | 스파이크 측정 항목 |
| Victorian Idle (유일한 Flame 추정 경영 게임) | Flame 사용 여부 미확인 | 사례로 인용 금지 |
| 카이로소프트 『농구클럽 이야기』의 구현 상세 | 아이소메트릭+슛 궤적 조합이라는 점만 | (모델 지식, 미검증) |
| Reddit 커뮤니티 논의 | 크롤러 차단으로 제목·URL만 확인, 본문 미검증 | 결측을 부재로 읽지 말 것 |

## 출처 목록 (핵심 — 전체 204개는 _workspace/04 참조)

- [bluefireteam/heeve](https://github.com/bluefireteam/heeve) / [ordered_map_component.dart](https://github.com/bluefireteam/heeve/blob/main/lib/ordered_map_component.dart) — 유일한 레퍼런스 구현
- [flame#1882](https://github.com/flame-engine/flame/issues/1882) — flame_tiled 아이소메트릭 "experimental" 기여자 발언
- [flame#3794](https://github.com/flame-engine/flame/issues/3794) — 아이소메트릭 배치 오프셋 버그 (open)
- [flame#2810](https://github.com/flame-engine/flame/issues/2810) — 정수배율 뷰포트 미구현 (open)
- [flame#1938](https://github.com/flame-engine/flame/issues/1938) — 전역 z-index 부재 (이 장르 비쟁점)
- [filiph.net 벤치마크](https://filiph.net/text/benchmarking-flutter-flame-unity-godot.html) + 그래프 [image8](https://filiph.net/text/imgs/image8.png)/[image9](https://filiph.net/text/imgs/image9.png) (직접 판독 검증)
- [awesome-flame](https://github.com/flame-engine/awesome-flame) — 66건 전수 조사 (아이소메트릭·타이쿤 0건)
- [2026-08-31 엔진 비교 리서치](2026-08-31_flutter-flame-vs-godot-2d-game.md) — Flame 채택 근거·공통 리스크
