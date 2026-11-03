"""ProtocolAnalysis.exe 本机 UIA 桥接；原文与结果只写入本机任务目录。"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time
import uuid

FROZEN = bool(getattr(sys, "frozen", False))
ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
APP_DIR = Path(sys.executable).resolve().parent if FROZEN else ROOT
DEFAULT_EXE = APP_DIR / "ProtocolAnalysis.exe"
TRACE_PATH: Path | None = None


def verify_runtime_dependencies() -> None:
    """发布包自检：确保 UI 自动化依赖确实被打进单文件程序。"""
    import win32api  # noqa: F401
    import win32con  # noqa: F401
    import win32gui  # noqa: F401
    from pywinauto import Application  # noqa: F401
    from pywinauto.application import process_get_modules  # noqa: F401
    from pywinauto.controls.hwndwrapper import HwndWrapper  # noqa: F401


def progress(message: str) -> None:
    if sys.stdout:
        try:
            print(f"[桥接] {message}", flush=True)
        except OSError:
            # PyInstaller --noconsole 下句柄对象可能存在但不可写；任务日志仍写文件。
            pass
    if TRACE_PATH:
        with TRACE_PATH.open("a", encoding="utf-8") as stream:
            stream.write(f"{time.strftime('%H:%M:%S')} {message}\n")


def classify_window(running: bool, exists: bool, enabled: bool, dialogs: list[str]) -> str:
    if not running or not exists:
        return "closed"
    if enabled:
        return "ready"
    return "modal" if dialogs else "disabled"


def crc_x25(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc ^ 0xFFFF


def output_counts(text: str) -> dict:
    error = re.search(r"共有错误的数据包\s*[:：]\s*(\d+)个", text)
    return {
        "output_packets": len(re.findall(r"原始数据\s*[:：]", text)),
        "official_error_packets": int(error[1]) if error else None,
    }


def output_complete(text: str) -> bool:
    """官方错误包仍是完整结果；只要求本次非空输出及官方结束统计。"""
    return bool(text.strip()) and "Parsing Time:" in text and (
        "序列号段丢失共有:" in text or "自动统计信息" in text
    )


@contextmanager
def task_lock(exe: Path):
    import msvcrt
    key = hashlib.sha256(str(exe.resolve()).casefold().encode()).hexdigest()[:24]
    path = Path(tempfile.gettempdir()) / f"official-bridge-{key}.lock"
    with path.open("a+b") as stream:
        if stream.seek(0, 2) == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        try:
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise RuntimeError("另一个桥接任务正在使用这个官方工具，请稍后再试") from exc
        try:
            yield
        finally:
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)


def data_snapshot(folder: Path) -> dict[Path, tuple[int, int]]:
    result = {}
    for path in folder.glob("*.txt"):
        try:
            stat = path.stat()
            result[path] = (stat.st_mtime_ns, stat.st_size)
        except OSError:
            pass
    return result


def decode_output(data: bytes) -> str:
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise ValueError("无法识别官方输出编码")


def foreground_window() -> int:
    try:
        import win32gui
        return int(win32gui.GetForegroundWindow())
    except Exception:
        return 0


def restore_foreground(handle: int) -> bool:
    if not handle:
        return False
    try:
        import win32con
        import win32gui
        if not win32gui.IsWindow(handle):
            return False
        win32gui.ShowWindow(handle, win32con.SW_RESTORE)
        return bool(win32gui.SetForegroundWindow(handle))
    except Exception:
        return False


def offscreen_window(handle: int) -> tuple[int, int, int, int]:
    import win32con
    import win32gui
    original = win32gui.GetWindowRect(handle)
    width = max(640, original[2] - original[0])
    virtual_left = win32api_metric(win32con.SM_XVIRTUALSCREEN)
    virtual_top = win32api_metric(win32con.SM_YVIRTUALSCREEN)
    win32gui.ShowWindow(handle, win32con.SW_SHOWNOACTIVATE)
    win32gui.SetWindowPos(
        handle, 0, virtual_left - width - 200, virtual_top, 0, 0,
        win32con.SWP_NOSIZE | win32con.SWP_NOZORDER | win32con.SWP_NOACTIVATE,
    )
    return original


def win32api_metric(index: int) -> int:
    import win32api
    return int(win32api.GetSystemMetrics(index))


def show_window(handle: int, rectangle: tuple[int, int, int, int]) -> None:
    import win32con
    import win32gui
    win32gui.ShowWindow(handle, win32con.SW_SHOWNOACTIVATE)
    win32gui.SetWindowPos(
        handle, 0, rectangle[0], rectangle[1], 0, 0,
        win32con.SWP_NOSIZE | win32con.SWP_NOZORDER | win32con.SWP_NOACTIVATE,
    )


def minimize_window(handle: int) -> None:
    try:
        import win32con
        import win32gui
        win32gui.ShowWindow(handle, win32con.SW_MINIMIZE)
    except Exception:
        pass


def window_state(app, window) -> tuple[str, list[str], list]:
    import win32gui
    exists = bool(win32gui.IsWindow(window.handle))
    dialogs, dialog_windows = [], []
    if exists and not window.is_enabled():
        for item in app.windows():
            if item.handle == window.handle or not item.is_visible():
                continue
            title = item.window_text().strip()
            if not title and item.class_name() != "#32770":
                continue
            body = "；".join(
                child.window_text() for child in item.descendants()
                if child.friendly_class_name() == "Static" and child.window_text()
            )
            dialogs.append((title or "未命名对话框") + (": " + body[:1500] if body else ""))
            dialog_windows.append(item)
    state = classify_window(app.is_process_running(), exists, window.is_enabled() if exists else False, dialogs)
    return state, dialogs, dialog_windows


def uia_controls(app, main) -> list:
    from pywinauto import Application
    ui = Application(backend="uia").connect(process=app.process)
    wrapped = ui.window(handle=main.handle).wrapper_object()
    controls = wrapped.descendants()
    progress(f"UIA 控件扫描：handle={main.handle}, controls={len(controls)}")
    return controls


def unique_id(controls: list, automation_id: str, kind: str):
    found = [item for item in controls if item.element_info.automation_id == automation_id
             and item.element_info.control_type == kind]
    if len(found) != 1:
        raise RuntimeError(f"控件结构不符合已验证版本：{automation_id}/{kind}，找到 {len(found)} 个")
    return found[0]


def required_editors_ready(controls: list) -> bool:
    """输入框和输出框都进入 UIA 树后才允许继续。"""
    editor_ids = {
        item.element_info.automation_id
        for item in controls
        if item.element_info.control_type == "Edit"
    }
    return {"RichTextBox1", "RichTextBox2"}.issubset(editor_ids)


def output_has_new_evidence(previous: str, current: str,
                            saw_activity: bool, new_file_matches: int) -> bool:
    """不清空官方输出时，仍需确认结果不是静止的旧内容。"""
    return saw_activity or current != previous or new_file_matches > 0


def acquire_controls(app, window, original_foreground: int) -> tuple[list, bool]:
    # 正常展开的离屏窗口通常可直接提供完整 UIA 树，先耐心轮询，不主动抢焦点。
    deadline = time.monotonic() + 3
    controls = []
    while time.monotonic() < deadline:
        controls = uia_controls(app, window)
        if required_editors_ready(controls):
            return controls, False
        time.sleep(.2)
    progress("UIA 控件树确实为空，短暂聚焦官方窗口进行降级恢复")
    window.set_focus()
    try:
        # 窗口刚获得焦点时，两个 RichTextBox 可能分批进入 UIA 树。
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            controls = uia_controls(app, window)
            if required_editors_ready(controls):
                break
            time.sleep(.2)
    finally:
        restore_foreground(original_foreground)
    return controls, True


def connect(exe: Path, launch: bool):
    from pywinauto import Application
    from pywinauto.application import process_get_modules

    if not exe.is_file():
        raise RuntimeError(f"找不到官方程序：{exe}")

    def candidates():
        matches = []
        for pid, path, _ in process_get_modules():
            if not path or str(Path(path).resolve()).casefold() != str(exe.resolve()).casefold():
                continue
            try:
                app = Application(backend="win32").connect(process=pid)
                matches.extend((app, win) for win in app.windows()
                               if win.is_visible() and win.window_text().startswith("Protocol Analysis"))
            except Exception:
                pass
        return matches

    matches = candidates()
    if len(matches) > 1:
        raise RuntimeError("找到多个官方主窗口，请仅保留一个再试")
    if matches:
        progress(f"已连接官方主窗口，PID={matches[0][0].process}")
        return matches[0]
    if not launch:
        raise RuntimeError("没有可用的官方主窗口，请启用自动启动")
    progress("正在启动官方工具")
    Application(backend="win32").start(f'"{exe}"', work_dir=str(exe.parent), timeout=20)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        matches = candidates()
        if len(matches) > 1:
            raise RuntimeError("启动后出现多个官方主窗口，请仅保留一个再试")
        if matches:
            progress(f"官方主窗口和进程已就绪，PID={matches[0][0].process}")
            return matches[0]
        time.sleep(.2)
    raise RuntimeError("启动后没有可用主窗口；请处理 ProtocolAnalysis 窗口")


def parse_with_official(app, window, exe: Path, job: Path, timeout: float,
                        raw_input: str, protocol_name: str, window_mode: str,
                        original_foreground: int) -> dict:
    from pywinauto.controls.hwndwrapper import HwndWrapper

    if window.is_minimized():
        progress("官方窗口最小化，正在无激活恢复为正常状态")
        import win32con
        import win32gui
        win32gui.ShowWindow(window.handle, win32con.SW_SHOWNOACTIVATE)
    rectangle = window.rectangle()
    original_rect = (rectangle.left, rectangle.top, rectangle.right, rectangle.bottom)
    if window_mode == "background":
        original_rect = offscreen_window(window.handle)
        progress("官方窗口已移到可视屏幕外，并保持正常展开")
        restore_foreground(original_foreground)
    controls, fallback_focus_used = acquire_controls(app, window, original_foreground)

    def native(automation_id: str, kind: str):
        return HwndWrapper(unique_id(controls, automation_id, kind).handle)

    input_box = native("RichTextBox1", "Edit")
    output_box = native("RichTextBox2", "Edit")
    analyze = native("Button2", "Button")
    analyze_uia = unique_id(controls, "Button2", "Button")
    pause = native("Button3", "Button")
    protocol = native("ComboBox1", "ComboBox")
    language = native("ComboBox2", "ComboBox")
    if analyze.window_text() != "分析数据包":
        raise RuntimeError("按钮名称不符合预期，请使用中文界面")
    items = protocol.item_texts()
    wanted = "CONCOX" if protocol_name == "concox" else "JT808"
    selected = next(
        (item for item in items if wanted in item.upper().replace("/", "")), None
    )
    if selected:
        protocol.select(selected)
    if "CHINESE" in language.item_texts():
        language.select("CHINESE")
    progress(f"正在提交原始日志（{len(raw_input)} 字符，协议 {wanted}）")
    (job / "input.txt").write_text(raw_input, encoding="utf-8", newline="")
    previous_output = output_box.window_text()
    before = data_snapshot(exe.parent / "Data")
    input_box.set_edit_text(raw_input)
    progress("正在提交：原文已交给官方工具，等待工具自动刷新输出")
    analyze_uia.invoke()
    progress("官方解析中")
    deadline = time.monotonic() + timeout
    stable_text, stable_since = None, time.monotonic()
    saw_activity = False
    modal_visible = False
    while timeout == 0 or time.monotonic() < deadline:
        if (job / "cancel.request").exists():
            raise RuntimeError("任务已由用户取消")
        state, dialogs, dialog_windows = window_state(app, window)
        if state == "closed":
            raise RuntimeError("官方工具窗口已关闭，任务中断")
        if state == "modal":
            if not modal_visible:
                show_window(window.handle, original_rect)
                progress("请处理 ProtocolAnalysis 窗口：" + "、".join(dialogs))
                if dialog_windows:
                    dialog_windows[0].set_focus()
                modal_visible = True
            time.sleep(.25)
            continue
        if modal_visible:
            modal_visible = False
            if window_mode == "background":
                offscreen_window(window.handle)
                restore_foreground(original_foreground)
            progress("弹窗已处理，官方解析继续")
        if state == "disabled":
            saw_activity = True
            time.sleep(.2)
            continue
        text = output_box.window_text()
        ready = analyze.is_enabled() and not pause.is_enabled()
        if not saw_activity and (not ready or text != previous_output):
            saw_activity = True
            progress("正在取回结果")
        if ready and output_complete(text):
            if text != stable_text:
                stable_text, stable_since = text, time.monotonic()
            elif time.monotonic() - stable_since >= 2:
                candidates = []
                for path, stat in data_snapshot(exe.parent / "Data").items():
                    if before.get(path) == stat:
                        continue
                    try:
                        candidate = decode_output(path.read_bytes())
                    except (OSError, ValueError):
                        continue
                    if candidate.strip() == text.strip() and output_complete(candidate):
                        candidates.append((path, candidate))
                if len(candidates) > 1:
                    raise RuntimeError("多个新文件匹配本次任务，无法唯一判定结果来源")
                if not output_has_new_evidence(
                    previous_output, text, saw_activity, len(candidates)
                ):
                    # 官方界面仍停留在完整的旧结果，继续等待，不得误报完成。
                    stable_since = time.monotonic()
                    time.sleep(.2)
                    continue
                source, output = (str(candidates[0][0]), candidates[0][1]) \
                    if candidates else ("window:RichTextBox2", text)
                (job / "parsed.txt").write_text(output, encoding="utf-8", newline="")
                progress("解析完成")
                return {
                    "status": "ok", "source": source, "output": str(job / "parsed.txt"),
                    "mode": "raw", "input_chars": len(raw_input),
                    "window_mode": window_mode, "fallback_focus_used": fallback_focus_used,
                    **output_counts(output),
                }
        else:
            stable_text = None
        time.sleep(.2)
    detail = "官方有响应，但输出未通过完整性核对" if saw_activity else "未观察到本次解析活动"
    raise RuntimeError(f"等待解析超时：{detail}；不会使用旧输出")


def main() -> int:
    global TRACE_PATH
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["parse", "inspect", "self-check"])
    parser.add_argument("--input", type=Path)
    parser.add_argument("--exe", type=Path)
    parser.add_argument("--protocol", choices=["concox", "jt808"], default="concox")
    parser.add_argument("--window-mode", choices=["background", "brief", "debug"], default="background")
    parser.add_argument("--launch", action="store_true")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--job-dir", type=Path)
    args = parser.parse_args()
    if args.command == "self-check":
        verify_runtime_dependencies()
        return 0
    if args.command == "parse" and not args.input:
        parser.error("parse 必须指定 --input")
    if args.timeout < 0:
        parser.error("--timeout 不能为负数；0 表示持续等待")
    exe = (args.exe or DEFAULT_EXE).resolve()
    if not args.worker:
        command = [sys.executable] + ([] if FROZEN else [str(Path(__file__).resolve())])
        child = subprocess.Popen(
            command + sys.argv[1:] + ["--worker"],
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace",
        )
        reader = threading.Thread(
            target=lambda: [print(line, end="", flush=True) for line in child.stdout], daemon=True
        )
        reader.start()
        try:
            code = child.wait(timeout=None if args.timeout == 0 else args.timeout + 35)
        except subprocess.TimeoutExpired:
            child.kill()
            code = 1
        reader.join(timeout=2)
        return code

    job = args.job_dir or ROOT / "tmp" / "official-bridge" / (
        time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8]
    )
    job.mkdir(parents=True, exist_ok=True)
    TRACE_PATH = job / "progress.log"
    original_foreground = foreground_window()
    window = None
    try:
        raw_input = decode_output(args.input.read_bytes()) if args.input else ""
        with task_lock(exe):
            app, window = connect(exe, args.launch)
            result = parse_with_official(
                app, window, exe, job, args.timeout, raw_input,
                args.protocol, args.window_mode, original_foreground,
            )
        (job / "result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        progress("解析完成")
        return 0
    except Exception as exc:
        progress("解析未完成，请重试。")
        (job / "result.json").write_text(
            json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return 1
    finally:
        if window is not None and args.window_mode != "debug":
            minimize_window(window.handle)
        restore_foreground(original_foreground)


if __name__ == "__main__":
    try:
        if sys.stdout and hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8")
        if sys.stderr and hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8")
    except OSError:
        pass
    raise SystemExit(main())
