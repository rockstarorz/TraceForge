import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_track_desktop/core/kml.dart';

import 'package:gps_track_desktop/core/models.dart';
import 'package:gps_track_desktop/core/parser.dart';
import 'package:gps_track_desktop/ui/analyzer_controller.dart';
import 'package:gps_track_desktop/ui/home.dart';
import 'package:gps_track_desktop/ui/theme.dart';
import 'package:gps_track_desktop/ui/timeline_panel.dart';
import 'package:gps_track_desktop/ui/widgets.dart';

const uiSample = '''
<=======这是第 1 条包=======>
包类型: 定位数据包(22)
IMEI号: 860000000000001(0860000000000001)
机种: VL110C
时间=26/8/13 18:16:10
纬度=N 32.305837°,经度=E 75.035083°,速度: 0KM/H
定位状态:已定位, 航向:17°
ACC低(00),实时上传(00)
信息序列号: 0001(0001)
校验信息: 5B90
<=======这是第 2 条包=======>
包类型: 报警包(26)
时间=26/8/13 18:20:10
纬度=N 32.306837°,经度=E 75.036083°,速度: 62KM/H
定位状态:已定位, 航向:91°
ACC高(01),实时上传(00)
告警类型:震动报警(003)
信息序列号: 0002(0002)
校验信息: 5B90
<=======这是第 3 条包=======>
包类型: 在线指令下发包(80)
指令长度: 15(0F)
指令内容: mileage,on#(6D696C656167652C6F6E23)
信息序列号: 0002(0002)
校验信息: 7D7A
''';

