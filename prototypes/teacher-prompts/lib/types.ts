export type Status = "present" | "late" | "absent" | null;
export type Lesson = {
  lesson_id: string;
  class_id: string;
  class_label: string;
  scheduled_start_at: string;
  scheduled_end_at: string;
  state:
    | "scheduled"
    | "in_progress"
    | "awaiting_attendance"
    | "overdue"
    | "submitted"
    | "cancelled";
  accountable_teacher_id: string;
  accountable_teacher_label: string;
  is_accountable: boolean;
  register_revision: string;
  roster_count: number;
  marked_count: number;
  submitted_at: string | null;
  next_prompt_at: string | null;
  snoozed_until: string | null;
  overdue_at: string;
  can_edit: boolean;
  can_submit: boolean;
  can_snooze: boolean;
};
export type Student = {
  student_id: string;
  display_name: string;
  status: Status;
  absence_informed: boolean | null;
  marked_at: string | null;
};
export type Detail = {
  server_now: string;
  lesson: Lesson;
  roster: Student[];
  feedback: { body: string; revision: string };
  submission: {
    id: string;
    submitted_at: string;
    submitted_by: string;
    register_revision: string;
  } | null;
};
export type Today = {
  server_now: string;
  date: string;
  lessons: Lesson[];
  outstanding_count: number;
  backlog: Lesson[];
};
export type Missing = {
  server_now: string;
  from: string;
  until: string;
  lessons: (Lesson & {
    delivery_state:
      "not_attempted" | "accepted" | "failed" | "no_devices" | "pending";
    last_attempt_at: string | null;
  })[];
};
export type Result<T> = { ok: true; data: T } | { ok: false; code: string };
