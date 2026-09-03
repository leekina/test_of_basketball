# Flame 게임 개발 가이드라인

이 프로젝트(`game_playground`)에서 Flame + flame_forge2d로 게임을 만들 때 공통으로 지키는 규칙을 정리한다. 게임별 세부 스펙이 아니라 **모든 게임에 공통 적용되는 원칙** 이다. 새 게임을 추가하거나 기존 게임을 리팩터링할 때 이 문서를 기준으로 한다.

> 살아있는 문서: Flame 사용 방식이나 컨벤션이 바뀌면 이 문서도 함께 업데이트한다.

---

## 1. 좌표계: 카메라 고정 해상도 + UI 분리

**원칙: 게임 플레이(물리 월드)는 카메라 고정 가상 해상도, UI는 화면 픽셀/overlay로 분리한다.**

`size.x` / `size.y`(실제 픽셀)에 맞춰 물리값을 계산하지 않는다. `flame_forge2d`(Box2D)는 중력·임펄스·밀도 등이 월드 좌표(미터) 기준으로 동작하므로, 픽셀에 맞춰 계산하면 디바이스마다 물리 거동(낙하감, 튕김, 병합 타이밍)이 달라진다. 카메라로 가상 해상도를 고정하면 모든 기기에서 동일한 플레이가 보장되고, 게임 로직이 실제 픽셀과 분리된다.

| 영역 | 좌표계 |
|------|--------|
| 물리 월드 (과일, 항아리 벽, 중력) | 카메라 가상 해상도(월드 단위) |
| 점수·버튼·게임오버 등 UI | Flutter `overlays` 또는 화면 픽셀 |

```dart
camera = CameraComponent.withFixedResolution(
  world: world,
  width: 360,   // 게임 디자인 기준 가상 해상도
  height: 640,
);
```

- 세로 고정 레이아웃(수박게임 등)은 `withFixedResolution`(비율 유지 + 레터박스)이 적합하다.
- 다른 옵션: `FixedAspectRatioViewport`(비율 고정), `MaxViewport` + Viewfinder의 `visibleGameSize`(특정 영역 항상 보이기).
- 화면 좌표 ↔ 월드 좌표 변환은 `camera.globalToLocal` / `localToGlobal` 사용.

`size.x` / `size.y`가 적합한 경우: 배경을 화면 끝까지 채울 때, UI 오버레이 배치.

---

## 2. 구조 / 컴포넌트

- Component 트리를 얕고 명확하게. 게임 로직은 `Component` / `PositionComponent`로 쪼개고 전역 상태를 한 클래스에 몰지 않는다. (예: `FruitComponent`, `WallComponent`, `ArenaComponent`)
- `HasGameReference` mixin으로 컴포넌트에서 game 인스턴스에 타입 안전하게 접근한다. `findGame()!` 남발 금지.
- 렌더링과 로직 분리: `update(dt)`에는 상태 변화만, `render(canvas)`에는 그리기만. `update`에서 그리거나 `render`에서 상태를 바꾸지 않는다.

## 3. 게임 루프 / 물리 (Forge2D 핵심)

- **`dt`를 반드시 사용.** 이동·타이머를 프레임이 아니라 `dt`(경과 시간) 기준으로 계산해야 기기 프레임레이트(60/120Hz)에 관계없이 동일하게 동작한다.
- **물리 콜백 중 바디 생성/삭제 금지.** `beginContact`(충돌 콜백) 안에서 바로 `createBody` / `removeBody`를 호출하면 Box2D가 크래시난다. → 큐에 담아 다음 `update`에서 처리한다. (수박게임의 "contact queue로 병합"이 이 패턴.)
- **월드 스케일 주의.** Box2D는 0.1~10m 크기에서 가장 안정적이다. 객체를 너무 크게 잡으면 물리가 불안정해진다. 적절한 픽셀↔미터 스케일 상수를 둔다.

## 4. 리소스 / 성능

- 에셋은 `onLoad`에서 한 번만 로드한다. 이미지/오디오를 `Images` · `FlameAudio` 캐시로 미리 로드하고 재사용. `update` / `render`에서 매번 로드 금지.
- `Paint` 객체 재사용. `render`에서 매 프레임 `Paint()`를 새로 만들지 말고 필드로 캐싱한다.
- 자주 생성/삭제되는 객체가 많아지면 오브젝트 풀링을 고려한다.

## 5. 입력 / 상태

- 입력 mixin 사용: `TapCallbacks`, `DragCallbacks` 등을 컴포넌트 단위로 적용.
- 게임 상태를 명시적 enum으로 둔다. `playing / paused / gameOver` 상태 머신을 두면 `pauseEngine()` / `resumeEngine()`과 깔끔하게 연동된다.
- UI(버튼·점수·게임오버 화면)는 Flame 렌더링 대신 Flutter 위젯 `overlays`로 처리한다 → 접근성·레이아웃이 쉬워진다.

## 6. 테스트 / 검증

(CLAUDE.md의 개발 워크플로우와 일치)

- **순수 로직은 단위 테스트(TDD).** 점수 계산, 병합 규칙(어떤 tier + 어떤 tier = 다음 tier), 게임오버 판정 등은 Flame 의존성 없이 순수 함수로 빼서 테스트한다.
- **물리 / 렌더 / 입력은 앱 실행으로 검증.**
- `flame_test`의 `testWithGame` / `testWithFlameGame`으로 컴포넌트 마운트·라이프사이클 테스트 가능.

## 7. 기타

- `debugMode = true`로 컴포넌트 경계·바디 외곽선을 확인하며 물리 디버깅한다.
- 반응형(responsive) 대응은 직접 계산하지 말고 카메라에 위임한다(섹션 1 참고).
