# 09. Flame 생태계 (확장 패키지)

Flame 코어 위에 얹는 공식 브리지 패키지들. 필요할 때 `flutter pub add` 한다.

| 패키지 | 용도 | 비고 |
|--------|------|------|
| `flame_forge2d` | Box2D 기반 2D 물리 (중력, 충돌 반응, 관절) | 사실적 물리 필요 시 |
| `flame_tiled` | [Tiled](https://www.mapeditor.org/) 맵 에디터(`.tmx`) 로딩 | 타일맵 레벨 |
| `flame_audio` | AudioPlayers 기반 오디오 | **이 프로젝트는 SoLoud 사용** — 보통 불필요 |
| `flame_bloc` | bloc 상태관리 연동 | 게임 ↔ 앱 상태 분리 |
| `flame_rive` | [Rive](https://rive.app) 인터랙티브 애니메이션 | 벡터 애니메이션 |
| `flame_svg` | SVG 렌더링 | 벡터 이미지 |
| `flame_spine` | Spine 2D 애니메이션 | — |
| `flame_lottie` | Lottie 애니메이션 | — |
| `flame_gamepads` | 게임패드/컨트롤러 입력 | 콘솔식 입력 |
| `flame_fire_atlas` | FireAtlas 텍스처 아틀라스 | 스프라이트 패킹 |
| `flame_texturepacker` | TexturePacker 스프라이트 시트 | 스프라이트 패킹 |
| `flame_network_assets` | 네트워크 에셋 로딩 | 원격 이미지 |
| `flame_isolate` | 무거운 연산을 Isolate 로 | 프레임 드랍 방지 |
| `flame_lint` | Flame 팀 lint 규칙 | 개발 편의 |

## 선택 가이드

- **물리 기반 게임(공 튀기기, 차량, 천 시뮬레이션 등)** → `flame_forge2d`.
  단순 이동/충돌만 필요하면 코어의 `update(dt)` + 히트박스로 충분하다([05](05-collision.md)).
- **타일 기반 레벨/맵** → Tiled 로 제작 후 `flame_tiled`.
- **사운드** → 이 프로젝트는 `flutter_soloud` 채택([08](08-assets-and-overlays.md)).
  굳이 `flame_audio` 를 함께 쓸 필요는 없다.
- **복잡한 앱 상태(메뉴/저장/과금) 연동** → `flame_bloc` 또는 일반 상태관리.

## 버전 호환 주의

확장 패키지는 코어 `flame` 버전에 강하게 묶인다. 추가 시
`flutter pub add flame_xxx` 후 `flutter pub get` 이 버전을 맞춰주며,
충돌 시 `flutter pub outdated` / SDK 업그레이드가 필요할 수 있다.

## 참고

- 패키지 목록(공식): https://docs.flame-engine.org/latest/#bridge-packages
- 모든 라이브 예제: https://examples.flame-engine.org
