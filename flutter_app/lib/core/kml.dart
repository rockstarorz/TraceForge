import 'dart:math' as math;

import 'models.dart';
import 'parser.dart';
import 'kml_text.dart';

class KmlResult {
  const KmlResult(this.text, this.driftCount);
  final String text;
  final int driftCount;
}

String xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String cdata(String value) =>
    '<![CDATA[${value.replaceAll(']]>', ']]]]><![CDATA[>')}]]>';
String utcTime(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first}Z';
double distance(GpsPoint a, GpsPoint b) {
  double rad(double n) => n * math.pi / 180;
  final p =
      math.pow(math.sin(rad(b.latitude - a.latitude) / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(rad(b.longitude - a.longitude) / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(p.clamp(0, 1)));
}

bool isDrift(GpsPoint a, GpsPoint b, ParseOptions options) =>
    b.time.difference(a.time).inMilliseconds / 1000 > options.driftSeconds &&
    distance(a, b) > options.driftMeters;

String alarmText(String raw, String code, bool chinese) {
  if (chinese || raw.isEmpty) return raw;
  return alarmNames[raw] ??
      (RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)
          ? (code.isNotEmpty ? 'Alarm ($code)' : 'Unknown Alarm')
          : raw);
}

String pointStyle(GpsPoint p) {
  if (p.alarm.isNotEmpty) return 'style_alarm';
  if (p.reupload) return p.acc ? 'style_upload_on' : 'style_upload_off';
  if (!p.acc) return 'style_acc_off';
  if (p.speed == 0) return 'style_acc_on_stop';
  return p.speed > 50 ? 'style_speed_high' : 'style_speed_low';
}

KmlResult generateKml(
  ParsedData data,
  ParseOptions options, {
  Progress? onProgress,
}) {
  if (data.points.isEmpty) {
    throw const FormatException('没有可导出的定位点 / No location points to export');
  }
  if (!options.driftMeters.isFinite ||
      !options.driftSeconds.isFinite ||
      options.driftMeters <= 0 ||
      options.driftSeconds <= 0) {
    throw const FormatException(
      '漂移距离和时长必须大于 0 / Distance and duration must be greater than 0',
    );
  }
  final points = data.points;
  final t = kmlText[options.chinese ? 'zh' : 'en']!;
  String label(String key) => t[key]!;
  String coord(GpsPoint p) =>
      '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)},${p.altitude}';
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2"><Document>',
  );
  final identity = <String>[
    if (data.model?.trim().isNotEmpty == true) data.model!.trim(),
    if (data.device?.trim().isNotEmpty == true) 'IMEI ${data.device!.trim()}',
  ].join(' - ');
  out.write(
    '<name>${xml('GPS Track${identity.isEmpty ? '' : ' - $identity'}')}</name>',
  );
  const iconRoot = 'https://maps.google.com/mapfiles/kml/shapes/';
  void icon(String id, String color, double scale, bool arrow, {String? href}) {
    out.write(
      '<Style id="$id"><IconStyle><color>$color</color><scale>$scale</scale><Icon><href>${href ?? '$iconRoot${arrow ? 'arrow.png' : 'placemark_circle.png'}'}</href></Icon></IconStyle><LabelStyle><scale>0.5</scale></LabelStyle></Style>',
    );
  }

  icon('style_acc_off', 'ff0000ff', 1.1, false);
  icon('style_acc_on_stop', 'ff00ffff', .55, false);
  icon(
    'style_alarm',
    'ffffffff',
    1.0,
    false,
    href: 'http://maps.google.com/mapfiles/kml/shapes/flag.png',
  );
  icon('style_speed_low', 'ff00ff00', .7, true);
  icon('style_speed_high', 'ff0080ff', .7, true);
  icon('style_upload_off', 'ffff00ff', 1.1, false);
  icon('style_upload_on', 'ffff00ff', .7, true);
  for (final entry in {
    'red': 'ff0000ff',
    'green': 'ff00ff00',
    'orange': 'ff0080ff',
    'drift': 'ff0000ff',
  }.entries) {
    out.write(
      '<Style id="style_track_${entry.key}"><LineStyle><color>${entry.value}</color><width>${entry.key == 'drift' ? 6 : 3.5}</width></LineStyle></Style>',
    );
  }
  final maxSpeed = points.fold<double>(0, (v, p) => math.max(v, p.speed));
  final report = StringBuffer(
    '<h2>${label('reportTitle')}</h2><p>${label('points')}: ${points.length}</p><p>${label('timeRange')}: ${localTime(points.first.time)} — ${localTime(points.last.time)} GMT+8</p><p>${label('maximumSpeed')}: $maxSpeed km/h</p><h3>${label('legend')}</h3>',
  );
  for (final key in [
    'accOffLegend',
    'accStopLegend',
    'alarmLegend',
    'lowSpeedLegend',
    'highSpeedLegend',
    'uploadOffLegend',
    'uploadOnLegend',
    'trackOffLegend',
    'trackLowLegend',
    'trackHighLegend',
  ]) {
    report.write('<p>${xml(label(key))}</p>');
  }
  report.write(
    '<p>${label('drift')}: &gt;${options.driftMeters / 1000} km &amp; &gt;${options.driftSeconds / 60} min</p>',
  );
  out.write(
    '<description>${cdata(report.toString())}</description><Folder><name>${label('trackFolder')}</name>',
  );
  var driftCount = 0;
  final driftPoints = <int>{};
  for (var i = 0; i < points.length - 1; i++) {
    if (i % 128 == 0) {
      onProgress?.call(
        .45 * i / points.length,
        '正在生成轨迹线段 / Building track segments',
      );
    }
    final a = points[i], b = points[i + 1];
    final drift = isDrift(a, b, options);
    if (drift) {
      driftCount++;
      driftPoints.add(i + 1);
    }
    final segmentSpeed = math.max(a.speed, b.speed);
    // Keep the source tool's segment style: starting ACC plus the segment's peak speed.
    final style = drift
        ? 'drift'
        : !a.acc
        ? 'red'
        : segmentSpeed > 50
        ? 'orange'
        : 'green';
    final end = b.time.isAfter(a.time)
        ? b.time
        : a.time.add(const Duration(seconds: 1));
    final name =
        '${label('segment')} ${i + 1}${drift ? ' [${label('drift')} ${(distance(a, b) / 1000).toStringAsFixed(2)}km/${b.time.difference(a.time).inMinutes}min]' : ''}';
    out.write(
      '<Placemark><name>${xml(name)}</name><styleUrl>#style_track_$style</styleUrl><TimeSpan><begin>${utcTime(a.time)}</begin><end>${utcTime(end)}</end></TimeSpan><LineString><tessellate>1</tessellate><coordinates>${coord(a)} ${coord(b)}</coordinates></LineString></Placemark>',
    );
  }
  out.write('</Folder>');
  final normal = StringBuffer(), alarms = StringBuffer();
  const compassEn = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
  ];
  const compassZh = [
    '北',
    '北东北',
    '东北',
    '东东北',
    '东',
    '东东南',
    '东南',
    '南东南',
    '南',
    '南西南',
    '西南',
    '西西南',
    '西',
    '西西北',
    '西北',
    '北西北',
  ];
  for (var i = 0; i < points.length; i++) {
    if (i % 128 == 0) {
      onProgress?.call(
        .45 + .55 * i / points.length,
        '正在生成定位点 / Building location points',
      );
    }
    final p = points[i], style = pointStyle(points[i]);
    final alarm = alarmText(p.alarm, p.alarmCode, options.chinese);
    final acc = p.acc ? 'ON' : 'OFF';
    final heading =
        '${p.heading}° ${(options.chinese ? compassZh : compassEn)[((p.heading + 11.25) % 360 / 22.5).floor()]}';
    final name =
        '${alarm.isEmpty ? '' : '[${label('alarmTag')}:$alarm] '}#${i + 1} ${localTime(p.time)} | ${p.speed}km/h | ACC:$acc${p.reupload ? ' [${label('reupload')}]' : ''}${driftPoints.contains(i) ? ' [${label('drift')}]' : ''}';
    final events = p.events
        .map((e) {
          if (options.chinese) return e;
          final prefix = e.startsWith('报警:')
              ? 'Alarm: '
              : e.startsWith('视频:')
              ? 'Video Alarm: '
              : 'Event: ';
          return '$prefix${alarmText(e.replaceFirst(RegExp(r'^(报警:|视频:)'), ''), '', false)}';
        })
        .join(options.chinese ? '、' : ', ');
    final rows = <String, String>{
      label('localTime'): '${localTime(p.time)} GMT+8',
      label('utcTime'): utcTime(p.time),
      label('latitude'): '${p.latitude}°',
      label('longitude'): '${p.longitude}°',
      label('altitude'): '${p.altitude} m',
      label('speed'): '${p.speed} km/h',
      label('heading'): heading,
      'ACC': acc,
      label('satellites'): '${p.satellites}',
      label('gpsFix'): label(p.positioned ? 'yes' : 'noCached'),
      label('statusByte'): '0x0',
      label('reupload'): label(p.reupload ? 'yes' : 'no'),
      if (alarm.isNotEmpty) label('alarmType'): alarm,
      if (events.isNotEmpty) label('event'): events,
    };
    final description = options.detailed
        ? '<h3>${label('point')} #${i + 1}</h3><table border="1" cellpadding="4">${rows.entries.map((e) => '<tr><td>${xml(e.key)}</td><td>${xml(e.value)}</td></tr>').join()}</table>${driftPoints.contains(i) ? '<p>${label('driftWarning')}</p>' : ''}'
        : xml(
            '#${i + 1} ${localTime(p.time)} GMT+8 | ${p.speed}km/h | Lat ${p.latitude}° | Lon ${p.longitude}° | ${label('heading')} $heading | ACC $acc${p.reupload ? ' | ${label('reupload')}' : ''}${alarm.isEmpty ? '' : ' | $alarm'}${events.isEmpty ? '' : ' | $events'}',
          );
    final target = p.alarm.isEmpty ? normal : alarms;
    target.write(
      '<Placemark><name>${xml(name)}</name><styleUrl>#$style</styleUrl><description>${cdata(description)}</description>',
    );
    if ([
      'style_speed_low',
      'style_speed_high',
      'style_upload_on',
    ].contains(style)) {
      target.write(
        '<Style><IconStyle><heading>${(p.heading + 180) % 360}</heading></IconStyle></Style>',
      );
    }
    target.write(
      '<TimeStamp><when>${utcTime(p.time)}</when></TimeStamp><Point><coordinates>${coord(p)}</coordinates></Point></Placemark>',
    );
  }
  out.write(
    '<Folder><name>${label('pointFolder')}</name>$normal</Folder><Folder><name>${label('alarmFolder')}</name>$alarms</Folder></Document></kml>',
  );
  onProgress?.call(1, 'KML 已生成 / KML complete');
  return KmlResult(out.toString(), driftCount);
}
