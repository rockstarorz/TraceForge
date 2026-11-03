import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/kml.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

typedef TimelineRangeChanged =
    void Function(
      DateTime? startTime,
      DateTime? endTime,
      int fallbackStart,
      int fallbackEnd,
    );

bool isLocationPacket(PacketRecord packet) =>
    !packet.alarm &&
    !packet.heartbeat &&
    RegExp(r'定位|位置', caseSensitive: false).hasMatch(packet.name);

bool packetFallsInTimeRange(PacketRecord packet, DateTime start, DateTime end) {
  final time = packet.timelineTime;
  return time != null && !time.isBefore(start) && !time.isAfter(end);
}

/// 生成 ACC 阶梯线：状态保持到下一次变化，并在变化时垂直跳变。
///
/// [points] 必须按时间升序排列。可见区间从此前最后一个 ACC 状态继续，
/// 因此缩放或拖动范围时，状态线不会从第一个可见定位点才出现。
List<Offset> buildAccStepOffsets({
  required List<GpsPoint> points,
  required DateTime start,
  required DateTime end,
  required double left,
  required double width,
  required double onY,
  required double offY,
}) {
  if (points.isEmpty || !end.isAfter(start)) return const <Offset>[];

  final startMs = start.millisecondsSinceEpoch;
  final endMs = end.millisecondsSinceEpoch;
  final spanMs = math.max(1, endMs - startMs);
  bool? state;

  // 先找到区间开始时仍在持续的最后一个状态。
  for (final point in points) {
    final pointMs = point.time.millisecondsSinceEpoch;
    if (pointMs <= startMs) {
      state = point.acc;
    } else {
      break;
    }
  }

  final offsets = <Offset>[];
  if (state != null) {
    offsets.add(Offset(left, state ? onY : offY));
  }

  for (final point in points) {
    final pointMs = point.time.millisecondsSinceEpoch;
    if (pointMs < startMs) continue;
    if (pointMs > endMs) break;

    final x = left + width * (pointMs - startMs) / spanMs;
    if (state == null) {
      state = point.acc;
      offsets.add(Offset(x, state ? onY : offY));
      continue;
    }
    if (point.acc == state) continue;

    // 同一个 x 先保持旧状态，再切到新状态，Canvas 会画出垂直跳变。
    offsets
      ..add(Offset(x, state ? onY : offY))
      ..add(Offset(x, point.acc ? onY : offY));
    state = point.acc;
  }

  if (state != null) {
    offsets.add(Offset(left + width, state ? onY : offY));
  }
  return offsets;
}

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.data,
    required this.options,
    required this.revision,
    required this.onCursor,
    required this.onRangeChanged,
    required this.onAlarmSelected,
    required this.onCommandSelected,
  });

  final ParsedData data;
  final ParseOptions options;
  final int revision;
  final ValueChanged<int?> onCursor;
  final TimelineRangeChanged onRangeChanged;
  final ValueChanged<PacketRecord> onAlarmSelected;
  final ValueChanged<PacketRecord> onCommandSelected;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel>
    with TickerProviderStateMixin {
  bool expanded = false;
  bool showLocations = true;
  bool showHeartbeat = true;
  bool showAlarm = true;
  bool showCommand = true;
  bool showAcc = true;
  int? hoverIndex;
  RangeValues range = const RangeValues(0, 1);
  List<(int, DateTime)> allTimedPackets = const [];
  List<(int, DateTime)> timedPackets = const [];
  List<GpsPoint> chronologicalPoints = const [];
  int minMs = 0;
  int maxMs = 1;

  late final AnimationController reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  bool get hasTime => allTimedPackets.isNotEmpty;
  int get timeSpanMs => math.max(1, maxMs - minMs);
  int get selectedStartMs => minMs + (timeSpanMs * range.start).round();
  int get selectedEndMs => minMs + (timeSpanMs * range.end).round();
  DateTime? get selectedStartTime => hasTime
      ? DateTime.fromMillisecondsSinceEpoch(selectedStartMs, isUtc: true)
      : null;
  DateTime? get selectedEndTime => hasTime
      ? DateTime.fromMillisecondsSinceEpoch(selectedEndMs, isUtc: true)
      : null;
  int get fallbackStart {
    final last = math.max(0, widget.data.packets.length - 1);
    return (range.start * last).round().clamp(0, last);
  }

  int get fallbackEnd {
    final last = math.max(0, widget.data.packets.length - 1);
    return (range.end * last).round().clamp(fallbackStart, last);
  }

  @override
  void initState() {
    super.initState();
    _rebuildTimeExtent();
    _rebuildChronologicalPoints();
    _rebuildTimedPackets();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyRange();
      if (MediaQuery.disableAnimationsOf(context)) {
        reveal.value = 1;
      } else {
        reveal.forward();
        if (_hasDrift) pulse.repeat();
      }
    });
  }

  void _rebuildTimeExtent() {
    allTimedPackets = [
      for (var i = 0; i < widget.data.packets.length; i++)
        if (widget.data.packets[i].timelineTime != null)
          (i, widget.data.packets[i].timelineTime!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (allTimedPackets.isNotEmpty) {
      minMs = allTimedPackets.first.$2.millisecondsSinceEpoch;
      maxMs = allTimedPackets.last.$2.millisecondsSinceEpoch;
      if (maxMs <= minMs) maxMs = minMs + 1;
    }
  }

  void _rebuildChronologicalPoints() {
    chronologicalPoints = List<GpsPoint>.of(widget.data.points)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  void didUpdateWidget(covariant TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        !identical(oldWidget.data, widget.data)) {
      _rebuildChronologicalPoints();
    }
  }

  bool get _hasDrift {
    final points = widget.data.points;
    for (var i = 1; i < points.length; i++) {
      if (isDrift(points[i - 1], points[i], widget.options)) return true;
    }
    return false;
  }

  bool _inRange(int index, PacketRecord packet) {
    if (!hasTime) return index >= fallbackStart && index <= fallbackEnd;
    return packetFallsInTimeRange(packet, selectedStartTime!, selectedEndTime!);
  }

  bool _packetVisible(PacketRecord packet) {
    if (packet.command) return showCommand;
    if (packet.alarm) return showAlarm;
    if (packet.heartbeat) return showHeartbeat;
    if (isLocationPacket(packet)) return showLocations;
    return true;
  }

  int get selectedCount {
    var count = 0;
    for (var i = 0; i < widget.data.packets.length; i++) {
      if (_inRange(i, widget.data.packets[i])) count++;
    }
    return count;
  }

  void _rebuildTimedPackets() {
    timedPackets = [
      for (var i = 0; i < widget.data.packets.length; i++)
        if (widget.data.packets[i].timelineTime != null &&
            _inRange(i, widget.data.packets[i]) &&
            _packetVisible(widget.data.packets[i]))
          (i, widget.data.packets[i].timelineTime!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
  }

  void _notifyRange() {
    widget.onRangeChanged(
      selectedStartTime,
      selectedEndTime,
      fallbackStart,
      fallbackEnd,
    );
  }

  void _toggleFilter(String type) {
    setState(() {
      switch (type) {
        case 'location':
          showLocations = !showLocations;
          break;
        case 'heartbeat':
          showHeartbeat = !showHeartbeat;
          break;
        case 'alarm':
          showAlarm = !showAlarm;
          break;
        case 'command':
          showCommand = !showCommand;
          break;
        case 'acc':
          showAcc = !showAcc;
          break;
      }
      hoverIndex = null;
      _rebuildTimedPackets();
    });
    widget.onCursor(null);
  }

  void _setRange(RangeValues value) {
    var start = value.start.clamp(0.0, 1.0);
    var end = value.end.clamp(0.0, 1.0);
    const minimumSpan = .0005;
    if (end - start < minimumSpan) {
      if (start + minimumSpan <= 1) {
        end = start + minimumSpan;
      } else {
        start = end - minimumSpan;
      }
    }
    final next = RangeValues(start, end);
    if (next.start == range.start && next.end == range.end) return;
    setState(() {
      range = next;
      hoverIndex = null;
      _rebuildTimedPackets();
    });
    widget.onCursor(null);
  }

  void _updateCursor(Offset local, double width) {
    final packets = widget.data.packets;
    if (packets.isEmpty) return;
    const chartLeft = 56.0, chartRight = 14.0;
    final chartWidth = math.max(1.0, width - chartLeft - chartRight);
    final fraction = ((local.dx - chartLeft) / chartWidth).clamp(0.0, 1.0);
    int index;
    if (timedPackets.isEmpty) {
      index =
          fallbackStart +
          (fraction * math.max(0, fallbackEnd - fallbackStart)).round();
    } else {
      final target =
          selectedStartMs +
          ((selectedEndMs - selectedStartMs) * fraction).round();
      var low = 0, high = timedPackets.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (timedPackets[middle].$2.millisecondsSinceEpoch < target) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      if (low == 0) {
        index = timedPackets.first.$1;
      } else if (low == timedPackets.length) {
        index = timedPackets.last.$1;
      } else {
        final before = timedPackets[low - 1];
        final after = timedPackets[low];
        index =
            target - before.$2.millisecondsSinceEpoch <=
                after.$2.millisecondsSinceEpoch - target
            ? before.$1
            : after.$1;
      }
    }
    if (index == hoverIndex) return;
    setState(() => hoverIndex = index);
    widget.onCursor(index);
  }

  int _nearestPacketIndex(int targetMs) {
    if (allTimedPackets.isEmpty) return fallbackStart;
    var low = 0, high = allTimedPackets.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (allTimedPackets[middle].$2.millisecondsSinceEpoch < targetMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return allTimedPackets.first.$1;
    if (low == allTimedPackets.length) return allTimedPackets.last.$1;
    final before = allTimedPackets[low - 1];
    final after = allTimedPackets[low];
    return targetMs - before.$2.millisecondsSinceEpoch <=
            after.$2.millisecondsSinceEpoch - targetMs
        ? before.$1
        : after.$1;
  }

  String _handleLabel(double fraction) {
    if (!hasTime) {
      final last = math.max(0, widget.data.packets.length - 1);
      return '#${(fraction * last).round() + 1}';
    }
    final targetMs = minMs + (timeSpanMs * fraction).round();
    final index = _nearestPacketIndex(targetMs);
    final packet = widget.data.packets[index];
    final anchor = packet.timeAnchorIndex;
    final mark = !packet.inferred
        ? ''
        : anchor != null && index > anchor
        ? '+'
        : '~';
    final time = DateTime.fromMillisecondsSinceEpoch(targetMs, isUtc: true);
    return '${localTime(time, seconds: false)} \u00b7 #${index + 1}$mark';
  }

  List<Widget> _alarmFlags(double width) {
    if (!showAlarm || !hasTime || selectedEndMs <= selectedStartMs) {
      return const [];
    }
    const left = 56.0, right = 14.0;
    final chartWidth = math.max(1.0, width - left - right);
    final bucketWidth = math.max(18.0, chartWidth / 90);
    final groups = <int, List<(int, PacketRecord)>>{};
    for (var i = 0; i < widget.data.packets.length; i++) {
      final packet = widget.data.packets[i];
      if (!packet.alarm ||
          !_inRange(i, packet) ||
          packet.timelineTime == null) {
        continue;
      }
      final fraction =
          (packet.timelineTime!.millisecondsSinceEpoch - selectedStartMs) /
          math.max(1, selectedEndMs - selectedStartMs);
      final bucket = (fraction * chartWidth / bucketWidth).round();
      groups.putIfAbsent(bucket, () => []).add((i, packet));
    }
    return [
      for (final entry in groups.entries)
        Positioned(
          left: (left + entry.key * bucketWidth - 10).clamp(
            left - 10,
            left + chartWidth - 10,
          ),
          top: 3,
          child: _AlarmFlag(
            key: ValueKey(
              'alarm-${entry.value.first.$1}-${entry.value.length}',
            ),
            packets: entry.value.map((item) => item.$2).toList(growable: false),
            onTap: () => widget.onAlarmSelected(entry.value.first.$2),
          ),
        ),
    ];
  }

  List<Widget> _commandMarkers(double width) {
    if (!showCommand || !hasTime || selectedEndMs <= selectedStartMs) {
      return const [];
    }
    const left = 56.0, right = 14.0;
    final chartWidth = math.max(1.0, width - left - right);
    final bucketWidth = math.max(18.0, chartWidth / 90);
    final groups = <int, List<(int, PacketRecord)>>{};
    final alarmBuckets = <int>{};
    for (var i = 0; i < widget.data.packets.length; i++) {
      final packet = widget.data.packets[i];
      if (!_inRange(i, packet) || packet.timelineTime == null) continue;
      final fraction =
          (packet.timelineTime!.millisecondsSinceEpoch - selectedStartMs) /
          math.max(1, selectedEndMs - selectedStartMs);
      final bucket = (fraction * chartWidth / bucketWidth).round();
      if (packet.alarm) alarmBuckets.add(bucket);
      if (packet.command) {
        groups.putIfAbsent(bucket, () => []).add((i, packet));
      }
    }
    double markerLeft(int bucket) {
      final minimum = left - 10;
      final maximum = left + chartWidth - 10;
      final base = (left + bucket * bucketWidth - 10).clamp(minimum, maximum);
      if (!alarmBuckets.contains(bucket)) return base;
      // Keep a full hit target between an alarm flag and command icon. Near
      // the right edge the command moves left instead of being clamped on top.
      return base + 24 <= maximum ? base + 24 : math.max(minimum, base - 24);
    }

    return [
      for (final entry in groups.entries)
        Positioned(
          left: markerLeft(entry.key),
          top: 4,
          child: _CommandMarker(
            key: ValueKey(
              'command-${entry.value.first.$1}-${entry.value.length}',
            ),
            packets: entry.value.map((item) => item.$2).toList(growable: false),
            onTap: () => widget.onCommandSelected(entry.value.first.$2),
          ),
        ),
    ];
  }

  @override
  void dispose() {
    reveal.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packets = widget.data.packets;
    // These colors come from AnimatedTheme. Passing them into CustomPainter
    // makes the chart repaint on every palette interpolation frame.
    final theme = Theme.of(context);
    final timelineAccent = theme.colorScheme.primary;
    final timelineText = theme.colorScheme.onSurface;
    final timelineMuted = theme.colorScheme.onSurfaceVariant;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: strongEaseInOut,
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: expanded ? 420 : 296,
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                  child: Row(
                    children: [
                      const Text(
                        '\u6570\u636e\u5305\u65f6\u95f4\u8f74 / PACKET TIMELINE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FilterChip(
                        color: timelineAccent,
                        label: '\u5b9a\u4f4d',
                        selected: showLocations,
                        onTap: () => _toggleFilter('location'),
                      ),
                      _FilterChip(
                        color: AppColors.heartbeat,
                        label: '\u5fc3\u8df3',
                        selected: showHeartbeat,
                        onTap: () => _toggleFilter('heartbeat'),
                      ),
                      _FilterChip(
                        color: AppColors.red,
                        label: '\u544a\u8b66',
                        selected: showAlarm,
                        onTap: () => _toggleFilter('alarm'),
                      ),
                      _FilterChip(
                        color: timelineAccent,
                        label: '\u6307\u4ee4',
                        selected: showCommand,
                        onTap: () => _toggleFilter('command'),
                      ),
                      _FilterChip(
                        color: AppColors.orange,
                        label: 'ACC',
                        selected: showAcc,
                        onTap: () => _toggleFilter('acc'),
                      ),
                      const Spacer(),
                      Text(
                        '$selectedCount / ${packets.length} PACKETS',
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        expanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    onHover: (event) => _updateCursor(
                      event.localPosition,
                      constraints.maxWidth,
                    ),
                    onExit: (_) {
                      setState(() => hoverIndex = null);
                      widget.onCursor(null);
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: Listenable.merge([reveal, pulse]),
                              builder: (_, _) => CustomPaint(
                                painter: TimelinePainter(
                                  data: widget.data,
                                  chronologicalPoints: chronologicalPoints,
                                  options: widget.options,
                                  startTime: selectedStartTime,
                                  endTime: selectedEndTime,
                                  fallbackStart: fallbackStart,
                                  fallbackEnd: fallbackEnd,
                                  reveal: reveal.value,
                                  pulse: pulse.value,
                                  cursorIndex: hoverIndex,
                                  showLocations: showLocations,
                                  showHeartbeat: showHeartbeat,
                                  showAlarm: showAlarm,
                                  showAcc: showAcc,
                                  locationColor: timelineAccent,
                                  gridColor: timelineText.withValues(
                                    alpha: .09,
                                  ),
                                  cursorColor: timelineText.withValues(
                                    alpha: .78,
                                  ),
                                  totalPacketsColor: timelineAccent.withValues(
                                    alpha: .18,
                                  ),
                                  labelColor: timelineText,
                                  mutedLabelColor: timelineMuted,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          ),
                        ),
                        ..._alarmFlags(constraints.maxWidth),
                        ..._commandMarkers(constraints.maxWidth),
                      ],
                    ),
                  ),
                ),
              ),
              if (packets.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 12, 8),
                  child: Column(
                    children: [
                      RangeSlider(
                        min: 0,
                        max: 1,
                        values: range,
                        labels: RangeLabels(
                          _handleLabel(range.start),
                          _handleLabel(range.end),
                        ),
                        onChanged: _setRange,
                        onChangeEnd: (_) => _notifyRange(),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '\u5f00\u59cb ${_handleLabel(range.start)}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 9,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          if (widget.data.packets.any(
                            (packet) => packet.inferred,
                          ))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                '+ \u665a\u4e8e\u951a\u70b9  ~ \u63a8\u5b9a',
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 8,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '\u7ed3\u675f ${_handleLabel(range.end)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 9,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                        ],
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

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool hovered = false;

  void _trigger() {
    widget.onTap();
    if (MediaQuery.disableAnimationsOf(context)) return;
    scale.value = .9;
    scale.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 430, damping: 27),
        scale.value,
        1,
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
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: ScaleTransition(
      scale: scale,
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Material(
          color: widget.selected
              ? widget.color.withValues(alpha: hovered ? .2 : .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _trigger,
            borderRadius: BorderRadius.circular(7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: widget.selected
                      ? widget.color.withValues(alpha: .5)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.selected ? widget.color : AppColors.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.selected ? AppColors.text : AppColors.muted,
                      fontSize: 9,
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

class _AlarmFlag extends StatefulWidget {
  const _AlarmFlag({super.key, required this.packets, required this.onTap});
  final List<PacketRecord> packets;
  final VoidCallback onTap;

  @override
  State<_AlarmFlag> createState() => _AlarmFlagState();
}

class _AlarmFlagState extends State<_AlarmFlag>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool hovered = false;

  void _setHover(bool value) {
    setState(() => hovered = value);
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = value ? 1.12 : 1;
      return;
    }
    motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 25),
        motion.value,
        value ? 1.12 : 1,
        0,
      ),
    );
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.packets.first;
    final names = widget.packets
        .map(
          (packet) => packet.alarmName.isEmpty
              ? '\u672a\u77e5\u544a\u8b66'
              : packet.alarmName,
        )
        .toSet()
        .join(' / ');
    final time = first.timelineTime == null
        ? '\u65e0\u65f6\u95f4'
        : localTime(first.timelineTime!);
    final suffix = widget.packets.length > 1
        ? ' \u00b7 ${widget.packets.length} \u6761'
        : '';
    return Tooltip(
      message: '$names$suffix\n$time',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: motion,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 22,
              height: 29,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FlagGlyphPainter(highlighted: hovered),
                    ),
                  ),
                  if (widget.packets.length > 1)
                    Positioned(
                      right: -5,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${widget.packets.length}',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
    );
  }
}

class _CommandMarker extends StatefulWidget {
  const _CommandMarker({super.key, required this.packets, required this.onTap});

  final List<PacketRecord> packets;
  final VoidCallback onTap;

  @override
  State<_CommandMarker> createState() => _CommandMarkerState();
}

class _CommandMarkerState extends State<_CommandMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool hovered = false;

  void _setHover(bool value) {
    setState(() => hovered = value);
    final target = value ? 1.14 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = target;
      return;
    }
    motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 390, damping: 25),
        motion.value,
        target,
        0,
      ),
    );
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.packets.first;
    final commands = widget.packets
        .map(
          (packet) => packet.commandContent.isEmpty
              ? '\u672a\u63d0\u53d6\u6307\u4ee4'
              : packet.commandContent,
        )
        .toSet()
        .join(' / ');
    final time = first.timelineTime == null
        ? '\u65e0\u65f6\u95f4'
        : localTime(first.timelineTime!);
    final suffix = widget.packets.length > 1
        ? ' \u00b7 ${widget.packets.length} \u6761'
        : '';
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: '$commands$suffix\n$time',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: motion,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 22,
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: hovered ? .22 : .12),
                        border: Border.all(
                          color: accent.withValues(alpha: hovered ? .9 : .6),
                        ),
                        shape: BoxShape.circle,
                        boxShadow: hovered
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: .28),
                                  blurRadius: 9,
                                ),
                              ]
                            : const [],
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: accent,
                      ),
                    ),
                  ),
                  if (widget.packets.length > 1)
                    Positioned(
                      right: -5,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${widget.packets.length}',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
    );
  }
}

