import 'dart:math' as math;
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/models.dart';
import 'analyzer_controller.dart';
import 'theme.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.protocol,
    required this.onMenu,
    this.busy = false,
    this.status = '',
  });
  final Protocol protocol;
  final VoidCallback onMenu;
  final bool busy;
  final String status;

  @override
  Widget build(BuildContext context) {
    final buttonColors = WindowButtonColors(
      iconNormal: AppColors.muted,
      mouseOver: AppColors.windowHover,
      mouseDown: AppColors.windowPressed,
      iconMouseOver: AppColors.text,
      iconMouseDown: AppColors.text,
    );
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: '输入面板 / Input panel',
              onPressed: onMenu,
              icon: const Icon(Icons.tune_rounded, size: 19),
            ),
          ),
          AppMark(),
          const SizedBox(width: 10),
          Text(
            'TRACEFORGE',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 14),
          ProtocolBadge(protocol: protocol),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MoveWindow(),
                if (busy)
                  IgnorePointer(
                    child: Center(
                      child: Text(
                        status,
                        key: const ValueKey('top-progress-stage'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const ThemeToggle(),
          const SizedBox(width: 4),
          MinimizeWindowButton(colors: buttonColors),
          MaximizeWindowButton(colors: buttonColors),
          CloseWindowButton(
            colors: WindowButtonColors(
              iconNormal: AppColors.muted,
              mouseOver: AppColors.red,
              mouseDown: const Color(0xFFB3261E),
              iconMouseOver: Colors.white,
              iconMouseDown: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeScope.of(context);
    final light = !controller.isDark;
    return Tooltip(
      message: light
          ? '\u5207\u6362\u5230\u9ed1\u591c\u6a21\u5f0f / Dark mode'
          : '\u5207\u6362\u5230\u767d\u5929\u6a21\u5f0f / Light mode',
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: strongEaseOut,
        width: 34,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: light ? .12 : .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.cyan.withValues(alpha: light ? .38 : .22),
          ),
          boxShadow: controller.transitioning
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: .24),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: IconButton(
          key: const ValueKey('theme-toggle-button'),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: controller.transitioning
              ? null
              : () => controller.toggle(
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                ),
          icon: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: strongEaseOut,
            switchOutCurve: strongEaseInOut,
            transitionBuilder: (child, animation) => RotationTransition(
              turns: Tween<double>(begin: -.18, end: 0).animate(animation),
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              light ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              key: ValueKey(light),
              size: 17,
              color: AppColors.cyan,
            ),
          ),
        ),
      ),
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({super.key});
  @override
  Widget build(BuildContext context) {
    // ColorScheme.primary is interpolated by MaterialApp, so the mark changes
    // with the passing theme wave instead of jumping after the animation.
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        border: Border.all(color: accent.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(Icons.satellite_alt_rounded, color: accent, size: 15),
    );
  }
}

class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge({super.key, required this.protocol});
  final Protocol protocol;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.cyan.withValues(alpha: .08),
      border: Border.all(color: AppColors.cyan.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 6,
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cyan,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          protocol == Protocol.concox ? 'CONCOX / GT06' : 'JT/T808',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: .6,
            color: AppColors.cyan,
          ),
        ),
      ],
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.alarm = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool alarm;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: BackdropFilter.grouped(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: alarm
                ? AppColors.red.withValues(alpha: .48)
                : Colors.white.withValues(alpha: .07),
          ),
          boxShadow: alarm
              ? [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: .08),
                    blurRadius: 18,
                  ),
                ]
              : const [],
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class SpringButton extends StatefulWidget {
  const SpringButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<SpringButton>
    with TickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _hovered = false;

  void _spring(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.value = target;
      return;
    }
    _scale.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 30),
        _scale.value,
        target,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      setState(() => _hovered = true);
      if (widget.primary && !MediaQuery.disableAnimationsOf(context)) {
        _shine.forward(from: 0);
      }
    },
    onExit: (_) => setState(() => _hovered = false),
    child: ScaleTransition(
      scale: _scale,
      child: Material(
        color: widget.primary ? AppColors.cyan : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPressed,
          onTapDown: widget.onPressed == null ? null : (_) => _spring(.965),
          onTapUp: widget.onPressed == null ? null : (_) => _spring(1),
          onTapCancel: widget.onPressed == null ? null : () => _spring(1),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: strongEaseOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.primary
                    ? AppColors.cyan
                    : (_hovered
                          ? AppColors.cyan.withValues(alpha: .5)
                          : AppColors.border),
              ),
            ),
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        size: 16,
                        color: widget.primary
                            ? AppColors.background
                            : AppColors.text,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.primary
                              ? AppColors.background
                              : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  if (widget.primary)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shine,
                          builder: (_, _) => FractionalTranslation(
                            translation: Offset(-1.8 + _shine.value * 3.6, 0),
                            child: Transform.rotate(
                              angle: -.28,
                              child: Container(
                                width: 34,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white.withValues(alpha: .34),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SpringSurface extends StatefulWidget {
  const SpringSurface({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<SpringSurface> createState() => _SpringSurfaceState();
}

class _SpringSurfaceState extends State<SpringSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool hovered = false;

  void _spring(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      scale.value = target;
      return;
    }
    scale.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 390, damping: 27),
        scale.value,
        target,
        0,
      ),
    );
  }

  @override
  void dispose() {
    scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    onEnter: (_) {
      setState(() => hovered = true);
      if (widget.onTap != null) _spring(1.012);
    },
    onExit: (_) {
      setState(() => hovered = false);
      _spring(1);
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _spring(.975),
      onTapUp: widget.onTap == null ? null : (_) => _spring(1.012),
      onTapCancel: widget.onTap == null ? null : () => _spring(1),
      child: ScaleTransition(scale: scale, child: widget.child),
    ),
  );
}

