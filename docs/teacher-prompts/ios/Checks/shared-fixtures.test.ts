// Offline parity check: import only pure modules, never DB/config/server code.
import { expect, test } from "bun:test";
import { pendingPath } from "../../../../prototypes/teacher-prompts/lib/identity.ts";
import { buildPromptPayload, type PromptKind } from "../../../../supabase/v2/functions/_shared/prompt-payload.ts";
import fixtures from "../Tests/PromptRouterTests/Fixtures/routes-v1.json";

// Web accepts relative next paths; native accepts only approved absolute links.
// Preserve raw path bytes so decoding/canonicalization cannot hide invalid input.
for (const row of fixtures.urls) {
  test(`shared web route fixture: ${row.name}`, () => {
    let relative = row.input;
    for (const host of fixtures.approved_hosts) {
      if (relative.startsWith(`https://${host}/`)) {
        relative = relative.slice(`https://${host}`.length);
        break;
      }
    }
    if (relative.startsWith("tava://teacher/lesson/")) {
      relative = relative.replace("tava://teacher/lesson/", "/t/lesson/");
    }
    const expected = row.lesson_id ? `/t/lesson/${row.lesson_id}`
      : row.name === "relative" ? row.input : null;
    expect(pendingPath(relative)).toBe(expected);
  });
}

for (const row of fixtures.payloads.filter(row => row.lesson_id !== null)) {
  test(`shared dispatcher payload fixture: ${row.name}`, () => {
    expect(buildPromptPayload(row.lesson_id!, row.user_info.kind as PromptKind)).toEqual(row.user_info);
  });
}
