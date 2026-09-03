# 04. 입력 처리

Flame의 권장 방식은 **컴포넌트 단위 믹스인**이다. 게임 전체에 거는 방식보다
"어떤 객체가 입력을 받는가"가 명확하다.

## 탭

컴포넌트에 `TapCallbacks`를 붙이면, 그 컴포넌트의 영역(`size`/`hitbox`) 안에서
일어난 탭만 받는다.

```dart
class Button extends PositionComponent with TapCallbacks {
  @override
  void onTapDown(TapDownEvent event) {
    // event.localPosition : 이 컴포넌트 기준 좌표
  }

  @override
  void onTapUp(TapUpEvent event) {}

  @override
  void onTapCancel(TapCancelEvent event) {}
}
```

게임 전체(빈 공간 포함) 탭을 받으려면 `FlameGame`에 직접 `TapCallbacks`를 건다.
이때 `event.localPosition`은 화면 좌표이므로 월드 변환이 필요할 수 있다:

```dart
class MyGame extends FlameGame with TapCallbacks {
  @override
  void onTapDown(TapDownEvent event) {
    final world = camera.globalToLocal(event.localPosition);
  }
}
```

## 드래그

```dart
class Draggable extends PositionComponent with DragCallbacks {
  @override
  void onDragUpdate(DragUpdateEvent event) {
    position += event.localDelta; // 이동량 누적
  }

  @override
  void onDragStart(DragStartEvent event) {}
  @override
  void onDragEnd(DragEndEvent event) {}
}
```

## 키보드

게임에 `HasKeyboardHandlerComponents`를 걸고, 키를 받을 컴포넌트에
`KeyboardHandler`를 붙인다.

```dart
class MyGame extends FlameGame with HasKeyboardHandlerComponents {}

class Player extends PositionComponent with KeyboardHandler {
  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      position.x += 5;
    }
    return true; // false 면 다른 핸들러로 전파
  }
}
```

게임 레벨에서 한 번에 처리하려면 `KeyboardEvents` 믹스인의 `onKeyEvent`를 쓴다.

## 포인터 호버/이동 (데스크톱·웹)

```dart
class Hoverable extends PositionComponent with HoverCallbacks {
  @override
  void onHoverEnter() {}
  @override
  void onHoverExit() {}
}
```

마우스 이동 추적은 `PointerMoveCallbacks`(`onPointerMove`).

## 정리

| 입력 | 컴포넌트 믹스인 | 게임 믹스인(전체 처리) |
|------|----------------|------------------------|
| 탭 | `TapCallbacks` | `TapCallbacks` |
| 드래그 | `DragCallbacks` | `DragCallbacks` |
| 키보드 | `KeyboardHandler` | `KeyboardEvents` (+ `HasKeyboardHandlerComponents`) |
| 호버 | `HoverCallbacks` | — |
| 포인터 이동 | `PointerMoveCallbacks` | `PointerMoveCallbacks` |

> 컴포넌트 단위 탭/드래그가 정확히 동작하려면 컴포넌트에 `size`가 설정되어 있거나
> 히트박스가 있어야 한다. 비정형 모양은 `add(RectangleHitbox())` 등으로 영역을 정의한다.

다음: [05-collision.md](05-collision.md)
