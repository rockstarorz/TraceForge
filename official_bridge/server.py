"""仅监听 127.0.0.1 的官方解析调试服务。"""
from __future__ import annotations

import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import subprocess
import sys
import threading
import uuid

from bridge import DEFAULT_EXE, FROZEN, ROOT

BRIDGE_VERSION = "2026-09-12-flutter-background-v1"


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, exe=None):
        super().__init__(address, Handler)
        self.exe = Path(exe or DEFAULT_EXE).resolve()
        self.token = secrets.token_urlsafe(32)
        self.origin = f"http://127.0.0.1:{self.server_port}"
        self.jobs = {}
        self.guard = threading.Lock()
        self.busy = False
        self.child = None

    def submit(self, text, protocol="concox", window_mode="background"):
        if not isinstance(text, str):
            raise ValueError("输入必须为文本")
        if protocol not in ("concox", "jt808"):
            raise ValueError("不支持的协议")
        if window_mode not in ("background", "brief", "debug"):
            raise ValueError("不支持的窗口模式")
        with self.guard:
            if self.busy:
                return None
            self.busy = True
            job_id = uuid.uuid4().hex
            self.jobs[job_id] = {
                "id": job_id, "state": "running", "progress": "准备官方解析",
                "input_chars": len(text),
            }
        threading.Thread(
            target=self.run_job, args=(job_id, text, protocol, window_mode), daemon=True
        ).start()
        return job_id

    def run_job(self, job_id, text, protocol, window_mode):
        job = ROOT / "tmp" / "official-bridge" / ("http-" + job_id)
        try:
            job.mkdir(parents=True, exist_ok=True)
            input_path = job / "submitted.txt"
            input_path.write_text(text, encoding="utf-8", newline="")
            command = [sys.executable] + ([] if FROZEN else [str(ROOT / "official_bridge" / "bridge.py")])
            self.child = subprocess.Popen(
                command + [
                    "parse", "--input", str(input_path), "--exe", str(self.exe),
                    "--launch", "--timeout", "0", "--worker", "--protocol", protocol,
                    "--window-mode", window_mode, "--job-dir", str(job),
                ],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                encoding="utf-8", errors="replace",
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            for line in self.child.stdout:
                if line.startswith("[桥接]"):
                    with self.guard:
                        self.jobs[job_id]["progress"] = line[4:].strip()
            code = self.child.wait()
            result_path = job / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else {}
            if code or result.get("status") != "ok":
                raise RuntimeError(result.get("error", "桥接未完成"))
            parsed = (job / "parsed.txt").read_text(encoding="utf-8")
            with self.guard:
                self.jobs[job_id].update(
                    state="done", progress="解析完成", parsed=parsed,
                    output_packets=result.get("output_packets"),
                    official_error_packets=result.get("official_error_packets"),
                )
        except Exception as exc:
            with self.guard:
                self.jobs[job_id].update(state="error", progress="解析失败", error=str(exc))
        finally:
            self.child = None
            with self.guard:
                self.busy = False


class Handler(BaseHTTPRequestHandler):
    server: BridgeServer

    def log_message(self, *_):
        pass

    def send_json(self, code, value):
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def allowed(self):
        host_ok = self.headers.get("Host") == self.server.origin.removeprefix("http://")
        origin = self.headers.get("Origin")
        token_ok = hmac.compare_digest(self.headers.get("X-Bridge-Token", ""), self.server.token)
        if not host_ok or (origin and origin != self.server.origin) or not token_ok:
            self.send_json(403, {"error": "仅允许持有本次令牌的本机客户端访问"})
            return False
        return True

    def do_GET(self):
        if not self.allowed():
            return
        if self.path == "/api/status":
            self.send_json(200, {
                "ready": self.server.exe.is_file(), "busy": self.server.busy,
                "max_chars": None, "version": BRIDGE_VERSION,
            })
            return
        if self.path.startswith("/api/jobs/"):
            with self.server.guard:
                job = dict(self.server.jobs.get(self.path.removeprefix("/api/jobs/"), {}))
            self.send_json(200 if job else 404, job or {"error": "任务不存在"})
            return
        self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        if not self.allowed():
            return
        if self.path != "/api/jobs":
            self.send_json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or self.headers.get_content_type() != "application/json":
                raise ValueError("需要非空 JSON 请求")
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("请求格式无效")
            job_id = self.server.submit(
                body.get("text"), body.get("protocol", "concox"),
                body.get("window_mode", "background"),
            )
            self.send_json(
                202 if job_id else 409,
                {"id": job_id} if job_id else {"error": "官方解析正在运行"},
            )
        except (ValueError, UnicodeError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)})


def main():
    server = BridgeServer(("127.0.0.1", 6872))
    print(json.dumps({"url": server.origin, "token": server.token}, ensure_ascii=False), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
