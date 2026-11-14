#!/usr/bin/env python3
"""Offline fixture sanity check, NOT a Swift compiler/state-machine test.

Web tests can read the same JSON manifest; no app/DB/server is imported here.
"""
import json
from pathlib import Path
import re
import unittest

FIXTURES = json.loads((Path(__file__).parent / "Tests/PromptRouterTests/Fixtures/routes-v1.json").read_text())
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
DEFAULT_ACTION = "com.apple.UNNotificationDefaultActionIdentifier"


def parse_link(value):
    prefixes = [f"https://{host}/t/lesson/" for host in FIXTURES["approved_hosts"]]
    prefixes.append("tava://teacher/lesson/")
    for prefix in prefixes:
        match = re.fullmatch(re.escape(prefix) + "(" + UUID + ")", value)
        if match:
            return match[1]
    return None


def parse_payload(payload, action):
    if action == DEFAULT_ACTION:
        action = "TAKE_ATTENDANCE"
    if action not in {"TAKE_ATTENDANCE", "SNOOZE_10"}:
        return None, None
    if set(payload) != {"aps", "v", "type", "lesson_id", "kind"}:
        return None, None
    if type(payload["v"]) not in (int, float) or payload["v"] != 1:
        return None, None
    lesson = payload["lesson_id"]
    if not isinstance(lesson, str) or not re.fullmatch(UUID, lesson):
        return None, None
    if payload["type"] != "teacher_prompt" or payload["kind"] not in {"heads_up", "attendance", "follow_up", "final"}:
        return None, None
    aps = payload["aps"]
    if not isinstance(aps, dict) or set(aps) != {"alert", "sound", "category", "thread-id"}:
        return None, None
    if (aps["category"], aps["sound"], aps["thread-id"]) != ("TAVA_TEACHER_PROMPT", "default", "teacher-lesson:" + lesson):
        return None, None
    alert = aps["alert"]
    if not isinstance(alert, dict) or set(alert) != {"title", "body"} or not all(isinstance(v, str) for v in alert.values()):
        return None, None
    return lesson, action


class FixtureTests(unittest.TestCase):
    pass


def url_test(row):
    def run(self):
        self.assertEqual(parse_link(row["input"]), row["lesson_id"])
    return run


def payload_test(row):
    def run(self):
        self.assertEqual(parse_payload(row["user_info"], row["action_identifier"]), (row["lesson_id"], row["action"]))
    return run


for fixture in FIXTURES["urls"]:
    setattr(FixtureTests, "test_url_" + fixture["name"], url_test(fixture))
for fixture in FIXTURES["payloads"]:
    setattr(FixtureTests, "test_payload_" + fixture["name"], payload_test(fixture))

if __name__ == "__main__":
    unittest.main(verbosity=2)
