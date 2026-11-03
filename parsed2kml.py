#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Convert an already-decoded GT06/4G 'parsed.txt' (A0 locate packets as text
produced by a third-party tool) into a KML track for Google Maps/Earth.

Extracts from the text fields: time, lat/lon, speed, heading, ACC, satellites.
The parsed.txt time field is device UTC -> local GMT+8 in the KML.
"""
import re
import sys
from pathlib import Path
from datetime import datetime, timedelta

# Python 会优先在当前脚本所在目录寻找模块，因此这里直接导入同一项目中的
# gps_parser.py。不要插入旧项目的绝对路径，否则修改新版代码也不会生效。
from gps_parser import generate_kml  # reuse the proven KML generator


def parse_parsed_txt(path):
    """Read the decoded log; return list of locate-point dicts."""
    points = []
    cur = None
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            # 有些数据从 Markdown/网页复制而来，会带 **加粗** 和 &#x20;
            # 空格实体。先清理显示标记，再使用与普通 parsed.txt 相同的规则。
            line = line.replace('**', '').replace('&#x20;', ' ').strip()
            if not line:
                continue
            m = re.match(r'<.*第\s*(\d+)\s*条包', line)
            if m:
                cur = {'idx': int(m.group(1))}
                continue
            if cur is None:
                continue

            # Note: several fields (lat/lon/speed) share ONE line, so every
            # regex is tried on each line (no early continue per field).
            # 普通定位包可能写“时间=”，报警包可能写“时间:”。
            m = re.match(r'时间\s*[=：:]\s*(\d+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+)', line)
            if m:
                y, mo, d, h, mi, s = map(int, m.groups())
                if y < 100:
                    y += 2000
                cur['time_utc'] = datetime(y, mo, d, h, mi, s)

            m = re.search(r'纬度\s*[=：:]\s*([NS])\s*([0-9.]+)°', line)
            if m:
                cur['latitude'] = float(m.group(2)) * (-1 if m.group(1) == 'S' else 1)

            m = re.search(r'经度\s*[=：:]\s*([EW])\s*(-?[0-9.]+)°', line)
            if m:
                v = float(m.group(2))
                cur['longitude'] = -abs(v) if m.group(1) == 'W' else abs(v)

            m = re.search(r'速度:\s*(\d+)KM/H', line)
            if m:
                cur['speed'] = int(m.group(1))

            m = re.search(r'航向:(\d+)°', line)
            if m:
                cur['direction'] = int(m.group(1))

            m = re.search(r'定位状态:([^,，\s]+)', line)
            if m:
                cur['gps_positioned'] = 1 if '已' in m.group(1) else 0

            m = re.search(r'参与定位的卫星数为(\d+)颗', line)
            if m:
                cur['sat_count'] = int(m.group(1))

            # 模块定位包会写“ACC状态:ACC高/低”，且经常没有括号代码。
            # 明确限制在状态字段或独立字段，避免误匹配“ACC关报警”等名称。
            m = (re.search(r'ACC状态\s*[：:]\s*ACC(开|关|高|低)(?:\(([0-9A-Fa-f]+)\))?', line)
                 or re.search(r'(?:^|[,，\s])ACC(开|关|高|低)(?:\(([0-9A-Fa-f]+)\))?(?=[,，\s]|$)', line))
            if m:
                cur['acc'] = 1 if m.group(1) in ('开', '高') else 0

            m = re.search(r'信息序列号:\s*([0-9A-F]{2,4})', line)
            if m:
                cur['serial'] = m.group(1)

            # 告警类型示例：“告警类型:震动报警 (003),[...]”。
            # 只保留括号前的人类可读名称；“无告警”不参与告警高亮。
            if '告警类型' in line:
                cur['is_alarm_packet'] = True
            m = re.search(
                r'告警类型\s*[：:]\s*(.+?)\s*\(([0-9A-Fa-f]+)\)\s*(?:[,，]|$)',
                line,
            )
            if m:
                alarm = m.group(1).strip()
                if alarm and '无告警' not in alarm:
                    cur['alarm'] = alarm
                    # 保存设备给出的报警代码。遇到尚未收录的中文报警时，
                    # 英文输出可显示 Alarm (code)，不会混入中文文本。
                    cur['alarm_code'] = m.group(2) or ''

            # 补传标志：解析工具对补传包输出「数据补传(01)」，实时包输出「实时上传(00)」
            m = re.search(r'数据补传\(([0-9A-Fa-f]+)\)', line)
            if m:
                cur['reupload'] = 1 if int(m.group(1), 16) != 0 else 0
            m = re.search(r'实时上传\(([0-9A-Fa-f]+)\)', line)
            if m:
                cur['reupload'] = 0 if int(m.group(1), 16) == 0 else 1

            # '校验信息' is the last field line of a packet -> finalize it
            if line.startswith('校验信息'):
                # 带有效坐标的告警包保留为 KML 报警点，由生成器放入报警文件夹。
                if not all(k in cur for k in ('time_utc', 'latitude', 'longitude')):
                    cur = None
                    continue
                cur['time_local'] = cur['time_utc'] + timedelta(hours=8)
                cur.setdefault('speed', 0)
                cur.setdefault('direction', 0)
                cur.setdefault('altitude', 0)
                cur.setdefault('acc', 0)
                cur.setdefault('sat_count', 0)
                cur.setdefault('gps_positioned', 0)
                cur.setdefault('gps_status', 0)
                cur.setdefault('reupload', 0)
                cur.setdefault('alarm', '')
                cur.setdefault('alarm_code', '')
                points.append(cur)
                cur = None
    return points


def main():
    # 保留这个文件的独立运行方式，但输入、输出都来自命令行，不再写死路径。
    if len(sys.argv) < 2:
        print('用法：python parsed2kml.py "parsed.txt 路径" [输出.kml]')
        return

    parsed_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2]) if len(sys.argv) > 2 else parsed_file.with_suffix('.kml')

    points = parse_parsed_txt(parsed_file)
    print(f'Parsed {len(points)} locate points from parsed.txt')
    if not points:
        print('No locate points found!')
        return
    points.sort(key=lambda p: p['time_utc'])
    acc_on = sum(1 for p in points if p['acc'] == 1)
    max_speed = max(p['speed'] for p in points)
    t0 = points[0]['time_local']
    t1 = points[-1]['time_local']
    print(f'Time span (GMT+8): {t0} ~ {t1}')
    print(f'ACC ON: {acc_on}, ACC OFF: {len(points)-acc_on}, max speed: {max_speed} km/h')
    for p in points[:4]:
        print(f'  {p["time_local"]}  lat={p["latitude"]:.6f} lon={p["longitude"]:.6f} '
              f'speed={p["speed"]} dir={p["direction"]} acc={p["acc"]}')
    generate_kml(points, [], output_file)
    print(f'KML written to: {output_file}')


if __name__ == '__main__':
    main()
