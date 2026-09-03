# test_of_basketball — 프로젝트 컨셉 정리

작성일: 2026-09-03

## 이 프로젝트는 무엇인가

**Flutter + Flame으로 아이소메트릭 농구 시뮬레이션 게임을 테스트하는 실험 프로젝트.**

- 레퍼런스: 카이로소프트(Kairosoft) 『농구클럽 이야기(Basketball Club Story)』
  - 아이소메트릭 픽셀 그래픽 + 팀 경영 타이쿤 + 자동 진행 경기 관전이라는 조합을 기준으로 삼는다
- 목적: 본편 제작이 아니라 **핵심 기술 요소가 Flame에서 성립하는지 검증**하는 테스트베드
- 전제: 코드 온리 워크플로우(Flame은 에디터가 없음), AI 코딩 에이전트 적극 활용

## 왜 Flame인가 (선행 리서치 결론)

[엔진 비교 리서치](./2026-08-31_flutter-flame-vs-godot-2d-game.md) 결론: Flutter 개발자 + 코드 온리 선호 + AI 에이전트 활용 전제에서는 Flame이 적합. 성능 상한은 Godot이 높지만, 이 장르(엔티티 수십~수백, UI 비중 큼, 물리 불필요)는 Flame의 약점을 대부분 비켜간다.

## 핵심 설계 방침 (선행 문서 요약)

1. **로직/렌더 분리** — 시뮬레이션(경기·경영)은 순수 Dart 코어로, Flame은 틱 스트림을 재생하는 연출 층으로만 사용. 헤드리스 대량 시뮬레이션과 `flutter test` 기반 검증 루프의 전제. ([매치 엔진 설계](./2026-09-02_basketball-tycoon-match-engine-design.md))
2. **경기 시뮬은 창발 코어** — 역할 스티어링 + 근접 트리거 판정 + 디렉터 가드레일 4종(스틸 쿨다운, 슛 효용 함수, 분리 벡터, 전역 템포 계수). 감독 지시 = 파라미터 런타임 변경.
3. **재현성 규율** — 고정 틱 + 시드 RNG + 이산적 개입 로그. 같은 시드 = 같은 경기.
4. **아이소메트릭 + z축은 투영 트릭** — 시뮬레이션은 `(x, y, z)` 3D, 렌더는 `isoProject(x,y) − z·heightScale` + 바닥 그림자. 깊이 정렬은 바닥 기준 `block.x + block.y`(Heeve 패턴). ([타당성 검토](./2026-09-02_flame-isometric-basketball-tycoon.md))
5. **최대 리스크는 선례 부재** — Flame 아이소메트릭 타이쿤은 확인된 선행 사례 0건. 유일한 레퍼런스는 [bluefireteam/heeve](https://github.com/bluefireteam/heeve) (2021년 코드, 현행 API로 포팅 필요).

## 이 테스트에서 검증할 것 (타당성 문서의 스파이크 항목)

1. Heeve `OrderedMapComponent` 패턴을 Flame 최신 API로 포팅 (깊이 정렬)
2. 코트+관중석 규모 맵에서 `IsometricTileMapComponent` 렌더 비용 측정
3. 캐릭터 다수 y-sort 프레임타임 측정
4. 슛 장면 1개 구현 — z 투영 포물선 + 그림자 + 림/백보드 가림 규칙 + `heightScale` 튜닝
5. 픽셀아트 정수 배율 줌 품질 확인
6. `leak_tracker` 메모리 프로파일

## 문서 목차

### 프로젝트 설계 문서
| 문서 | 내용 |
|---|---|
| [2026-08-31_flutter-flame-vs-godot-2d-game.md](./2026-08-31_flutter-flame-vs-godot-2d-game.md) | 엔진 선정 리서치 — Flame 채택 근거 |
| [2026-09-02_flame-isometric-basketball-tycoon.md](./2026-09-02_flame-isometric-basketball-tycoon.md) | 아이소메트릭·z축 기술 타당성 검토 (조건부 GO) |
| [2026-09-02_basketball-tycoon-match-engine-design.md](./2026-09-02_basketball-tycoon-match-engine-design.md) | 경기 시뮬레이션 엔진 설계 (창발 코어 + 감독 개입) |

### Flame 개발 레퍼런스 (`flame/` — game_playground에서 가져옴)
| 문서 | 내용 |
|---|---|
| [flame/01-getting-started.md](./flame/01-getting-started.md) | 설치, pubspec, 첫 게임 (`GameWidget`, `FlameGame`) |
| [flame/02-components.md](./flame/02-components.md) | 컴포넌트 시스템 (FCS) |
| [flame/03-game-loop.md](./flame/03-game-loop.md) | 게임 루프, `update`/`render` |
| [flame/04-input.md](./flame/04-input.md) | 탭·드래그 등 입력 처리 |
| [flame/05-collision.md](./flame/05-collision.md) | 충돌 감지 |
| [flame/06-camera-and-world.md](./flame/06-camera-and-world.md) | 카메라·월드·뷰포트 |
| [flame/07-effects-and-animation.md](./flame/07-effects-and-animation.md) | 이펙트·스프라이트 애니메이션 |
| [flame/08-assets-and-overlays.md](./flame/08-assets-and-overlays.md) | 에셋 로딩, Flutter overlay 연동 |
| [flame/09-ecosystem.md](./flame/09-ecosystem.md) | 생태계 패키지 (flame_tiled 등) |
| [flame/flame-guidelines.md](./flame/flame-guidelines.md) | 공통 개발 가이드라인 (고정 가상 해상도, UI 분리 등) |
| [flame/세로 모바일 게임 화면 비율 설계 가이드.md](./flame/세로%20모바일%20게임%20화면%20비율%20설계%20가이드.md) | 기기별 화면 비율 대응 설계 |

> 주의: `flame/` 문서들은 game_playground 프로젝트(Flame 1.35.x, forge2d 사용) 기준으로 작성됐다. 이 프로젝트는 물리 엔진(forge2d)을 쓰지 않으며, 버전·pubspec 수치는 이 프로젝트 기준으로 재확인할 것.
