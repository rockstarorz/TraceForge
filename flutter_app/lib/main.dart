import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

import 'ui/home.dart';
import 'ui/theme.dart';

void main() {
  runApp(const GpsTrackApp());
  doWhenWindowReady(() {
    const initialSize = Size(1280, 780);
    appWindow
      ..minSize = const Size(960, 640)
      ..size = initialSize
      ..alignment = Alignment.center
      ..title = 'TRACEFORGE'
      ..show();
  });
}

class GpsTrackApp extends StatefulWidget {
  const GpsTrackApp({super.key});

  @override
  State<GpsTrackApp> createState() => _GpsTrackAppState();
}

class _GpsTrackAppState extends State<GpsTrackApp> {
  final AppThemeController _themeController = AppThemeController();

  @override
  void initState() {
    super.initState();
    AppColors.apply(Brightness.dark);
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (_, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'TRACEFORGE',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: _themeController.mode,
          themeAnimationDuration: const Duration(milliseconds: 260),
          themeAnimationCurve: strongEaseOut,
          builder: (context, child) => ThemeTransitionShield(
            controller: _themeController,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AnalyzerHome(),
        ),
      ),
    );
  }
}
