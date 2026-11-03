import 'dart:typed_data';

import 'models.dart';
import 'parser.dart';

class RawLogRecord {
  const RawLogRecord({
    required this.line,
    required this.serverTimeText,
    required this.direction,
    required this.endpoint,
    required this.hex,
    this.issue = '',
  });
  final int line;
  final String serverTimeText, direction, endpoint, hex, issue;
}

class RawLogData {
  const RawLogData(this.records, this.issues, this.messages);
  final List<RawLogRecord> records;
  final List<String> issues;
  final int messages;
}

String? normalizeHex(String source) {
  final value = source.trim().replaceFirst(RegExp(r'[\s,]+$'), '');
  if (value.isEmpty ||
      !RegExp(
        r'^(?:[0-9a-f]{2})(?:[\s,]*[0-9a-f]{2})*$',
        caseSensitive: false,
      ).hasMatch(value)) {
    return null;
  }
  return value.replaceAll(RegExp(r'[\s,]'), '').toUpperCase();
}

RawLogData parseRawLog(String source) {
  final records = <RawLogRecord>[];
  final issues = <String>[];
  var messages = 0;
  final header = RegExp(
    r'(?:(?:\d{4}[-/])?\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+(?:TRN|MSG)\b',
  );
  final headers = header.allMatches(source).toList();
  if (headers.isEmpty) return _parseRelayLog(source);
  final trn = RegExp(
    r'^\s*((?:\d{4}[-/])?\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+TRN\s+(-->>|<<--|<\+--)\s+(.*?)\s+\((\d+)\)\s*\{([^}]*)\}',
    dotAll: true,
  );
  var physicalLine = 1, lastOffset = 0;
  for (var i = 0; i < headers.length; i++) {
    physicalLine += '\n'
        .allMatches(source.substring(lastOffset, headers[i].start))
        .length;
    lastOffset = headers[i].start;
    final block = source.substring(
      headers[i].start,
      i + 1 < headers.length ? headers[i + 1].start : source.length,
    );
    if (RegExp(r'^\S+\s+\S+\s+MSG\b').hasMatch(block)) {
      messages++;
      continue;
    }
    final match = trn.firstMatch(block);
    if (match == null) {
      issues.add('原始行 $physicalLine：未提取时间或 HEX');
      continue;
    }
    final value = normalizeHex(match[5]!);
    final declared = int.parse(match[4]!);
    final issue = value == null
        ? 'HEX 格式无效'
        : value.length ~/ 2 != declared
        ? '声明长度与 HEX 不符'
        : '';
    records.add(
      RawLogRecord(
        line: physicalLine,
        serverTimeText: match[1]!,
        direction: match[2]!,
        endpoint: match[3]!,
        hex: value ?? '',
        issue: issue,
      ),
    );
  }
  return RawLogData(records, issues, messages);
}

RawLogData _parseRelayLog(String source) {
  final records = <RawLogRecord>[];
  final relay = RegExp(
    r'^(\d{4}[-/]\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2}[.,]\d{1,3})\s+(\S+)\s+(\S+)\s+(0x[0-9a-fA-F]+)\s+([<>])\s+([0-9a-fA-F, ]+)[\s,]*$',
  );
  final lines = source.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final match = relay.firstMatch(lines[i]);
    if (match == null) continue;
    final value = normalizeHex(match[6]!) ?? '';
    records.add(
      RawLogRecord(
        line: i + 1,
        serverTimeText: match[1]!.replaceAll(',', '.'),
        direction: match[5]!,
        endpoint: '${match[3]} ${match[4]}',
        hex: value,
        issue: value.isEmpty ? 'HEX 格式无效' : '',
      ),
    );
  }
  final issues = records.isEmpty && source.trim().isNotEmpty
      ? <String>['原始行 1：未识别日志时间；不影响官方解析结果']
      : <String>[];
  return RawLogData(records, issues, 0);
}