class InputSidebar extends StatefulWidget {
  const InputSidebar({super.key, required this.controller});
  final AnalyzerController controller;

  @override
  State<InputSidebar> createState() => _InputSidebarState();
}

class _InputSidebarState extends State<InputSidebar>
    with SingleTickerProviderStateMixin {
  final ScrollController _textScroll = ScrollController();
  final ScrollController _lineScroll = ScrollController();
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  int _revision = 0;
  bool _loadingPreviewPage = false;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.importRevision;
    _textScroll.addListener(_syncLineNumbers);
  }

  @override
  void didUpdateWidget(covariant InputSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.controller.importRevision) {
      _revision = widget.controller.importRevision;
      if (!MediaQuery.disableAnimationsOf(context)) _scan.forward(from: 0);
    }
  }

  void _syncLineNumbers() {
    if (!_textScroll.hasClients || !_lineScroll.hasClients) return;
    // Long raw-data rows wrap in the editor and make its pixel height much
    // larger than the gutter. Synchronize by scroll progress so the gutter
    // keeps moving all the way to the final visible source line.
    final textMax = _textScroll.position.maxScrollExtent;
    final gutterMax = _lineScroll.position.maxScrollExtent;
    final progress = textMax <= 0 ? 0.0 : _textScroll.offset / textMax;
    _lineScroll.jumpTo((progress * gutterMax).clamp(0.0, gutterMax));

    final source = widget.controller.source;
    if (_loadingPreviewPage ||
        !source.hasMorePreview ||
        _textScroll.position.extentAfter > 140) {
      return;
    }
    // 一次滚轮到底只追加一个 16k 分页。等待新布局完成后再解锁，
    // 避免同一批滚动事件把整份日志立即塞进 TextField。
    _loadingPreviewPage = true;
    source.loadNextPreviewPage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadingPreviewPage = false);
      _syncLineNumbers();
    });
  }

  @override
  void dispose() {
    _textScroll.dispose();
    _lineScroll.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller;
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '输入 / INPUT',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                _ParserSettingsMenu(controller: state),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起 / Collapse',
                  onPressed: state.toggleSidebar,
                  icon: const Icon(
                    Icons.keyboard_double_arrow_left_rounded,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<InputMode>(
              initialValue: state.inputMode,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              dropdownColor: AppColors.surfaceRaised,
              decoration: const InputDecoration(labelText: '输入模式 / Input mode'),
              items: const [
                DropdownMenuItem(
                  value: InputMode.officialText,
                  child: Text('官方解析文本'),
                ),
                DropdownMenuItem(
                  value: InputMode.rawLog,
                  child: Text('原始日志 · 调用官方工具'),
                ),
              ],
              onChanged: state.busy
                  ? null
                  : (value) => state.setInputMode(value!),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Protocol>(
                    initialValue: state.protocol,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: AppColors.surfaceRaised,
                    decoration: const InputDecoration(
                      labelText: '协议 / Protocol',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: Protocol.concox,
                        child: Text('Concox (GT06)'),
                      ),
                      DropdownMenuItem(
                        value: Protocol.jt808,
                        enabled: false,
                        child: Text('JT/T808（施工中）'),
                      ),
                      DropdownMenuItem<Protocol>(
                        enabled: false,
                        child: Text('自动识别（施工中）'),
                      ),
                    ],
                    onChanged: state.busy
                        ? null
                        : (value) => state.setProtocol(value!),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: DropdownButtonFormField<bool>(
                    initialValue: state.chineseKml,
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: AppColors.surfaceRaised,
                    decoration: const InputDecoration(labelText: 'KML'),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('EN')),
                      DropdownMenuItem(value: true, child: Text('中文')),
                    ],
                    onChanged: state.busy
                        ? null
                        : (value) => state.setChineseKml(value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.editor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 42,
                            color: AppColors.editorGutter,
                            padding: const EdgeInsets.only(top: 12, right: 8),
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: state.source,
                              builder: (_, value, _) {
                                final count = math.max(
                                  1,
                                  '\n'.allMatches(value.text).length + 1,
                                );
                                return SingleChildScrollView(
                                  controller: _lineScroll,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Text(
                                    List.generate(
                                      count,
                                      (index) => '${index + 1}',
                                    ).join('\n'),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 12,
                                      height: 1.45,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: state.source,
                              scrollController: _textScroll,
                              enabled: !state.busy,
                              readOnly: false,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 12,
                                height: 1.45,
                                color: AppColors.editorText,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Paste protocol dump here…',
                                filled: true,
                                fillColor: AppColors.editor,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      AnimatedBuilder(
                        animation: _scan,
                        builder: (_, _) => Positioned(
                          left: 42,
                          right: 0,
                          top: (_scan.value * 2 - .2) * 360,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: (1 - _scan.value).clamp(0, 1),
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      AppColors.cyan.withValues(alpha: .18),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (state.source.isPreviewing) ...[
              const SizedBox(height: 7),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: state.source,
                builder: (_, value, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: .08),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: .24),
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '\u5df2\u8f7d\u5165 ${state.source.sourceLineCount} \u884c \u00b7 '
                    '\u5df2\u9884\u89c8 ${state.source.visibleLength}/${state.source.sourceLength} \u5b57\u7b26'
                    '${state.source.hasMorePreview ? ' \u00b7 \u4e0b\u62c9\u7ee7\u7eed\u52a0\u8f7d' : ' \u00b7 \u9884\u89c8\u5df2\u5b8c\u6574'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 9,
                      color: AppColors.cyan,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SpringButton(
                    label: '粘贴',
                    icon: Icons.content_paste_rounded,
                    onPressed: state.busy ? null : state.paste,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SpringButton(
                    label: '导入',
                    icon: Icons.file_open_rounded,
                    onPressed: state.busy ? null : state.importFile,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SpringButton(
                    label: state.busy
                        ? '${state.progressLabel} ${(state.progress * 100).round()}%'
                        : state.inputMode == InputMode.rawLog
                        ? '官方解析'
                        : '开始解析',
                    icon: state.busy
                        ? Icons.sync_rounded
                        : Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: state.busy ? null : state.parse,
                  ),
                ),
                if (state.busy) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('cancel-parse-button'),
                    tooltip: '取消 / Cancel',
                    onPressed: state.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                ],
              ],
            ),
            if (state.busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: state.progress,
                minHeight: 2,
                color: AppColors.cyan,
                backgroundColor: AppColors.border,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParserSettingsMenu extends StatelessWidget {
  const _ParserSettingsMenu({required this.controller});

  final AnalyzerController controller;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(-258, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceRaised),
        elevation: const WidgetStatePropertyAll(14),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 304,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 17, color: AppColors.cyan),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '\u89e3\u6790\u8bbe\u7f6e / PARSER SETTINGS',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '\u6f02\u79fb\u5224\u5b9a / DRIFT DETECTION',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: _ParameterField(
                        label: '\u8ddd\u79bb km',
                        controller: controller.distanceKm,
                        enabled: !controller.busy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ParameterField(
                        label: '\u65f6\u957f min',
                        controller: controller.durationMin,
                        enabled: !controller.busy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '官方窗口 / OFFICIAL WINDOW',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 7),
                DropdownButtonFormField<OfficialWindowMode>(
                  key: const ValueKey('official-window-mode'),
                  initialValue: controller.officialWindowMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '窗口策略'),
                  items: const [
                    DropdownMenuItem(
                      value: OfficialWindowMode.background,
                      child: Text('后台模式（默认）'),
                    ),
                    DropdownMenuItem(
                      value: OfficialWindowMode.brief,
                      child: Text('短暂显示模式'),
                    ),
                    DropdownMenuItem(
                      value: OfficialWindowMode.debug,
                      child: Text('调试模式（始终显示）'),
                    ),
                  ],
                  onChanged: controller.busy
                      ? null
                      : (value) => controller.setOfficialWindowMode(value!),
                ),
                const SizedBox(height: 8),
                _ParameterField(
                  label: '心跳预期间隔 min',
                  controller: controller.heartbeatExpectedMin,
                  enabled: !controller.busy,
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 6),
                _FilterCheckbox(
                  key: const ValueKey('filter-zero-option'),
                  value: controller.filterZero,
                  enabled: !controller.busy,
                  title: '\u8fc7\u6ee4 0E 0N \u5b9a\u4f4d\u70b9',
                  subtitle: 'FILTER ZERO COORDINATES',
                  onChanged: controller.setFilterZero,
                ),
                _FilterCheckbox(
                  key: const ValueKey('filter-mtk-option'),
                  value: controller.filterMtkRollback,
                  enabled: !controller.busy,
                  title: '\u8fc7\u6ee4 MTK \u661f\u5386\u5012\u8f6c\u70b9',
                  subtitle:
                      '\u65e9\u4e8e\u5f53\u524d/\u672c\u6279\u6700\u65b0\u65f6\u95f4 10 \u5e74 / MTK ROLLBACK',
                  onChanged: controller.setFilterMtkRollback,
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TRACEFORGE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'V0.3.12.3',
                      key: ValueKey('app-version-label'),
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '\u6307\u4ee4\u4e8b\u4ef6\u89e3\u6790\u76ee\u524d\u4ec5\u652f\u6301 CONCOX \u534f\u8bae',
                  style: TextStyle(color: AppColors.muted, fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (context, menuController, child) => IconButton(
        key: const ValueKey('parser-settings-button'),
        visualDensity: VisualDensity.compact,
        tooltip: '\u89e3\u6790\u8bbe\u7f6e / Parser settings',
        onPressed: controller.busy
            ? null
            : () {
                if (menuController.isOpen) {
                  menuController.close();
                } else {
                  menuController.open();
                }
              },
        icon: AnimatedRotation(
          turns: menuController.isOpen ? .125 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: strongEaseOut,
          child: Icon(Icons.settings_rounded, size: 18),
        ),
      ),
    );
  }
}

class _FilterCheckbox extends StatelessWidget {
  const _FilterCheckbox({
    super.key,
    required this.value,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      enabled: enabled,
      onChanged: enabled ? (next) => onChanged(next ?? false) : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      activeColor: AppColors.cyan,
      checkColor: AppColors.background,
      title: Text(title, style: TextStyle(fontSize: 12)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.muted,
          fontFamily: 'Consolas',
          fontSize: 9,
        ),
      ),
    );
  }
}

class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.label,
    required this.controller,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.number,
    style: TextStyle(fontFamily: 'Consolas', fontSize: 12),
    decoration: InputDecoration(labelText: label),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onOpen});
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cyan.withValues(alpha: .08),
            border: Border.all(color: AppColors.cyan.withValues(alpha: .2)),
          ),
          child: Icon(Icons.radar_rounded, color: AppColors.cyan, size: 28),
        ),
        const SizedBox(height: 18),
        Text(
          '等待协议数据',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '导入数据后，结果工作区将在这里展开',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        SpringButton(
          label: '打开输入面板',
          icon: Icons.keyboard_double_arrow_right_rounded,
          onPressed: onOpen,
        ),
      ],
    ),
  );
}

