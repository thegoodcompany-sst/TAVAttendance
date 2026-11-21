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

// Fixture sanity only: Swift XCTest exercises the actual lifecycle with these rows.
import registration from "../Tests/PromptRouterTests/Fixtures/registration-v1.json";
for (const row of registration.scenarios) {
  test(`shared registration fixture: ${row.name}`, () => {
    let failures = row.failures, enabled = false, owner = false, token = false, device = false, pending = false;
    const calls: string[] = [];
    function revoke() {
      pending = true;
      for (let i = 0; i < registration.max_attempts; i++) {
        calls.push(registration.unregister_rpc);
        if (failures > 0) { failures--; continue; }
        pending = false; device = false; return;
      }
    }
    for (const event of row.events) {
      if (event === "on") { enabled = true; token = false; }
      if (event === "register" && enabled) { owner = true; calls.push(registration.register_rpc); token = true; device = true; }
      if (event === "off" || event === "signout") { const changed = enabled; enabled = false; token = false; if (changed && owner) revoke(); }
      if (event === "retry" && pending) revoke();
    }
    expect(calls).toEqual(row.calls);
    expect([pending, token, device]).toEqual([row.pending, row.has_token, row.has_device]);
    expect(registration.unregister_parameter).toBe("p_installation_id");
  });
}
