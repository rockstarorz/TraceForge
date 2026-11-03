import 'dart:isolate';

import 'kml.dart';
import 'models.dart';
import 'packet_fusion.dart';
import 'parser.dart';

class WorkerRequest {
  const WorkerRequest(
    this.sendPort,
    this.source,
    this.options, {
    this.rawSource,
  });
  final SendPort sendPort;
  final String source;
  final ParseOptions options;
  final String? rawSource;
}

/// 后台消息协议：
/// [0, progress, label] 表示进度；[1, ParsedData, KmlResult] 表示成功；
/// [2, error, stack] 表示失败。使用简单 List 可降低 Isolate 通信复杂度。
void generateInBackground(WorkerRequest request) {
  try {
    request.sendPort.send([
      0,
      0.0,
      request.rawSource == null ? '正在解析数据包' : '正在融合原始日志',
    ]);
    final parsed = request.rawSource == null
        ? parseText(request.source, request.options)
        : fuseRawWithOfficial(
            request.rawSource!,
            request.source,
            request.options,
          );
    final hasAlarms = parsed.packets.any((packet) => packet.alarm);
    final hasCommands = parsed.packets.any((packet) => packet.command);
    final hasHeartbeats = parsed.packets.any((packet) => packet.heartbeat);
    if (parsed.points.isEmpty && !hasAlarms && !hasCommands && !hasHeartbeats) {
      throw const FormatException(
        '未解析到定位点、心跳、告警包或指令包 / No supported packets found',
      );
    }
    // 只有告警或指令的样本也应进入结果界面。没有定位点时不生成空 KML；
    // 指令事件只进入统计、菜单和时间轴，不写入 Google Earth。
    final kml = parsed.points.isEmpty
        ? const KmlResult('', 0)
        : generateKml(
            parsed,
            request.options,
            onProgress: (value, label) =>
                request.sendPort.send([0, .42 + value * .58, label]),
          );
    request.sendPort.send([1, parsed, kml]);
  } catch (error, stack) {
    request.sendPort.send([2, error.toString(), stack.toString()]);
  }
}
