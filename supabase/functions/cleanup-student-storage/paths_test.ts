import { assertEquals } from "jsr:@std/assert@1";
import {
  canonicalUuid,
  joinStoragePath,
  normalizeUuidLike,
  rootNameMatchesStudent,
} from "./paths.ts";

const hex = "aaaaaaaabbbbccccddddeeeeeeeeeeee";
const canonical = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

Deno.test("normalizeUuidLike accepts hyphenated, bare hex, braced, and upper case", () => {
  assertEquals(normalizeUuidLike(canonical), hex);
  assertEquals(normalizeUuidLike(hex), hex);
  assertEquals(normalizeUuidLike(`{${canonical}}`), hex);
  assertEquals(normalizeUuidLike(canonical.toUpperCase()), hex);
});

Deno.test("normalizeUuidLike rejects non-UUID root names", () => {
  assertEquals(normalizeUuidLike("photos"), null);
  assertEquals(normalizeUuidLike("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee"), null);
  assertEquals(normalizeUuidLike(`${canonical}/extra`), null);
});

Deno.test("canonicalUuid formats the storage prefix used for student folders", () => {
  assertEquals(canonicalUuid(hex), canonical);
});

Deno.test("rootNameMatchesStudent only matches equivalent UUID spellings", () => {
  assertEquals(rootNameMatchesStudent(canonical, hex), true);
  assertEquals(rootNameMatchesStudent(hex, hex), true);
  assertEquals(rootNameMatchesStudent(`{${canonical.toUpperCase()}}`, hex), true);
  assertEquals(rootNameMatchesStudent("other-student-folder", hex), false);
  assertEquals(
    rootNameMatchesStudent("aaaaaaaa-bbbb-cccc-dddd-ffffffffffff", hex),
    false,
  );
});

Deno.test("joinStoragePath builds nested storage keys", () => {
  assertEquals(joinStoragePath("", "file.pdf"), "file.pdf");
  assertEquals(joinStoragePath(canonical, "slip.pdf"), `${canonical}/slip.pdf`);
});
