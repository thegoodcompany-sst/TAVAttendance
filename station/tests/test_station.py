from __future__ import annotations

import sys
import unittest
from pathlib import Path

_STATION_ROOT = Path(__file__).resolve().parents[1]
if str(_STATION_ROOT) not in sys.path:
    sys.path.insert(0, str(_STATION_ROOT))

from tava_station.chip_uid import normalize_chip_uid
from tava_station.cues import cue_for_payload


class ChipUidTests(unittest.TestCase):
    def test_colon_and_spaces(self) -> None:
        self.assertEqual(normalize_chip_uid("04:a1:b2:c3"), "04A1B2C3")
        self.assertEqual(normalize_chip_uid(" 04a1b2c3d4e5f6 "), "04A1B2C3D4E5F6")

    def test_bytes(self) -> None:
        self.assertEqual(normalize_chip_uid(bytes.fromhex("04a1b2c3")), "04A1B2C3")

    def test_rejects_garbage(self) -> None:
        self.assertIsNone(normalize_chip_uid("zzzz"))
        self.assertIsNone(normalize_chip_uid("ABC"))
        self.assertIsNone(normalize_chip_uid(""))
        self.assertIsNone(normalize_chip_uid(None))


class CueTests(unittest.TestCase):
    def test_on_time_and_unknown(self) -> None:
        ok = cue_for_payload({"outcome": "on_time", "full_name": "Alex Tan"})
        self.assertEqual(ok.tone, "ok")
        self.assertEqual(ok.detail, "Alex Tan")
        unknown = cue_for_payload({"outcome": "unknown_card", "chip_uid": "FFFFFFFF"})
        self.assertEqual(unknown.tone, "fail")
        self.assertEqual(unknown.detail, "FFFFFFFF")

    def test_fail_closed_default(self) -> None:
        cue = cue_for_payload({"outcome": "surprise"})
        self.assertEqual(cue.tone, "fail")


if __name__ == "__main__":
    unittest.main()
