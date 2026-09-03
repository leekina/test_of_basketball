/// 코트 치수(미터, FIBA) — 순수 Dart. 시뮬레이션과 렌더 양쪽이 참조한다.
class CourtDims {
  static const double length = 28;
  static const double width = 15;
  static const double centerY = width / 2;

  static const double basketX = 1.575; // 림 중심, 베이스라인에서
  static const double backboardX = 1.2;
  static const double backboardHalf = 0.9;
  static const double rimRadius = 0.225;
  static const double rimHeight = 3.05;
  static const double keyLength = 5.8;
  static const double keyHalfWidth = 2.45;
  static const double ftCircleRadius = 1.8;
  static const double centerCircleRadius = 1.8;
  static const double threeRadius = 6.75;
  static const double threeSideOffset = 0.9;
}
