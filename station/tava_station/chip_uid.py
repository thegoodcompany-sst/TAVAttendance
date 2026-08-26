"""Normalize an NFC chip UID the same way as public.normalize_nfc_chip_uid."""

from __future__ import annotations

import re

_HEX = re.compile(r"[^0-9A-Fa-f]")


def normalize_chip_uid(raw: str | bytes | bytearray | None) -> str | None:
    if raw is None:
        return None
    if isinstance(raw, (bytes, bytearray)):
        hex_str = bytes(raw).hex().upper()
    else:
        hex_str = _HEX.sub("", str(raw)).upper()
    if not 8 <= len(hex_str) <= 20 or len(hex_str) % 2 != 0:
        return None
    if any(ch not in "0123456789ABCDEF" for ch in hex_str):
        return None
    return hex_str
