import 'dart:io';
import 'package:gps_track_desktop/core/kml.dart';
import 'package:gps_track_desktop/core/models.dart';
import 'package:gps_track_desktop/core/parser.dart';

void main() {
  const source = '''
<=======这是第 1 条包=======>
包类型: 定位数据包(22)
IMEI号: 860000000000001(0860000000000001)
时间=26/8/13 18:16:10(1A080D12100A)
纬度=N 32.305837°,经度=E 75.035083°,速度: 0KM/H(00)
定位状态:已定位, 航向:17°
ACC低(00),实时上传(00)
信息序列号: 0001(0001)
校验信息: 5B90
<=======这是第 2 条包=======>
包类型: 报警包(26)
时间=26/8/13 19:00:10(1A080D13000A)
纬度=N 33.805837°,经度=E 76.535083°,速度: 60KM/H(3C)
定位状态:已定位, 航向:91°
ACC高(01),数据补传(01)
告警类型:震动报警(01)
信息序列号: 0002(0002)
校验信息: 5B90
''';
  final data = parseText(source, const ParseOptions());
  if (data.points.length != 2 ||
      data.packets.where((p) => p.alarm).length != 1) {
    throw StateError('Parser smoke test failed');
  }
  final kml = generateKml(data, const ParseOptions());
  if (kml.driftCount != 1 || !kml.text.contains('[ALARM:')) {
    throw StateError('KML smoke test failed');
  }
  stdout.writeln(
    'PASS: parsed ${data.points.length} points and generated ${kml.text.length} KML characters.',
  );
}
