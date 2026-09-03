# 01. 시작하기

## 의존성 (이미 설정됨)

`pubspec.yaml`:

```yaml
dependencies:
  flame: ^1.35.1
  flutter_soloud: ^3.5.4        # 사운드

dev_dependencies:
  build_runner: ^2.15.0
  flutter_gen_runner: ^5.14.1   # 에셋 코드 생성

flutter_gen:
  output: lib/gen/
  integrations:
    image: true
  assets:
    exclude:
      - assets/**/.gitkeep

flutter:
  assets:
    - assets/images/
    - assets/audio/
```

## 가장 작은 게임

```dart
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(GameWidget(game: MyGame()));
}

class MyGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    // 컴포넌트를 여기서 추가한다.
  }
}
```

- **`FlameGame`**: 게임 루프와 컴포넌트 트리를 관리하는 루트 클래스.
- **`GameWidget`**: `FlameGame`을 Flutter 위젯 트리에 삽입하는 위젯. `MaterialApp`의
  `home` 등 어디든 둘 수 있다.

## `GameWidget` 의 두 가지 생성 방식

```dart
// 1) 게임 인스턴스를 직접 전달 (가장 단순)
GameWidget(game: MyGame())

// 2) 팩토리로 지연 생성 + 오버레이/로딩 위젯 지정
GameWidget.controlled(
  gameFactory: MyGame.new,
  loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
  overlayBuilderMap: {
    'pause': (context, MyGame game) => PauseMenu(game: game),
  },
)
```

> 핫리스타트 시 게임 상태를 보존하려면 게임 인스턴스를 `State` 에 보관하고
> 같은 인스턴스를 `GameWidget(game: ...)` 에 넘기면 된다.

## 실행

```bash
flutter pub get
dart run build_runner build   # 에셋을 추가/변경했다면
flutter run
```

## 다음 단계

게임은 결국 **컴포넌트의 트리**다. → [02-components.md](02-components.md)
