from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Cue:
    tone: str
    title: str
    detail: str


def cue_for_payload(payload: dict[str, Any]) -> Cue:
    outcome = str(payload.get("outcome") or "")
    name = str(payload.get("full_name") or "").strip()
    uid = str(payload.get("chip_uid") or "").strip()

    if outcome == "on_time":
        return Cue("ok", "On time", name)
    if outcome == "late":
        return Cue("late", "Late", name)
    if outcome == "already_signed_in":
        return Cue("info", "Already signed in", name)
    if outcome == "already_dismissed":
        return Cue("info", "Already dismissed", name)
    if outcome == "not_on_roster":
        return Cue("fail", "Not on today's roster", name)
    if outcome == "marked_absent":
        return Cue("fail", "Marked absent", "Ask a tutor to override on the named grid.")
    if outcome == "unknown_card":
        detail = uid if uid else "This card is not paired."
        return Cue("fail", "Unknown card", detail)
    return Cue("fail", "Could not sign in", "Use paper and tell a tutor.")
