import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export const role = v.union(v.literal("teacher"), v.literal("admin"));
export const status = v.union(
  v.literal("present"),
  v.literal("late"),
  v.literal("absent"),
);
export const environment = v.union(
  v.literal("sandbox"),
  v.literal("production"),
);
export const kind = v.union(
  v.literal("heads_up"),
  v.literal("attendance"),
  v.literal("follow_up"),
  v.literal("final"),
);
const tag = { demo: v.optional(v.string()) };
const publicId = { ...tag, uuid: v.string() };
const lesson = { ...tag, lesson: v.id("lessons") };
const staff = v.id("profiles");
const number = v.number(),
  string = v.string(),
  bool = v.boolean();
const time = v.optional(number);
export default defineSchema({
  users: defineTable({}),
  profiles: defineTable({
    ...publicId,
    email: string,
    name: string,
    role,
    active: bool,
    user: v.optional(v.id("users")),
    invitationHash: v.optional(string),
    invitationExpires: time,
  })
    .index("email", ["email"])
    .index("user", ["user"])
    .index("uuid", ["uuid"]),
  classes: defineTable({
    ...publicId,
    label: string,
    subject: string,
    studySpace: bool,
    active: bool,
  })
    .index("label", ["label"])
    .index("demo", ["demo"]),
  students: defineTable({ ...publicId, name: string, active: bool })
    .index("uuid", ["uuid"])
    .index("demo", ["demo"]),
  enrollments: defineTable({
    ...tag,
    student: v.id("students"),
    class: v.id("classes"),
    from: string,
    until: v.optional(string),
  })
    .index("class_from", ["class", "from"])
    .index("pair", ["class", "student"])
    .index("demo", ["demo"]),
  terms: defineTable({
    ...tag,
    label: string,
    from: string,
    until: string,
  }).index("demo", ["demo"]),
  timetable_rules: defineTable({
    ...tag,
    class: v.id("classes"),
    term: v.id("terms"),
    weekday: number,
    start: string,
    minutes: number,
    from: string,
    until: string,
    teacher: staff,
    active: bool,
  })
    .index("active", ["active"])
    .index("teacher", ["teacher"])
    .index("demo", ["demo"]),
  calendar_exceptions: defineTable({
    ...tag,
    class: v.optional(v.id("classes")),
    from: string,
    until: string,
    reason: v.union(v.literal("public_holiday"), v.literal("centre_closed")),
  })
    .index("class_until", ["class", "until"])
    .index("demo", ["demo"]),
  lessons: defineTable({
    ...publicId,
    class: v.id("classes"),
    rule: v.optional(v.id("timetable_rules")),
    occurrence: string,
    start: number,
    end: number,
    lead: staff,
    revision: number,
    planRevision: number,
    snoozes: number,
    snoozedUntil: time,
    overdue: number,
    cancelled: time,
    reason: v.optional(string),
    submitted: time,
    moved: v.optional(bool),
    substituted: v.optional(bool),
  })
    .index("uuid", ["uuid"])
    .index("open", ["cancelled", "submitted"])
    .index("rule_date", ["rule", "occurrence"])
    .index("start", ["start"])
    .index("lead_start", ["lead", "start"])
    .index("class_start", ["class", "start"])
    .index("demo", ["demo"]),
  lesson_staff: defineTable({
    ...lesson,
    teacher: staff,
    assignment: v.union(
      v.literal("regular"),
      v.literal("substitute"),
      v.literal("assistant"),
    ),
  })
    .index("lesson_teacher", ["lesson", "teacher"])
    .index("demo", ["demo"]),
  lesson_roster: defineTable({
    ...lesson,
    student: v.id("students"),
    enrollment: v.id("enrollments"),
  })
    .index("lesson_student", ["lesson", "student"])
    .index("demo", ["demo"]),
  attendance: defineTable({
    ...lesson,
    student: v.id("students"),
    status,
    informed: v.union(bool, v.null()),
    actor: staff,
    at: number,
    mutation: string,
  })
    .index("lesson_student", ["lesson", "student"])
    .index("demo", ["demo"]),
  feedback: defineTable({
    ...lesson,
    body: string,
    revision: number,
    actor: staff,
    at: number,
  })
    .index("lesson", ["lesson"])
    .index("demo", ["demo"]),
  submissions: defineTable({
    ...lesson,
    uuid: string,
    revision: number,
    feedbackRevision: number,
    actor: staff,
    mutation: string,
    at: number,
  })
    .index("lesson", ["lesson"])
    .index("demo", ["demo"]),
  mutation_receipts: defineTable({
    ...lesson,
    actor: staff,
    mutation: string,
    operation: string,
    hash: string,
    result: v.record(string, v.union(string, number, bool, v.null())),
  })
    .index("actor_mutation", ["actor", "mutation"])
    .index("demo", ["demo"]),
  audit_events: defineTable({
    ...tag,
    lesson: v.optional(v.id("lessons")),
    actor: v.optional(staff),
    event: string,
  })
    .index("lesson", ["lesson"])
    .index("demo", ["demo"]),
  prompt_policy: defineTable({
    key: v.literal("default"),
    offsets: v.array(number),
    grace: number,
    maxSnoozes: number,
  }).index("key", ["key"]),
  feature_flags: defineTable({
    key: v.union(
      v.literal("teacher_prompts"),
      v.literal("teacher_prompt_push"),
    ),
    enabled: bool,
  }).index("key", ["key"]),
  runtime_settings: defineTable({
    key: v.literal("default"),
    demoEnabled: bool,
  }).index("key", ["key"]),
  notification_plans: defineTable({
    ...lesson,
    kind,
    recipient: staff,
    revision: number,
    due: number,
    available: number,
    status: v.union(
      v.literal("pending"),
      v.literal("active"),
      v.literal("completed"),
      v.literal("cancelled"),
      v.literal("superseded"),
    ),
  })
    .index("lesson_kind", ["lesson", "kind"])
    .index("status_available", ["status", "available"])
    .index("demo", ["demo"]),
  teacher_devices: defineTable({
    ...publicId,
    owner: staff,
    installation: string,
    token: string,
    environment,
    seen: number,
    revoked: time,
  })
    .index("installation_owner", ["installation", "owner"])
    .index("token", ["environment", "token"])
    .index("installation", ["owner", "installation", "environment"])
    .index("active", ["owner", "revoked", "seen"])
    .index("demo", ["demo"]),
  outbox: defineTable({
    ...lesson,
    uuid: string,
    plan: v.id("notification_plans"),
    device: v.optional(v.id("teacher_devices")),
    recipient: staff,
    status: v.union(
      v.literal("pending"),
      v.literal("claimed"),
      v.literal("sending"),
      v.literal("sent"),
      v.literal("failed"),
      v.literal("cancelled"),
    ),
    revision: number,
    available: number,
    attempts: number,
    lease: v.optional(string),
    deviceSeen: time,
  })
    .index("plan_device", ["plan", "device"])
    .index("status_available", ["status", "available"])
    .index("demo", ["demo"]),
  deliveries: defineTable({
    ...lesson,
    outbox: v.id("outbox"),
    attempt: number,
    outcome: string,
    transport: string,
    code: v.optional(string),
    provider: v.optional(string),
  })
    .index("outbox_attempt", ["outbox", "attempt"])
    .index("lesson", ["lesson"])
    .index("demo", ["demo"]),
});
