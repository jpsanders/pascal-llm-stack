#!/usr/bin/env python3
"""
Front-end host + API proxy for the local llama.cpp server.

  browser/capivara -> :8080 (this proxy) -> 127.0.0.1:8090 (llama-server)

  /            -> serves $HOME/www-llm/index.html (the chat GUI)
  /v1/*, /health, /props -> streamed pass-through to llama-server
  /models (ollama-style alias) -> /v1/models

Streaming (SSE) is relayed chunk-by-chunk so tokens render live.
"""
import http.server
import os
import socketserver
import sys
import urllib.request
import urllib.error

PORT = 8080
UPSTREAM = "http://127.0.0.1:8090"
WEBROOT = os.path.expanduser("~/www-llm")

API_PREFIXES = ("/v1/", "/health", "/props", "/models")
HOP_HEADERS = {"connection", "keep-alive", "transfer-encoding", "te",
               "trailer", "proxy-authorization", "proxy-authenticate",
               "upgrade", "content-encoding", "content-length"}


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    # ---- routing -----------------------------------------------------------
    def do_GET(self):
        if self.path.startswith("/models"):
            self.path = "/v1/models"
        if self._is_api():
            self._proxy()
        else:
            self._static()

    def do_POST(self):
        self._proxy()

    def do_OPTIONS(self):
        self._proxy()

    def _is_api(self):
        return any(self.path == p or self.path.startswith(p)
                   for p in API_PREFIXES)

    # ---- static ------------------------------------------------------------
    def _static(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            fp = os.path.join(WEBROOT, "index.html")
        else:
            fp = os.path.normpath(os.path.join(WEBROOT, path.lstrip("/")))
            if not fp.startswith(WEBROOT):
                fp = ""
        if not fp or not os.path.isfile(fp):
            self.send_error(404, "not found")
            return
        body = open(fp, "rb").read()
        ctype = "text/html; charset=utf-8" if fp.endswith(".html") else \
                "text/css" if fp.endswith(".css") else \
                "application/javascript" if fp.endswith(".js") else \
                "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    # ---- proxy -------------------------------------------------------------
    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        req = urllib.request.Request(UPSTREAM + self.path, data=body,
                                     method=self.command)
        for h in ("Content-Type", "Authorization", "Accept"):
            if self.headers.get(h):
                req.add_header(h, self.headers[h])
        req.add_header("Connection", "close")

        try:
            upstream = urllib.request.urlopen(req, timeout=3600)
        except urllib.error.HTTPError as e:
            upstream = e
        except Exception as e:
            self.send_error(502, "llama-server unreachable: %s" % e)
            return

        self.send_response(upstream.status if hasattr(upstream, "status")
                           else upstream.code)
        ctype = upstream.headers.get("Content-Type", "application/json")
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")

        is_stream = "text/event-stream" in ctype
        if is_stream:
            self.send_header("Transfer-Encoding", "chunked")
        else:
            data = upstream.read()
            self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()

        if not is_stream:
            self.wfile.write(data)
            return

        # SSE: relay chunks as they arrive
        try:
            while True:
                chunk = upstream.read(1024)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass  # client disconnected (stop button) - upstream aborts too


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    os.makedirs(WEBROOT, exist_ok=True)
    with Server(("0.0.0.0", PORT), Proxy) as srv:
        print(f"GUI+API proxy on :{PORT} -> {UPSTREAM} (webroot {WEBROOT})")
        srv.serve_forever()
