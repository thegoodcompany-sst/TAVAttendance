import { it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import ts from "typescript";
import {
  buildPromptPayload,
  lessonPath,
} from "../../../supabase/v2/functions/_shared/prompt-payload";
const root = new URL("..", import.meta.url).pathname;
function files(path: string): string[] {
  return readdirSync(path, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? files(join(path, entry.name))
      : [join(path, entry.name)],
  );
}
it("centralizes visible JSX copy and literal aria labels", () => {
  const violations: string[] = [];
  for (const path of [
    ...files(join(root, "app")),
    ...files(join(root, "components")),
  ].filter((p) => p.endsWith(".tsx"))) {
    const source = ts.createSourceFile(
      path,
      readFileSync(path, "utf8"),
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TSX,
    );
    function visit(node: ts.Node) {
      if (ts.isJsxText(node) && /[A-Za-z]{2}/.test(node.text.trim()))
        violations.push(path + ":" + node.text.trim());
      if (
        ts.isJsxAttribute(node) &&
        ["aria-label", "placeholder", "title"].includes(
          node.name.getText(source),
        ) &&
        node.initializer &&
        ts.isStringLiteral(node.initializer)
      )
        violations.push(path + ":" + node.initializer.text);
      ts.forEachChild(node, visit);
    }
    visit(source);
  }
  expect(violations).toEqual([]);
});
it("uses only the approved palette", () => {
  const css = readFileSync(join(root, "app/globals.css"), "utf8");
  expect(css).not.toMatch(/\b(red|orange|amber|rose)\b/i);
  for (const hex of css.matchAll(/#([0-9a-f]{6})(?:[0-9a-f]{2})?\b/gi)) {
    const [r, g, b] = [0, 2, 4].map((i) =>
      parseInt(hex[1].slice(i, i + 2), 16),
    );
    expect(r > g * 1.25 && r > b * 1.25 && r > 120).toBe(false);
  }
});
it("uses a generic allowlisted push with only lesson UUID in links", () => {
  const id = "10000000-0000-4000-8000-000000000001";
  const payload = buildPromptPayload(id, "attendance");
  expect(Object.keys(payload).sort()).toEqual([
    "aps",
    "kind",
    "lesson_id",
    "type",
    "v",
  ]);
  expect(JSON.stringify(payload)).not.toMatch(
    /student|teacher A|class_label|token/i,
  );
  expect(lessonPath(id)).toBe("/t/lesson/" + id);
  expect(() => lessonPath("../admin")).toThrow();
});
