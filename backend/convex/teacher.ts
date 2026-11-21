import { v } from "convex/values";
import { query, mutation, type MutationCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import {
  actor,
  dateSG,
  day,
  digest,
  editError,
  fail,
  iso,
  midnight,
  minute,
  review,
  uuid,
} from "./lib/common";
import { closePlans, planLesson, plansFor, policy } from "./lib/planner";
import { summary, rosterFor, marksFor, feedbackFor } from "./lib/projection";
import { status } from "./schema";

const id = { p_lesson_id: v.string() },
  base = { ...id, p_mutation_id: v.string() },
  register = { ...base, p_expected_revision: v.string() },
  submitArgs = { ...register, p_expected_feedback_revision: v.string() };

export const my_profile = query({
  args: {},
  handler: async (ctx) => {
    const p = await actor(ctx);
    return { id: p.uuid, display_name: p.name, role: p.role, active: p.active };
  },
});
export const my_lessons_today = query({
  args: { p_date: v.optional(v.union(v.string(), v.null())) },
  handler: async (ctx, { p_date }) => {
    const p = await actor(ctx),
      now = Date.now(),
      date = p_date ?? dateSG(now),
      start = midnight(date),
      from = start - (p.role === "admin" ? 92 : 7) * day,
      end = start + day;
    const rows =
      p.role === "admin"
        ? await ctx.db
            .query("lessons")
            .withIndex("start", (q) => q.gte("start", from).lt("start", end))
            .collect()
        : await ctx.db
            .query("lessons")
            .withIndex("lead_start", (q) =>
              q.eq("lead", p._id).gte("start", from).lt("start", end),
            )
            .collect();
    type Summary = Awaited<ReturnType<typeof summary>>;
    const lessons: Summary[] = [],
      backlog: Summary[] = [];
    let outstanding_count = 0;
    for (const l of rows) {
      if (
        (await ctx.db.get(l.class))?.studySpace !== false ||
        (l.start < start &&
          (l.cancelled !== undefined || l.submitted !== undefined))
      )
        continue;
      (l.start < start ? backlog : lessons).push(await summary(ctx, l, p));
      if (
        l.start <= now &&
        l.cancelled === undefined &&
        l.submitted === undefined
      )
        outstanding_count++;
    }
    return { server_now: iso(now), date, lessons, backlog, outstanding_count };
  },
});
export const lesson_for_prompt = query({
  args: id,
  handler: async (ctx, { p_lesson_id }) => {
    const { l, p } = await review(ctx, p_lesson_id);
    const [members, marks, f, s] = await Promise.all([
      rosterFor(ctx, l._id),
      marksFor(ctx, l._id),
      feedbackFor(ctx, l._id),
      ctx.db
        .query("submissions")
        .withIndex("lesson", (q) => q.eq("lesson", l._id))
        .unique(),
    ]);
    const byStudent = new Map(marks.map((m) => [m.student, m]));
    const roster = await Promise.all(
      members.map(async (r) => {
        const student = (await ctx.db.get(r.student))!,
          mark = byStudent.get(r.student);
        return {
          student_id: student.uuid,
          display_name: student.name,
          status: mark?.status ?? null,
          absence_informed: mark?.informed ?? null,
          marked_at: mark ? iso(mark.at) : null,
        };
      }),
    );
    roster.sort(
      (a, b) =>
        a.display_name.localeCompare(b.display_name) ||
        a.student_id.localeCompare(b.student_id),
    );
    return {
      server_now: iso(Date.now()),
      lesson: await summary(ctx, l, p),
      roster,
      feedback: { body: f?.body ?? "", revision: String(f?.revision ?? 0) },
      submission: s
        ? {
            id: s.uuid,
            submitted_at: iso(s.at),
            submitted_by: (await ctx.db.get(s.actor))!.uuid,
            register_revision: String(s.revision),
          }
        : null,
    };
  },
});

type Result = Doc<"mutation_receipts">["result"];
type Work = { l: Doc<"lessons">; p: Doc<"profiles">; mutation: string };
async function write<R extends Result>(
  ctx: MutationCtx,
  args: { p_lesson_id: string; p_mutation_id: string },
  op: string,
  fn: (work: Work) => Promise<R>,
): Promise<R & { lesson_id: string; replayed: boolean }> {
  const { l, p } = await review(ctx, args.p_lesson_id),
    mutation = uuid(args.p_mutation_id);
  const hash = await digest(
    JSON.stringify([
      op,
      Object.entries(args)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => [k, k.endsWith("_id") ? uuid(String(v)) : v]),
    ]),
  );
  const receipt = await ctx.db
    .query("mutation_receipts")
    .withIndex("actor_mutation", (q) =>
      q.eq("actor", p._id).eq("mutation", mutation),
    )
    .unique();
  if (receipt) {
    if (receipt.hash !== hash) fail("TP_MUTATION_REUSED");
    // Matching operation and request hash establish the stored response type.
    return { ...(receipt.result as R), lesson_id: l.uuid, replayed: true };
  }
  const error = editError(l, p.role === "admin");
  if (error) fail(error);
  const result = {
    ...(await fn({ p, l, mutation })),
    lesson_id: l.uuid,
    replayed: false,
  };
  await ctx.db.insert("mutation_receipts", {
    lesson: l._id,
    actor: p._id,
    mutation,
    operation: op,
    hash,
    result,
    demo: l.demo,
  });
  await ctx.db.insert("audit_events", {
    lesson: l._id,
    actor: p._id,
    event: op,
    demo: l.demo,
  });
  return result;
}
function revision(actual: number, expected: string) {
  if (String(actual) !== expected) fail("TP_CONFLICT");
}

