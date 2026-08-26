"""PC/SC NFC reader. Optional: unit tests and --once/--stdin do not import pyscard."""

from __future__ import annotations

import time
from collections.abc import Iterator

from tava_station.chip_uid import normalize_chip_uid

# ACR122U / typical CCID readers: GET DATA (UID).
_GET_UID = [0xFF, 0xCA, 0x00, 0x00, 0x00]


def iter_chip_uids(*, debounce_seconds: float = 2.0, poll_seconds: float = 0.25) -> Iterator[str]:
    try:
        from smartcard.System import readers
        from smartcard.Exceptions import CardConnectionException, NoCardException
    except ImportError as exc:
        raise RuntimeError(
            "pyscard is not installed. Use --once/--stdin, or pip install '.[nfc]'."
        ) from exc

    available = readers()
    if not available:
        raise RuntimeError("No PC/SC reader found. Plug in a USB CCID reader (for example ACR122U).")

    reader = available[0]
    last_uid = ""
    last_at = 0.0

    while True:
        connection = reader.createConnection()
        try:
            connection.connect()
            data, sw1, sw2 = connection.transmit(_GET_UID)
            if sw1 == 0x90 and sw2 == 0x00:
                uid = normalize_chip_uid(bytes(data))
                now = time.monotonic()
                if uid and (uid != last_uid or now - last_at >= debounce_seconds):
                    last_uid = uid
                    last_at = now
                    yield uid
        except (NoCardException, CardConnectionException):
            last_uid = ""
        except Exception:
            last_uid = ""
        finally:
            try:
                connection.disconnect()
            except Exception:
                pass
        time.sleep(poll_seconds)
