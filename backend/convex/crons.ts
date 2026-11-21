import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";
const crons = cronJobs();
crons.interval(
  "dispatch due teacher prompts",
  { minutes: 1 },
  internal.queue.tick,
  {},
);
crons.daily(
  "generate six weeks of lessons",
  { hourUTC: 16, minuteUTC: 5 },
  internal.calendar.generate_lessons,
  {},
);
export default crons;