export const mark_attendance = mutation({
  args: {
    ...register,
    p_student_id: v.string(),
    p_status: v.union(status, v.null()),
    p_absence_informed: v.union(v.boolean(), v.null()),
    p_observed_marked_at: v.union(v.string(), v.null()),
  },
  handler: (ctx, a) =>
    write(ctx, a, "mark_attendance", async ({ l, p, mutation }) => {
      revision(l.revision, a.p_expected_revision);
      const student = await ctx.db
        .query("students")
        .withIndex("uuid", (q) => q.eq("uuid", uuid(a.p_student_id)))
        .unique();
      if (
        !student ||
        !(await ctx.db
          .query("lesson_roster")
          .withIndex("lesson_student", (q) =>
            q.eq("lesson", l._id).eq("student", student._id),
          )
          .unique()) ||
        (a.p_status !== "absent" && a.p_absence_informed !== null)
      )
        fail("TP_INVALID_INPUT");
      const row = await ctx.db
        .query("attendance")
        .withIndex("lesson_student", (q) =>
          q.eq("lesson", l._id).eq("student", student._id),
        )
        .unique();
      if ((row ? iso(row.at) : null) !== a.p_observed_marked_at)
        fail("TP_CONFLICT");
      let at = row?.at,
        rev = l.revision;
      if (
        (row?.status ?? null) !== a.p_status ||
        (row?.informed ?? null) !== a.p_absence_informed
      ) {
        if (a.p_status === null) {
          await ctx.db.delete(row!._id);
          at = undefined;
        } else {
          at = Math.max(Date.now(), (row?.at ?? 0) + 1);
          const fields = {
            status: a.p_status,
            informed: a.p_absence_informed,
            at,
            actor: p._id,
            mutation,
          };
          if (row) await ctx.db.patch(row._id, fields);
          else
            await ctx.db.insert("attendance", {
              ...fields,
              lesson: l._id,
              student: student._id,
              demo: l.demo,
            });
        }
        rev++;
        await ctx.db.patch(l._id, { revision: rev });
      }
      return {
        student_id: student.uuid,
        status: a.p_status,
        absence_informed: a.p_absence_informed,
        marked_at: at === undefined ? null : iso(at),
        register_revision: String(rev),
      };
    }),
});
async function fill(ctx: MutationCtx, { l, p, mutation }: Work) {
  const marked = new Set((await marksFor(ctx, l._id)).map((m) => m.student)),
    roster = await rosterFor(ctx, l._id);
  const missing = roster.filter((r) => !marked.has(r.student));
  for (const r of missing)
    await ctx.db.insert("attendance", {
      lesson: l._id,
      student: r.student,
      status: "present",
      informed: null,
      at: Date.now(),
      actor: p._id,
      mutation,
      demo: l.demo,
    });
  const rev = l.revision + Number(missing.length > 0);
  if (rev !== l.revision) await ctx.db.patch(l._id, { revision: rev });
  return { changed_count: missing.length, register_revision: String(rev) };
}
export const mark_all_present = mutation({
  args: register,
  handler: (ctx, a) =>
    write(ctx, a, "mark_all_present", (w) => {
      revision(w.l.revision, a.p_expected_revision);
      return fill(ctx, w);
    }),
});
export const save_feedback = mutation({
  args: {
    ...base,
    p_body: v.string(),
    p_expected_feedback_revision: v.string(),
  },
  handler: (ctx, a) =>
    write(ctx, a, "save_feedback", async ({ l, p }) => {
      const prior = await feedbackFor(ctx, l._id),
        body = a.p_body.trim();
      revision(prior?.revision ?? 0, a.p_expected_feedback_revision);
      if ([...body].length > 1000 || /[stfgm]\d{7}[a-z]/i.test(body))
        fail("TP_INVALID_INPUT");
      const fields = {
        body,
        revision: (prior?.revision ?? 0) + 1,
        actor: p._id,
        at: Date.now(),
      };
      if (prior) await ctx.db.patch(prior._id, fields);
      else
        await ctx.db.insert("feedback", {
          ...fields,
          lesson: l._id,
          demo: l.demo,
        });
      return { feedback_revision: String(fields.revision) };
    }),
});
function submission(confirm: boolean) {
  return mutation({
    args: submitArgs,
    handler: (ctx, a) =>
      write(
        ctx,
        a,
        confirm ? "confirm_all_present_and_submit" : "submit_lesson",
        async (w) => {
          const { l, p, mutation } = w,
            f = await feedbackFor(ctx, l._id);
          revision(l.revision, a.p_expected_revision);
          revision(f?.revision ?? 0, a.p_expected_feedback_revision);
          const roster = await rosterFor(ctx, l._id);
          if (
            (!roster.length && p.role !== "admin") ||
            (!confirm && roster.length !== (await marksFor(ctx, l._id)).length)
          )
            fail("TP_INCOMPLETE");
          const rev = confirm
            ? Number((await fill(ctx, w)).register_revision)
            : l.revision;
          const id = crypto.randomUUID(),
            at = Date.now();
          await ctx.db.insert("submissions", {
            lesson: l._id,
            uuid: id,
            actor: p._id,
            mutation,
            at,
            revision: rev,
            feedbackRevision: f?.revision ?? 0,
            demo: l.demo,
          });
          await ctx.db.patch(l._id, { submitted: at });
          await closePlans(ctx, l._id);
          return {
            submission_id: id,
            submitted_at: iso(at),
            register_revision: String(rev),
          };
        },
      ),
  });
}
export const submit_lesson = submission(false);
export const confirm_all_present_and_submit = submission(true);
export const snooze_prompt = mutation({
  args: { ...base, p_minutes: v.number() },
  handler: (ctx, a) =>
    write(ctx, a, "snooze_prompt", async ({ l }) => {
      if (a.p_minutes !== 10) fail("TP_INVALID_INPUT");
      const now = Date.now(),
        base = Math.max(now, l.snoozedUntil ?? 0),
        until = Math.min(l.end + 60 * minute, base + 10 * minute);
      if (now < l.end - 5 * minute) fail("TP_TOO_EARLY");
      if (l.snoozes >= (await policy(ctx)).maxSnoozes || until <= base)
        fail("TP_SNOOZE_LIMIT");
      const pending = (await plansFor(ctx, l._id)).filter(
        (p) => p.status === "pending" || p.status === "active",
      );
      if (!pending.length) fail("TP_NO_PENDING_PROMPT");
      await ctx.db.patch(l._id, {
        snoozedUntil: until,
        snoozes: l.snoozes + 1,
        planRevision: l.planRevision + 1,
      });
      await planLesson(ctx, l._id);
      const next = (await plansFor(ctx, l._id))
        .filter((p) => p.status === "pending")
        .map((p) => p.due);
      return {
        snoozed_until: iso(until),
        next_prompt_at: next.length ? iso(Math.min(...next)) : null,
        overdue_at: iso((await ctx.db.get(l._id))!.overdue),
      };
    }),
});
