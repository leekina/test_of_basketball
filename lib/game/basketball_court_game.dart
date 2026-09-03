import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'court_lines.dart';
import 'court_spec.dart';
import 'court_tileset.dart';
import 'tile_highlight.dart';

/// 아이소메트릭 농구 코트 스파이크.
/// - 코트 타일맵 + 코트 라인 렌더
/// - 드래그로 카메라 패닝 (맵 경계 클램프)
/// - 탭으로 타일 선택 (getBlock 클릭 판정 검증)
class BasketballCourtGame extends FlameGame {
  BasketballCourtGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: viewWidth,
            height: viewHeight,
          ),
        );

  /// 가상 해상도 — 맵보다 작아 일부만 보이고 패닝으로 이동한다.
  static const double viewWidth = 640;
  static const double viewHeight = 360;

  late final CourtMapComponent courtMap;

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
  }

  void panCamera(Vector2 worldDelta) {
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

/// 코트 타일맵 + 입력 처리(탭 선택, 드래그 패닝).
class CourtMapComponent extends IsometricTileMapComponent
    with TapCallbacks, DragCallbacks, HasGameReference<BasketballCourtGame> {
  CourtMapComponent(super.tileset, super.matrix, {super.destTileSize});

  late final TileHighlightComponent _highlight;

  @override
  Future<void> onLoad() async {
    add(CourtLinesComponent(map: this));
    _highlight = TileHighlightComponent(tileSize: CourtTileset.diamondSize);
    add(_highlight);
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
}
