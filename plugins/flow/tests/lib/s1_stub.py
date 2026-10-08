"""A stub System One server for the end-to-end scenarios of bin/flow-s1.sh.

Started by e2e_stub_start in tests/lib/e2e.sh. It binds 127.0.0.1 on a port
the kernel picks, writes that port to --port-file once it is listening (the
harness waits for the file), and logs every request it receives, whatever the
method, as one JSON line in --log: method, path, headers (names lower-cased,
Authorization included), body, and t, the time the request arrived in
milliseconds on the stub's monotonic clock (comparable only between requests to
the same stub). A request is logged before the stub waits or replies, so a
client that gives up early is still seen to have called.

--config is a JSON object:
  status     HTTP status to reply with (default 200)
  statuses   a list of statuses for the first requests, in the order they
             arrive; once it is used up, status applies
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
  replies    a list of {status, body, delay_ms}, answered in request order,
             the last one repeated once the list runs out. Each entry's keys
             replace the top-level ones for that request, so a scenario with
             several requests can give each its own reply. Without it every
             request gets the top-level reply. The count includes requests
             that get 401; statuses, by_state and rules then apply on top of
             the entry chosen
  rules      a list of {"contains": text, "body": value}: the first rule
             whose text occurs in the raw request body replies with its
             body (status and the other keys still apply); with no rule
             matching, body is used (after any by_state replacement)
  by_state   a list of {match, body, status, delay_ms}: the first entry whose
             match is a substring of the request's state, serialized as
             json.dumps(state, sort_keys=True), replaces body, status and
             delay_ms (each one it names) for that request. With sort_keys a
             criterion's id is followed by its text, so the match
             '"id": "AC2", "text"' picks the state about AC2 and no other.
             A status from statuses still comes first for the requests it
             covers

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
    ap.add_argument("--lifetime", type=float, default=600.0)
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        base_cfg = json.load(f)
    log_lock = threading.Lock()
    arrived = [0]
    served = [0]

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
                "t": int(time.monotonic() * 1000),
                "method": self.command,
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }
            with log_lock:
                with open(args.log, "a", encoding="utf-8") as f:
                    f.write(json.dumps(entry, sort_keys=True) + "\n")
                k = arrived[0]
                arrived[0] += 1
            cfg = base_cfg
            replies = base_cfg.get("replies")
            if replies:
                cfg = dict(base_cfg)
                cfg.update(replies[min(k, len(replies) - 1)])

            rule = dict(cfg)
            state = body.get("state") if isinstance(body, dict) else None
            serialized = json.dumps(state, sort_keys=True)
            for entry in cfg.get("by_state") or []:
                if entry.get("match", "") in serialized:
                    rule.update({k: entry[k] for k in ("body", "status", "delay_ms") if k in entry})
                    break
            if rule.get("delay_ms"):
                time.sleep(rule["delay_ms"] / 1000.0)
            bearer = cfg.get("bearer")
            if bearer and self.headers.get("Authorization") != "Bearer " + bearer:
                self._send(401, {"detail": "invalid api key"})
                return
            with log_lock:
                n = served[0]
                served[0] += 1
            seq = cfg.get("statuses") or []
            status = int(seq[n]) if n < len(seq) else int(rule.get("status", 200))
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
            for body_rule in cfg.get("rules") or ():
                if body_rule.get("contains", "") in raw.decode("utf-8", "replace"):
                    self._send(status, body_rule.get("body", {}))
                    return
            self._send(status, rule.get("body", {}))

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
