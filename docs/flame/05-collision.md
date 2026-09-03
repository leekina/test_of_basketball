# 05. 충돌 감지

## 켜기

게임에 `HasCollisionDetection`을 걸고, 충돌에 참여할 컴포넌트에 **히트박스**를 추가한다.

```dart
class MyGame extends FlameGame with HasCollisionDetection {}

class Player extends PositionComponent with CollisionCallbacks {
  @override
  Future<void> onLoad() async {
    add(RectangleHitbox()); // 컴포넌트 size 에 맞는 사각 히트박스
  }
}
```

## 히트박스 종류

| 히트박스 | 모양 |
|----------|------|
| `RectangleHitbox` | 사각형 (기본은 부모 size 전체) |
| `CircleHitbox` | 원 |
| `PolygonHitbox` | 임의 다각형 |

```dart
add(RectangleHitbox(size: Vector2(20, 40), position: Vector2(5, 0)));
add(CircleHitbox(radius: 16, anchor: Anchor.center));
// 디버그 시 히트박스 보이기
add(RectangleHitbox()..debugMode = true);
// 충돌 판정은 하지 않고 영역 감지만(예: 트리거)
add(RectangleHitbox(collisionType: CollisionType.passive));
```

`collisionType`:
- `active` (기본): 다른 active/passive 와 충돌 검사.
- `passive`: active 와만 검사 (벽, 트리거 등 정적 객체에 적합 — 성능↑).
- `inactive`: 검사 제외.

## 콜백

`CollisionCallbacks` 믹스인:

```dart
class Player extends PositionComponent with CollisionCallbacks {
  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    if (other is Enemy) takeDamage();
  }

  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    // 충돌이 지속되는 매 프레임
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    // 떨어지는 순간
  }
}
```

- `points`: 교차 지점들(월드 좌표).
- `other`: 충돌 상대 컴포넌트. `is` 로 타입을 가려 분기한다.

## 레이캐스팅 / 광선

`HasCollisionDetection`을 켜면 `collisionDetection`을 통해 광선 추적도 가능하다.

```dart
final ray = Ray2(origin: pos, direction: dir.normalized());
final result = collisionDetection.raycast(ray);
if (result?.hitbox != null) { /* 맞은 대상 */ }

// 다중 광선(시야, 폭발 범위 등)
final results = collisionDetection.raycastAll(pos, numberOfRays: 36);
```

## 성능 팁

- 정적 객체(벽 등)는 `passive`로.
- 화면 밖 객체는 제거하거나 `inactive`로.
- 매우 많은 객체엔 `QuadTreeCollisionDetection`(`HasQuadTreeCollisionDetection`) 고려.

다음: [06-camera-and-world.md](06-camera-and-world.md)
