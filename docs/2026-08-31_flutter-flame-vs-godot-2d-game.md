# Flutter Casual Games Toolkit vs Flame vs Godot — 2D 모바일 게임 스택 비교 리서치
조사일: 2026-08-31 | 조사 범위: 공식 문서·GitHub/pub.dev API 실측·filiph.net 벤치마크(원본 그래프 직접 판독)·커뮤니티(Reddit 미러/HN/Godot Forum)
전제 조건: ① 2D 게임 ② Flutter 개발자가 제작 ③ 에디터 마우스 조작 비선호(코드 온리 선호) ④ AI 코딩 에이전트(Claude Code 등) 적극 활용

> 상세 원자료: `_workspace/01_researcher_flutter-games-flame.md`(툴킷·Flame, 출처 91개),
> `_workspace/02_researcher_godot-code-first.md`(Godot 코드 중심 개발),
> `_workspace/03_researcher_ai-assisted-gamedev.md`(AI 활용 적합성)

---

## 핵심 발견 (결론 먼저)

1. **비교 구도 자체가 잘못됐다 — Casual Games Toolkit은 선택지가 아니다.** 툴킷은 엔진이 아니라 템플릿 3종+샘플 3종의 스캐폴딩이며, "조용한 방치(quiet neglect)" 상태다: 2026년 사람 커밋 3건, GitHub Issues 비활성화, 간판 데모 3종 전부 아카이브(`superdash.flutter.dev`·`pinball.flutter.dev`는 DNS 사망), 공식 로드맵에서 casual games 문장이 [PR #166332로 명시 삭제](https://github.com/flutter/flutter/commit/43bb8a669d6f88999394966e51a4dbf4f779a8e4)(2025-04-02), 공식 블로그 27개월 침묵, 담당자(Filip Hráček) 퇴사. 실질 비교는 **Flame vs Godot**이다. ([상세](../_workspace/01_researcher_flutter-games-flame.md) §2)

2. **툴킷 방치 ≠ Flame 방치.** 툴킷 템플릿 3종 중 Flame 의존은 `endless_runner` 하나뿐(pubspec 실측). Flame은 독립 커뮤니티([flame-engine.org](https://flame-engine.org/)) 소유로 v1.38.2(2026-08-27) 활발히 유지보수 중 — Flutter 3.47 출시 다음 날 대응 커밋, 최근 90일 병합 PR 66건, 월 다운로드 121k. ([pub.dev](https://pub.dev/packages/flame))

3. **"코드 온리" 제약은 Flame이 구조적으로 만족시킨다.** Flame에는 비주얼 에디터가 아예 없어 코드 온리가 유일한 방식이다. Godot에서 코드 온리는 기술적으로 100% 가능하지만(`ClassName.new()`/`add_child()`, `PackedScene.pack()`, custom MainLoop) **공식 베스트 프랙티스 문서가 "현저히 느리다(significantly slower)"고 명시적으로 비권장**하며, 커뮤니티 합의도 "goes against the flow"다. ([Godot 공식 문서](https://docs.godotengine.org/en/stable/tutorials/best_practices/scenes_versus_scripts.html), [Godot Forum](https://forum.godotengine.org/t/is-it-possible-to-only-use-gdscript-and-completely-avoid-the-gui/20943))

4. **AI 적극 활용 전제에서는 격차가 더 벌어진다.**
   - 훈련 데이터: GitHub `language:Dart` 2,085,722 리포 vs `language:GDScript` 220,744 (9.4배, 2026-08-31 API 실측)
   - GDScript 고유 리스크: Godot 3→4 "버전 환각" — 특히 `connect("pressed", self, "_on_pressed")`는 Godot 4에서 **문법은 유효하나 무동작(무성 실패)**. Dart는 정적 타입+analyzer가 환각 API를 즉시 검출
   - 1st-party 하네스: Flutter는 Dart/Flutter MCP·Agent Skills·Agentic Hot Reload 전부 공식 Stable([docs.flutter.dev/ai/tools](https://docs.flutter.dev/ai/tools)). Godot은 공식 AI 도구 0개, 서드파티 MCP 486개로 파편화(최다 스타 프로젝트 4.5개월 정체)
   - 자율 검증 루프: Flame은 `flame_test` 골든 테스트로 GPU 없이 렌더 픽셀 검증 가능. Godot `--headless`는 렌더링을 꺼 스크린샷 불가([proposals#5790](https://github.com/godotengine/godot-proposals/issues/5790) 2022년 개설, 여전히 open) ([상세](../_workspace/03_researcher_ai-assisted-gamedev.md))

5. **성능 상한은 명확히 Godot 우위, 단 모바일 실효 지표는 Flame 우위.** filiph.net 벤치마크(2024-09, Flame 1.18/Godot 4.2.2) **원본 그래프 4장을 조사일에 직접 판독해 검증**한 수치:

   | 지표 | Flutter | **Flame** | Unity | **Godot** |
   |---|---:|---:|---:|---:|
   | 웹 최대 엔티티(프레임 드랍 전) | 400 | **2,500** | 7,200 | **8,300** |
   | iOS 최대 엔티티 | 4,300 | **5,900** | 13,500 | **2,500**⚠ |
   | 웹 최대 메모리(낮을수록 좋음) | 1,014MB | **2,277MB** | 520MB | **636MB** |
   | iOS 최대 메모리 | 764MB | **766MB** | 1,034MB | **1,089MB** |

   ⚠ Godot iOS 2,500은 저자가 자기 구현 오류 가능성을 명시한 이상치 — Godot 폄하 근거로 쓰지 말 것. 시사점: **Flame의 진짜 웹 약점은 엔티티 수가 아니라 메모리**(전 엔진 최악, Unity의 4.4배)이고, iOS에서는 최상위권. 시점 주의: Godot은 4.6(2026-01) 2D 렌더러 재설계로 1.1~7배 개선됐고 Flame도 20개 마이너 버전 경과 — 현재 수치는 재측정 필요. ([원문](https://filiph.net/text/benchmarking-flutter-flame-unity-godot.html), 그래프: image8/9/5/10.png)

6. **모바일 배포 실무는 Flame이 수월하다.** Godot 기본 APK는 90~114MB급이며, 검증된 최소화(40MB)조차 SCons+NDK로 엔진 직접 빌드가 필요하다. 광고/IAP도 Godot은 서드파티 플러그인 생태계 학습이 필요한 반면, Flame은 이미 쓰던 `google_mobile_ads`·`in_app_purchase` 등 Flutter 패키지를 그대로 쓴다. 메뉴·설정·상점 UI도 Flutter 위젯 재사용. ([상세](../_workspace/02_researcher_godot-code-first.md) §5)

7. **Flame의 감수해야 할 리스크(반대 근거).**
   - "게임 엔진이 아니라 프레임워크" — 패스파인딩·에셋 파이프라인·레벨 에디터 등을 직접 구현("게임 전에 엔진부터 만들게 된다"는 커뮤니티 합의)
   - **핫 리로드 통념은 거짓**: 게임 컴포넌트 트리에는 미적용([flame#3454](https://github.com/flame-engine/flame/issues/3454) open). Flutter 위젯 레이어(UI/HUD)만 가능
   - 메모리 해제 설계 교착([flame#3974](https://github.com/flame-engine/flame/issues/3974) — `Transform2D`가 `dispose()` 미구현, 수정 계획 없음): 장시간 구동 게임은 `leak_tracker` 자체 측정 필수
   - 기반의 얇음: 유지 주체 Blue Fire 연 예산 약 €2,925·핵심 기여자 3인(버스 팩터)
   - 오디오가 최대 실무 고통 지점(커뮤니티는 `audioplayers` 대신 `flutter_soloud` 권장), 상용 성공작 개발자들의 차기작 Godot 이탈 사례(Steam SDK 부재·물리 감각)
   - 최대 확인 수익 사례가 WalkScape 연 매출 €62,000 수준 — "가능하다"와 "흔하다"를 구분할 것

---

## 조건별 판정 매트릭스

| 기준 (질문자 전제) | Flame | Godot |
|---|---|---|
| 코드 온리 워크플로우 | ✅ 유일한 방식 (에디터 자체가 없음) | ⚠ 가능하나 공식 비권장·성능 경고 |
| 언어 (Flutter 개발자) | ✅ Dart 그대로 | ❌ GDScript 신규 (Dart와 안 닮음: 들여쓰기·snake_case·gradual typing) |
| AI 에이전트 코드 생성 품질 | ✅ 훈련 데이터 9.4배, analyzer가 환각 즉시 검출 | ❌ Godot 3/4 버전 환각, 무성 실패 유형 존재 |
| AI 자율 루프 (편집→테스트→검증) | ✅ `flutter test`+골든 테스트, 공식 MCP Stable | ⚠ 헤드리스 스크린샷 불가, MCP 전부 서드파티·파편화 |
| 게임이 텍스트인가 | ✅ 100% Dart | ⚠ `.tscn`/`.tres`/UID — 평문 편집 시 무성 파손 위험 |
| 앱 용량 / 기동 속도 | ✅ 수 MB급 / 빠름 | ❌ 기본 90MB+, 최적화에 엔진 직접 빌드 필요 |
| 광고·IAP·UI | ✅ Flutter 패키지·위젯 재사용 | ⚠ 별도 플러그인 생태계 (AdMob은 성숙, IAP는 3파전) |
| 2D 게임 전용 기능 내장 | ❌ 직접 구현 비중 큼 | ✅ 타일맵·애니메이션 트리·물리·셰이더 내장 |
| 렌더링 성능 상한 (엔티티 수) | ❌ 웹 2,500 / iOS 5,900 | ✅ 웹 8,300 (+4.6 렌더러 개선) |
| 상업적 검증 (2D) | ⚠ 인디 소규모 위주 | ✅ Brotato·Dome Keeper 급 (2차 소스, 개별 검증 필요) |
| 개발 반복 속도 | ⚠ 게임 로직 핫 리로드 불가 | ⚠ 에디터 의존 루프 (코드 온리 시 더 불리) |

## 권고

**질문자의 4개 전제를 모두 놓고 보면 Flutter + Flame이 맞다.** 단, 다음 형태로:

1. **Casual Games Toolkit은 의존 대상이 아니라 참고 자료로만** — `basic` 템플릿의 메뉴/설정/진행도 구조만 훔쳐 배우고, 시작은 Flame 공식 문서·코드랩에서 직접.
2. **AI 하네스를 먼저 깐다** — `claude plugin install dart-flutter@dart-flutter` (Dart/Flutter MCP + Agent Skills), `flame_test` 골든 테스트를 CI 루프에 포함.
3. **설계 시점에 Flame의 함정 3개를 회피** — 로직/렌더 분리(순수 Dart 게임 코어 + Flame은 렌더만: 13개 출시 개발자 검증 구조), 무거운 연산은 isolate로, 오디오는 `flutter_soloud` 검토.
4. **Godot으로 가야 하는 예외 조건** — 화면 내 엔티티 수백~수천(Vampire Survivors류), 복잡한 물리/스켈레탈 애니메이션 중심, 향후 3D·Steam 확장 계획. 이 경우 "코드 온리" 선호는 일부 포기하고 "씬은 최소 에디터, 로직은 전부 코드" 하이브리드가 현실적.
5. **1~2일 PoC가 어떤 추가 리서치보다 낫다** — Flame+Claude Code로 소형 게임 하나를 완주해 (a) 게임 로직 핫 리로드 부재의 실제 체감 (b) AI 생성 코드 품질 (c) `leak_tracker` 메모리 프로파일을 직접 측정할 것.

---

## 상충/불확실 정보

| 쟁점 | 내용 | 판정 |
|---|---|---|
| filiph 벤치마크 절대 수치 | 조사 과정에서 판독 시도마다 값이 엇갈렸음 (수치가 그래프 이미지에만 존재) | **조사일에 원본 PNG 4장(image5/8/9/10) 직접 판독으로 확정** — 위 표가 검증값 |
| 동 벤치마크 스타트업/용량 수치 (Flame ~0.8s vs Godot ~3.1s, 웹 8MB vs 35MB) | 에이전트 보고값, 그래프 직접 판독은 미수행 | 배수 관계만 신뢰, 절대값 인용 시 원문 재확인 |
| 벤치마크 시점 | 2024-09 (Flame 1.18 / Godot 4.2.2) — 이후 양쪽 다 대폭 변경 | 현재 격차는 재측정 없이 미확정 |
| Godot 4.7.2 릴리스일 | 공식 아카이브 08-18 vs 일부 요약 08-26 | 08-18 유력 |
| Agentic Hot Reload의 Flame 적용 | 공식 발표에 게임/Flame 언급 없음 | Flame 게임도 Flutter 앱이므로 동일 경로 추정 (모델 지식, 미검증) — PoC 확인 항목 |
| "Godot이 AI를 금지했다" 보도 | 2026-07-01 정책은 **엔진 리포 기여 PR 한정** | 게임 개발 AI 사용과 무관 |
| Godot 2D 상업 사례 (Brotato 등) | 2차 소스(gameenginehub) | 개별 검증 필요 |
| 커버리지 결측 | Reddit(Godot 조사분)·X/Bluesky·네이버 블로그 접근 불가 | 결측을 "부재"로 읽지 말 것 |

## 출처 목록 (핵심만 — 전체는 _workspace 3개 파일 참조)

- [docs.flutter.dev/resources/games-toolkit](https://docs.flutter.dev/resources/games-toolkit) — 툴킷 공식 문서
- [flutter/flutter@43bb8a66](https://github.com/flutter/flutter/commit/43bb8a669d6f88999394966e51a4dbf4f779a8e4) — 로드맵에서 casual games 삭제 (가장 결정적 단일 증거)
- [pub.dev/packages/flame](https://pub.dev/packages/flame) — v1.38.2, 월 121k 다운로드
- [docs.godotengine.org — Scenes versus scripts](https://docs.godotengine.org/en/stable/tutorials/best_practices/scenes_versus_scripts.html) — 코드 온리 공식 비권장 원문
- [Godot Forum — code-only 스레드](https://forum.godotengine.org/t/is-it-possible-to-only-use-gdscript-and-completely-avoid-the-gui/20943)
- [filiph.net 벤치마크](https://filiph.net/text/benchmarking-flutter-flame-unity-godot.html) + 그래프 [image8](https://filiph.net/text/imgs/image8.png)/[image9](https://filiph.net/text/imgs/image9.png)/[image5](https://filiph.net/text/imgs/image5.png)/[image10](https://filiph.net/text/imgs/image10.png)
- [docs.flutter.dev/ai/tools](https://docs.flutter.dev/ai/tools) — 공식 AI 하네스 (전부 Stable)
- [godot-proposals#5790](https://github.com/godotengine/godot-proposals/issues/5790) — 오프스크린 렌더링 미지원 (open)
- [flame#3454](https://github.com/flame-engine/flame/issues/3454) 핫 리로드 미지원 / [flame#3974](https://github.com/flame-engine/flame/issues/3974) 메모리 설계 교착
- [Godot Mobile update 2026-04](https://godotengine.org/article/godot-mobile-update-apr-2026/) / [Godot 4.7](https://godotengine.org/releases/4.7/)
- [arXiv 2410.03981](https://arxiv.org/pdf/2410.03981) — 저자원 언어 LLM 성능 저하 서베이
