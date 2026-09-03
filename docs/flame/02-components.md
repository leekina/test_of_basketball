# 02. 컴포넌트 시스템 (FCS)

Flame의 모든 것은 **컴포넌트**다. 게임은 `FlameGame`을 루트로 하는 컴포넌트 트리이며,
각 컴포넌트는 자식을 가질 수 있다.

## 라이프사이클

호출 순서와 용도:

| 메서드 | 시점 | 용도 |
|--------|------|------|
| `onLoad()` `async` | 마운트 직전 1회 | 에셋 로드, 초기 자식 추가. `await` 가능 |
| `onMount()` | 트리에 붙을 때마다 | 부모/게임에 의존하는 초기화 |
| `onGameResize(size)` | 마운트 시 + 화면 크기 변경 시 | 레이아웃 대응 |
| `update(dt)` | 매 프레임 | 게임 로직 (이동, 상태 갱신) |
| `render(canvas)` | 매 프레임 | 그리기 |
| `onRemove()` | 트리에서 제거될 때 | 정리 |

```dart
class Enemy extends PositionComponent {
  @override
  Future<void> onLoad() async {
    // 에셋 로드 등 무거운 초기화. async 가능.
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x += 100 * dt; // 초당 100px 이동
  }
}
```

## 컴포넌트 추가/제거

```dart
add(child);                 // 자식 1개 추가 (async — 마운트는 다음 프레임)
addAll([a, b, c]);          // 여러 개 추가
await add(child);           // 마운트 완료까지 대기
remove(child);              // 제거
child.removeFromParent();   // 스스로 제거
```

> 추가/제거는 즉시가 아니라 다음 프레임 경계에서 반영된다. 순회 중 안전하게 변경하기 위해서다.

## 주요 내장 컴포넌트

| 컴포넌트 | 설명 |
|----------|------|
| `Component` | 시각 표현 없는 기본 단위 (로직 묶음, 매니저 등) |
| `PositionComponent` | `position`/`size`/`anchor`/`angle`/`scale` 을 가진 화면 객체의 기반 |
| `SpriteComponent` | 단일 스프라이트(이미지) 렌더링 |
| `SpriteAnimationComponent` | 프레임 애니메이션 |
| `SpriteGroupComponent` | 상태(state)에 따라 스프라이트 교체 (버튼 등) |
| `TextComponent` | 텍스트 렌더링 |
| `RectangleComponent` / `CircleComponent` / `PolygonComponent` | 도형 |
| `ParallaxComponent` | 시차 스크롤 배경 |
| `SpawnComponent` | 일정 주기/영역으로 컴포넌트 자동 생성 |

### PositionComponent의 핵심 속성

```dart
final c = PositionComponent(
  position: Vector2(100, 50), // 부모 기준 좌표
  size: Vector2(64, 64),
  anchor: Anchor.center,      // 기본은 topLeft
);
c.angle = pi / 4;             // 라디안 회전
c.scale = Vector2.all(2);     // 2배 확대
c.priority = 10;              // 렌더 순서 (클수록 위)
```

## 게임/부모 참조

컴포넌트에서 게임 인스턴스가 필요하면 `HasGameReference` 믹스인을 쓴다.

```dart
class Bullet extends PositionComponent with HasGameReference<MyGame> {
  void fire() {
    game.score += 1;            // 타입 안전하게 게임 접근
  }
}
```

부모 참조: `parent`, 트리 탐색: `ancestors()`, `firstChild<T>()`, `children`.

## 자주 쓰는 믹스인

| 믹스인 | 역할 |
|--------|------|
| `HasGameReference<T>` | `game` 게터로 루트 게임 접근 |
| `TapCallbacks` / `DragCallbacks` | 컴포넌트 단위 입력 ([04](04-input.md)) |
| `CollisionCallbacks` | 충돌 콜백 ([05](05-collision.md)) |
| `HasVisibility` | `isVisible` 토글 |

다음: [03-game-loop.md](03-game-loop.md)
