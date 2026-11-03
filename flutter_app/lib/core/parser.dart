import 'models.dart';

typedef Progress = void Function(double value, String message);

class _Draft {
  DateTime? time;
  double? latitude, longitude;
  double speed = 0, heading = 0, altitude = 0;
  int satellites = 0;
  bool acc = false, positioned = false, reupload = false;
  String alarm = '', alarmCode = '';
  final List<String> events = [];
}

/// 把解析器输出的文本转成包摘要和定位点。
///
/// 本函数只处理业务数据，不依赖 Flutter 控件，因此可以安全放进后台 Isolate。
/// [onProgress] 以较低频率回报进度，避免大量消息反过来拖慢主界面。
ParsedData parseText(
  String source,
  ParseOptions options, {
  Progress? onProgress,
}) {
  final jt = options.protocol == Protocol.jt808;
  final lines = source.split('\n');
  final points = <GpsPoint>[];
  final packets = <PacketRecord>[];
  var filtered = 0, zeroCoordinatesFiltered = 0, mtkRollbackFiltered = 0;
  var packetHeaders = 0, alarmLines = 0, alarmMatches = 0;
  var alarmCoordinatesDetected = 0;
  String? device, model;
  _Draft? draft;
  PacketRecord? packet;
  var packetLines = <String>[];
  final regex = <String, RegExp>{};
  RegExpMatch? match(String pattern, String line) =>
      (regex[pattern] ??= RegExp(pattern)).firstMatch(line);
  // 一个数据包可能没有定位字段；只有普通包的时间、纬度、经度齐全时才生成定位点。
  // 告警包保留包级分类，同时其有效坐标会作为报警点写入 KML。
  void commitPoint() {
    final d = draft;
    if (d != null &&
        (packet?.alarm ?? false) &&
        d.time != null &&
        d.latitude != null &&
        d.longitude != null) {
      alarmCoordinatesDetected++;
    }
    if (d != null &&
        d.time != null &&
        d.latitude != null &&
        d.longitude != null) {
      if (options.filterZero &&
          d.latitude!.abs() < 1e-9 &&
          d.longitude!.abs() < 1e-9) {
        filtered++;
        zeroCoordinatesFiltered++;
      } else {
        points.add(
          GpsPoint(
            time: d.time!,
            latitude: d.latitude!,
            longitude: d.longitude!,
            speed: d.speed,
            heading: d.heading,
            altitude: d.altitude,
            acc: d.acc,
            satellites: d.satellites,
            positioned: d.positioned,
            reupload: d.reupload,
            alarm: d.alarm,
            alarmCode: d.alarmCode,
            events: List.of(d.events),
          ),
        );
      }
    }
    draft = null;
  }

  // 每遇到下一包包头或校验行，就把当前包摘要提交到时间轴数据中。
  void commitPacket() {
    if (packet != null) {
      if (packet!.alarm || packet!.command) {
        packet!.details = packetLines.join('\n');
      }
      packets.add(packet!);
    }
    packet = null;
    packetLines = <String>[];
  }

  for (var i = 0; i < lines.length; i++) {
    if (i % 1024 == 0) {
      onProgress?.call(i / lines.length, '正在解析数据包 / Parsing packets');
    }
    final line = lines[i]
        .replaceAll('\uFEFF', '')
        .replaceAll('**', '')
        .replaceAll(RegExp('&#x20;', caseSensitive: false), ' ')
        .trim();
    if (line.isEmpty) continue;
    // 新包头也是上一包的边界。先提交旧数据，再创建当前包的临时状态。
    final packetHeader = match(r'<.*第\s*(\d+)\s*条包', line);
    if (packetHeader != null) {
      commitPoint();
      commitPacket();
      draft = _Draft();
      packetHeaders++;
      packet = PacketRecord(number: int.parse(packetHeader[1]!));
      continue;
    }
    if (draft == null) continue;
    packetLines.add(line);
    if (jt && line.startsWith('封包第')) {
      commitPoint();
      draft = _Draft();
      continue;
    }
    final d = draft!;
    RegExpMatch? m;
    m = match(r'原始数据\s*[：:]\s*([^\r\n]+)', line);
    if (m != null && packet != null) {
      packet!.rawHex = m[1]!.replaceAll(RegExp(r'[\s,]'), '').toUpperCase();
    }
    m = match(r'包类型\s*[：:]\s*(.+?)\s*\(([0-9A-Fa-f]+)\)', line);
    if (m != null && packet != null) {
      packet!.name = m[1]!.trim();
      packet!.code = m[2]!.toUpperCase();
      // Concox protocol 0x80 downlink packets are command events. Replies
      // (0x21) remain ordinary packets and are not counted as sent commands.
      packet!.command =
          !jt &&
          packet!.code == '80' &&
          packet!.name.contains('\u5728\u7ebf\u6307\u4ee4\u4e0b\u53d1');
    }
    device ??=
        (match(r'IMEI号:\s*(\d+)', line) ??
        match(r'终端手机号:\s*([0-9A-Fa-f]+)', line))?[1];
    model ??= match(r'机种:\s*([^\s(]+)', line)?[1];
    m = match(r'时间\s*[=：:]\s*(\d+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+)', line);
    if (m != null) {
      var y = int.parse(m[1]!);
      if (y < 100) y += 2000;
      final parts = [for (var j = 2; j <= 6; j++) int.parse(m[j]!)];
      // Device logs already display GMT+8 wall-clock time. Validate that wall
      // time first, then normalize once to UTC for KML and internal sorting.
      final wallTime = DateTime.utc(
        y,
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
      );
      if (wallTime.year == y &&
          wallTime.month == parts[0] &&
          wallTime.day == parts[1] &&
          wallTime.hour == parts[2] &&
          wallTime.minute == parts[3] &&
          wallTime.second == parts[4]) {
        final utc = wallTime.subtract(const Duration(hours: 8));
        d.time = utc;
        packet?.time ??= utc;
      }
    }
    m = match(r'纬度\s*[=：:]\s*([NS])\s*([0-9.]+)°', line);
    if (m != null) {
      final value = double.tryParse(m[2]!);
      if (value != null && value <= 90) {
        d.latitude = value * (m[1] == 'S' ? -1 : 1);
      }
    }
    m = match(r'经度\s*[=：:]\s*([EW])\s*(-?[0-9.]+)°', line);
    if (m != null) {
      final value = double.tryParse(m[2]!);
      if (value != null && value.abs() <= 180) {
        d.longitude = value.abs() * (m[1] == 'W' ? -1 : 1);
      }
    }
    m = match(r'速度:\s*(\d+(?:\.\d+)?)KM/H', line);
    if (m != null) d.speed = double.parse(m[1]!);
    m = match(jt ? r'方向角:(\d+)°' : r'航向:(\d+)°', line);
    if (m != null) d.heading = double.parse(m[1]!) % 360;
    if (jt) {
      m = match(r'海拔高度:(-?\d+)m', line);
      if (m != null) d.altitude = double.parse(m[1]!);
    }
    m = match(r'定位状态:([^,，\s]+)', line);
    if (m != null) {
      d.positioned = m[1]!.contains('已定位') && !m[1]!.contains('未定位');
    }
    m =
        match(r'参与定位的卫星数为(\d+)颗', line) ??
        (jt ? match(r'卫星数:\s*(\d+)', line) : null);
    if (m != null) d.satellites = int.parse(m[1]!);
    // 模块定位包常写成“ACC状态:ACC高”，且不附带 (01)/(00)。
    // 先匹配明确状态字段，再兼容独立 ACC高/低、ACC开/关，避免命中告警名称。
    m =
        match(r'ACC状态\s*[：:]\s*ACC(开|关|高|低)(?:\(([0-9A-Fa-f]+)\))?', line) ??
        match(
          r'(?:^|[,，\s])ACC(开|关|高|低)(?:\(([0-9A-Fa-f]+)\))?(?=[,，\s]|$)',
          line,
        );
    if (m != null) d.acc = m[1] == '开' || m[1] == '高';
    m =
        match(r'消息流水号\s*[：:]\s*\d+\s*\(([0-9A-Fa-f]+)\)', line) ??
        match(r'信息序列号:\s*([0-9A-Fa-f]{2,4})', line);
    if (m != null && packet != null) packet!.serial = m[1]!.toUpperCase();
    if (!jt && (packet?.command ?? false)) {
      m = match(
        r'\u6307\u4ee4\u5185\u5bb9\s*[：:]\s*(.+?)\s*\(([0-9A-Fa-f]+)\)',
        line,
      );
      if (m != null && packet != null) {
        packet!.commandContent = m[1]!.trim();
      }
    }
    // 包级统计只认“告警类型”标记，不要求该包同时带有有效定位。
    if (line.contains('告警类型')) {
      alarmLines++;
      packet?.alarm = true;
    }
    m =
        match(r'告警类型\s*[：:]\s*(.+?)\s*\(([0-9A-Fa-f]+)\)\s*(?:[,，]|$)', line) ??
        match(r'告警类型\s*[：:]\s*(.+?)\s*$', line);
    if (m != null) {
      alarmMatches++;
      final alarmName = m[1]!.trim();
      final alarmCode = m.groupCount >= 2 ? m[2] ?? '' : '';
      if (packet != null) {
        packet!.alarmName = alarmName;
        packet!.alarmCode = alarmCode;
      }
      if (!alarmName.contains('无告警')) {
        d.alarm = alarmName;
        d.alarmCode = alarmCode;
      }
    }
    if (!jt) {
      m =
          match(r'数据补传\(([0-9A-Fa-f]+)\)', line) ??
          match(r'实时上传\(([0-9A-Fa-f]+)\)', line);
      if (m != null) d.reupload = int.parse(m[1]!, radix: 16) != 0;
    } else {
      void event(String prefix, String? raw) {
        if (raw == null || raw.trim().isEmpty || raw.contains('无报警')) return;
        final value = '$prefix${raw.trim()}';
        if (!d.events.contains(value)) d.events.add(value);
      }

      event('报警:', match(r'报警标志:\s*(.+?)(?:[,(]|$)', line)?[1]);
      final video = match(r'视频相关报警:\s*(.+?)(?:,|$)', line)?[1];
      event('视频:', video);
      if (video?.contains('存储单元故障报警') ?? false) {
        d.alarm = '存储单元故障报警';
        d.alarmCode = 'JT808-STORAGE';
      }
      final extra = match(r'扩展告警ID/事件ID:([^(\s]+)', line)?[1];
      if (extra != null && (extra.contains('告警') || extra.contains('报警'))) {
        event('', extra);
      }
    }
    if (line.startsWith('校验信息') || line.startsWith('校验位')) {
      commitPoint();
      commitPacket();
    }
  }
  commitPoint();
  commitPacket();

  if (options.filterMtkRollback && points.isNotEmpty) {
    // MTK 异常会把 2026 年倒转成 2006 年。以当前时间和本批数据最新时间
    // 中较晚者为基准，因此整批都倒转到旧年份时仍能过滤。
    var reference = options.mtkReferenceTime?.toUtc() ?? DateTime.now().toUtc();
    for (final item in packets) {
      final time = item.time;
      if (time != null && time.isAfter(reference)) reference = time;
    }
    final cutoffYear = reference.year - 10;
    final lastDay = DateTime.utc(cutoffYear, reference.month + 1, 0).day;
    final cutoff = DateTime.utc(
      cutoffYear,
      reference.month,
      reference.day > lastDay ? lastDay : reference.day,
      reference.hour,
      reference.minute,
      reference.second,
      reference.millisecond,
      reference.microsecond,
    );
    final before = points.length;
    points.removeWhere((point) => !point.time.isAfter(cutoff));
    mtkRollbackFiltered = before - points.length;
    filtered += mtkRollbackFiltered;

    if (mtkRollbackFiltered > 0) {
      // 同时取消异常旧时间的锚点资格，否则时间轴仍会被拉到 2006 年。
      // 包本身仍保留；存在正常锚点时，后续会从附近正常包推定时间。
      for (final item in packets) {
        final time = item.time;
        if (time != null && !time.isAfter(cutoff)) item.time = null;
      }
    }
  }

  inferPacketTimes(packets);
  // Stable ordering for equal timestamps preserves packet arrival order.
  final indexed = points.indexed.toList()
    ..sort((a, b) {
      final cmp = a.$2.time.compareTo(b.$2.time);
      return cmp == 0 ? a.$1.compareTo(b.$1) : cmp;
    });
  onProgress?.call(1, '解析完成 / Parsing complete');
  return ParsedData(
    points: indexed.map((e) => e.$2).toList(),
    packets: packets,
    filtered: filtered,
    device: device,
    model: model,
    diagnostics: ParseDiagnostics(
      packetHeaders: packetHeaders,
      alarmLines: alarmLines,
      alarmMatches: alarmMatches,
      alarmCoordinatesDetected: alarmCoordinatesDetected,
      zeroCoordinatesFiltered: zeroCoordinatesFiltered,
      mtkRollbackFiltered: mtkRollbackFiltered,
    ),
  );
}

