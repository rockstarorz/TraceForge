#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GT06 parsed.txt -> KML 一键生成（命令行 / 拖拽版）

用法：
    python kml_tool.py "D:\\path\\to\\parsed.txt"            # 生成精简版 KML
    python kml_tool.py "D:\\path\\to\\parsed.txt" --detailed # 生成详细描述版

也可以直接把 parsed.txt 拖到本脚本上，或拖到「生成KML.bat」上。
输出：与源文件同目录，文件名 = 源名.kml（例如 parsed.kml）。
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parsed2kml
from gps_parser import generate_kml

def extract_device(src):
    """从解析文本里提取 IMEI 与机型（取第一次命中）。"""
    imei = None
    model = None
    with open(src, encoding='utf-8', errors='replace') as f:
        for line in f:
            if not imei:
                m = re.search(r'IMEI号:\s*(\d+)', line)
                if m:
                    imei = m.group(1)
            if not model:
                m = re.search(r'机种:\s*([^\s(]+)', line)
                if m:
                    model = m.group(1)
            if imei and model:
                break
    return imei, model


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    detailed = '--detailed' in sys.argv

    if not args:
        print('用法：python kml_tool.py "parsed.txt 路径" [--detailed]')
        print('也可以把文件拖到本脚本，或拖到「生成KML.bat」上。')
        return

    src = args[0].strip().strip('"').strip("'")
    if not os.path.isfile(src):
        print('文件不存在：', src)
        return

    t0 = time.time()
    pts = parsed2kml.parse_parsed_txt(src)
    if not pts:
        print('未解析到定位点，请确认输入是「解析后的数据」（parsed.txt 格式）。')
        return
    pts.sort(key=lambda p: p['time_utc'])

    imei, model = extract_device(src)

    base = os.path.splitext(os.path.basename(src))[0]
    out = os.path.join(os.path.dirname(src), base + '.kml')

    # 直接把 IMEI 交给生成函数，不再生成后用字符串替换整份 KML。
    # 参数传递更明确，也不会误替换正文中碰巧相同的数字。
    generate_kml(pts, [], out, detailed=detailed, device_imei=imei)

    acc_on = sum(1 for p in pts if p['acc'])
    reup = sum(1 for p in pts if p.get('reupload'))
    print('=' * 52)
    print('生成成功：', out)
    print('  定位点      ：', len(pts))
    print('  补传点(紫)  ：', reup)
    print('  ACC ON/OFF  ：', acc_on, '/', len(pts) - acc_on)
    if imei:
        print('  IMEI        ：', imei)
    if model:
        print('  机型        ：', model)
    print('  时间范围    ：', pts[0]['time_local'], '~', pts[-1]['time_local'], '(GMT+8)')
    print('  KML 大小    ： %.2f MB' % (os.path.getsize(out) / 1024 / 1024))
    print('  耗时        ： %.2f 秒' % (time.time() - t0))
    print('=' * 52)


if __name__ == '__main__':
    main()
