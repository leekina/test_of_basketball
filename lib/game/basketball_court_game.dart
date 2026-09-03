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
  /// (크게 잡을수록 카메라가 뒤로 빠진 느낌 — 코트가 더 넓게 보인다)
  static const double viewWidth = 880;
  static const double viewHeight = 495;

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

    camera.viewport.add(
      TextComponent(
        text: '노란 링: 볼 소유 · 머리 위 빨간 칸: HP (압박당하면 감소) · 발밑: 현재 상태',
        textRenderer: TextPaint(
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xCCFFFFFF),
            shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
          ),
        ),
        anchor: Anchor.bottomLeft,
        position: Vector2(8, viewHeight - 6),
      ),
    );

    camera.viewport.add(FollowBallButton());
    camera.viewport.add(ZoneButton(ZoneScheme.twoThree, '2-3', slot: 1));
    camera.viewport.add(ZoneButton(ZoneScheme.threeTwo, '3-2', slot: 0));
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

/// 수동 패닝 중일 때 우하단에 뜨는 "공 따라가기" 버튼.
class FollowBallButton extends PositionComponent
    with TapCallbacks, HasGameReference<BasketballCourtGame> {
  FollowBallButton()
      : super(
          size: Vector2(112, 34),
          anchor: Anchor.bottomRight,
          position: Vector2(
            BasketballCourtGame.viewWidth - 10,
            BasketballCourtGame.viewHeight - 52, // 존 버튼 위
          ),
        );

  static final Paint _bgPaint = Paint()..color = const Color(0xCC222831);
  static final Paint _borderPaint = Paint()
    ..color = const Color(0xFFFFE066)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final TextPaint _labelPaint = TextPaint(
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFE066),
    ),
  );

  @override
  bool containsLocalPoint(Vector2 point) =>
      !game.followBall && super.containsLocalPoint(point);

  @override
  void render(Canvas canvas) {
    if (game.followBall) {
      return; // 이미 추적 중이면 숨김
    }
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, _bgPaint);
    canvas.drawRRect(rect, _borderPaint);
    _labelPaint.render(
      canvas,
      '📷 공 따라가기',
      size / 2,
      anchor: Anchor.center,
    );
  }

  @override
  void onTapUp(TapUpEvent event) {
    game.followBall = true;
  }
}

/// 우하단 지역방어 대형 전환 버튼 (2-3 / 3-2) — 언제든 탭으로 변경.
class ZoneButton extends PositionComponent
    with TapCallbacks, HasGameReference<BasketballCourtGame> {
  ZoneButton(this.scheme, this.label, {required int slot})
      : super(
          size: Vector2(52, 32),
          anchor: Anchor.bottomRight,
          position: Vector2(
            BasketballCourtGame.viewWidth - 10 - slot * 58,
            BasketballCourtGame.viewHeight - 10,
          ),
        );

  final ZoneScheme scheme;
  final String label;

  static final Paint _bgPaint = Paint()..color = const Color(0xCC222831);
  static final Paint _activeBgPaint = Paint()
    ..color = const Color(0xCC3D6BFF);
  static final Paint _borderPaint = Paint()
    ..color = const Color(0x88FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final TextPaint _labelPaint = TextPaint(
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFFFFFF),
    ),
  );

  @override
  void render(Canvas canvas) {
    final active = game.sim.zoneScheme == scheme;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, active ? _activeBgPaint : _bgPaint);
    canvas.drawRRect(rect, _borderPaint);
    _labelPaint.render(canvas, label, size / 2, anchor: Anchor.center);
  }

  @override
  void onTapUp(TapUpEvent event) {
    game.sim.zoneScheme = scheme;
  }
}
