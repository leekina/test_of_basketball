# 03. 게임 루프와 좌표계

## 루프 구조

Flame은 매 프레임마다 트리 전체를 순회하며:

1. `update(dt)` — 모든 컴포넌트의 로직 갱신
2. `render(canvas)` — 모든 컴포넌트 그리기

를 호출한다.

### `dt` (delta time)

`dt`는 **직전 프레임으로부터 흐른 시간(초)**. 프레임레이트가 흔들려도 일정한 속도를
유지하려면 항상 `dt`를 곱한다.

```dart
@override
void update(double dt) {
  super.update(dt);
  position.x += speed * dt; // ✅ 프레임레이트 독립적
  // position.x += 5;       // ❌ 빠른 기기에서 더 빨리 움직임
}
```

> 백그라운드 복귀 등으로 `dt`가 비정상적으로 커질 수 있다. `FlameGame`의
> `maxFrameTime`(기본 1초)으로 상한이 걸린다.

### `super`를 반드시 호출

`update`/`render`를 오버라이드하면 `super.update(dt)` / `super.render(canvas)`를
호출해야 자식 컴포넌트들이 함께 갱신·렌더링된다.

## Vector2

Flame의 모든 좌표/크기/속도는 `Vector2`(2D 벡터)다.

```dart
final v = Vector2(3, 4);
v.length;            // 5.0
v.normalized();      // 단위 벡터
v + Vector2(1, 1);   // 연산자 오버로드
v.scale(2);          // 제자리 스케일
Vector2.zero();      // (0,0)
Vector2.all(10);     // (10,10)
```

벡터 연산은 **제자리(in-place)** 메서드가 많으니 주의:
`a.add(b)`는 `a`를 바꾸고, `a + b`는 새 벡터를 만든다.

## 좌표계

- **로컬 좌표**: 컴포넌트 자신/부모 기준.
- **글로벌(화면) 좌표**: 위젯 픽셀 기준 — 입력 이벤트가 주는 좌표.
- **월드 좌표**: 카메라가 비추는 게임 세계 기준.

카메라가 있으면 화면 ↔ 월드 변환이 필요하다:

```dart
final worldPoint = camera.globalToLocal(screenPoint);
final screenPoint = camera.localToGlobal(worldPoint);
```

좌표계와 카메라 자세한 내용 → [06-camera-and-world.md](06-camera-and-world.md)

## 시간 제어

```dart
game.pauseEngine();   // 루프 정지
game.resumeEngine();  // 재개
game.paused = true;   // 동일

// 일정 시간 뒤 1회 실행
add(TimerComponent(period: 2, removeOnFinish: true, onTick: () => spawn()));

// 반복 실행
add(TimerComponent(period: 1, repeat: true, onTick: () => tick()));
```

다음: [04-input.md](04-input.md)
