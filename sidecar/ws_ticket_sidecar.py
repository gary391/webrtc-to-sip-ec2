#!/usr/bin/env python3
"""Demo WebSocket ticket validation sidecar.

This is intentionally local-demo scoped. It validates opaque synthetic tickets
minted into a local state file and atomically marks each valid ticket consumed.
Production deployments should replace this with the VG/shared-cache validator.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import http.server
import json
import logging
import os
import pathlib
import re
import secrets
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterator

DEFAULT_STATE_FILE = "/tmp/webrtc-to-sip-ws-tickets.json"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9090
DEFAULT_SCOPE = "sip-ws"
DEFAULT_TTL_SECONDS = 60
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,256}$")


@dataclass(frozen=True)
class ValidationResult:
    ok: bool
    status: int
    reason: str


def _now() -> int:
    return int(time.time())


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _redacted_token_id(token: str) -> str:
    return _token_hash(token)[:12]


def _empty_state() -> dict:
    return {"tickets": {}}


def _read_state(path: pathlib.Path) -> dict:
    if not path.exists():
        return _empty_state()
    with path.open("r", encoding="utf-8") as handle:
        state = json.load(handle)
    if not isinstance(state, dict) or not isinstance(state.get("tickets"), dict):
        raise ValueError(f"invalid state file: {path}")
    return state


def _write_state(path: pathlib.Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, sort_keys=True)
            handle.write("\n")
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


@contextmanager
def _locked_state(path: pathlib.Path) -> Iterator[dict]:
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_state(path)
        yield state
        _write_state(path, state)


def mint_ticket(
    state_file: str = DEFAULT_STATE_FILE,
    ttl_seconds: int = DEFAULT_TTL_SECONDS,
    scope: str = DEFAULT_SCOPE,
) -> str:
    if ttl_seconds < 1 or ttl_seconds > 3600:
        raise ValueError("ttl_seconds must be between 1 and 3600")
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", scope):
        raise ValueError("scope contains unsupported characters")

    token = secrets.token_urlsafe(32)
    record = {
        "expires_at": _now() + ttl_seconds,
        "scope": scope,
        "consumed_at": None,
    }
    path = pathlib.Path(state_file)
    with _locked_state(path) as state:
        state["tickets"][_token_hash(token)] = record
    return token


def validate_ticket(
    token: str | None,
    state_file: str = DEFAULT_STATE_FILE,
    scope: str = DEFAULT_SCOPE,
) -> ValidationResult:
    if not token:
        return ValidationResult(False, 401, "missing")
    if not TOKEN_RE.fullmatch(token):
        return ValidationResult(False, 401, "malformed")

    path = pathlib.Path(state_file)
    token_id = _token_hash(token)
    with _locked_state(path) as state:
        tickets = state["tickets"]
        record = tickets.get(token_id)
        if record is None:
            return ValidationResult(False, 401, "unknown")
        if record.get("scope") != scope:
            return ValidationResult(False, 403, "wrong-scope")
        if record.get("consumed_at"):
            return ValidationResult(False, 403, "reused")
        if int(record.get("expires_at", 0)) < _now():
            return ValidationResult(False, 401, "expired")
        record["consumed_at"] = _now()
        return ValidationResult(True, 204, "ok")


class TicketHandler(http.server.BaseHTTPRequestHandler):
    server_version = "WsTicketSidecar/0.1"

    def do_GET(self) -> None:
        if self.path.split("?", 1)[0] != "/validate":
            self.send_error(404)
            return

        token = self.headers.get("X-WS-Ticket")
        result = validate_ticket(token, self.server.state_file, self.server.scope)
        token_label = _redacted_token_id(token) if token else "none"
        logging.info(
            "ws_ticket_validation status=%s reason=%s token_id=%s origin=%s host=%s request_id=%s",
            result.status,
            result.reason,
            token_label,
            self.headers.get("Origin", ""),
            self.headers.get("Host", ""),
            self.headers.get("X-Request-ID", ""),
        )
        self.send_response(result.status)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def log_message(self, fmt: str, *args: object) -> None:
        logging.info("http " + fmt, *args)


class TicketServer(http.server.ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], handler, state_file: str, scope: str):
        super().__init__(server_address, handler)
        self.state_file = state_file
        self.scope = scope


def serve(host: str, port: int, state_file: str, scope: str) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    server = TicketServer((host, port), TicketHandler, state_file, scope)
    logging.info("ws_ticket_sidecar listening on http://%s:%s/validate", host, server.server_port)
    server.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser(description="Demo WebSocket ticket sidecar")
    parser.add_argument("--state-file", default=DEFAULT_STATE_FILE)
    parser.add_argument("--scope", default=DEFAULT_SCOPE)
    subparsers = parser.add_subparsers(dest="command", required=True)

    mint = subparsers.add_parser("mint", help="mint one synthetic ticket")
    mint.add_argument("--ttl", type=int, default=DEFAULT_TTL_SECONDS)

    validate = subparsers.add_parser("validate", help="validate and consume a ticket")
    validate.add_argument("ticket", nargs="?")

    serve_parser = subparsers.add_parser("serve", help="serve HTTP validation endpoint")
    serve_parser.add_argument("--host", default=DEFAULT_HOST)
    serve_parser.add_argument("--port", type=int, default=DEFAULT_PORT)

    args = parser.parse_args()
    if args.command == "mint":
        print(mint_ticket(args.state_file, args.ttl, args.scope))
        return 0
    if args.command == "validate":
        result = validate_ticket(args.ticket, args.state_file, args.scope)
        print(result.reason)
        return 0 if result.ok else 1
    if args.command == "serve":
        serve(args.host, args.port, args.state_file, args.scope)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
