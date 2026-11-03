#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GT06 Protocol GPS Log Parser
Parses GPS tracker logs -> generates KML for Google Maps/Earth
Extracts: coordinates, speed, direction, ACC status, altitude, timestamps
"""
import re
import math
import struct
import argparse
from pathlib import Path
from datetime import datetime, timedelta


def packet_layout(packet):
    """返回一个 GT06 数据包中几个关键字段的位置。

    GT06 有两种包头：
    - ``78 78``：长度字段占 1 字节，协议号位于下标 3；
    - ``79 79``：长度字段占 2 字节，协议号位于下标 4。

    把差异集中在这里处理，可以避免后面的解析函数误把扩展包的
    “长度低字节”当成协议号。
    """
    if len(packet) >= 4 and packet[:2] == [0x78, 0x78]:
        return {
            'protocol_index': 3,
            'data_index': 4,
            'length': packet[2],
        }
    if len(packet) >= 5 and packet[:2] == [0x79, 0x79]:
        return {
            'protocol_index': 4,
            'data_index': 5,
            'length': (packet[2] << 8) | packet[3],
        }
    return None

def parse_hex_from_braces(text):
    """Extract hex bytes from {XX XX XX ... } format"""
    match = re.search(r'\{([0-9A-Fa-f ]+)\}', text)
    if match:
        hex_str = match.group(1).strip()
        return [int(x, 16) for x in hex_str.split()]
    return None

def extract_packets(hex_bytes):
    """Split concatenated GT06 packets.
    Standard: [78 78 len protocol data... serial(2) crc(2) 0D 0A]
    Extended: [79 79 len(2) protocol data... serial(2) crc(2) 0D 0A]
    """
    packets = []
    i = 0
    n = len(hex_bytes)
    while i < n:
        if hex_bytes[i] == 0x78 and i + 1 < n and hex_bytes[i+1] == 0x78:
            if i + 2 >= n:
                break
            length = hex_bytes[i+2]
            total_packet_len = 2 + 1 + length + 2
            if total_packet_len > n - i:
                break
            packet = hex_bytes[i:i+total_packet_len]
            if len(packet) >= 2 and packet[-2] == 0x0D and packet[-1] == 0x0A:
                packets.append(packet)
                i += total_packet_len
            else:
                i += 1
        elif hex_bytes[i] == 0x79 and i + 1 < n and hex_bytes[i+1] == 0x79:
            if i + 3 >= n:
                break
            length = (hex_bytes[i+2] << 8) | hex_bytes[i+3]
            total_packet_len = 2 + 2 + length + 2
            if total_packet_len > n - i:
                break
            packet = hex_bytes[i:i+total_packet_len]
            if len(packet) >= 2 and packet[-2] == 0x0D and packet[-1] == 0x0A:
                packets.append(packet)
                i += total_packet_len
            else:
                i += 1
        else:
            i += 1
    return packets

def parse_gps_packet(packet):
    """Parse 0x22 GPS Location Data packet"""
    layout = packet_layout(packet)
    if not layout:
        return None
    protocol = packet[layout['protocol_index']]
    if protocol != 0x22:
        return None
    length = layout['length']
    data_len = length - 5  # proto(1) + serial(2) + crc(2)
    if data_len < 20:
        return None
    data_index = layout['data_index']
    raw_data = packet[data_index:data_index+data_len]
    if len(raw_data) < 20:
        return None

    year = 2000 + raw_data[0]
    month = raw_data[1]
    day = raw_data[2]
    hour = raw_data[3]
    minute = raw_data[4]
    second = raw_data[5]
    dt = datetime(year, month, day, hour, minute, second)
    dt_local = dt + timedelta(hours=8)

    sat_byte = raw_data[6]
    lat_raw = struct.unpack('>I', bytes(raw_data[7:11]))[0]
    lon_raw = struct.unpack('>I', bytes(raw_data[11:15]))[0]
    latitude = lat_raw / 1800000.0
    longitude = lon_raw / 1800000.0
    speed = raw_data[15]

    dir_status = (raw_data[16] << 8) | raw_data[17]
    direction = dir_status & 0x03FF
    bit13 = (dir_status >> 13) & 1
    bit12 = (dir_status >> 12) & 1
    bit11 = (dir_status >> 11) & 1
    if bit12 == 0:
        longitude = -longitude
    if bit11 == 1:
        latitude = -latitude

    altitude = (raw_data[18] << 8) | raw_data[19]

    acc = None
    gps_status = None
    if len(raw_data) > 26:
        acc = raw_data[26]
    if len(raw_data) > 27:
        gps_status = raw_data[27]

    sat_count = sat_byte & 0x0F

    return {
        'time_utc': dt,
        'time_local': dt_local,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'direction': direction,
        'altitude': altitude,
        'acc': acc,
        'gps_status': gps_status,
        'sat_count': sat_count,
        'sat_byte': sat_byte,
        'gps_positioned': bit13,
    }

def parse_status_packet(packet):
    """Parse 0x13 Status/Heartbeat packet"""
    layout = packet_layout(packet)
    if not layout:
        return None
    protocol = packet[layout['protocol_index']]
    if protocol != 0x13:
        return None
    length = layout['length']
    data_len = length - 5
    data_index = layout['data_index']
    raw_data = packet[data_index:data_index+data_len]
    if len(raw_data) < 5:
        return None
    terminal_info = raw_data[0]
    voltage = raw_data[1]
    gsm = raw_data[2]
    alarm = raw_data[3]
    language = raw_data[4]
    acc = (terminal_info >> 1) & 1
    door = (terminal_info >> 6) & 1
    oil = (terminal_info >> 5) & 1
    return {
        'terminal_info': terminal_info,
        'voltage': voltage,
        'gsm': gsm,
        'alarm': alarm,
        'language': language,
        'acc': acc,
        'door': door,
        'oil': oil,
    }

def dir_to_text(deg):
    """Convert degrees to compass text"""
    compass = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW']
    idx = int(((deg + 11.25) % 360) / 22.5)
    return compass[idx]


# 第三方解析文本通常输出中文报警名称。KML 默认是英文输出，因此需要在
# 一个集中位置完成翻译，避免各个标签分别处理后出现中英文混杂。
ALARM_NAME_EN = {
    '震动报警': 'Vibration Alarm',
    'SOS报警': 'SOS Alarm',
    '断电报警': 'Power Disconnect Alarm',
    '低电报警': 'Low Battery Alarm',
    '超速报警': 'Overspeed Alarm',
    '位移报警': 'Movement Alarm',
    '进围栏报警': 'Geofence Entry Alarm',
    '出围栏报警': 'Geofence Exit Alarm',
    '非法点火报警': 'Unauthorized Ignition Alarm',
    '碰撞报警': 'Collision Alarm',
    '拆除报警': 'Tamper Alarm',
    '光感报警': 'Light Sensor Alarm',
}


def alarm_to_english(alarm, alarm_code=''):
    """Translate an alarm name for an English KML without leaking Chinese.

    Known names use a precise translation. For an unknown Chinese name, the
    protocol alarm code is safer than guessing its meaning. Already-English
    device text is kept unchanged.
    """
    alarm = str(alarm or '').strip()
    alarm_code = str(alarm_code or '').strip()
    if not alarm:
        return ''
    if alarm in ALARM_NAME_EN:
        return ALARM_NAME_EN[alarm]
    if re.search(r'[\u4e00-\u9fff]', alarm):
        return f'Alarm ({alarm_code})' if alarm_code else 'Unknown Alarm'
    return alarm

def parse_log_file(filepath):
    """Parse the entire log file.
    A physical line may contain MULTIPLE timestamped TRN events (both
    device->server and server->device). Split by timestamp first, then
    handle each event independently.
    """
    gps_points = []
    status_points = []
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Split into segments, each starting with a timestamp
            segments = re.split(r'(?=\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
            for seg in segments:
                seg = seg.strip()
                if not seg:
                    continue
                parsed = {}
                time_match = re.match(r'(\d{2}-\d{2} \d{2}:\d{2}:\d{2})', seg)
                if time_match:
                    parsed['log_time'] = time_match.group(1)
                if 'TRN -->>' in seg:
                    parsed['direction'] = 'device_to_server'
                elif 'TRN <<--' in seg:
                    parsed['direction'] = 'server_to_device'
                else:
                    parsed['direction'] = None
                hex_bytes = parse_hex_from_braces(seg)
                if not hex_bytes:
                    continue
                # Compact format segments (timestamp + hex, no TRN marker) are device data
                if parsed.get('direction') is None and not re.match(r'\d{2}-\d{2} \d{2}:\d{2}:\d{2} MSG', seg):
                    parsed['direction'] = 'device_to_server'
                if parsed.get('direction') != 'device_to_server':
                    continue
                packets = extract_packets(hex_bytes)
                for pkt in packets:
                    layout = packet_layout(pkt)
                    if not layout:
                        continue
                    protocol = pkt[layout['protocol_index']]
                    if protocol == 0x22:
                        gps = parse_gps_packet(pkt)
                        if gps:
                            gps['log_time'] = parsed.get('log_time', '')
                            gps_points.append(gps)
                    elif protocol == 0x13:
                        status = parse_status_packet(pkt)
                        if status:
                            status['log_time'] = parsed.get('log_time', '')
                            status_points.append(status)
    return gps_points, status_points

def haversine(lat1, lon1, lat2, lon2):
    """Great-circle distance between two coordinates in meters."""
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))

def generate_kml(gps_points, status_points, output_path, detailed=True,
                 device_imei='Unknown'):
    """Generate KML file with track, placemarks, speed vectors, ACC status"""

    # 这个函数需要至少一个定位点。提前给出明确错误，比稍后出现
    # “列表下标越界”更方便初学者定位输入数据的问题。
    if not gps_points:
        raise ValueError('无法生成 KML：没有 GPS 定位点')

    # 时间回放要求轨迹按时间排列。sorted 会生成新列表，不改变调用者
    # 原来的数据顺序，便于在调试时比较解析前后的结果。
    gps_points = sorted(gps_points, key=lambda point: point['time_utc'])

    # IMEI 会写入 XML 文本，所以先转成字符串并转义 XML 特殊字符。
    device_imei = str(device_imei or 'Unknown')
    device_imei_xml = (device_imei.replace('&', '&amp;')
                       .replace('<', '&lt;')
                       .replace('>', '&gt;'))

    styles = """<Style id="style_acc_off">
