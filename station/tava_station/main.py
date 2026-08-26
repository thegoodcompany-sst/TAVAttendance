from __future__ import annotations

import argparse
import logging
import sys
import time

from tava_station.chip_uid import normalize_chip_uid
from tava_station.client import StationClient
from tava_station.config import load_config
from tava_station.cue_server import CueState, start_cue_server

log = logging.getLogger("tava.station")


def _tap(client: StationClient, state: CueState, raw_uid: str) -> int:
    uid = normalize_chip_uid(raw_uid)
    if uid is None:
        state.set_payload({"outcome": "unknown_card"})
        log.info("outcome=unknown_card reason=invalid_uid")
        return 1
    try:
        payload = client.tap(uid)
    except Exception:
        state.set_error()
        log.exception("tap_failed")
        return 2
    state.set_payload(payload)
    outcome = str(payload.get("outcome") or "error")
    log.info("outcome=%s", outcome)
    return 0 if outcome in {"on_time", "late", "already_signed_in"} else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="TAVA NFC arrival station")
    parser.add_argument("--config", help="Path to config.toml")
    parser.add_argument("--once", metavar="UID", help="Tap one UID and exit")
    parser.add_argument("--stdin", action="store_true", help="Read UIDs from stdin, one per line")
    parser.add_argument("--no-http", action="store_true", help="Do not serve the local cue page")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config = load_config(args.config)
    client = StationClient(config.supabase_url, config.supabase_anon_key)
    client.sign_in(config.station_email, config.station_password)

    state = CueState()
    if not args.no_http:
        start_cue_server(config.http_host, config.http_port, state)
        log.info("cue_ui http://%s:%s", config.http_host, config.http_port)

    if args.once:
        return _tap(client, state, args.once)

    if args.stdin:
        for line in sys.stdin:
            raw = line.strip()
            if raw:
                _tap(client, state, raw)
        return 0

    from tava_station.nfc_reader import iter_chip_uids

    log.info("waiting_for_cards")
    for uid in iter_chip_uids(debounce_seconds=config.debounce_seconds):
        _tap(client, state, uid)
        time.sleep(0.05)
    return 0
