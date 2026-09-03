# 07. 이펙트와 애니메이션

## 이펙트 (Effects)

이펙트는 컴포넌트의 속성(위치/회전/크기/투명도/색)을 시간에 따라 변화시키는
컴포넌트다. `add` 하면 동작하고 끝나면 보통 스스로 제거된다.

```dart
// 1초 동안 (200, 300) 으로 이동
player.add(MoveEffect.to(Vector2(200, 300), EffectController(duration: 1)));

// 상대 이동
player.add(MoveEffect.by(Vector2(0, -50), EffectController(duration: 0.5)));

// 회전 / 크기 / 투명도 / 색
player.add(RotateEffect.by(pi, EffectController(duration: 1)));
player.add(ScaleEffect.to(Vector2.all(2), EffectController(duration: 0.3)));
player.add(OpacityEffect.fadeOut(EffectController(duration: 0.5)));
player.add(ColorEffect(Colors.red, EffectController(duration: 0.2)));
```

### EffectController — 타이밍 제어

```dart
EffectController(
  duration: 1,
  reverseDuration: 1,   // 되돌아오기
  infinite: true,       // 무한 반복 (펄스 등)
  alternate: true,      // 정방향↔역방향 번갈아
  curve: Curves.easeInOut,
  startDelay: 0.5,
);
```

### 조합

```dart
// 순차 실행
player.add(SequenceEffect([
  MoveEffect.by(Vector2(50, 0), EffectController(duration: 0.5)),
  RotateEffect.by(pi, EffectController(duration: 0.5)),
]));
```

## 스프라이트 (단일 이미지)

```dart
class Coin extends SpriteComponent {
  @override
  Future<void> onLoad() async {
    // assets/images/coin.png 로드 (Flame 기본 prefix: assets/images/)
    sprite = await Sprite.load('coin.png');
    size = Vector2.all(32);
  }
}
```

## 스프라이트 애니메이션 (프레임)

스프라이트 시트(가로로 나열된 프레임)에서 애니메이션을 만든다.

```dart
class Hero extends SpriteAnimationComponent {
  @override
  Future<void> onLoad() async {
    final image = await Flame.images.load('hero_run.png');
    animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 8,                  // 프레임 수
        stepTime: 0.1,              // 프레임당 시간(초)
        textureSize: Vector2(48, 48),
      ),
    );
    size = Vector2(48, 48);
  }
}
```

## 상태별 애니메이션 — SpriteAnimationGroupComponent

이동/정지/점프처럼 상태에 따라 애니메이션을 바꾼다.

```dart
enum HeroState { idle, run }

class Hero extends SpriteAnimationGroupComponent<HeroState> {
  @override
  Future<void> onLoad() async {
    animations = {
      HeroState.idle: idleAnim,
      HeroState.run: runAnim,
    };
    current = HeroState.idle;
  }
}
// 전환: hero.current = HeroState.run;
```

## 파티클

폭발/먼지 같은 짧은 효과는 `ParticleSystemComponent`.

```dart
add(ParticleSystemComponent(
  particle: Particle.generate(
    count: 20,
    generator: (i) => AcceleratedParticle(
      acceleration: Vector2(0, 100),
      child: CircleParticle(radius: 2, paint: Paint()..color = Colors.orange),
    ),
  ),
));
```

다음: [08-assets-and-overlays.md](08-assets-and-overlays.md)
