// 用真实中转日志与真实官方输出做一次完整融合自检。
//
// 用法（在 flutter_app 目录下）：
//   dart run tool/validate_fusion.dart <原始日志.txt> <官方输出.txt>
//
// 这个脚本只读文件、只打印统计，不写入任何内容；用于在接入新的
// ProtocolAnalysis.exe 版本或改动融合逻辑后快速确认关联率没有退化。
import 'dart:io';

import 'package:gps_track_desktop/core/models.dart';
import 'package:gps_track_desktop/core/packet_fusion.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法：dart run tool/validate_fusion.dart <原始日志> <官方输出>');
    exit(64);
  }
  final rawSource = File(args[0]).readAsStringSync();
  final officialSource = File(args[1]).readAsStringSync();

  final raw = parseRawLog(rawSource);
  final data = fuseRawWithOfficial(
    rawSource,
    officialSource,
    const ParseOptions(),
  );
  final diagnostics = data.diagnostics;

  String percent(int part, int whole) =>
      whole == 0 ? 'n/a' : '${(part * 100 / whole).toStringAsFixed(1)}%';

  stdout
    ..writeln('原始日志字符数     : ${rawSource.length}')
    ..writeln('官方输出字符数     : ${officialSource.length}')
    ..writeln('--- 原始日志 ---')
    ..writeln('TRN 记录           : ${raw.records.length}')
    ..writeln('MSG 记录           : ${raw.messages}')
    ..writeln(
      '格式异常记录       : ${raw.records.where((r) => r.issue.isNotEmpty).length}',
    )
    ..writeln(
      '无 HEX 记录        : ${raw.records.where((r) => r.hex.isEmpty).length}',
    )
    ..writeln('--- 关联 ---')
    ..writeln(
      '已关联             : ${diagnostics.fusedRecords} '
      '(${percent(diagnostics.fusedRecords, raw.records.length)} of 原始记录)',
    )
    ..writeln('重复 HEX 歧义      : ${diagnostics.ambiguousRecords}')
    ..writeln('未匹配原始记录     : ${diagnostics.unmatchedRawRecords}')
    ..writeln('未关联官方包       : ${diagnostics.unmatchedOfficialPackets}')
    ..writeln('官方报告错误包     : ${diagnostics.officialErrorPackets ?? 'unknown'}')
    ..writeln('--- 结果 ---')
    ..writeln('数据包总数         : ${data.packets.length}')
    ..writeln('定位点             : ${data.points.length}')
    ..writeln('告警包             : ${data.packets.where((p) => p.alarm).length}')
    ..writeln(
      '心跳包             : ${data.packets.where((p) => p.heartbeat).length}',
    );

  final heartbeats = HeartbeatStats.fromPackets(data.packets);
  String interval(Duration? value) {
    if (value == null) return '--';
    final seconds = value.inMilliseconds / 1000;
    return seconds >= 60
        ? '${(seconds / 60).toStringAsFixed(1)} min'
        : '${seconds.toStringAsFixed(1)} s';
  }

  stdout
    ..writeln('心跳上行/回复      : ${heartbeats.uplink} / ${heartbeats.replies}')
    ..writeln('心跳精确时间       : ${heartbeats.exactTimes}')
    ..writeln('心跳未解决         : ${heartbeats.unresolved}')
    ..writeln(
      '心跳首次           : ${heartbeats.first == null ? '--' : localTime(heartbeats.first!)}',
    )
    ..writeln(
      '心跳末次           : ${heartbeats.last == null ? '--' : localTime(heartbeats.last!)}',
    )
    ..writeln(
      '心跳平均/最短/最长 : ${interval(heartbeats.averageInterval)} / '
      '${interval(heartbeats.shortestInterval)} / ${interval(heartbeats.longestInterval)}',
    )
    ..writeln('心跳断点           : ${heartbeats.breakpoints}');

  final bySource = <PacketTimeSource, int>{};
  for (final packet in data.packets) {
    bySource[packet.timeSource] = (bySource[packet.timeSource] ?? 0) + 1;
  }
  stdout.writeln('时间来源分布       : $bySource');

  // 回归门槛：真实样本必须保持住已知关联水平，退化就显式失败。
  final failures = <String>[];
  if (diagnostics.fusedRecords < 600) {
    failures.add('关联数 ${diagnostics.fusedRecords} 低于已知基线 600');
  }
  if (data.points.length < 60) {
    failures.add('定位点 ${data.points.length} 低于已知基线 60');
  }
  if (heartbeats.exactTimes == 0) {
    failures.add('心跳没有任何精确服务器时间');
  }
  if (failures.isEmpty) {
    stdout.writeln('\n结果：通过（关联、定位点与心跳时间均达到已知基线）');
    return;
  }
  for (final failure in failures) {
    stderr.writeln('结果：失败 — $failure');
  }
  exit(1);
}
