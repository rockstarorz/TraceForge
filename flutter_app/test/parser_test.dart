import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_track_desktop/core/kml.dart';
import 'package:gps_track_desktop/core/models.dart';
import 'package:gps_track_desktop/core/parser.dart';
import 'package:gps_track_desktop/core/worker.dart';

const sample = '''
<===============总共 2 条包,这是第 1 条包=============== >
包类型: 定位数据包(22)
IMEI号: 860000000000001(0860000000000001)
机种: VL110C
时间=26/8/13 18:16:10(1A080D12100A)
纬度=N 32.305837°(03774E6A),经度=E 75.035083°(080CE66E),速度: 0KM/H(00)
定位状态:已定位, 航向:17°(1411)
ACC低(00),实时上传(00)
参与定位的卫星数为8颗
信息序列号: 0001(0001)
校验信息: 5B90(5B90)
<===============总共 2 条包,这是第 2 条包=============== >
包类型: 报警包(26)
时间=26/8/13 19:00:10(1A080D13000A)
纬度=N 33.805837°(03774E6A),经度=E 76.535083°(080CE66E),速度: 60.5KM/H(00)
定位状态:已定位, 航向:91°(1411)
ACC高(01),数据补传(01)
告警类型:震动报警(01)
信息序列号: 0002(0002)
校验信息: 5B90(5B90)
''';

const commandSample = '''
<================总共 2 条包,这是第 1 条包================>
包类型: 在线指令下发包(80)
指令长度: 15(0F)
指令内容: mileage,on#(6D696C656167652C6F6E23)
信息序列号: 0001(0001)
校验信息: 7D7A(7D7A)
<================总共 2 条包,这是第 2 条包================>
包类型: 在线指令下发包(80)
指令长度: 12(0C)
指令内容: SENDS,0#(53454E44532C3023)
信息序列号: 0002(0002)
校验信息: C913(C913)
''';