class _FlagGlyphPainter extends CustomPainter {
  const _FlagGlyphPainter({required this.highlighted});
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final pole = Paint()
      ..color = highlighted ? Colors.white : const Color(0xFFC6CDD7)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(5, 3), Offset(5, size.height - 2), pole);
    canvas.drawLine(
      Offset(2, size.height - 2),
      Offset(9, size.height - 2),
      pole,
    );
    final flag = Path()
      ..moveTo(5, 4)
      ..lineTo(size.width - 2, 7)
      ..lineTo(size.width - 7, 13)
      ..lineTo(5, 11)
      ..close();
    canvas.drawShadow(flag, AppColors.red, highlighted ? 7 : 3, true);
    canvas.drawPath(flag, Paint()..color = AppColors.red);
  }

  @override
  bool shouldRepaint(covariant _FlagGlyphPainter oldDelegate) =>
      oldDelegate.highlighted != highlighted;
}

class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.data,
    required this.chronologicalPoints,
    required this.options,
    required this.startTime,
    required this.endTime,
    required this.fallbackStart,
    required this.fallbackEnd,
    required this.reveal,
    required this.pulse,
    required this.cursorIndex,
    required this.showLocations,
    required this.showHeartbeat,
    required this.showAlarm,
    required this.showAcc,
    required this.locationColor,
    required this.gridColor,
    required this.cursorColor,
    required this.totalPacketsColor,
    required this.labelColor,
    required this.mutedLabelColor,
  });

  final ParsedData data;
  final List<GpsPoint> chronologicalPoints;
  final ParseOptions options;
  final DateTime? startTime;
  final DateTime? endTime;
  final int fallbackStart;
  final int fallbackEnd;
  final double reveal;
  final double pulse;
  final int? cursorIndex;
  final bool showLocations;
  final bool showHeartbeat;
  final bool showAlarm;
  final bool showAcc;
  final Color locationColor;
  final Color gridColor;
  final Color cursorColor;
  final Color totalPacketsColor;
  final Color labelColor;
  final Color mutedLabelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final packets = data.packets;
    if (packets.isEmpty) return;
    const left = 56.0, right = 14.0, top = 34.0, bottom = 38.0;
    final width = math.max(1.0, size.width - left - right);
    final height = math.max(1.0, size.height - top - bottom);
    final baseline = top + height;
    final hasTimeRange = startTime != null && endTime != null;
    final start = fallbackStart.clamp(0, packets.length - 1);
    final end = fallbackEnd.clamp(start, packets.length - 1);
    final firstMs = hasTimeRange ? startTime!.millisecondsSinceEpoch : 0;
    final lastMs = hasTimeRange
        ? math.max(firstMs + 1, endTime!.millisecondsSinceEpoch)
        : math.max(1, end - start);
    final spanMs = math.max(1, lastMs - firstMs);
    final visible = <PacketRecord>[
      for (var i = 0; i < packets.length; i++)
        if (hasTimeRange
            ? packets[i].timelineTime != null &&
                  packets[i].timelineTime!.millisecondsSinceEpoch >= firstMs &&
                  packets[i].timelineTime!.millisecondsSinceEpoch <= lastMs
            : i >= start && i <= end)
          packets[i],
    ];
    final binCount = math.max(1, math.min((width / 7).floor(), 160));
    final total = List<int>.filled(binCount, 0);
    final location = List<int>.filled(binCount, 0);
    final heartbeat = List<int>.filled(binCount, 0);
    final alarm = List<int>.filled(binCount, 0);

    for (var local = 0; local < visible.length; local++) {
      final packet = visible[local];
      final fraction = !hasTimeRange || packet.timelineTime == null
          ? local / math.max(1, visible.length - 1)
          : (packet.timelineTime!.millisecondsSinceEpoch - firstMs) / spanMs;
      final bin = (fraction * (binCount - 1)).round().clamp(0, binCount - 1);
      total[bin]++;
      if (packet.alarm) {
        alarm[bin]++;
      } else if (packet.heartbeat) {
        heartbeat[bin]++;
      } else if (isLocationPacket(packet)) {
        location[bin]++;
      }
    }
    var maxCount = 1;
    for (var i = 0; i < binCount; i++) {
      maxCount = math.max(maxCount, total[i]);
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final y = top + height * row / 4;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), grid);
      final value = (maxCount * (4 - row) / 4).round();
      _label(
        canvas,
        '$value',
        Offset(left - 9 - _measure('$value'), y - 6),
        muted: true,
      );
      canvas.drawLine(Offset(left - 4, y), Offset(left, y), grid);
    }
    canvas.drawLine(Offset(left, top), Offset(left, baseline), grid);
    canvas.drawLine(
      Offset(left, baseline),
      Offset(left + width, baseline),
      grid,
    );
    _label(canvas, '包数', const Offset(9, 8), muted: true);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(left, top, width * reveal, height));
    final barWidth = math.max(2.0, width / binCount - 1.2);
    for (var i = 0; i < binCount; i++) {
      final x = left + width * i / binCount;
      var y = baseline;
      void segment(int count, Color color) {
        if (count == 0) return;
        final segmentHeight = height * count / maxCount;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y - segmentHeight, barWidth, segmentHeight),
            const Radius.circular(1.2),
          ),
          Paint()..color = color,
        );
        y -= segmentHeight;
      }

      // The pale wide bar is the total packet density and remains as context.
      final totalHeight = height * total[i] / maxCount;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - .8,
            baseline - totalHeight,
            barWidth + 1.6,
            totalHeight,
          ),
          const Radius.circular(1.2),
        ),
        Paint()..color = totalPacketsColor,
      );
      if (showLocations) {
        segment(location[i], locationColor.withValues(alpha: .82));
      }
      if (showHeartbeat) {
        segment(heartbeat[i], AppColors.heartbeat.withValues(alpha: .92));
      }
      if (showAlarm) segment(alarm[i], AppColors.red);
    }

    final points = chronologicalPoints
        .where((point) {
          if (!hasTimeRange) return false;
          final ms = point.time.millisecondsSinceEpoch;
          return ms >= firstMs && ms <= lastMs;
        })
        .toList(growable: false);
    if (showAcc && hasTimeRange && chronologicalPoints.isNotEmpty) {
      // ON 使用固定像素轨道，图表展开或收缩时不会随高度漂移；
      // OFF 保留原来的低位比例，继续贴近横轴。
      final onY = (baseline - 24.0).clamp(top, baseline).toDouble();
      final offY = baseline - height * .045;
      final offsets = buildAccStepOffsets(
        points: chronologicalPoints,
        start: startTime!,
        end: endTime!,
        left: left,
        width: width,
        onY: onY,
        offY: offY,
      );
      if (offsets.isNotEmpty) {
        final accPath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
        for (final offset in offsets.skip(1)) {
          accPath.lineTo(offset.dx, offset.dy);
        }
        canvas.drawPath(
          accPath,
          Paint()
            ..color = AppColors.orange
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }

      for (var i = 1; i < points.length; i++) {
        if (!isDrift(points[i - 1], points[i], options)) continue;
        final x =
            left +
            width * (points[i].time.millisecondsSinceEpoch - firstMs) / spanMs;
        final opacity = .18 + .20 * (math.sin(pulse * math.pi * 2) + 1) / 2;
        canvas.drawRect(
          Rect.fromLTWH(x - 3, top, 6, height),
          Paint()..color = AppColors.red.withValues(alpha: opacity),
        );
      }
    }
    canvas.restore();

    const tickCount = 6;
    for (var i = 0; i < tickCount; i++) {
      final fraction = i / (tickCount - 1);
      final x = left + width * fraction;
      canvas.drawLine(Offset(x, baseline), Offset(x, baseline + 4), grid);
      final label = !hasTimeRange
          ? '#${start + (fraction * (end - start)).round() + 1}'
          : _axisTime(
              DateTime.fromMillisecondsSinceEpoch(
                firstMs + (spanMs * fraction).round(),
                isUtc: true,
              ),
              spanMs,
            );
      final labelWidth = _measure(label);
      _label(
        canvas,
        label,
        Offset(
          (x - labelWidth / 2).clamp(left, left + width - labelWidth),
          baseline + 8,
        ),
        muted: true,
      );
    }

    final cursor = cursorIndex;
    if (cursor != null && cursor >= start && cursor <= end) {
      final packet = packets[cursor];
      final fraction = !hasTimeRange || packet.timelineTime == null
          ? (cursor - start) / math.max(1, end - start)
          : (packet.timelineTime!.millisecondsSinceEpoch - firstMs) / spanMs;
      final x = left + width * fraction.clamp(0, 1);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, baseline),
        Paint()
          ..color = cursorColor
          ..strokeWidth = 1,
      );
      final name = packet.alarm
          ? '${packet.alarmName} (${packet.alarmCode})'
          : packet.command
          ? '\u6307\u4ee4 ${packet.commandContent}'
          : packet.name;
      final anchor = packet.timeAnchorIndex;
      final inferred = !packet.inferred
          ? ''
          : anchor != null && cursor > anchor
          ? '  [晚于时间锚点]'
          : '  [推定时间]';
      final label = '#${cursor + 1}  $name$inferred';
      _label(
        canvas,
        label,
        Offset((x + 8).clamp(left, size.width - 190), top + 4),
      );
    }
  }

  String _axisTime(DateTime utc, int spanMs) {
    final value = localTime(utc);
    if (spanMs <= const Duration(hours: 6).inMilliseconds) {
      return value.substring(11, 19);
    }
    if (spanMs <= const Duration(days: 3).inMilliseconds) {
      return value.substring(5, 16);
    }
    return value.substring(5, 10);
  }

  double _measure(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'Consolas', fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  void _label(
    Canvas canvas,
    String value,
    Offset offset, {
    bool muted = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 9,
          color: muted ? mutedLabelColor : labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 185);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.startTime != startTime ||
      oldDelegate.endTime != endTime ||
      oldDelegate.fallbackStart != fallbackStart ||
      oldDelegate.fallbackEnd != fallbackEnd ||
      oldDelegate.reveal != reveal ||
      oldDelegate.pulse != pulse ||
      oldDelegate.cursorIndex != cursorIndex ||
      oldDelegate.showLocations != showLocations ||
      oldDelegate.showHeartbeat != showHeartbeat ||
      oldDelegate.showAlarm != showAlarm ||
      oldDelegate.showAcc != showAcc ||
      oldDelegate.locationColor != locationColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.cursorColor != cursorColor ||
      oldDelegate.totalPacketsColor != totalPacketsColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.mutedLabelColor != mutedLabelColor;
}
