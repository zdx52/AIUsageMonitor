#!/usr/bin/env python3
"""Hindsight Dashboard Server - serves HTML + proxies API calls"""
import http.server
import urllib.request
import json
import os
import time

HINDSIGHT_API = "http://localhost:9077"
CACHE = {"pypi": None, "pypi_time": 0}
CACHE_TTL = 1800  # 30 分钟缓存 PyPI 结果

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/"):
            # Proxy to Hindsight API
            target = HINDSIGHT_API + self.path.replace("/api", "/v1/default/banks/hermes", 1)
            try:
                req = urllib.request.Request(target)
                resp = urllib.request.urlopen(req, timeout=10)
                data = resp.read()
                self.send_response(200)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.end_headers()
                self.wfile.write(data)
            except urllib.error.HTTPError as e:
                self.send_response(e.code)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.end_headers()
                self.wfile.write(e.read())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
            return
        if self.path == "/health":
            try:
                resp = urllib.request.urlopen(HINDSIGHT_API + "/health", timeout=5)
                data = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.end_headers()
                self.wfile.write(data)
            except:
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.end_headers()
                self.wfile.write(b'{"status":"unavailable"}')
            return
        if self.path == "/check-update":
            self._handle_check_update()
            return
        # Serve static files with no-cache headers
        if self.path == "/hindsight-dashboard.html":
            try:
                filepath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hindsight-dashboard.html")
                with open(filepath, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"Not found")
            return
        super().do_GET()

    def _handle_check_update(self):
        """返回当前版本 + PyPI 最新版本"""
        result = {"current": "?.?.?", "latest": "?.?.?", "has_update": False, "error": None}
        # 获取本地版本
        try:
            resp = urllib.request.urlopen(HINDSIGHT_API + "/version", timeout=5)
            vdata = json.loads(resp.read())
            result["current"] = vdata.get("api_version", "?.?.?")
        except Exception as e:
            result["error"] = f"本地: {e}"
        # 查 PyPI（30分钟缓存）
        now = time.time()
        if CACHE["pypi"] and (now - CACHE["pypi_time"]) < CACHE_TTL:
            result["latest"] = CACHE["pypi"]
        else:
            try:
                req = urllib.request.Request(
                    "https://pypi.org/pypi/hindsight-api/json",
                    headers={"Cache-Control": "no-cache"},
                )
                resp = urllib.request.urlopen(req, timeout=15)
                pdata = json.loads(resp.read())
                info = pdata.get("info", {})
                latest = info.get("version", "?.?.?")
                CACHE["pypi"] = latest
                CACHE["pypi_time"] = now
                result["latest"] = latest
            except Exception as e:
                result["error"] = f"PyPI: {e}" if not result["error"] else f"{result['error']}; PyPI: {e}"
        if result["current"] != "?.?.?" and result["latest"] != "?.?.?" and result["latest"] != result["current"]:
            result["has_update"] = True
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())

    def do_POST(self):
        if self.path.startswith("/api/"):
            target = HINDSIGHT_API + self.path.replace("/api", "/v1/default/banks/hermes", 1)
            content_len = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_len) if content_len else b"{}"
            try:
                req = urllib.request.Request(target, data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST")
                resp = urllib.request.urlopen(req, timeout=30)
                data = resp.read()
                self.send_response(200)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
                self.end_headers()
                self.wfile.write(data)
            except urllib.error.HTTPError as e:
                self.send_response(e.code)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(e.read())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
            return

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    server = http.server.HTTPServer(("127.0.0.1", 8080), ProxyHandler)
    print("🚀 Hindsight 看板: http://localhost:8080/hindsight-dashboard.html")
    server.serve_forever()
