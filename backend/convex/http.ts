import { httpRouter, type FunctionReference } from "convex/server";
import { ConvexError } from "convex/values";
import { api } from "./_generated/api";
import { httpAction } from "./_generated/server";

const http = httpRouter();
const codes: Record<string, number> = {
  sessionExpired: 401,
  TP_DISABLED: 403,
  TP_NOT_AVAILABLE: 404,
  TP_INVALID_INPUT: 400,
  TP_CONFLICT: 409,
  TP_INCOMPLETE: 409,
  TP_LOCKED: 409,
  TP_TOO_EARLY: 409,
  TP_TOO_OLD: 409,
  TP_SNOOZE_LIMIT: 409,
  TP_NO_PENDING_PROMPT: 409,
  TP_MUTATION_REUSED: 409,
};
const reply = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
function route(
  name: string,
  ref: FunctionReference<"query" | "mutation", "public">,
  kind: "query" | "mutation",
) {
  http.route({
    path: "/v2/" + name,
    method: "POST",
    handler: httpAction(async (ctx, req) => {
      if (!(await ctx.runQuery(api.auth.isAuthenticated, {})))
        return reply({ error: "sessionExpired" }, 401);
      let args;
      try {
        args = JSON.parse(await req.text());
      } catch {
        return reply({ error: "TP_INVALID_INPUT" }, 400);
      }
      if (!args || typeof args !== "object" || Array.isArray(args))
        return reply({ error: "TP_INVALID_INPUT" }, 400);
      try {
        const result =
          kind === "query"
            ? await ctx.runQuery(ref as FunctionReference<"query">, args)
            : await ctx.runMutation(ref as FunctionReference<"mutation">, args);
        return reply(result);
      } catch (e) {
        if (
          e instanceof ConvexError &&
          typeof e.data === "string" &&
          Object.hasOwn(codes, e.data)
        )
          return reply({ error: e.data }, codes[e.data]);
        if (e instanceof Error && e.message.includes("ArgumentValidationError"))
          return reply({ error: "TP_INVALID_INPUT" }, 400);
        return reply({ error: "network" }, 500);
      }
    }),
  });
}
for (const name of [
  "my_profile",
  "my_lessons_today",
  "lesson_for_prompt",
] as const)
  route(name, api.teacher[name], "query");
for (const name of [
  "mark_all_present",
  "mark_attendance",
  "save_feedback",
  "submit_lesson",
  "confirm_all_present_and_submit",
  "snooze_prompt",
] as const)
  route(name, api.teacher[name], "mutation");
for (const name of ["register_device", "unregister_device"] as const)
  route(name, api.devices[name], "mutation");
export default http;