/// 给没有自身时间的回复包、心跳包和告警包补一个时间轴位置。
/// 优先匹配相同流水号；匹配不到时使用距离最近的有时间数据包。
void inferPacketTimes(List<PacketRecord> packets) {
  final anchors = <int>[];
  final bySerial = <String, (int, DateTime)>{};
  for (var i = 0; i < packets.length; i++) {
    final packet = packets[i];
    packet.timelineTime = packet.serverTime ?? packet.deviceTime;
    packet.timeSource = packet.serverTime != null
        ? PacketTimeSource.server
        : packet.deviceTime != null
        ? PacketTimeSource.device
        : PacketTimeSource.unknown;
    packet.timeAnchorIndex = packet.timelineTime == null ? null : i;
    packet.inferred = false;
    if (packet.timelineTime != null) {
      anchors.add(i);
      if (packet.serial.isNotEmpty) {
        bySerial[packet.serial] = (i, packet.timelineTime!);
      }
    }
  }
  if (anchors.isEmpty) return;
  var next = 0;
  for (var i = 0; i < packets.length; i++) {
    final packet = packets[i];
    if (packet.timelineTime != null) continue;
    final serialAnchor = bySerial[packet.serial];
    if (serialAnchor != null) {
      packet.timelineTime = serialAnchor.$2;
      packet.timeAnchorIndex = serialAnchor.$1;
    }
    if (packet.timelineTime == null) {
      while (next < anchors.length && anchors[next] < i) {
        next++;
      }
      final before = next > 0 ? anchors[next - 1] : null;
      final after = next < anchors.length ? anchors[next] : null;
      final chosen = before == null
          ? after!
          : after == null
          ? before
          : (after - i <= i - before ? after : before);
      packet.timelineTime = packets[chosen].timelineTime;
      packet.timeAnchorIndex = chosen;
    }
    packet.inferred = true;
    packet.timeSource = PacketTimeSource.inferred;
  }
}