void configureDesktopView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('repeated parse resets state and completes again', () async {
    final controller = AnalyzerController();
    addTearDown(controller.dispose);
    controller.setSource(uiSample);

    await controller.parse();
    expect(controller.resultRevision, 1);
    expect(controller.busy, isFalse);
    expect(controller.progress, 1);
    expect(controller.sidebarOpen, isFalse);

    controller.toggleSidebar();
    await controller.parse();
    expect(controller.resultRevision, 2);
    expect(controller.busy, isFalse);
    expect(controller.progress, 1);
    expect(controller.sidebarOpen, isFalse);
    expect(
      controller.logs.where((line) => line.contains('[DONE]')),
      hasLength(2),
    );
  });

  testWidgets('input sidebar and terminal render without layout errors', (
    tester,
  ) async {
    configureDesktopView(tester);
    final controller = AnalyzerController();
    controller.terminalOpen = true;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 350, child: InputSidebar(controller: controller)),
              Expanded(
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: TerminalPanel(controller: controller),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('输入 / INPUT'), findsOneWidget);
    expect(find.text('排查日志 / TERMINAL'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    Object? terminalClipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          terminalClipboard = call.arguments;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final terminalCopyButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('copy-terminal-logs')),
    );
    expect(terminalCopyButton.onPressed, isNotNull);
    await controller.copyTerminalLogs();
    expect(
      (terminalClipboard as Map<Object?, Object?>)['text'],
      contains('[READY] Parser core initialized'),
    );
    await tester.tap(find.byKey(const ValueKey('parser-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-zero-option')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-mtk-option')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-version-label')), findsOneWidget);
    expect(find.text('V0.3.12.3'), findsOneWidget);
    expect(find.textContaining('\u4ec5\u652f\u6301 CONCOX'), findsOneWidget);
    expect(controller.filterZero, isTrue);
    expect(controller.filterMtkRollback, isFalse);
    await tester.tap(find.byKey(const ValueKey('filter-mtk-option')));
    await tester.pump();
    expect(controller.filterMtkRollback, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parsed dashboard renders cards and timeline', (tester) async {
    configureDesktopView(tester);
    final controller = AnalyzerController();
    addTearDown(controller.dispose);
    controller
      ..parsed = parseText(uiSample, const ParseOptions())
      ..kml = generateKml(
        parseText(uiSample, const ParseOptions()),
        const ParseOptions(),
      );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ResultsWorkspace(controller: controller)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    final copyButton = find.byKey(const ValueKey('copy-kml-button'));
    final exportButton = find.byKey(const ValueKey('export-kml-button'));
    expect(copyButton, findsOneWidget);
    expect(exportButton, findsOneWidget);
    expect(
      tester.getCenter(copyButton).dx,
      lessThan(tester.getCenter(exportButton).dx),
    );

    Object? clipboardPayload;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardPayload = call.arguments;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(copyButton);
    await tester.pump();
    expect(find.text('\u5df2\u590d\u5236'), findsOneWidget);
    expect(
      (clipboardPayload as Map<Object?, Object?>)['text'],
      controller.kml!.text,
    );

    expect(find.text('区间包数 / RANGE PACKETS'), findsOneWidget);
    expect(find.text('游标速度 / CURSOR SPEED'), findsOneWidget);
    expect(find.text('游标方位 / HEADING'), findsOneWidget);
    expect(find.text('告警总数 / TOTAL ALARMS'), findsOneWidget);
    expect(find.text('数据包时间轴 / PACKET TIMELINE'), findsOneWidget);
    expect(find.textContaining('心跳统计 / HEARTBEAT'), findsNothing);
    expect(find.byType(RangeSlider), findsOneWidget);
    expect(find.text('定位'), findsOneWidget);
    expect(find.text('心跳'), findsOneWidget);
    expect(find.text('告警'), findsOneWidget);
    expect(find.text('指令'), findsOneWidget);
    expect(find.text('ACC'), findsOneWidget);
    expect(find.text('生成 KML'), findsOneWidget);
    expect(find.textContaining('3 / 3 PACKETS'), findsOneWidget);
    await tester.tap(find.text('心跳'));
    await tester.pump(const Duration(milliseconds: 500));

    final initialSlider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    initialSlider.onChanged!(const RangeValues(0, .5));
    await tester.pump();
    initialSlider.onChangeEnd!(const RangeValues(0, .5));
    await tester.pump(const Duration(milliseconds: 250));
    final changedSlider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    expect(changedSlider.values.end, .5);
    expect(find.textContaining('2026-08-13 18:18'), findsWidgets);
    changedSlider.onChanged!(const RangeValues(0, 1));
    await tester.pump();
    changedSlider.onChangeEnd!(const RangeValues(0, 1));
    await tester.pump(const Duration(milliseconds: 250));

    final flag = find.byWidgetPredicate(
      (widget) => widget is Tooltip && (widget.message ?? '').contains('震动报警'),
    );
    expect(flag, findsOneWidget);
    await tester.tap(flag);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('告警菜单 / ALARM EVENTS'), findsOneWidget);
    expect(find.textContaining('告警类型:震动报警(003)'), findsOneWidget);

    final commandMarker = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip && (widget.message ?? '').contains('mileage,on#'),
    );
    expect(commandMarker, findsOneWidget);
    await tester.tap(commandMarker);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('指令菜单 / COMMAND EVENTS'), findsOneWidget);
    expect(find.textContaining('mileage,on#'), findsWidgets);
    expect(find.textContaining('CONCOX 0x80'), findsOneWidget);
    expect(find.textContaining('指令内容: mileage,on#'), findsOneWidget);
    expect(find.byKey(const ValueKey('event-menus-true-true')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'theme toggle blocks input and applies vibrant blue light palette',
    (tester) async {
      configureDesktopView(tester);
      AppColors.apply(Brightness.dark);
      addTearDown(() => AppColors.apply(Brightness.dark));

      final controller = AppThemeController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppThemeScope(
          controller: controller,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, _) => MaterialApp(
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              themeMode: controller.mode,
              themeAnimationDuration: const Duration(milliseconds: 260),
              builder: (_, child) => ThemeTransitionShield(
                controller: controller,
                child: child ?? const SizedBox.shrink(),
              ),
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: ThemeToggle(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      final toggle = find.byKey(const ValueKey('theme-toggle-button'));
      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AbsorbPointer &&
              widget.absorbing &&
              widget.child is Stack,
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(toggle).onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(AppColors.cyan, AppColors.vibrantBlue);

      await tester.pump(const Duration(milliseconds: 400));
      expect(Theme.of(tester.element(toggle)).brightness, Brightness.light);
      expect(tester.widget<IconButton>(toggle).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timeline and app mark interpolate theme colors without hover', (
    tester,
  ) async {
    configureDesktopView(tester);
    AppColors.apply(Brightness.dark);
    addTearDown(() => AppColors.apply(Brightness.dark));
    final themeController = AppThemeController();
    addTearDown(themeController.dispose);
    final data = parseText(uiSample, const ParseOptions());

    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: AnimatedBuilder(
          animation: themeController,
          builder: (_, _) => MaterialApp(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: themeController.mode,
            themeAnimationDuration: const Duration(milliseconds: 260),
            themeAnimationCurve: strongEaseOut,
            home: Scaffold(
              body: Column(
                children: [
                  const AppMark(),
                  Expanded(
                    child: TimelinePanel(
                      data: data,
                      options: const ParseOptions(),
                      revision: 1,
                      onCursor: (_) {},
                      onRangeChanged: (_, _, _, _) {},
                      onAlarmSelected: (_) {},
                      onCommandSelected: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    TimelinePainter timelinePainter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimelinePainter>()
        .single;
    Icon markIcon() => tester.widget<Icon>(
      find.descendant(
        of: find.byType(AppMark),
        matching: find.byIcon(Icons.satellite_alt_rounded),
      ),
    );

    expect(timelinePainter().locationColor, AppColors.darkAccent);
    expect(markIcon().color, AppColors.darkAccent);

    themeController.toggle();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 100));
    final middleTimelineColor = timelinePainter().locationColor;
    final middleMarkColor = markIcon().color;
    expect(middleTimelineColor, isNot(AppColors.darkAccent));
    expect(middleTimelineColor, isNot(AppColors.vibrantBlue));
    expect(middleMarkColor, middleTimelineColor);

    await tester.pump(const Duration(milliseconds: 300));
    expect(timelinePainter().locationColor, AppColors.vibrantBlue);
    expect(markIcon().color, AppColors.vibrantBlue);
    expect(tester.takeException(), isNull);
  });

  test('ACC step line holds state and jumps vertically at packet time', () {
    final start = DateTime.utc(2026, 1, 1);
    final points = <GpsPoint>[
      GpsPoint(time: start, latitude: 0, longitude: 0, acc: false),
      GpsPoint(
        time: start.add(const Duration(seconds: 10)),
        latitude: 0,
        longitude: 0,
        acc: true,
      ),
      GpsPoint(
        time: start.add(const Duration(seconds: 20)),
        latitude: 0,
        longitude: 0,
        acc: false,
      ),
    ];

    final fullRange = buildAccStepOffsets(
      points: points,
      start: start,
      end: start.add(const Duration(seconds: 30)),
      left: 0,
      width: 300,
      onY: 76,
      offY: 94,
    );
    expect(fullRange, const <Offset>[
      Offset(0, 94),
      Offset(100, 94),
      Offset(100, 76),
      Offset(200, 76),
      Offset(200, 94),
      Offset(300, 94),
    ]);

    // 区间从两个状态点之间开始时，左边界继承此前持续的 ACC ON。
    final zoomedRange = buildAccStepOffsets(
      points: points,
      start: start.add(const Duration(seconds: 15)),
      end: start.add(const Duration(seconds: 25)),
      left: 0,
      width: 100,
      onY: 76,
      offY: 94,
    );
    expect(zoomedRange, const <Offset>[
      Offset(0, 76),
      Offset(50, 76),
      Offset(50, 94),
      Offset(100, 94),
    ]);
  });

  test(
    'time range excludes a sequence-earlier packet anchored in the future',
    () {
      final start = DateTime.utc(2026, 8, 27, 23, 20);
      final end = DateTime.utc(2026, 8, 28, 7, 53);
      final futureAnchored = PacketRecord(number: 100)
        ..timelineTime = DateTime.utc(2026, 8, 28, 8, 46)
        ..inferred = true
        ..timeAnchorIndex = 400;
      expect(packetFallsInTimeRange(futureAnchored, start, end), isFalse);
      futureAnchored.timelineTime = end;
      expect(packetFallsInTimeRange(futureAnchored, start, end), isTrue);
    },
  );
}
