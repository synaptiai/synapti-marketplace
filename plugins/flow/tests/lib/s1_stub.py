"""A stub System One server for the end-to-end scenarios of bin/flow-s1.sh.

Started by e2e_stub_start in tests/lib/e2e.sh. It binds 127.0.0.1 on a port
the kernel picks, writes that port to --port-file once it is listening (the
harness waits for the file), and logs every request it receives, whatever the
method, as one JSON line in --log: method, path, headers (names lower-cased,
Authorization included) and body. A request is logged before the stub waits or
replies, so a client that gives up early is still seen to have called.

--config is a JSON object:
  status     HTTP status to reply with (default 200)
  body       reply body: a JSON value is sent as JSON, a string is sent as is
  bearer     when set, a request without "Authorization: Bearer <bearer>"
             gets 401 instead
  delay_ms   wait this long before sending anything
  drip_ms    send the headers, then one byte of body every drip_ms, for
             drip_count bytes (a server that is slow but never silent)
  location   with a 3xx status, the Location header
  body_file  send this file's bytes as the reply body, as is (a large body
             stays out of the artifact that logs the config)
  declare_length
             with body_file: declare this Content-Length, send the file,
             then hold the connection for hold_ms before closing it (a
             reply longer than it arrives)
  hold_ms    see declare_length
  by_state   a list of rules [{"contains": <text>, "status": ..., "body":
             ...}], tried in order: the first rule whose text appears in
             the request body (as received, before any parsing) gives the
             status and body for that request, each falling back to the
             top-level status and body. So one stub can answer the
             candidates of one run differently

The stub exits by itself after --lifetime seconds, so a scenario that aborts
before the harness kills it cannot leave a process behind.
"""

import argparse
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--port-file", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--lifetime", type=float, default=60.0)
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    log_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):  # keep stderr quiet
            pass

        def _handle(self):
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw.decode("utf-8")) if raw else None
            except ValueError:
                body = raw.decode("utf-8", "replace")
            entry = {
                "method": self.command,
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }
            with log_lock:
                with open(args.log, "a", encoding="utf-8") as f:
                    f.write(json.dumps(entry, sort_keys=True) + "\n")

            if cfg.get("delay_ms"):
                time.sleep(cfg["delay_ms"] / 1000.0)
            bearer = cfg.get("bearer")
            if bearer and self.headers.get("Authorization") != "Bearer " + bearer:
                self._send(401, {"detail": "invalid api key"})
                return
            reply = cfg
            text = raw.decode("utf-8", "replace")
            for rule in cfg.get("by_state") or []:
                if rule.get("contains") and rule["contains"] in text:
                    reply = dict(cfg, **{k: v for k, v in rule.items() if k in ("status", "body")})
                    break
            status = int(reply.get("status", 200))
            if cfg.get("location"):
                self.send_response(status)
                self.send_header("Location", cfg["location"])
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if cfg.get("drip_ms"):
                count = int(cfg.get("drip_count", 60))
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(count))
                self.end_headers()
                for _ in range(count):
                    try:
                        self.wfile.write(b" ")
                        self.wfile.flush()
                    except OSError:
                        return
                    time.sleep(cfg["drip_ms"] / 1000.0)
                return
            if cfg.get("body_file"):
                with open(cfg["body_file"], "rb") as f:
                    data = f.read()
                if cfg.get("declare_length"):
                    # Declare more than is sent, send it, and hold the
                    # connection for hold_ms before closing it.
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(int(cfg["declare_length"])))
                    self.end_headers()
                    try:
                        self.wfile.write(data)
                        self.wfile.flush()
                    except OSError:
                        return
                    time.sleep(int(cfg.get("hold_ms", 0)) / 1000.0)
                    self.close_connection = True
                    return
                self._send(status, data)
                return
            self._send(status, reply.get("body", {}))

        def _send(self, status, body):
            if isinstance(body, bytes):
                data = body
            else:
                data = body.encode("utf-8") if isinstance(body, str) else json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except OSError:
                pass

        do_GET = do_POST = do_PUT = do_HEAD = do_DELETE = do_CONNECT = _handle

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    timer = threading.Timer(args.lifetime, lambda: os._exit(0))
    timer.daemon = True
    timer.start()
    tmp = args.port_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(server.server_address[1]))
    os.replace(tmp, args.port_file)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
