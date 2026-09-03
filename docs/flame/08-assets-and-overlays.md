# 08. 에셋 · 사운드 · 오버레이

이 프로젝트는 **에셋 관리에 flutter_gen**, **사운드에 flutter_soloud**를 쓴다.

## 에셋 (flutter_gen)

### 흐름

1. 파일을 `assets/images/` 또는 `assets/audio/` 에 넣는다.
2. `pubspec.yaml`의 `flutter > assets` 에 디렉터리가 등록돼 있어야 한다(이미 됨).
3. 코드 생성:
   ```bash
   dart run build_runner build           # 1회
   dart run build_runner watch           # 파일 변경 자동 감지
   ```
4. `lib/gen/assets.gen.dart` 에 타입 안전한 접근자가 생성된다.

```dart
import 'package:game_playground/gen/assets.gen.dart';

Assets.images.player.path;   // 'assets/images/player.png'
Assets.audio.shoot.path;     // 'assets/audio/shoot.wav'  ※ 오타 시 컴파일 에러
```

> `.gitkeep` 등은 `flutter_gen.assets.exclude` 로 제외돼 있다.

### flutter_gen 경로를 Flame 에 연결

Flame의 이미지 로더(`Sprite.load`, `Flame.images.load`)는 기본 prefix
`assets/images/` 를 **앞에 자동으로 붙인다**. 반면 flutter_gen의 `.path`는
`assets/images/...` 전체 경로다. 그대로 넘기면 경로가 중복된다.

**해결: prefix 를 비우고 flutter_gen 전체 경로를 그대로 사용한다.**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Flame.images.prefix = '';            // ← 한 번만 설정
  // ...
}

// 이후 어디서든 타입 안전하게:
sprite = await Sprite.load(Assets.images.player.path);
final image = await Flame.images.load(Assets.images.player.path);
```

(prefix 를 비우지 않으려면 파일명만 직접 문자열로 넘겨도 되지만, 그러면
flutter_gen 의 컴파일 타임 안전성을 못 누린다.)

## 사운드 (flutter_soloud)

`flame_audio` 대신 SoLoud 를 쓴다. 더 낮은 지연시간과 세밀한 제어가 장점.

### 초기화 (1회)

```dart
// lib/main.dart
await SoLoud.instance.init();
```

### 효과음 / BGM 재생

```dart
final soloud = SoLoud.instance;

// 1) 에셋을 메모리에 로드 (AudioSource). 보통 onLoad 등에서 미리 로드.
final shootSfx = await soloud.loadAsset(Assets.audio.shoot.path);
final bgm      = await soloud.loadAsset(Assets.audio.bgm.path);

// 2) 재생 — SoundHandle 반환
final handle = await soloud.play(shootSfx);

// 반복 재생(BGM)
final bgmHandle = await soloud.play(bgm, looping: true, volume: 0.6);

// 3) 제어
soloud.setVolume(bgmHandle, 0.3);
soloud.setPause(bgmHandle, true);
await soloud.stop(handle);

// 4) 더 안 쓰는 소스 해제
await soloud.disposeSource(shootSfx);
```

> `loadAsset` 은 `assets/...` 형태의 에셋 키를 그대로 받으므로 flutter_gen 의
> `Assets.audio.xxx.path` 와 정확히 호환된다(이미지와 달리 prefix 조정 불필요).

권장 패턴: 자주 쓰는 사운드는 게임 시작 시 한 번 `loadAsset` 해두고
`AudioSource`를 보관 → 재생 때마다 `play()` 만 호출.

## Flutter UI 오버레이

게임 위에 일반 Flutter 위젯(메뉴, HUD 버튼, 일시정지 화면)을 띄운다.

```dart
GameWidget(
  game: game,
  overlayBuilderMap: {
    'pause': (context, MyGame game) => PauseMenu(game),
    'gameOver': (context, MyGame game) => GameOverScreen(game),
  },
)
```

게임 코드에서 표시/숨김:

```dart
overlays.add('pause');       // 보이기
overlays.remove('pause');    // 숨기기
overlays.isActive('pause');
```

화면 전환(라우팅)이 많다면 `RouterComponent`(`Route`/`OverlayRoute`)도 고려.

다음: [09-ecosystem.md](09-ecosystem.md)
