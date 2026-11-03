import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'analyzer_controller.dart';
import 'theme.dart';
import 'timeline_panel.dart';
import 'widgets.dart';

class AnalyzerHome extends StatefulWidget {
  const AnalyzerHome({super.key});
  @override
  State<AnalyzerHome> createState() => _AnalyzerHomeState();
}

class _AnalyzerHomeState extends State<AnalyzerHome> {
  final controller = AnalyzerController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // 让根布局跟随主题的 InheritedWidget 重建。
    return BackdropGroup(
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.7, -.8),
              radius: 1.3,
              colors: [AppColors.heroGlow, AppColors.background],
              stops: [0, .55],
            ),
          ),
          child: Column(
            children: [
              AppTopBar(
                protocol: controller.protocol,
                onMenu: controller.toggleSidebar,
                busy: controller.busy,
                status: controller.progressLabel,
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: strongEaseInOut,
                      width: controller.sidebarOpen ? 350 : 0,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(),
                      child: SizedBox(
                        width: 350,
                        child: InputSidebar(controller: controller),
                      ),
                    ),
                    if (controller.sidebarOpen) const VerticalDivider(width: 1),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            bottom: controller.terminalOpen ? 214 : 38,
                            child: controller.parsed == null
                                ? EmptyState(onOpen: controller.toggleSidebar)
                                : ResultsWorkspace(
                                    key: ValueKey(controller.resultRevision),
                                    controller: controller,
                                  ),
                          ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class ResultsWorkspace extends StatefulWidget {
  const ResultsWorkspace({super.key, required this.controller});

  final AnalyzerController controller;

  @override
  State<ResultsWorkspace> createState() => _ResultsWorkspaceState();
}

class _ResultsWorkspaceState extends State<ResultsWorkspace> {
  final GlobalKey eventMenusKey = GlobalKey();
  int? cursorIndex;
  DateTime? rangeStartTime;
  DateTime? rangeEndTime;
  int fallbackStart = 0;
  late int fallbackEnd = math.max(
    0,
    widget.controller.parsed!.packets.length - 1,
  );
  bool alarmMenuOpen = false;
  bool commandMenuOpen = false;
  PacketRecord? selectedAlarm;
  PacketRecord? selectedCommand;

  bool _packetInRange(int index, PacketRecord packet) {
    if (rangeStartTime == null || rangeEndTime == null) {
      return index >= fallbackStart && index <= fallbackEnd;
    }
    final time = packet.timelineTime;
    return time != null &&
        !time.isBefore(rangeStartTime!) &&
        !time.isAfter(rangeEndTime!);
  }

  List<GpsPoint> _pointsInRange(ParsedData data) {
    if (data.points.isEmpty) return const [];
    if (rangeStartTime == null || rangeEndTime == null) {
      return fallbackStart == 0 && fallbackEnd == data.packets.length - 1
          ? data.points
          : const [];
    }
    return data.points
        .where(
          (point) =>
              !point.time.isBefore(rangeStartTime!) &&
              !point.time.isAfter(rangeEndTime!),
        )
        .toList(growable: false);
  }

  GpsPoint? _pointAtCursor(ParsedData data) {
    final index = cursorIndex;
    if (index == null || index < 0 || index >= data.packets.length) return null;
    final packet = data.packets[index];
    final time = packet.timelineTime;
    if (time == null || packet.heartbeat || packet.alarm || packet.command) {
      return null;
    }
    for (final point in data.points) {
      if (point.time.isAtSameMomentAs(time)) return point;
    }
    return null;
  }

  void _openAlarm(PacketRecord packet) {
    setState(() {
      selectedAlarm = packet;
      alarmMenuOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = eventMenusKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          curve: strongEaseOut,
          alignment: .12,
        );
      }
    });
  }

  void _openCommand(PacketRecord packet) {
    setState(() {
      selectedCommand = packet;
      commandMenuOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = eventMenusKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          curve: strongEaseOut,
          alignment: .12,
        );
      }
    });
  }

  String _rangeLabel() {
    if (rangeStartTime == null || rangeEndTime == null) {
      return '#${fallbackStart + 1}\u2013#${fallbackEnd + 1}';
    }
    return '${localTime(rangeStartTime!, seconds: false)} \u2013 '
        '${localTime(rangeEndTime!, seconds: false)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final data = controller.parsed!;
    final points = _pointsInRange(data);
    final currentPoint = _pointAtCursor(data);
    final alarms = data.packets.where((packet) => packet.alarm).toList();
    final commands = data.packets.where((packet) => packet.command).toList();
    final alarmTotal = alarms.length;
    final commandTotal = commands.length;
    final accOn = points.where((point) => point.acc).length;
    final accOff = points.length - accOn;
    var selectedCount = 0;
    for (var i = 0; i < data.packets.length; i++) {
      if (_packetInRange(i, data.packets[i])) selectedCount++;
    }
    final cursorPacket = cursorIndex == null
        ? null
        : data.packets[cursorIndex!];
    final cursorTimeNote = cursorPacket == null || !cursorPacket.inferred
        ? ''
        : cursorPacket.timeAnchorIndex != null &&
              cursorIndex! > cursorPacket.timeAnchorIndex!
        ? ' \u00b7 \u665a\u4e8e\u65f6\u95f4\u951a\u70b9'
        : ' \u00b7 \u63a8\u5b9a\u65f6\u95f4';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.device == null
                          ? '\u89e3\u6790\u7ed3\u679c / ANALYSIS'
                          : '${data.device}  /  ${data.model ?? 'UNKNOWN MODEL'}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cursorPacket == null
                          ? '\u65f6\u95f4\u533a\u95f4 ${_rangeLabel()} \u00b7 $selectedCount PACKETS'
                          : '\u5149\u6807 #${cursorIndex! + 1} \u00b7 ${cursorPacket.name}$cursorTimeNote',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                ),
              ),
              SpringButton(
                label: '\u91cd\u65b0\u8f93\u5165',
                icon: Icons.edit_note_rounded,
                onPressed: controller.toggleSidebar,
              ),
              const SizedBox(width: 8),
              _KmlActions(controller: controller),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (_, constraints) {
              final columns = constraints.maxWidth >= 1440
                  ? 6
                  : constraints.maxWidth >= 760
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              Widget cell(int index, Widget child) => SizedBox(
                width: width,
                height: 112,
                child: StaggerReveal(index: index, child: child),
              );
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  cell(
                    0,
                    ReadoutCard(
                      label: '\u533a\u95f4\u5305\u6570 / RANGE PACKETS',
                      value: '$selectedCount',
                      detail: '\u603b\u8ba1 ${data.packets.length}',
                      color: AppColors.cyan,
                      icon: Icons.data_usage_rounded,
                    ),
                  ),
                  cell(
                    1,
                    ReadoutCard(
                      label: '\u6e38\u6807\u901f\u5ea6 / CURSOR SPEED',
                      value: currentPoint == null
                          ? '--'
                          : currentPoint.speed.toStringAsFixed(1),
                      detail: currentPoint == null
                          ? '\u6307\u5411\u5b9a\u4f4d\u5305\u4ee5\u8bfb\u53d6'
                          : 'km/h',
                      color: AppColors.cyan,
                      icon: Icons.speed_rounded,
                    ),
                  ),
                  cell(
                    2,
                    ReadoutCard(
                      label: '\u6e38\u6807\u65b9\u4f4d / HEADING',
                      value: currentPoint == null
                          ? '--'
                          : '${currentPoint.heading.toStringAsFixed(0)}\u00b0',
                      detail: currentPoint == null
                          ? '\u6307\u5411\u5b9a\u4f4d\u5305\u4ee5\u8bfb\u53d6'
                          : '0\u00b0 = North',
                      color: AppColors.orange,
                      icon: Icons.explore_rounded,
                    ),
                  ),
                  cell(
                    3,
                    SpringSurface(
                      onTap: alarmTotal == 0
                          ? null
                          : () => setState(() {
                              alarmMenuOpen = !alarmMenuOpen;
                              selectedAlarm ??= alarms.first;
                            }),
                      child: AlarmPulse(
                        enabled: alarmTotal > 0,
                        child: ReadoutCard(
                          label: '\u544a\u8b66\u603b\u6570 / TOTAL ALARMS',
                          value: '$alarmTotal',
                          detail: alarmMenuOpen
                              ? '\u70b9\u51fb\u6536\u8d77\u544a\u8b66\u83dc\u5355'
                              : '\u70b9\u51fb\u67e5\u770b\u5168\u90e8\u544a\u8b66',
                          color: AppColors.red,
                          icon: Icons.flag_rounded,
                          alarm: alarmTotal > 0,
                        ),
                      ),
                    ),
                  ),
                  cell(
                    4,
                    SpringSurface(
                      onTap: commandTotal == 0
                          ? null
                          : () => setState(() {
                              commandMenuOpen = !commandMenuOpen;
                              selectedCommand ??= commands.first;
                            }),
                      child: ReadoutCard(
                        label: '\u6307\u4ee4\u4e0b\u53d1 / COMMANDS',
                        value: '$commandTotal',
                        detail: commandMenuOpen
                            ? '\u70b9\u51fb\u6536\u8d77 \u00b7 CONCOX'
                            : '\u4ec5\u652f\u6301 CONCOX \u00b7 \u70b9\u51fb\u67e5\u770b',
                        color: Theme.of(context).colorScheme.primary,
                        icon: Icons.info_outline_rounded,
                      ),
                    ),
                  ),
                  cell(5, AccRatioCard(onCount: accOn, offCount: accOff)),
                ],
              );
            },
          ),
          AnimatedSwitcher(
            key: eventMenusKey,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            reverseDuration: const Duration(milliseconds: 170),
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: animation,
                curve: strongEaseOut,
                reverseCurve: Curves.easeInCubic,
              ),
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -.06),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            ),
            child: !alarmMenuOpen && !commandMenuOpen
                ? const SizedBox.shrink(key: ValueKey('event-menus-closed'))
                : Padding(
                    key: ValueKey(
                      'event-menus-$alarmMenuOpen-$commandMenuOpen',
                    ),
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (alarmMenuOpen)
                          Expanded(
                            child: SizedBox(
                              height: 310,
                              child: _AlarmMenu(
                                alarms: alarms,
                                selected: selectedAlarm,
                                onSelect: (packet) =>
                                    setState(() => selectedAlarm = packet),
                                onClose: () =>
                                    setState(() => alarmMenuOpen = false),
                              ),
                            ),
                          ),
                        if (alarmMenuOpen && commandMenuOpen)
                          const SizedBox(width: 10),
                        if (commandMenuOpen)
                          Expanded(
                            child: SizedBox(
                              height: 310,
                              child: _CommandMenu(
                                commands: commands,
                                selected: selectedCommand,
                                onSelect: (packet) =>
                                    setState(() => selectedCommand = packet),
                                onClose: () =>
                                    setState(() => commandMenuOpen = false),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          StaggerReveal(
            index: 5,
            child: TimelinePanel(
              data: data,
              options: controller.options,
              revision: controller.resultRevision,
              onCursor: (value) => setState(() => cursorIndex = value),
              onAlarmSelected: _openAlarm,
              onCommandSelected: _openCommand,
              onRangeChanged: (start, end, first, last) => setState(() {
                rangeStartTime = start;
                rangeEndTime = end;
                fallbackStart = first;
                fallbackEnd = last;
                cursorIndex = null;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmMenu extends StatelessWidget {
  const _AlarmMenu({
    required this.alarms,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });
  final List<PacketRecord> alarms;
  final PacketRecord? selected;
  final ValueChanged<PacketRecord> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: EdgeInsets.zero,
    alarm: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded, size: 15, color: AppColors.red),
              const SizedBox(width: 7),
              Text(
                '\u544a\u8b66\u83dc\u5355 / ALARM EVENTS \u00b7 ${alarms.length}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: '\u6536\u8d77 / Close',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 5),
            itemCount: alarms.length,
            itemBuilder: (_, index) {
              final packet = alarms[index];
              final active = identical(packet, selected);
              final name = packet.alarmName.isEmpty
                  ? '\u672a\u77e5\u544a\u8b66'
                  : packet.alarmName;
              final time = packet.timelineTime == null
                  ? '\u65e0\u65f6\u95f4'
                  : localTime(packet.timelineTime!);
              return InkWell(
                onTap: () => onSelect(packet),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  color: active
                      ? AppColors.red.withValues(alpha: .08)
                      : Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#${packet.number}  $name${packet.alarmCode.isEmpty ? '' : ' (${packet.alarmCode})'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active ? AppColors.red : AppColors.text,
                              ),
                            ),
                          ),
                          Text(
                            time,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 9,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      if (active) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          packet.details.isEmpty
                              ? '\u8be5\u544a\u8b66\u5305\u6ca1\u6709\u53ef\u7528\u7684\u6587\u672c\u8be6\u60c5'
                              : packet.details,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            height: 1.45,
                            color: Color(0xFFB9C2CE),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _CommandMenu extends StatelessWidget {
  const _CommandMenu({
    required this.commands,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final List<PacketRecord> commands;
  final PacketRecord? selected;
  final ValueChanged<PacketRecord> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: accent),
                const SizedBox(width: 7),
                Text(
                  '\u6307\u4ee4\u83dc\u5355 / COMMAND EVENTS \u00b7 ${commands.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '\u6536\u8d77 / Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 5),
              itemCount: commands.length,
              itemBuilder: (_, index) {
                final packet = commands[index];
                final active = identical(packet, selected);
                final content = packet.commandContent.isEmpty
                    ? '\u672a\u63d0\u53d6\u6307\u4ee4\u5185\u5bb9'
                    : packet.commandContent;
                final time = packet.timelineTime == null
                    ? '\u65e0\u65f6\u95f4'
                    : localTime(packet.timelineTime!);
                return InkWell(
                  onTap: () => onSelect(packet),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    color: active
                        ? accent.withValues(alpha: .08)
                        : Colors.transparent,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '#${packet.number}  $content',
                                maxLines: active ? 3 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: active ? accent : AppColors.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 9,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        if (active) ...[
                          const SizedBox(height: 5),
                          Text(
                            packet.serial.isEmpty
                                ? 'CONCOX 0x80'
                                : 'CONCOX 0x80 \u00b7 SERIAL ${packet.serial}',
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 9,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            packet.details.isEmpty
                                ? '\u8be5\u6307\u4ee4\u5305\u6ca1\u6709\u53ef\u7528\u7684\u6587\u672c\u8be6\u60c5'
                                : packet.details,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 10,
                              height: 1.45,
                              color: AppColors.editorText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _KmlActions extends StatefulWidget {
  const _KmlActions({required this.controller});

  final AnalyzerController controller;

  @override
  State<_KmlActions> createState() => _KmlActionsState();
}

class _KmlActionsState extends State<_KmlActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Timer? _feedbackTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
    });
  }

  Future<void> _copy() async {
    if (!await widget.controller.copyKml() || !mounted) return;
    _feedbackTimer?.cancel();
    setState(() => _copied = true);
    _feedbackTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.controller.kml?.text.isNotEmpty == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _reveal,
          builder: (context, child) {
            final value = strongEaseOut.transform(_reveal.value);
            return SizedBox(
              width: 140 * value,
              height: 40,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 140,
                      child: Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(12 * (1 - value), 0),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SpringButton(
              key: const ValueKey('copy-kml-button'),
              label: _copied ? '\u5df2\u590d\u5236' : '\u590d\u5236 KML',
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              onPressed: enabled ? _copy : null,
            ),
          ),
        ),
        SpringButton(
          key: const ValueKey('export-kml-button'),
          label: '\u751f\u6210 KML',
          icon: Icons.public_rounded,
          primary: true,
          onPressed: enabled ? widget.controller.exportKml : null,
        ),
      ],
    );
  }
}

class StaggerReveal extends StatefulWidget {
  const StaggerReveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.index * 80), () {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        animation.value = 1;
      } else {
        animation.forward();
      }
    });
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: widget.child,
    builder: (_, child) {
      final value = strongEaseOut.transform(animation.value);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      );
    },
  );
}

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.controller});
  final AnalyzerController controller;
  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  double expandedHeight = 214;

  @override
  Widget build(BuildContext context) {
    final open = widget.controller.terminalOpen;
    final height = open ? expandedHeight : 38.0;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: strongEaseOut,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: open
                ? (details) => setState(
                    () => expandedHeight = (expandedHeight - details.delta.dy)
                        .clamp(120, 420),
                  )
                : null,
            onDoubleTap: widget.controller.toggleTerminal,
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(Icons.terminal_rounded, size: 15, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  const Text(
                    '排查日志 / TERMINAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.controller.logs.length} LINES',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 9,
                      color: AppColors.muted,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('copy-terminal-logs'),
                    tooltip: '复制全部日志 / Copy all',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.controller.copyTerminalLogs,
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                  ),
                  IconButton(
                    tooltip: open ? '收起 / Collapse' : '展开 / Expand',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.controller.toggleTerminal,
                    icon: Icon(
                      open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Expanded(
              child: SelectionArea(
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  itemCount: widget.controller.logs.length,
                  itemBuilder: (_, reverseIndex) {
                    final index =
                        widget.controller.logs.length - 1 - reverseIndex;
                    final line = widget.controller.logs[index];
                    final color = line.contains('[ERROR]')
                        ? AppColors.red
                        : line.contains('[WARN]') || line.contains('[ALARM]')
                        ? AppColors.orange
                        : AppColors.cyan.withValues(alpha: .8);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _TerminalTypedLine(
                        key: ValueKey(line),
                        value: line,
                        color: color,
                        animate: index == widget.controller.logs.length - 1,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AlarmPulse extends StatefulWidget {
  const AlarmPulse({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<AlarmPulse> createState() => _AlarmPulseState();
}

class _AlarmPulseState extends State<AlarmPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.enabled && !MediaQuery.disableAnimationsOf(context)) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
    }
  }

  @override
  void didUpdateWidget(covariant AlarmPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) didChangeDependencies();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: widget.child,
    builder: (_, child) {
      final wave = (math.sin(animation.value * math.pi * 2) + 1) / 2;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.red.withValues(
              alpha: widget.enabled ? .18 + .34 * wave : 0,
            ),
          ),
          boxShadow: widget.enabled
              ? [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: .05 + .11 * wave),
                    blurRadius: 18,
                  ),
                ]
              : const [],
        ),
        child: child,
      );
    },
  );
}

class _TerminalTypedLine extends StatelessWidget {
  const _TerminalTypedLine({
    super.key,
    required this.value,
    required this.color,
    required this.animate,
  });
  final String value;
  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget line(String text) => Text(
      text,
      style: TextStyle(
        fontFamily: 'Consolas',
        fontSize: 11,
        height: 1.35,
        color: color,
        shadows: [Shadow(color: color.withValues(alpha: .25), blurRadius: 5)],
      ),
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) return line(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.linear,
      builder: (_, progress, _) {
        final end = (value.length * progress).ceil().clamp(0, value.length);
        return line(value.substring(0, end));
      },
    );
  }
}
