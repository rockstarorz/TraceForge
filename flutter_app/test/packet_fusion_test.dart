import 'package:flutter_test/flutter_test.dart';
import 'package:gps_track_desktop/core/models.dart';
import 'package:gps_track_desktop/core/packet_fusion.dart';

const firstHex = '78780A13040603000200F0AC080D0A';
const secondHex = '78780A13040603000200F820400D0A';

String officialPacket(int number, String hex, String serial) =>
    '''
<=======这是第 $number 条包=======>
原始数据:${hex.replaceAllMapped(RegExp(r'..'), (m) => '${m[0]} ')}
包类型: 心跳数据包(13)
信息序列号: $serial($serial)
校验信息: 0000
''';

void main() {
  test('TRN parser keeps server time direction and exact HEX', () {
    final raw = parseRawLog(
      '2026-09-12 10:00:00.123 TRN -->> device (15) {$firstHex}',
    );
    expect(raw.records, hasLength(1));
    expect(raw.records.single.serverTimeText, '2026-09-12 10:00:00.123');
    expect(raw.records.single.direction, '-->>');
    expect(raw.records.single.hex, firstHex);
    expect(raw.records.single.issue, isEmpty);
  });

  test('fusion uses server timestamps for real heartbeat intervals', () {
    final raw =
        '''
2026-09-12 10:00:00.000 TRN -->> device (15) {$firstHex}
2026-09-12 10:06:00.000 TRN -->> device (15) {$secondHex}
2026-09-12 10:06:01.000 TRN <<-- device (10) {78780513000814D40D0A}
''';
    final official =
        '${officialPacket(1, firstHex, '00F0')}'
        '${officialPacket(2, secondHex, '00F8')}'
        'Parsing Time:10ms\n序列号段丢失共有:0段\n共有错误的数据包:0个';
    final data = fuseRawWithOfficial(raw, official, const ParseOptions());
    final stats = HeartbeatStats.fromPackets(
      data.packets,
      expectedInterval: const Duration(minutes: 5),
    );
    expect(data.diagnostics.fusedRecords, 2);
    expect(data.diagnostics.unmatchedRawRecords, 1);
    expect(stats.total, 3);
    expect(stats.uplink, 2);
    expect(stats.replies, 1);
    expect(stats.exactTimes, 3);
    expect(stats.averageInterval, const Duration(minutes: 6));
    expect(stats.breakpoints, 1);
    expect(data.packets.first.timeSource, PacketTimeSource.server);
    expect(localTime(data.packets.first.serverTime!), '2026-09-12 10:00:00');
  });

  test('yearless server timestamps inherit the official device year', () {
    final raw = '09-14 00:01:32 TRN -->> device (15) {$firstHex}';
    final official =
        '''
<=======这是第 1 条包=======>
原始数据:${firstHex.replaceAllMapped(RegExp(r'..'), (m) => '${m[0]} ')}
包类型: 心跳数据包(13)
时间=26/9/13 23:59:30
信息序列号: 00F0(00F0)
校验信息: 0000
Parsing Time:10ms
序列号段丢失共有:0段
''';
    final data = fuseRawWithOfficial(raw, official, const ParseOptions());
    expect(data.packets, hasLength(1));
    expect(localTime(data.packets.single.serverTime!), '2026-09-14 00:01:32');
  });

  test('timeline inference never becomes an exact heartbeat time', () {
    final heartbeat = PacketRecord(name: '心跳包', code: '13');
    final stats = HeartbeatStats.fromPackets([heartbeat]);
    expect(stats.total, 1);
    expect(stats.exactTimes, 0);
    expect(stats.unresolved, 1);
  });

  test('JT808 platform heartbeat is recognized directly from raw HEX', () {
    const hex = '7E000200000123456789010001ABCD7E';
    expect(rawProtocol(hex), '0002');
    expect(rawIsHeartbeat(hex), isTrue);
  });

  test('real relay record keeps every HEX byte including trailing 0D 0A', () {
    // 客户真实中转日志的写法：HEX 与结尾 <CR><LF> 之间有空格的 0D 0A。
    final data = parseRawLog(
      '08-26 00:00:24 TRN -->> 0860000000000001*203.0.113.10:58402 (14) '
      '{79 79 00 08 94 00 04 96 03 C5 9C A4 0D 0A }',
    );
    expect(data.records, hasLength(1));
    final record = data.records.single;
    expect(record.direction, '-->>');
    expect(record.issue, isEmpty);
    // 声明 14 字节 => 28 个 HEX 字符；漏掉 0D 0A 就会只剩 26。
    expect(record.hex.length, 28);
    expect(record.hex, '797900089400049603C59CA40D0A');
  });

  test('relay record with glued 0D0A is still read as a full packet', () {
    final data = parseRawLog(
      '08-26 00:00:24 TRN -->> 0860000000000001*203.0.113.10:58402 (14) '
      '{79 79 00 08 94 00 04 96 03 C5 9C A4 0D0A }',
    );
    expect(data.records, hasLength(1));
    expect(data.records.single.issue, isEmpty);
    expect(data.records.single.hex, '797900089400049603C59CA40D0A');
  });

  test('identical duplicate HEX keeps occurrence order when lists align', () {
    final raw =
        '''
2026-09-12 10:00:00 TRN -->> d (15) {$firstHex}
2026-09-12 10:01:00 TRN -->> d (15) {$firstHex}
''';
    final official =
        '${officialPacket(1, firstHex, '00F0')}'
        '${officialPacket(2, firstHex, '00F0')}'
        'Parsing Time:10ms\n序列号段丢失共有:0段';
    final data = fuseRawWithOfficial(raw, official, const ParseOptions());
    expect(data.diagnostics.fusedRecords, 2);
    expect(data.diagnostics.ambiguousRecords, 0);
    expect(data.packets[0].serverTimeText, '2026-09-12 10:00:00');
    expect(data.packets[1].serverTimeText, '2026-09-12 10:01:00');
  });
}
