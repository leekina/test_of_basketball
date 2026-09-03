import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../sim/match_sim.dart';
import 'court_lines.dart';
import 'court_spec.dart';
import 'court_tileset.dart';
import 'iso_projection.dart';
import 'match_layer.dart';
import 'tile_highlight.dart';

/// 아이소메트릭 농구 스파이크.
/// - 코트 타일맵 + 코트 라인 + 5v5 룰 기반 경기 시뮬 재생
/// - 카메라는 기본으로 공을 따라간다. 드래그하면 수동 패닝(추적 해제),
///   더블탭하면 다시 공 추적.
/// - 탭으로 타일 선택 (getBlock 클릭 판정 검증)
class BasketballCourtGame extends FlameGame {
  BasketballCourtGame({int simSeed = 42})
      : sim = MatchSim(seed: simSeed),
        super(
          camera: CameraComponent.withFixedResolution(
            width: viewWidth,
            height: viewHeight,
          ),
        );

  /// 가상 해상도 — 맵보다 작아 일부만 보이고 패닝으로 이동한다.
  static const double viewWidth = 640;
  static const double viewHeight = 360;

  final MatchSim sim;
  late final CourtMapComponent courtMap;
  late final TextComponent _scoreText;
  bool followBall = true;

  @override
  Future<void> onLoad() async {
    final tileset = await CourtTileset.generate();
    courtMap = CourtMapComponent(
      tileset,
      CourtSpec.buildMatrix(),
      destTileSize: CourtTileset.srcTileSize,
    );
    world.add(courtMap);
    camera.viewfinder.position = courtMap.size / 2;

    _scoreText = TextComponent(
      textRenderer: TextPaint(
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFFFFF),
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
        ),
      ),
      anchor: Anchor.topCenter,
      position: Vector2(viewWidth / 2, 8),
    );
    camera.viewport.add(_scoreText);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _scoreText.text =
        'HOME ${sim.homeScore} : ${sim.awayScore} AWAY   ⏱ ${sim.shotClock.toStringAsFixed(0)}';
    if (followBall && courtMap.isLoaded) {
      final ballPos = courtMap.matchLayer.ballCourtPos;
      final target = courtMap.iso.courtToLocal(ballPos.x, ballPos.y);
      final pos = camera.viewfinder.position;
      camera.viewfinder.position =
          pos + (target - pos) * (dt * 4).clamp(0.0, 1.0);
      _clampCamera();
    }
  }

  void panCamera(Vector2 worldDelta) {
    followBall = false;
    camera.viewfinder.position -= worldDelta;
    _clampCamera();
  }

  void _clampCamera() {
    final visible = camera.visibleWorldRect;
    final pos = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      _clampAxis(pos.x, visible.width / 2, courtMap.size.x),
      _clampAxis(pos.y, visible.height / 2, courtMap.size.y),
    );
  }

  /// 보이는 영역이 맵보다 크면 중앙 고정, 작으면 경계 안으로 클램프
  double _clampAxis(double value, double halfView, double mapExtent) {
    if (halfView * 2 >= mapExtent) {
      return mapExtent / 2;
    }
    return value.clamp(halfView, mapExtent - halfView);
  }
}

/// 코트 타일맵 + 경기 레이어 + 입력 처리(탭 선택, 드래그 패닝, 더블탭 추적).
class CourtMapComponent extends IsometricTileMapComponent
    with
        TapCallbacks,
        DragCallbacks,
        DoubleTapCallbacks,
        HasGameReference<BasketballCourtGame> {
  CourtMapComponent(super.tileset, super.matrix, {super.destTileSize});

  late final IsoProjection iso;
  late final MatchLayer matchLayer;
  late final TileHighlightComponent _highlight;

  @override
  Future<void> onLoad() async {
    iso = IsoProjection(this);
    add(CourtLinesComponent(iso: iso)..priority = 1);
    _highlight = TileHighlightComponent(tileSize: CourtTileset.diamondSize)
      ..priority = 2;
    add(_highlight);
    matchLayer = MatchLayer(sim: game.sim, iso: iso)..priority = 3;
    add(matchLayer);
  }

  @override
  void onTapUp(TapUpEvent event) {
    final block = getBlock(event.localPosition);
    if (!containsBlock(block)) {
      _highlight.visible = false;
      return;
    }
    _highlight
      ..position = getBlockRenderPosition(block)
      ..visible = true;
    debugPrint('tapped block: (${block.x}, ${block.y}) '
        'id=${blockValue(block)}');
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    game.panCamera(event.localDelta);
  }

  @override
  void onDoubleTapUp(DoubleTapEvent event) {
    game.followBall = true;
  }
}
