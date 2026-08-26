from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from tava_station.cues import Cue, cue_for_payload

_STATIC = Path(__file__).with_name("static")
_IDLE = Cue("idle", "Tap card", "Hold the card on the reader.")


class CueState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._cue = _IDLE

    def set_payload(self, payload: dict) -> Cue:
        cue = cue_for_payload(payload)
        with self._lock:
            self._cue = cue
        return cue

    def set_error(self) -> Cue:
        cue = Cue("fail", "Could not sign in", "Use paper and tell a tutor.")
        with self._lock:
            self._cue = cue
        return cue

    def snapshot(self) -> Cue:
        with self._lock:
            return self._cue


def start_cue_server(host: str, port: int, state: CueState) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            return

        def do_GET(self) -> None:  # noqa: N802
            if self.path in ("/", "/index.html"):
                body = (_STATIC / "index.html").read_bytes()
                self._send(200, "text/html; charset=utf-8", body)
                return
            if self.path == "/cue":
                cue = state.snapshot()
                body = json.dumps(
                    {"tone": cue.tone, "title": cue.title, "detail": cue.detail}
                ).encode()
                self._send(200, "application/json", body)
                return
            self._send(404, "text/plain", b"not found")

        def _send(self, status: int, content_type: str, body: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer((host, port), Handler)
    thread = threading.Thread(target=server.serve_forever, name="tava-cue", daemon=True)
    thread.start()
    return server
