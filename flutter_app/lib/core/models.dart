/// 支持的解析文本协议。协议选择会决定字段名称和告警规则。
enum Protocol { concox, jt808 }

/// 输入来源：官方解析文本可直接分析；原始日志需先调用本机官方工具。
enum InputMode { officialText, rawLog }

/// ProtocolAnalysis 窗口显示策略。
enum OfficialWindowMode { background, brief, debug }

/// 时间轴当前采用的时间来源。只有 [server] 可用于精确心跳间隔。
enum PacketTimeSource { server, device, inferred, unknown }

class ParseOptions {
  const ParseOptions({
    this.protocol = Protocol.concox,
    this.filterZero = true,
    this.filterMtkRollback = false,
    this.detailed = false,
    this.chinese = false,
    this.driftMeters = 1500,
    this.driftSeconds = 1800,
    this.mtkReferenceTime,
  });
  final Protocol protocol;
  final bool filterZero, filterMtkRollback, detailed, chinese;
  final double driftMeters, driftSeconds;
  final DateTime? mtkReferenceTime;
}

/// 一个可写入 KML 的定位点。告警信息属于定位点时也保存在这里。
class GpsPoint {
  const GpsPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.speed = 0,
    this.heading = 0,
    this.altitude = 0,
    this.acc = false,
    this.satellites = 0,
    this.positioned = false,
    this.reupload = false,
    this.alarm = '',
    this.alarmCode = '',
    this.events = const [],
  });
  final DateTime time;
  final double latitude, longitude, speed, heading, altitude;
  final bool acc, positioned, reupload;
  final int satellites;
  final String alarm, alarmCode;
  final List<String> events;
}

/// 时间轴使用的数据包摘要。
///
/// [alarm] 是包级分类：包内只要出现“告警类型”就为 true；它与该包是否
/// 同时产生 [GpsPoint] 无关。[alarmName] 和 [alarmCode] 用于后续统计明细。
class PacketRecord {
  PacketRecord({
    this.number = 0,
    this.name = 'Unknown',
    this.code = '',
    this.serial = '',
    DateTime? time,
    DateTime? deviceTime,
    this.serverTime,
    this.serverTimeText = '',
    this.timelineTime,
    this.timeSource = PacketTimeSource.unknown,
    this.direction = '',
    this.rawHex = '',
    this.fusionStatus = '',
    this.rawHeartbeat = false,
    this.alarm = false,
    this.alarmName = '',
    this.alarmCode = '',
    this.command = false,
    this.commandContent = '',
  }) : deviceTime = deviceTime ?? time;
  int number;
  String name, code, serial, alarmName, alarmCode, commandContent;
  String details = '';
  DateTime? serverTime, deviceTime, timelineTime;
  PacketTimeSource timeSource;
  String direction, rawHex, fusionStatus, serverTimeText;
  bool rawHeartbeat;
  int? timeAnchorIndex;
  bool inferred = false, alarm, command;
  // 兼容现有调用方；业务含义始终是设备报文内部时间。
  DateTime? get time => deviceTime;
  set time(DateTime? value) => deviceTime = value;
  bool get heartbeat =>
      rawHeartbeat ||
      code == '0002' ||
      code == '13' ||
      RegExp(r'心跳|heartbeat', caseSensitive: false).hasMatch(name);
}

/// 解析器内部计数，用于区分文本未命中、包未归类和界面未渲染。
class ParseDiagnostics {
  const ParseDiagnostics({
    this.packetHeaders = 0,
    this.alarmLines = 0,
    this.alarmMatches = 0,
    this.alarmCoordinatesDetected = 0,
    this.zeroCoordinatesFiltered = 0,
    this.mtkRollbackFiltered = 0,
    this.rawRecords = 0,
    this.fusedRecords = 0,
    this.ambiguousRecords = 0,
    this.unmatchedRawRecords = 0,
    this.unmatchedOfficialPackets = 0,
    this.rawFormatIssues = 0,
    this.officialErrorPackets,
  });

  final int packetHeaders;
  final int alarmLines;
  final int alarmMatches;
  final int alarmCoordinatesDetected;
  final int zeroCoordinatesFiltered;
  final int mtkRollbackFiltered;
  final int rawRecords;
  final int fusedRecords;
  final int ambiguousRecords;
  final int unmatchedRawRecords;
  final int unmatchedOfficialPackets;
  final int rawFormatIssues;
  final int? officialErrorPackets;
}

class HeartbeatStats {
  const HeartbeatStats({
    required this.total,
    required this.uplink,
    required this.replies,
    required this.unknownDirection,
    required this.exactTimes,
    required this.unresolved,
    required this.breakpoints,
    this.first,
    this.last,
    this.averageInterval,
    this.shortestInterval,
    this.longestInterval,
  });

  final int total, uplink, replies, unknownDirection, exactTimes, unresolved;
  final int breakpoints;
  final DateTime? first, last;
  final Duration? averageInterval, shortestInterval, longestInterval;

  factory HeartbeatStats.fromPackets(
    Iterable<PacketRecord> packets, {
    Duration expectedInterval = const Duration(minutes: 5),
  }) {
    final heartbeats = packets.where((p) => p.heartbeat).toList();
    bool isUplink(String value) => value == '-->>' || value == '>';
    bool isReply(String value) =>
        value == '<<--' || value == '<+--' || value == '<';
    final exactHeartbeats = heartbeats
        .where((p) => p.serverTime != null)
        .toList();
    final intervalTimes =
        heartbeats
            .where((p) => p.serverTime != null && isUplink(p.direction))
            .map((p) => p.serverTime!)
            .toList()
          ..sort();
    final gaps = <Duration>[
      for (var i = 1; i < intervalTimes.length; i++)
        intervalTimes[i].difference(intervalTimes[i - 1]),
    ];
    Duration? shortest, longest, average;
    if (gaps.isNotEmpty) {
      shortest = gaps.reduce((a, b) => a <= b ? a : b);
      longest = gaps.reduce((a, b) => a >= b ? a : b);
      average = Duration(
        microseconds:
            gaps.fold<int>(0, (sum, item) => sum + item.inMicroseconds) ~/
            gaps.length,
      );
    }
    return HeartbeatStats(
      total: heartbeats.length,
      uplink: heartbeats.where((p) => isUplink(p.direction)).length,
      replies: heartbeats.where((p) => isReply(p.direction)).length,
      unknownDirection: heartbeats
          .where((p) => !isUplink(p.direction) && !isReply(p.direction))
          .length,
      exactTimes: exactHeartbeats.length,
      unresolved: heartbeats
          .where((p) => p.serverTime == null || p.fusionStatus.contains('歧义'))
          .length,
      breakpoints: gaps.where((gap) => gap > expectedInterval).length,
      first: intervalTimes.isEmpty ? null : intervalTimes.first,
      last: intervalTimes.isEmpty ? null : intervalTimes.last,
      averageInterval: average,
      shortestInterval: shortest,
      longestInterval: longest,
    );
  }
}

/// 后台 Isolate 返回给界面的轻量结果，不保留数百万字符的原始输入副本。
class ParsedData {
  const ParsedData({
    required this.points,
    required this.packets,
    required this.filtered,
    this.device,
    this.model,
    this.diagnostics = const ParseDiagnostics(),
  });
  final List<GpsPoint> points;
  final List<PacketRecord> packets;
  final int filtered;
  final String? device, model;
  final ParseDiagnostics diagnostics;
}

String localTime(DateTime utc, {bool seconds = true}) {
  final t = utc.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}${seconds ? ':${two(t.second)}' : ''}';
}