<IconStyle><color>ff0000ff</color><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>
<Style id="style_acc_on_stop">
<IconStyle><color>ff00ffff</color><scale>0.55</scale><Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>
<Style id="style_alarm">
<IconStyle><color>ffffffff</color><scale>1.0</scale><Icon><href>http://maps.google.com/mapfiles/kml/shapes/flag.png</href></Icon></IconStyle>
<LabelStyle><scale>0.9</scale></LabelStyle>
</Style>
<Style id="style_speed_low">
<IconStyle><color>ff00ff00</color><scale>0.7</scale><heading>0</heading><Icon><href>http://maps.google.com/mapfiles/kml/shapes/arrow.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>
<Style id="style_speed_high">
<IconStyle><color>ff0080ff</color><scale>0.7</scale><heading>0</heading><Icon><href>http://maps.google.com/mapfiles/kml/shapes/arrow.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>
<Style id="style_track_green">
<LineStyle><color>ff00ff00</color><width>3.5</width></LineStyle>
</Style>
<Style id="style_track_red">
<LineStyle><color>ff0000ff</color><width>3.5</width></LineStyle>
</Style>
<Style id="style_track_orange">
<LineStyle><color>ff0080ff</color><width>3.5</width></LineStyle>
</Style>
<Style id="style_track_drift">
<LineStyle><color>ff0000ff</color><width>6</width></LineStyle>
</Style>
<Style id="style_upload_off">
<IconStyle><color>ffff00ff</color><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>
<Style id="style_upload_on">
<IconStyle><color>ffff00ff</color><scale>0.7</scale><heading>0</heading><Icon><href>http://maps.google.com/mapfiles/kml/shapes/arrow.png</href></Icon></IconStyle>
<LabelStyle><scale>0.5</scale></LabelStyle>
</Style>"""

    lines = []
    lines.append('<?xml version="1.0" encoding="UTF-8"?>')
    lines.append('<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">')
    lines.append('<Document>')
    lines.append(f'<name>GT06 GPS Track - IMEI {device_imei_xml}</name>')

    t0 = gps_points[0]['time_local'].strftime('%Y-%m-%d %H:%M:%S')
    t1 = gps_points[-1]['time_local'].strftime('%Y-%m-%d %H:%M:%S')
    desc = ('<![CDATA[<h2>GPS Track Analysis Report</h2>'
            f'<p>IMEI: <b>{device_imei_xml}</b></p>'
            f'<p>GPS Points: <b>{len(gps_points)}</b></p>'
            f'<p>Status Reports: <b>{len(status_points)}</b></p>'
            f'<p>Time Range: {t0} ~ {t1} (GMT+8)</p>'
            f'<p>Maximum Speed: <b>{max(p["speed"] for p in gps_points)} km/h</b></p>'
            '<hr><h3>Legend</h3>'
            '<p><span style="color:red">●</span> ACC OFF (red dot)</p>'
            '<p><span style="color:yellow">●</span> ACC ON / stopped (yellow dot)</p>'
            '<p><span style="color:darkblue">●</span> Active alarm (dark-blue large dot, highest priority)</p>'
            '<p><span style="color:green">▲</span> ACC ON / moving ≤50 km/h (green arrow)</p>'
            '<p><span style="color:orange">▲</span> ACC ON / moving &gt;50 km/h (orange arrow)</p>'
            '<p><span style="color:purple">●</span> Re-upload / ACC OFF (purple dot)</p>'
            '<p><span style="color:purple">▲</span> Re-upload / ACC ON (purple arrow)</p>'
            '<p><span style="color:red">━</span> Track / ACC OFF</p>'
            '<p><span style="color:green">━</span> Track / ACC ON, ≤50 km/h</p>'
            '<p><span style="color:orange">━</span> Track / ACC ON, &gt;50 km/h</p>'
            '<p><span style="color:red;font-weight:bold">━</span> Drift segment (&gt;1.5 km and &gt;30 min)</p>'
            ']]>')
    lines.append(f'<description>{desc}</description>')
    lines.append(styles)

    # Folder: Track segments
    lines.append('<Folder><name>Track Path</name>')
    for i in range(len(gps_points) - 1):
        pt1 = gps_points[i]
        pt2 = gps_points[i+1]
        speed = max(pt1['speed'], pt2['speed'])
        acc = pt1.get('acc', 0)
        dist = haversine(pt1['latitude'], pt1['longitude'], pt2['latitude'], pt2['longitude'])
        gap = (pt2['time_utc'] - pt1['time_utc']).total_seconds()
        drift = (dist > 1500 and gap > 1800)  # >1.5 km and >30 min gap
        if drift:
            style_id = 'style_track_drift'
        elif acc == 0:
            style_id = 'style_track_red'
        elif speed > 50:
            style_id = 'style_track_orange'
        else:
            style_id = 'style_track_green'
        lines.append('<Placemark>')
        name = f'Segment {i+1}'
        if drift:
            name += f' [Drift {dist/1000:.2f}km/{gap/60:.0f}min]'
        lines.append(f'<name>{name}</name>')
        lines.append(f'<styleUrl>#{style_id}</styleUrl>')

        # TimeSpan 给“这一小段线”增加有效时间范围。
        # begin 是第一个点的 UTC 时间，end 是第二个点的 UTC 时间。
        # Google Earth 回放到这个区间时才显示该段；如果没有 TimeSpan，
        # Google Earth 会把它当作永久对象，所以拖动时间轴时整条轨迹都可见。
        begin_time = pt1['time_utc']
        end_time = pt2['time_utc']
        if end_time <= begin_time:
            end_time = begin_time + timedelta(seconds=1)
        begin_utc = begin_time.strftime('%Y-%m-%dT%H:%M:%SZ')
        end_utc = end_time.strftime('%Y-%m-%dT%H:%M:%SZ')
        lines.append(
            f'<TimeSpan><begin>{begin_utc}</begin><end>{end_utc}</end></TimeSpan>'
        )

        lines.append('<LineString><tessellate>1</tessellate>')
        lines.append(f'<coordinates>{pt1["longitude"]:.6f},{pt1["latitude"]:.6f},{pt1["altitude"]} {pt2["longitude"]:.6f},{pt2["latitude"]:.6f},{pt2["altitude"]}</coordinates>')
        lines.append('</LineString></Placemark>')
    lines.append('</Folder>')

    # 普通定位点与告警点分别缓存，最后写入两个独立文件夹。
    gps_point_lines = []
    alarm_point_lines = []
    for i, pt in enumerate(gps_points):
        speed = pt['speed']
        acc = pt.get('acc', 0)
        direction = pt['direction']
        drift_html = ''
        drift_tag = ''
        if i > 0:
            prev = gps_points[i-1]
            d_prev = haversine(prev['latitude'], prev['longitude'], pt['latitude'], pt['longitude'])
            g_prev = (pt['time_utc'] - prev['time_utc']).total_seconds()
            if d_prev > 1500 and g_prev > 1800:
                drift_tag = ' [Drift]'
                drift_html = (f'<p style="color:red;font-weight:bold">'
                              f'Warning: drift from previous point: {d_prev/1000:.2f} km / '
                              f'{g_prev/60:.0f} min</p>')
        reup = pt.get('reupload', 0)
        alarm_raw = str(pt.get('alarm', '') or '').strip()
        alarm = alarm_to_english(alarm_raw, pt.get('alarm_code', ''))
        alarm_safe = (alarm.replace('&', '&amp;')
                      .replace('<', '&lt;')
                      .replace('>', '&gt;'))

        # 告警优先级最高：只要不是“无告警”，就强制使用深蓝色告警点，
        # 不再考虑补传、ACC 和速度对应的颜色/箭头。
        if alarm:
            style_id = 'style_alarm'
        elif reup:
            style_id = 'style_upload_off' if acc == 0 else 'style_upload_on'
        elif acc == 0:
            style_id = 'style_acc_off'
        elif speed == 0:
            style_id = 'style_acc_on_stop'
        elif speed > 50:
            style_id = 'style_speed_high'
        else:
            style_id = 'style_speed_low'
        acc_str = 'ON' if acc else 'OFF'
        time_str = pt['time_local'].strftime('%Y-%m-%d %H:%M:%S')
        time_utc = pt['time_utc'].strftime('%H:%M:%S')
        color = 'orange' if speed > 50 else ('green' if speed > 0 else 'gray')
        if detailed:
            desc = ('<![CDATA[<div style="font-family:monospace">'
                    f'<h3>GPS Point #{i+1}</h3>'
                    '<table border="1" cellpadding="4" style="border-collapse:collapse;font-size:13px">'
                    f'<tr><td><b>Local Time</b></td><td>{time_str} GMT+8</td></tr>'
                    f'<tr><td><b>UTC Time</b></td><td>{time_utc}</td></tr>'
                    f'<tr><td><b>Latitude</b></td><td>{pt["latitude"]:.6f}°N</td></tr>'
                    f'<tr><td><b>Longitude</b></td><td>{pt["longitude"]:.6f}°E</td></tr>'
                    f'<tr><td><b>Altitude</b></td><td>{pt["altitude"]} m</td></tr>'
                    f'<tr><td><b>Speed</b></td><td><span style="color:{color}"><b>{speed} km/h</b></span></td></tr>'
                    f'<tr><td><b>Heading</b></td><td>{direction}° ({dir_to_text(direction)})</td></tr>'
                    f'<tr><td><b>ACC</b></td><td><span style="color:{"green" if acc else "red"}"><b>{acc_str}</b></span></td></tr>'
                    f'<tr><td><b>Satellites</b></td><td>{pt["sat_count"]}</td></tr>'
                    f'<tr><td><b>GPS Fix</b></td><td>{"Yes" if pt["gps_positioned"] else "No / Cached"}</td></tr>'
                    f'<tr><td><b>Status Byte</b></td><td>0x{pt.get("gps_status", 0):02X}</td></tr>'
                    f'<tr><td><b>Re-upload</b></td><td>{"Yes" if reup else "No"}</td></tr>'
                    + (f'<tr><td><b>Alarm Type</b></td><td style="color:#00008B"><b>{alarm_safe}</b></td></tr>'
                       if alarm else '') +
                    '</table>' + drift_html + '</div>]]>')
        else:
            desc = (f'<![CDATA[#{i+1} {time_str} GMT+8 | {speed}km/h | '
                f'Lat {pt["latitude"]:.6f}° | Lon {pt["longitude"]:.6f}° | '
                f'Heading {direction}° {dir_to_text(direction)} | ACC {acc_str}'
                    + (' | Re-upload' if reup else '')
                    + (f' | Alarm:{alarm_safe}' if alarm else '') + ']]>')

        # 一个定位点只进入一个文件夹，避免在 Google Earth 左侧重复。
        point_lines = []
        point_lines.append('<Placemark>')
        reup_tag = ' [Re-upload]' if reup else ''
        alarm_tag = f'[ALARM:{alarm_safe}] ' if alarm else ''
        point_lines.append(f'<name>{alarm_tag}#{i+1} {time_str} | {speed}km/h | ACC:{acc_str}{reup_tag}{drift_tag}</name>')
        point_lines.append(f'<styleUrl>#{style_id}</styleUrl>')
        point_lines.append(f'<description>{desc}</description>')
        if style_id in ('style_speed_low', 'style_speed_high', 'style_upload_on'):
            # Google arrow.png 默认朝下(南)，heading 需 +180° 补偿，使箭头指向实际航向
            arrow_heading = (direction + 180) % 360
            point_lines.append(f'<Style><IconStyle><heading>{arrow_heading}</heading></IconStyle></Style>')
        point_lines.append(f'<TimeStamp><when>{pt["time_utc"].strftime("%Y-%m-%dT%H:%M:%SZ")}</when></TimeStamp>')
        point_lines.append('<Point>')
        point_lines.append(f'<coordinates>{pt["longitude"]:.6f},{pt["latitude"]:.6f},{pt["altitude"]}</coordinates>')
        point_lines.append('</Point></Placemark>')

        if alarm:
            alarm_point_lines.extend(point_lines)
        else:
            gps_point_lines.extend(point_lines)

    lines.append('<Folder><name>GPS Points</name>')
    lines.extend(gps_point_lines)
    lines.append('</Folder>')
    lines.append('<Folder><name>Alarm Points</name>')
    lines.extend(alarm_point_lines)
    lines.append('</Folder>')

    lines.append('</Document>')
    lines.append('</kml>')

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return output_path

def main():
    # argparse 负责读取命令行参数。这样代码不再绑定某台电脑的绝对路径。
    parser = argparse.ArgumentParser(description='解析 GT06 原始日志并生成 KML')
    parser.add_argument('log_file', help='要解析的 gps_log.txt 路径')
    parser.add_argument('-o', '--output', help='输出 KML 路径（默认与日志同目录）')
    parser.add_argument('--imei', default='Unknown', help='显示在 KML 中的设备 IMEI')
    args = parser.parse_args()

    log_file = Path(args.log_file)
    output_file = Path(args.output) if args.output else log_file.with_suffix('.kml')
    gps_points, status_points = parse_log_file(log_file)
    print(f'Parsed {len(gps_points)} GPS points, {len(status_points)} status reports')
    if gps_points:
        for p in gps_points[:5]:
            print(f'  {p["time_local"]}  lat={p["latitude"]:.6f} lon={p["longitude"]:.6f} '
                  f'speed={p["speed"]} dir={p["direction"]} acc={p["acc"]} alt={p["altitude"]}')
        generate_kml(gps_points, status_points, output_file,
                     device_imei=args.imei)
        print(f'KML written to: {output_file}')
    else:
        print('No GPS points found!')

if __name__ == '__main__':
    main()
