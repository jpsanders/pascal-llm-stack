#!/usr/bin/env python3
"""
Transparent streaming reverse proxy:

    :8080 (LAN/tailnet) -> 127.0.0.1:8090 (llama-server + its embedded web UI)

Exposes llama.cpp's official web UI at / and the OpenAI-compatible API at
/v1/* on one port. SSE streaming is relayed chunk-by-chunk so tokens render
live. Run:  bash start-web.sh   (llama-server must be up on 8090)
"""
import http.server
import socketserver
import urllib.request
import urllib.error

PORT = 8080
UPSTREAM = "http://127.0.0.1:8090"
HOP = {"connection", "keep-alive", "transfer-encoding", "te", "trailer",
       "proxy-authorization", "proxy-authenticate", "upgrade"}


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def _relay(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=body,
                                     method=self.command)
        for h in ("Content-Type", "Authorization", "Accept"):
            if self.headers.get(h):
                req.add_header(h, self.headers[h])
        req.add_header("Connection", "close")
        try:
            up = urllib.request.urlopen(req, timeout=3600)
        except urllib.error.HTTPError as e:
            up = e
        except Exception as e:
            self.send_error(502, "llama-server unreachable: %s" % e)
            return
        self.send_response(up.status if hasattr(up, "status") else up.code)
        ctype = up.headers.get("Content-Type", "application/octet-stream")
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.close_connection = True

        if "text/event-stream" in ctype:
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            try:
                while True:
                    chunk = up.read(1024)
                    if not chunk:
                        break
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            data = up.read()
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_OPTIONS = do_PATCH = _relay


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    import sys
    with Server(("0.0.0.0", PORT), Proxy) as srv:
        print(f"reverse proxy :{PORT} -> {UPSTREAM}")
        srv.serve_forever()