class ReadoutCard extends StatelessWidget {
  const ReadoutCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
    this.alarm = false,
  });
  final String label;
  final String value;
  final String detail;
  final Color color;
  final IconData icon;
  final bool alarm;

  @override
  Widget build(BuildContext context) => GlassCard(
    alarm: alarm,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              const SizedBox(height: 7),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 9,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        Icon(icon, size: 27, color: color.withValues(alpha: .72)),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.series,
    this.alarm = false,
  });
  final String label;
  final double value;
  final String unit;
  final Color color;
  final List<double> series;
  final bool alarm;

  @override
  Widget build(BuildContext context) => GlassCard(
    alarm: alarm,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, current, _) => Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value % 1 == 0
                            ? current.round().toString()
                            : current.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 74,
          height: 40,
          child: CustomPaint(painter: SparklinePainter(series, color)),
        ),
      ],
    ),
  );
}

class SparklinePainter extends CustomPainter {
  const SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(.001, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y =
          size.height - 3 - (values[i] - minValue) / range * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class AccRatioCard extends StatelessWidget {
  const AccRatioCard({
    super.key,
    required this.onCount,
    required this.offCount,
  });
  final int onCount;
  final int offCount;
  @override
  Widget build(BuildContext context) {
    final total = onCount + offCount;
    final ratio = total == 0 ? 0.0 : onCount / total;
    return GlassCard(
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: CustomPaint(
              painter: RingPainter(ratio),
              child: Center(
                child: Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'ACC 占比 / DUTY',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _Dot(color: AppColors.orange, text: 'ON $onCount'),
                    const SizedBox(width: 10),
                    _Dot(color: AppColors.heartbeat, text: 'OFF $offCount'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontFamily: 'Consolas', fontSize: 10)),
    ],
  );
}

class RingPainter extends CustomPainter {
  const RingPainter(this.value);
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = math.min(size.width, size.height) * .1;
    canvas.drawArc(
      rect.deflate(stroke),
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = AppColors.heartbeat.withValues(alpha: .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = AppColors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) =>
      oldDelegate.value != value;
}
