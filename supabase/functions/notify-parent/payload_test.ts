import { assertEquals } from "jsr:@std/assert@1";
import { NOTIFIABLE_STATUSES, parsePayload } from "./payload.ts";

const student = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const session = "11111111-2222-3333-4444-555555555555";

Deno.test("parsePayload accepts late/absent/dismissed with valid student UUID", () => {
  for (const status of NOTIFIABLE_STATUSES) {
    const got = parsePayload(
      JSON.stringify({ student_id: student, status, session_id: session }),
    );
    assertEquals(got?.student_id, student);
    assertEquals(got?.status, status);
    assertEquals(got?.session_id, session);
  }
});

Deno.test("parsePayload rejects present and unknown statuses", () => {
  assertEquals(
    parsePayload(JSON.stringify({ student_id: student, status: "present" })),
    null,
  );
  assertEquals(
    parsePayload(JSON.stringify({ student_id: student, status: "excused" })),
    null,
  );
});

Deno.test("parsePayload rejects non-UUID student_id and malformed JSON", () => {
  assertEquals(
    parsePayload(JSON.stringify({ student_id: "not-a-uuid", status: "late" })),
    null,
  );
  assertEquals(parsePayload("{"), null);
  assertEquals(parsePayload("[]"), null);
  assertEquals(parsePayload("null"), null);
});

Deno.test("parsePayload rejects invalid optional session_id or dismissal_id", () => {
  assertEquals(
    parsePayload(
      JSON.stringify({
        student_id: student,
        status: "late",
        session_id: "bad",
      }),
    ),
    null,
  );
  assertEquals(
    parsePayload(
      JSON.stringify({
        student_id: student,
        status: "dismissed",
        dismissal_id: "nope",
      }),
    ),
    null,
  );
});
