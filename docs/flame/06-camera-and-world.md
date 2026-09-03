# 06. 카메라와 월드

Flame은 **게임 세계(`World`)** 와 **그것을 비추는 카메라(`CameraComponent`)** 를
분리한다. `FlameGame`은 기본적으로 `world`와 `camera`를 미리 들고 있다.

```dart
class MyGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    world.add(Player());   // 게임 세계에 추가 (카메라 영향 받음)
    camera.viewport.add(Hud()); // 화면 고정 UI (카메라 영향 안 받음)
  }
}
```

- `world`에 넣은 것: 카메라의 이동/줌/회전에 따라 보이는 영역이 바뀐다.
- `camera.viewport`에 넣은 것: 화면에 고정된 HUD/UI.

## CameraComponent 구조

```
CameraComponent
├── Viewport   (화면에서 보이는 사각 영역 — 크기/위치)
│   └── Viewfinder (월드의 어디를, 얼마나 확대/회전해서 볼지)
└── World (별도 참조; 카메라가 무엇을 비출지)
```

직접 구성:

```dart
final world = World();
final camera = CameraComponent(world: world);
addAll([world, camera]);
```

## 카메라 조작

```dart
camera.viewfinder.position = Vector2(100, 200); // 보는 위치
camera.viewfinder.zoom = 2.0;                    // 확대
camera.viewfinder.angle = 0.1;                   // 회전(라디안)

// 대상 따라가기
camera.follow(player);
camera.follow(player, maxSpeed: 200); // 부드럽게
camera.stop();

// 한 번 이동
camera.moveTo(Vector2(500, 0));

// 이동 가능 범위 제한
camera.setBounds(Rectangle.fromLTRB(0, 0, 2000, 1000));
```

## 뷰포트 종류

| Viewport | 동작 |
|----------|------|
| `MaxViewport` (기본) | 사용 가능한 전체 영역 사용 |
| `FixedResolutionViewport` | 논리 해상도 고정, 레터박스로 비율 유지 |
| `FixedSizeViewport` | 고정 크기 사각 영역 |
| `CircularViewport` | 원형 클리핑 |

```dart
camera.viewport = FixedResolutionViewport(resolution: Vector2(640, 360));
```

## 좌표 변환

입력 이벤트는 화면 좌표를 주므로, 월드의 객체와 비교하려면 변환한다.

```dart
final worldPoint  = camera.globalToLocal(screenPoint);
final screenPoint = camera.localToGlobal(worldPoint);
```

## 디버그

`FlameGame`에서 `debugMode = true`(또는 컴포넌트별)로 좌표/히트박스/경계를 표시.

다음: [07-effects-and-animation.md](07-effects-and-animation.md)