void main() {
  test('parses Concox 0x80 downlink command events and content', () {
    final parsed = parseText(commandSample, const ParseOptions());
    final commands = parsed.packets.where((packet) => packet.command).toList();
    expect(commands, hasLength(2));
    expect(commands.first.commandContent, 'mileage,on#');
    expect(commands.last.commandContent, 'SENDS,0#');
    expect(commands.first.details, contains('指令内容: mileage,on#'));
    expect(commands.last.serial, '0002');

    final jt = parseText(
      commandSample,
      const ParseOptions(protocol: Protocol.jt808),
    );
    expect(jt.packets.where((packet) => packet.command), isEmpty);
  });

  test('parses Concox points and emits core KML semantics', () {
    final parsed = parseText(sample, const ParseOptions());
    expect(parsed.points, hasLength(2));
    expect(parsed.device, '860000000000001');
    expect(parsed.model, 'VL110C');
    expect(parsed.points.last.reupload, isTrue);
    expect(parsed.points.last.alarm, '震动报警');
    expect(parsed.packets.where((packet) => packet.alarm), hasLength(1));
    final alarmPacket = parsed.packets.singleWhere((packet) => packet.alarm);
    expect(alarmPacket.alarmName, '震动报警');
    expect(alarmPacket.details, contains('告警类型:震动报警(01)'));
    final result = generateKml(parsed, const ParseOptions());
    expect(result.driftCount, 1);
    expect(result.text, contains('GPS Track - VL110C - IMEI 860000000000001'));
    expect(result.text, contains('75.035083'));
    expect(result.text, contains('76.535083'));
    expect(result.text, contains('[ALARM:Vibration Alarm]'));
    expect(
      result.text,
      contains('http://maps.google.com/mapfiles/kml/shapes/flag.png'),
    );
  });

  test('filters zero coordinate and escapes XML safely', () {
    final zero = sample
        .replaceAll('N 32.305837°', 'N 0°')
        .replaceAll('E 75.035083°', 'E 0°');
    final parsed = parseText(zero, const ParseOptions());
    expect(parsed.filtered, 1);
    expect(parsed.points, hasLength(1));
    final unfiltered = parseText(zero, const ParseOptions(filterZero: false));
    expect(unfiltered.filtered, 0);
    expect(unfiltered.points, hasLength(2));
    expect(xml('<&"\''), '&lt;&amp;&quot;&apos;');
    expect(cdata('a]]>b'), '<![CDATA[a]]]]><![CDATA[>b]]>');
  });

  test('filters MTK year rollback points against the newest log time', () {
    final rollback = sample.replaceFirst('26/8/13 18:16:10', '6/8/13 18:16:10');

    final retained = parseText(rollback, const ParseOptions());
    expect(retained.points, hasLength(2));
    expect(localTime(retained.points.first.time), startsWith('2006-'));

    final filtered = parseText(
      rollback,
      ParseOptions(
        filterMtkRollback: true,
        mtkReferenceTime: DateTime.utc(2026, 8, 13, 19),
      ),
    );
    expect(filtered.points, hasLength(1));
    expect(localTime(filtered.points.single.time), startsWith('2026-'));
    expect(filtered.filtered, 1);
    expect(filtered.diagnostics.mtkRollbackFiltered, 1);
    expect(filtered.packets.first.time, isNull);
    expect(filtered.packets.first.inferred, isTrue);
    expect(
      localTime(filtered.packets.first.timelineTime!),
      startsWith('2026-'),
    );
    final allRolledBack = sample.replaceAll('26/8/13', '6/8/13');
    final allFiltered = parseText(
      allRolledBack,
      ParseOptions(
        filterMtkRollback: true,
        mtkReferenceTime: DateTime.utc(2026, 8, 13, 19),
      ),
    );
    expect(allFiltered.points, isEmpty);
    expect(allFiltered.diagnostics.mtkRollbackFiltered, 2);
    expect(
      allFiltered.packets.every((packet) => packet.timelineTime == null),
      isTrue,
    );
  });

  test('parses ACC status fields without parenthesized codes', () {
    const source = '''
<=======这是第 1 条包======= >
包类型: 定位包(38)
时间=26/8/6 10:38:30
纬度=N 25.309713°,经度=E 55.637760°,速度: 0KM/H
ACC状态:ACC低, ACC状态:有效, 定位状态:已定位, 航向:132°
<=======这是第 2 条包======= >
包类型: 定位包(38)
时间=26/8/6 10:39:30
纬度=N 25.309813°,经度=E 55.637860°,速度: 12KM/H
ACC状态:ACC高, ACC状态:有效, 定位状态:已定位, 航向:133°
''';
    final parsed = parseText(source, const ParseOptions());
    expect(parsed.points.map((point) => point.acc), [isFalse, isTrue]);
  });
  test('infers heartbeat time from matching serial', () {
    final heartbeat = PacketRecord(name: '心跳数据包', code: '13', serial: '0001');
    final location = PacketRecord(
      serial: '0001',
      time: DateTime.utc(2026, 8, 13),
    );
    inferPacketTimes([heartbeat, location]);
    expect(heartbeat.heartbeat, isTrue);
    expect(heartbeat.inferred, isTrue);
    expect(heartbeat.timelineTime, location.time);
  });

  test('parses JT808 batch point fields and storage alarm', () {
    const jt = '''
<=======这是第 1 条包=======>
包类型: 位置批量上传(0704)
终端手机号: 013800138000
封包第1个
时间:26/8/13 18:16:10
纬度=N 32.305837°,经度=E 75.035083°,速度: 18.9KM/H
方向角:181°
海拔高度:35m
卫星数: 9
ACC开(1)
视频相关报警:存储单元故障报警,
校验位: 7E
''';
    final parsed = parseText(jt, const ParseOptions(protocol: Protocol.jt808));
    expect(parsed.points, hasLength(1));
    expect(parsed.points.single.speed, 18.9);
    expect(parsed.points.single.altitude, 35);
    expect(parsed.points.single.acc, isTrue);
    expect(parsed.points.single.alarm, '存储单元故障报警');
  });

  test('background worker exports located alarm-only input to KML', () async {
    const alarmOnly = '''
<=======总共 1 条包,这是第 1 条包======= >
包类型: 报警包(39)
时间:26/8/6 8:7:43
纬度:N 25.309684°,经度:E 55.637924°,速度: 4KM/H
ACC状态:ACC高, ACC状态:有效, 定位状态:已定位, 航向:141°
告警类型:ACC开报警 (0FE),[请注意上述告警类型!],不需要平台回复(0)
信息序列号: 0026(0026)
校验信息: EC9D(EC9D)
''';
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      generateInBackground,
      WorkerRequest(port.sendPort, alarmOnly, const ParseOptions()),
    );
    try {
      await for (final raw in port) {
        final event = raw as List<Object?>;
        if (event[0] == 1) {
          final parsed = event[1] as ParsedData;
          final kml = event[2] as KmlResult;
          expect(parsed.points, hasLength(1));
          expect(parsed.packets.where((packet) => packet.alarm), hasLength(1));
          expect(kml.text, contains('[ALARM:ACC On Alarm]'));
          break;
        }
        if (event[0] == 2) fail(event[1] as String);
      }
    } finally {
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  });
  test('background worker accepts command-only Concox input', () async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      generateInBackground,
      WorkerRequest(port.sendPort, commandSample, const ParseOptions()),
    );
    try {
      await for (final raw in port) {
        final event = raw as List<Object?>;
        if (event[0] == 1) {
          final parsed = event[1] as ParsedData;
          final kml = event[2] as KmlResult;
          expect(
            parsed.packets.where((packet) => packet.command),
            hasLength(2),
          );
          expect(kml.text, isEmpty);
          break;
        }
        if (event[0] == 2) fail(event[1] as String);
      }
    } finally {
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  });

  test('background worker reports real progress and returns result', () async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      generateInBackground,
      WorkerRequest(port.sendPort, sample, const ParseOptions()),
    );
    final progress = <double>[];
    try {
      await for (final raw in port) {
        final event = raw as List<Object?>;
        if (event[0] == 0) {
          progress.add(event[1] as double);
        } else if (event[0] == 1) {
          expect(event[1], isA<ParsedData>());
          expect((event[2] as KmlResult).driftCount, 1);
          break;
        } else {
          fail(event[1] as String);
        }
      }
    } finally {
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
    expect(progress, isNotEmpty);
    expect(progress.first, 0);
    expect(progress.last, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('device wall-clock time is converted from GMT+8 exactly once', () {
    final parsed = parseText(sample, const ParseOptions());
    expect(localTime(parsed.points.first.time), '2026-08-13 18:16:10');
    expect(utcTime(parsed.points.first.time), '2026-08-13T10:16:10Z');
  });

  test('inferred packet remembers whether it follows its time anchor', () {
    final anchor = PacketRecord(number: 1, time: DateTime.utc(2026, 8, 13, 10));
    final later = PacketRecord(number: 2, name: '心跳包', code: '13');
    inferPacketTimes([anchor, later]);
    expect(later.inferred, isTrue);
    expect(later.timeAnchorIndex, 0);
    expect(later.timelineTime, anchor.time);
  });
}