DateTime? parseServerTime(String value, {int? fallbackYear}) {
  final match = RegExp(
    r'^(?:(\d{4})[-/])?(\d{2})[-/](\d{2})\s+(\d{2}):(\d{2}):(\d{2})(?:[.,](\d+))?$',
  ).firstMatch(value);
  if (match == null) return null;
  // 部分服务器日志只记录 MM-dd。旧逻辑固定补 2000，导致所有精确
  // 心跳时间落到错误年份；调用方应优先传入官方包设备时间推断出的年份。
  final year = int.parse(match[1] ?? '${fallbackYear ?? DateTime.now().year}');
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final millisecond = int.parse(
    (match[7] ?? '').padRight(3, '0').substring(0, 3),
  );
  final result = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
  );
  final valid =
      result.year == year &&
          result.month == month &&
          result.day == day &&
          result.hour == hour &&
          result.minute == minute &&
          result.second == second
      ? result
      : null;
  // 服务器日志与设备时间一样按 GMT+8 墙上时间记录；内部统一保存 UTC。
  return valid?.subtract(const Duration(hours: 8));
}

int _officialYearHint(ParsedData parsed) {
  final counts = <int, int>{};
  for (final packet in parsed.packets) {
    final time = packet.deviceTime;
    if (time == null) continue;
    final year = time.toUtc().add(const Duration(hours: 8)).year;
    if (year >= 2000 && year <= DateTime.now().year + 1) {
      counts[year] = (counts[year] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return DateTime.now().year;
  return counts.entries.reduce((best, item) {
    if (item.value != best.value) return item.value > best.value ? item : best;
    return item.key > best.key ? item : best;
  }).key;
}

String rawProtocol(String hex) {
  if (hex.startsWith('7878') && hex.length >= 8) return hex.substring(6, 8);
  if (hex.startsWith('7979') && hex.length >= 10) return hex.substring(8, 10);
  if (hex.startsWith('7E') && hex.length >= 6) return hex.substring(2, 6);
  return '';
}

String rawSerial(String hex) =>
    (hex.startsWith('7878') || hex.startsWith('7979')) && hex.length >= 12
    ? hex.substring(hex.length - 12, hex.length - 8)
    : '';

bool rawIsHeartbeat(String hex) {
  final protocol = rawProtocol(hex);
  return protocol == '13' || protocol == '0002';
}

ParsedData fuseRawWithOfficial(
  String rawSource,
  String officialSource,
  ParseOptions options,
) {
  final raw = parseRawLog(rawSource);
  final parsed = parseText(officialSource, options);
  final serverYear = _officialYearHint(parsed);
  final originalOfficialCount = parsed.packets.length;
  final officialByHex = <String, List<int>>{};
  final rawByHex = <String, List<int>>{};
  for (var i = 0; i < parsed.packets.length; i++) {
    final value = parsed.packets[i].rawHex;
    if (value.isNotEmpty) (officialByHex[value] ??= []).add(i);
  }
  for (var i = 0; i < raw.records.length; i++) {
    final record = raw.records[i];
    if (record.issue.isEmpty && record.hex.isNotEmpty) {
      (rawByHex[record.hex] ??= []).add(i);
    }
  }

  final forced = _forcedAlignment(raw.records, parsed.packets);
  final used = <int>{};
  var fused = 0, ambiguous = 0, unmatchedRaw = 0;
  for (var i = 0; i < raw.records.length; i++) {
    final record = raw.records[i];
    final candidates = officialByHex[record.hex] ?? const <int>[];
    int? match;
    var status = record.issue.isNotEmpty ? '原始数据异常' : '未匹配';
    if (record.issue.isEmpty && candidates.isNotEmpty) {
      if (candidates.length == 1 && (rawByHex[record.hex]?.length ?? 0) == 1) {
        match = candidates.single;
        status = '精确匹配';
      } else if (forced.containsKey(i)) {
        match = forced[i];
        status = '顺序/协议/流水号匹配';
      } else {
        status = '重复 HEX 歧义';
        ambiguous++;
      }
    }
    if (match == null) {
      unmatchedRaw++;
      if (rawIsHeartbeat(record.hex)) {
        parsed.packets.add(
          PacketRecord(
            number: parsed.packets.length + 1,
            name: '原始日志心跳包',
            code: rawProtocol(record.hex),
            serial: rawSerial(record.hex),
            serverTime: parseServerTime(
              record.serverTimeText,
              fallbackYear: serverYear,
            ),
            serverTimeText: record.serverTimeText,
            direction: record.direction,
            rawHex: record.hex,
            fusionStatus: status,
            rawHeartbeat: true,
          ),
        );
      }
      continue;
    }
    final packet = parsed.packets[match];
    packet
      ..serverTime = parseServerTime(
        record.serverTimeText,
        fallbackYear: serverYear,
      )
      ..serverTimeText = record.serverTimeText
      ..direction = record.direction
      ..rawHex = record.hex
      ..fusionStatus = status
      ..rawHeartbeat = rawIsHeartbeat(record.hex);
    used.add(match);
    fused++;
  }
  inferPacketTimes(parsed.packets);
  final officialErrors = RegExp(
    r'共有错误的数据包\s*[：:]\s*(\d+)个',
  ).firstMatch(officialSource);
  final old = parsed.diagnostics;
  return ParsedData(
    points: parsed.points,
    packets: parsed.packets,
    filtered: parsed.filtered,
    device: parsed.device,
    model: parsed.model,
    diagnostics: ParseDiagnostics(
      packetHeaders: old.packetHeaders,
      alarmLines: old.alarmLines,
      alarmMatches: old.alarmMatches,
      alarmCoordinatesDetected: old.alarmCoordinatesDetected,
      zeroCoordinatesFiltered: old.zeroCoordinatesFiltered,
      mtkRollbackFiltered: old.mtkRollbackFiltered,
      rawRecords: raw.records.length,
      fusedRecords: fused,
      ambiguousRecords: ambiguous,
      unmatchedRawRecords: unmatchedRaw,
      unmatchedOfficialPackets: originalOfficialCount - used.length,
      rawFormatIssues:
          raw.issues.length +
          raw.records.where((r) => r.issue.isNotEmpty).length,
      officialErrorPackets: officialErrors == null
          ? null
          : int.parse(officialErrors[1]!),
    ),
  );
}

Map<int, int> _forcedAlignment(
  List<RawLogRecord> raw,
  List<PacketRecord> official,
) {
  bool equal(int i, int j) =>
      raw[i].issue.isEmpty &&
      raw[i].hex.isNotEmpty &&
      raw[i].hex == official[j].rawHex &&
      (rawProtocol(raw[i].hex).isEmpty ||
          official[j].code.isEmpty ||
          rawProtocol(raw[i].hex) == official[j].code) &&
      (rawSerial(raw[i].hex).isEmpty ||
          official[j].serial.isEmpty ||
          rawSerial(raw[i].hex) == official[j].serial);
  final result = <int, int>{};
  if (raw.length == official.length &&
      List.generate(raw.length, (i) => i).every((i) => equal(i, i))) {
    for (var i = 0; i < raw.length; i++) {
      result[i] = i;
    }
    return result;
  }
  final cells = (raw.length + 1) * (official.length + 1);
  if (cells > 4000000) return result;
  final width = official.length + 1;
  final pre = Uint32List(cells), post = Uint32List(cells);
  for (var i = 0; i < raw.length; i++) {
    for (var j = 0; j < official.length; j++) {
      pre[(i + 1) * width + j + 1] = equal(i, j)
          ? pre[i * width + j] + 1
          : _max(pre[i * width + j + 1], pre[(i + 1) * width + j]);
    }
  }
  for (var i = raw.length - 1; i >= 0; i--) {
    for (var j = official.length - 1; j >= 0; j--) {
      post[i * width + j] = equal(i, j)
          ? post[(i + 1) * width + j + 1] + 1
          : _max(post[(i + 1) * width + j], post[i * width + j + 1]);
    }
  }
  final length = pre[raw.length * width + official.length];
  for (var j = 0; j < official.length; j++) {
    var candidate = -1, count = 0, canSkip = false;
    for (var i = 0; i <= raw.length; i++) {
      if (pre[i * width + j] + post[i * width + j + 1] == length) {
        canSkip = true;
      }
      if (i < raw.length &&
          equal(i, j) &&
          pre[i * width + j] + 1 + post[(i + 1) * width + j + 1] == length) {
        candidate = i;
        count++;
      }
    }
    if (count == 1 && !canSkip) {
      result[candidate] = j;
    }
  }
  return result;
}

int _max(int a, int b) => a > b ? a : b;
