import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const darkAccent = Color(0xFF00D4AA);
  static const vibrantBlue = Color(0xFF1677FF);

  static Color background = const Color(0xFF0F1115);
  static Color surface = const Color(0xFF171A20);
  static Color surfaceRaised = const Color(0xFF1A1D23);
  static Color border = const Color(0xFF2A2F39);
  static Color text = const Color(0xFFF2F5F7);
  static Color muted = const Color(0xFF89919E);
  static Color cyan = darkAccent;
  static Color heroGlow = const Color(0xFF14201F);
  static Color editor = const Color(0xFF0B0D10);
  static Color editorGutter = const Color(0xFF101319);
  static Color editorText = const Color(0xFFB9C2CE);
  static Color timelineGrid = const Color(0x12FFFFFF);
  static Color timelineCursor = const Color(0xC7FFFFFF);
  static Color totalPackets = const Color(0x2E73B7C9);
  static Color windowHover = const Color(0xFF262B33);
  static Color windowPressed = const Color(0xFF303640);

  static const orange = Color(0xFFFF6B35);
  static const red = Color(0xFFFF453A);
  static const heartbeat = Color(0xFF69717E);

  static void apply(Brightness brightness) {
    final light = brightness == Brightness.light;
    background = light ? const Color(0xFFF2F6FC) : const Color(0xFF0F1115);
    surface = light ? const Color(0xFFF8FAFD) : const Color(0xFF171A20);
    surfaceRaised = light ? Colors.white : const Color(0xFF1A1D23);
    border = light ? const Color(0xFFD4DEEC) : const Color(0xFF2A2F39);
    text = light ? const Color(0xFF172033) : const Color(0xFFF2F5F7);
    muted = light ? const Color(0xFF64748B) : const Color(0xFF89919E);
    cyan = light ? vibrantBlue : darkAccent;
    heroGlow = light ? const Color(0xFFDCEAFF) : const Color(0xFF14201F);
    editor = light ? const Color(0xFFF7FAFF) : const Color(0xFF0B0D10);
    editorGutter = light ? const Color(0xFFEDF3FC) : const Color(0xFF101319);
    editorText = light ? const Color(0xFF27364D) : const Color(0xFFB9C2CE);
    timelineGrid = light ? const Color(0x1F355070) : const Color(0x12FFFFFF);
    timelineCursor = light ? const Color(0xB82C4A70) : const Color(0xC7FFFFFF);
    totalPackets = light ? const Color(0x301677FF) : const Color(0x2E73B7C9);
    windowHover = light ? const Color(0xFFE4ECF8) : const Color(0xFF262B33);
    windowPressed = light ? const Color(0xFFD8E4F3) : const Color(0xFF303640);
  }
}

class AppThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  bool _transitioning = false;
  int _revision = 0;
  Timer? _unlockTimer;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  bool get transitioning => _transitioning;
  int get revision => _revision;

  void toggle({bool reduceMotion = false}) {
    if (_transitioning) return;
    _transitioning = true;
    _revision++;
    notifyListeners();

    // \u5148\u8ba9\u53f3\u4e0a\u89d2\u6269\u6563\u5149\u6655\u8d77\u6b65\uff0c\u518d\u4ea4\u6362\u8272\u677f\uff0c\u964d\u4f4e\u9875\u9762\u77ac\u95ea\u611f\u3002
    Future<void>.delayed(
      reduceMotion ? Duration.zero : const Duration(milliseconds: 70),
      () {
        _mode = isDark ? ThemeMode.light : ThemeMode.dark;
        AppColors.apply(
          _mode == ThemeMode.light ? Brightness.light : Brightness.dark,
        );
        notifyListeners();
      },
    );

    _unlockTimer?.cancel();
    _unlockTimer = Timer(
      reduceMotion
          ? const Duration(milliseconds: 40)
          : const Duration(milliseconds: 390),
      () {
        _transitioning = false;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this context.');
    return scope!.notifier!;
  }
}

ThemeData buildDarkTheme() => _buildTheme(
  brightness: Brightness.dark,
  background: const Color(0xFF0F1115),
  surface: const Color(0xFF171A20),
  surfaceRaised: const Color(0xFF1A1D23),
  border: const Color(0xFF2A2F39),
  text: const Color(0xFFF2F5F7),
  muted: const Color(0xFF89919E),
  accent: AppColors.darkAccent,
);

ThemeData buildLightTheme() => _buildTheme(
  brightness: Brightness.light,
  background: const Color(0xFFF2F6FC),
  surface: const Color(0xFFF8FAFD),
  surfaceRaised: Colors.white,
  border: const Color(0xFFD4DEEC),
  text: const Color(0xFF172033),
  muted: const Color(0xFF64748B),
  accent: AppColors.vibrantBlue,
);

// \u4fdd\u7559\u65e7\u5165\u53e3\uff0c\u4fbf\u4e8e\u5df2\u6709\u5c0f\u90e8\u4ef6\u6d4b\u8bd5\u5355\u72ec\u6302\u8f7d\u9ed1\u591c\u4e3b\u9898\u3002
ThemeData buildAppTheme() => buildDarkTheme();

ThemeData _buildTheme({
  required Brightness brightness,
  required Color background,
  required Color surface,
  required Color surfaceRaised,
  required Color border,
  required Color text,
  required Color muted,
  required Color accent,
}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        surface: surface,
      ).copyWith(
        primary: accent,
        onPrimary: brightness == Brightness.light ? Colors.white : background,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        outlineVariant: border,
      );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Segoe UI',
    useMaterial3: true,
    dividerColor: border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceRaised,
      labelStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accent),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: border,
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: .12),
      rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
      rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      showValueIndicator: ShowValueIndicator.onlyForDiscrete,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: brightness == Brightness.light
            ? const Color(0xFF172033)
            : const Color(0xFF252A33),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

class ThemeTransitionShield extends StatefulWidget {
  const ThemeTransitionShield({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppThemeController controller;
  final Widget child;

  @override
  State<ThemeTransitionShield> createState() => _ThemeTransitionShieldState();
}

class _ThemeTransitionShieldState extends State<ThemeTransitionShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 390),
  );
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.revision;
  }

  @override
  void didUpdateWidget(covariant ThemeTransitionShield oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.controller.revision) {
      _revision = widget.controller.revision;
      if (MediaQuery.disableAnimationsOf(context)) {
        _wave.value = 1;
      } else {
        _wave.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: widget.controller.transitioning,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _wave,
                builder: (_, _) => CustomPaint(
                  painter: _ThemeWavePainter(
                    progress: _wave.value,
                    color: widget.controller.isDark
                        ? AppColors.darkAccent
                        : AppColors.vibrantBlue,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeWavePainter extends CustomPainter {
  const _ThemeWavePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final eased = strongEaseOut.transform(progress);
    final radius = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final opacity = math.sin(progress * math.pi) * .14;
    canvas.drawCircle(
      Offset(size.width - 118, 0),
      24 + radius * eased,
      Paint()..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _ThemeWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

const strongEaseOut = Cubic(0.23, 1, 0.32, 1);
const strongEaseInOut = Cubic(0.77, 0, 0.175, 1);
