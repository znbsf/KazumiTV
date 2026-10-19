"""One-shot loopback form: fill an empty, focused TV Access Token editor via ADB.

No APK installation, account API calls, saved-token export, or automatic save.
"""
import argparse
import json
import re
import secrets
import subprocess
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PACKAGE = "com.znbsf.kazumi.fluttertv"
TOKEN = re.compile(r"[A-Za-z0-9._~-]{8,2048}\Z")


def adb_run(adb, serial, *args, timeout=15):
    result = subprocess.run(
        [adb, "-s", serial, *args], capture_output=True, timeout=timeout
    )
    if result.returncode:
        raise RuntimeError("电视命令失败；请检查连接，不会自动重发。")
    return result.stdout.decode("utf-8", "replace")


def check_editor(adb, serial):
    if adb_run(adb, serial, "shell", "getprop", "ro.product.device").strip() != "mulan":
        raise RuntimeError("设备身份与本次授权的小米电视不符。")
    windows = adb_run(adb, serial, "shell", "dumpsys", "window", "windows")
    focus = next((line for line in windows.splitlines() if "mCurrentFocus=" in line), "")
    if PACKAGE + "/" not in focus:
        raise RuntimeError("请先在电视正式版打开 Access Token 编辑框。")
    xml = adb_run(adb, serial, "exec-out", "uiautomator", "dump", "/dev/tty", timeout=18)
    start, end = xml.find("<?xml"), xml.rfind("</hierarchy>")
    if start < 0 or end < 0:
        raise RuntimeError("无法取得本次输入框状态；未发送文字。")
    root = ET.fromstring(xml[start : end + len("</hierarchy>")])
    nodes = list(root.iter("node"))
    if not any("Access Token" in (n.get("text", "") + n.get("content-desc", "")) for n in nodes):
        raise RuntimeError("当前界面不是 Access Token 编辑框。")
    editors = [n for n in nodes if n.get("class") == "android.widget.EditText" and n.get("focused") == "true"]
    if len(editors) != 1 or editors[0].get("password") != "true":
        raise RuntimeError("请让电视 Access Token 编辑框保持隐藏文本并取得光标。")
    # Only inspect whether it is empty. Never return or log existing contents.
    if editors[0].get("text", ""):
        raise RuntimeError("请先在电视清空输入框，再提交；本工具不会读取或覆盖已有 Token。")
    if editors[0].get("content-desc", "") not in ("", "Access Token"):
        raise RuntimeError("输入框包含现有内容或状态不明确，请先在电视清空。")


class LocalInputServer(HTTPServer):
    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(10)
        return connection, address


def make_handler(adb, serial, route, origin):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def respond(self, status, body, content_type="application/json; charset=utf-8"):
            data = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(data)

        def valid_path(self):
            return self.path == route and self.headers.get("Host") == origin.removeprefix("http://")

        def do_GET(self):
            if not self.valid_path():
                self.respond(404, "{}")
                return
            self.respond(200, PAGE, "text/html; charset=utf-8")

        def do_POST(self):
            if not self.valid_path() or self.headers.get("Origin") != origin:
                self.respond(403, "{}")
                return
            if self.headers.get("Content-Type") != "application/json":
                self.respond(415, "{}")
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 8192 or self.server.sent:
                    raise ValueError()
                token = json.loads(self.rfile.read(size)).get("token")
                if not isinstance(token, str) or not TOKEN.fullmatch(token):
                    raise ValueError()
                check_editor(adb, serial)
                # Mark consumed before the command: an uncertain result must not replay.
                self.server.sent = True
                try:
                    adb_run(adb, serial, "shell", "input", "text", token)
                finally:
                    token = None
                message = "已向电视输入框发送新 Token。请在电视确认内容，再点击“确定”和“验证并保存”。本地入口已关闭。"
                self.respond(200, json.dumps({"message": message}, ensure_ascii=False))
            except (ValueError, TypeError, AttributeError, json.JSONDecodeError):
                self.respond(400, json.dumps({"message": "请输入完整 Token，不要包含空格或换行。"}, ensure_ascii=False))
            except (RuntimeError, subprocess.TimeoutExpired, ET.ParseError) as error:
                message = str(error) if isinstance(error, RuntimeError) else "状态检查或输入超时；请查看电视，不会自动重发。"
                self.respond(409, json.dumps({"message": message}, ensure_ascii=False))

    return Handler


PAGE = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>KazumiTV · 输入新 Token</title>
<style>body{font:17px/1.7 system-ui;margin:10vh auto;padding:24px;max-width:580px;background:#f7faef;color:#191d17}input,button{box-sizing:border-box;width:100%;font:inherit;padding:14px;border:1px solid #c3cbbd;border-radius:12px;margin:12px 0}button{background:#3e6838;color:white;cursor:pointer}p{color:#42493d}#status{white-space:pre-wrap}</style>
<h1>输入新的 Bangumi Token</h1><p>先在电视打开 Access Token 编辑框，清空原内容，保持输入光标。这里只发送你新粘贴的内容；不回读旧 Token。发送后，请在电视确认并保存。</p>
<form autocomplete="off"><label for="token">新的 Access Token</label><input id="token" type="password" autocomplete="off" spellcheck="false" autocapitalize="off" required maxlength="2048"><button>填入电视</button></form><p id="status" role="status">仅本机访问，成功发送一次后自动关闭。30 分钟未提交也会关闭。</p>
<script>const form=document.querySelector('form'),field=document.getElementById('token'),status=document.getElementById('status'),button=document.querySelector('button');form.onsubmit=async e=>{e.preventDefault();button.disabled=true;status.textContent='正在检查电视输入框…';try{const r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:field.value})});const data=await r.json();status.textContent=data.message;if(r.ok){field.value='';field.disabled=true;return;}}catch(_){status.textContent='连接或输入结果未确认，请先查看电视；不会自动重发。';field.value='';return;}button.disabled=false;};window.addEventListener('pagehide',()=>{field.value='';});</script></html>"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--port", type=int, default=18769)
    parser.add_argument("--ready", type=Path)
    args = parser.parse_args()
    route = "/" + secrets.token_urlsafe(24)
    origin = f"http://127.0.0.1:{args.port}"
    server = LocalInputServer(("127.0.0.1", args.port), make_handler(args.adb, args.serial, route, origin))
    server.timeout = 1
    server.sent = False
    info = {"url": origin + route, "expiresInSeconds": 1800}
    if args.ready:
        args.ready.write_text(json.dumps(info), encoding="utf-8")
    print(json.dumps(info), flush=True)
    deadline = time.monotonic() + 1800
    try:
        while not server.sent and time.monotonic() < deadline:
            server.handle_request()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
