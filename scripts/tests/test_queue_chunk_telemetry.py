"""Source contracts for native telemetry wiring (no native SDK required).

The batching algorithms have native unit tests. These guards cover the roster
callbacks themselves: testing a copied telemetry builder would miss a caller
accidentally passing the original queue size again.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class QueueChunkTelemetryTests(unittest.TestCase):
    def test_ios_success_event_counts_the_submitted_batch(self):
        source = (ROOT / "iOS/TAVAttendance/Views/Session/RosterView.swift").read_text()
        callback = source.split("send: { batch in", 1)[1].split("// Terminal outcomes", 1)[0]
        self.assertIn("syncPending(batch)", callback)
        self.assertIn('name: "sync_result"', callback)
        counts = re.findall(r'"pending_before":\s*\.integer\(([^)]+)\)', callback)
        # 501 queued mutations must emit 500 + 1, not 501 + 501.
        # Using the submitted batch also covers recursively split rejections.
        self.assertEqual(counts, ["batch.count"])

    def test_android_success_event_counts_the_submitted_batch(self):
        source = (ROOT / "Android/app/src/main/java/com/example/tavattendance/screens/RosterScreen.kt").read_text()
        callback = source.split("send = { batch ->", 1)[1].split("// RPC success", 1)[0]
        self.assertIn("syncPending(batch)", callback)
        self.assertIn('"sync_result"', callback)
        counts = re.findall(r'put\("pending_before",\s*([^)]+)\)', callback)
        self.assertEqual(counts, ["batch.size"])


if __name__ == "__main__":
    unittest.main()
