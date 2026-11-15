# Teacher prompt strings

Generated from the three source files below. They remain authoritative; every entry is stand-in copy pending Edmund’s approval. Template placeholders are shown in braces. No translated or invented values are substituted.

Push title/body strings and native notification action titles are **lock-screen visible** in a future real-push integration. This prototype sends no real push.

## Web prototype

Source: [prototypes/teacher-prompts/lib/strings.ts](../../prototypes/teacher-prompts/lib/strings.ts). **124 entries.**

| Key | Stand-in text | Where shown |
|---|---|---|
| `previewAccess` | Enter preview | [Preview entry](../../prototypes/teacher-prompts/app/preview/page.tsx) |
| `accessCode` | Access code | [Preview entry](../../prototypes/teacher-prompts/app/preview/page.tsx) |
| `invalidAccessCode` | Check the access code. | [Preview entry](../../prototypes/teacher-prompts/app/preview/page.tsx) |
| `title` | TAVA · Teacher prompts | [Page title](../../prototypes/teacher-prompts/app/layout.tsx) |
| `brand` | TAVA | [App header](../../prototypes/teacher-prompts/components/shell.tsx) |
| `demo` | Demo · fake data | [App header](../../prototypes/teacher-prompts/components/shell.tsx), [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `today` | My lessons today | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `backlog` | Still to review | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `admin` | Missing submissions | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx), [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `identity` | Choose an identity | [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `identityHelp` | Use a demo account to try a lesson. | [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `continue` | Continue | [Preview entry](../../prototypes/teacher-prompts/app/preview/page.tsx), [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `switchAccount` | Switch account | [Error boundary](../../prototypes/teacher-prompts/app/error.tsx), [App header](../../prototypes/teacher-prompts/components/shell.tsx), [Lesson page](../../prototypes/teacher-prompts/app/t/lesson/[lessonId]/page.tsx) |
| `signOut` | Sign out | [App header](../../prototypes/teacher-prompts/components/shell.tsx) |
| `signedOut` | Signed out | [App header](../../prototypes/teacher-prompts/components/shell.tsx) |
| `light` | Light | [components/theme](../../prototypes/teacher-prompts/components/theme.tsx) |
| `dark` | Dark | [components/theme](../../prototypes/teacher-prompts/components/theme.tsx) |
| `theme` | Change appearance | [components/theme](../../prototypes/teacher-prompts/components/theme.tsx) |
| `date` | Lesson date | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `show` | Show lessons | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `empty` | No lessons for this date. | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `emptyBacklog` | You are up to date. | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `outstanding` | to review | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `teacher` | Teacher | Reserved in source; no current call site |
| `attendance` | Attendance | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `review` | Review your lesson | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `progress` | marked | [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `notMarked` | Not Here Yet | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `present` | Present | Reserved in source; no current call site |
| `late` | Late | Reserved in source; no current call site |
| `absent` | Absent | Reserved in source; no current call site |
| `informed` | Informed absence | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `clear` | Clear | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `cycleHint` | Tap a status to change it. Clear returns it to Not Here Yet. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `allPresent` | All present | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `markPresentOnly` | Mark present without submitting | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirmAndSubmit` | Confirm and submit | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirmAllSubmit` | Review and submit? | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `presentSummary` | {present} present, {marked} already marked late/absent | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirmAll` | Mark all unmarked students present? | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirmAllHelp` | Existing late and absent marks stay as they are. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirm` | Confirm | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/confirm-dialog](../../prototypes/teacher-prompts/components/confirm-dialog.tsx) |
| `cancel` | Cancel | [components/confirm-dialog](../../prototypes/teacher-prompts/components/confirm-dialog.tsx) |
| `notes` | Lesson notes | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `optional` | Optional | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `notesHelp` | Lesson notes only. Leave out personal details. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `saveNotes` | Save notes | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `saved` | Saved | Reserved in source; no current call site |
| `submit` | Submit lesson | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `remaining` | still to mark | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `submitHelp` | Review every student before submitting. | Reserved in source; no current call site |
| `done` | Lesson submitted | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `doneHelp` | Your register has been reviewed. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `readOnly` | This lesson is read-only. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `cancelled` | Lesson cancelled | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `back` | Back to lessons | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx), [Lesson page](../../prototypes/teacher-prompts/app/t/lesson/[lessonId]/page.tsx) |
| `ping` | Send me a ping now | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx) |
| `preview` | Demo notification · dry run | [components/notification-banner](../../prototypes/teacher-prompts/components/notification-banner.tsx) |
| `takeAttendance` | Take attendance | [components/notification-banner](../../prototypes/teacher-prompts/components/notification-banner.tsx) |
| `remind` | Remind me in 10 | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/notification-banner](../../prototypes/teacher-prompts/components/notification-banner.tsx) |
| `snoozed` | Reminder moved by 10 minutes. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx) |
| `nextPrompt` | Next reminder | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `noPrompt` | No pending reminder | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `now` | now | [components/notification-banner](../../prototypes/teacher-prompts/components/notification-banner.tsx) |
| `unavailable` | This lesson is not available. | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx), [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx), [Lesson page](../../prototypes/teacher-prompts/app/t/lesson/[lessonId]/page.tsx) |
| `retry` | Try again | [Error boundary](../../prototypes/teacher-prompts/app/error.tsx) |
| `error` | Something went wrong. Try again. | [Error boundary](../../prototypes/teacher-prompts/app/error.tsx), [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `stale` | This lesson changed. Review the latest register. Your unsaved notes are kept here. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `saving` | Saving… | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `savedNotes` | Notes saved. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `from` | From date | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `until` | Until date | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `filter` | Apply dates | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `noMissing` | No missing submissions in this range. | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `delivery` | Demo delivery | [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `editSchedule` | Update schedule | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `start` | Starts at | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `end` | Ends at | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `substitute` | Accountable teacher | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `assign` | Assign teacher | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `cancelLesson` | Cancel lesson | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `confirmCancel` | Cancel this lesson? | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `adminTools` | Lesson administration | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `updated` | Lesson updated. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `pendingRoute` | Continue to the lesson after choosing an account. | [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `noDevices` | Reminders are optional. Your lesson list always works. | [Lesson list](../../prototypes/teacher-prompts/app/page.tsx) |
| `demoAdmin` | Demo Admin | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts), [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `demoA` | Demo Teacher A | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts) |
| `demoB` | Demo Teacher B | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts) |
| `demoC` | Demo Teacher C | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts) |
| `demoD` | Demo Teacher D | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts) |
| `demoParent` | Demo Parent | [lib/identity](../../prototypes/teacher-prompts/lib/identity.ts) |
| `selectIdentity` | Demo identity | [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx) |
| `unavailableHelp` | Choose another account or return to your lessons. | [Demo identity selector](../../prototypes/teacher-prompts/app/demo/page.tsx), [Lesson page](../../prototypes/teacher-prompts/app/t/lesson/[lessonId]/page.tsx) |
| `confirmSubmit` | Submit the reviewed register | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `submitNotice` | Submission records a review, not a dismissal. | [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx) |
| `close` | Close notification | [components/notification-banner](../../prototypes/teacher-prompts/components/notification-banner.tsx) |
| `statusLabel` | Attendance status | Reserved in source; no current call site |
| `savedReadOnly` | Submitted register | Reserved in source; no current call site |
| `locale` | en-SG | Date/time formatting locale — [lib/format](../../prototypes/teacher-prompts/lib/format.ts) |
| `timezone` | Asia/Singapore | Date/time formatting timezone — [lib/format](../../prototypes/teacher-prompts/lib/format.ts) |
| `noRole` | Choose an account to continue. | Reserved in source; no current call site |
| `states.scheduled` | Scheduled | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `states.in_progress` | In progress | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `states.awaiting_attendance` | Ready for review | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `states.overdue` | Needs review | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `states.submitted` | Submitted | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `states.cancelled` | Cancelled | Lesson state label — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [Lesson card](../../prototypes/teacher-prompts/components/lesson-card.tsx) |
| `deliveries.not_attempted` | Not attempted | Admin delivery status — [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `deliveries.accepted` | Accepted · dry run | Admin delivery status — [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `deliveries.failed` | Failed · dry run | Admin delivery status — [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `deliveries.no_devices` | No devices | Admin delivery status — [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `deliveries.pending` | Pending · dry run | Admin delivery status — [Admin outstanding list](../../prototypes/teacher-prompts/app/admin/page.tsx) |
| `errors.TP_DISABLED` | This demo is turned off. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_NOT_AVAILABLE` | This lesson is not available. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_CONFLICT` | This lesson changed. Review the latest register. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_INCOMPLETE` | Mark every student before submitting. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_LOCKED` | This lesson is read-only. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_TOO_EARLY` | This lesson has not started. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_TOO_OLD` | Ask an admin to review this lesson. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_SNOOZE_LIMIT` | No more reminders can be postponed. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_NO_PENDING_PROMPT` | There is no pending reminder. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_MUTATION_REUSED` | Refresh the lesson and try again. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |
| `errors.TP_INVALID_INPUT` | Check the details and try again. | RPC error message — [Attendance review](../../prototypes/teacher-prompts/components/lesson-review.tsx), [components/prompt-preview](../../prototypes/teacher-prompts/components/prompt-preview.tsx), [lib/rpc](../../prototypes/teacher-prompts/lib/rpc.ts), [app/actions/lessons](../../prototypes/teacher-prompts/app/actions/lessons.ts) |

## Push and dispatcher

Source: [supabase/v2/functions/_shared/prompt-strings.ts](../../supabase/v2/functions/_shared/prompt-strings.ts). **11 entries.**

| Key | Stand-in text | Where shown |
|---|---|---|
| `title` | TAVA | **Lock-screen visible:** notification title; also simulated notification |
| `bodies.heads_up` | Your lesson ends soon. | **Lock-screen visible:** notification heads_up body; also simulated notification |
| `bodies.attendance` | Please take attendance. | **Lock-screen visible:** notification attendance body; also simulated notification |
| `bodies.follow_up` | Please review your lesson. | **Lock-screen visible:** notification follow_up body; also simulated notification |
| `bodies.final` | Your lesson is waiting for review. | **Lock-screen visible:** notification final body; also simulated notification |
| `methodNotAllowed` | Method not allowed. | [teacher-prompt-dispatch/index](../../supabase/v2/functions/teacher-prompt-dispatch/index.ts) |
| `forbidden` | Not allowed. | [teacher-prompt-dispatch/index](../../supabase/v2/functions/teacher-prompt-dispatch/index.ts) |
| `invalidRequest` | Invalid request. | [teacher-prompt-dispatch/index](../../supabase/v2/functions/teacher-prompt-dispatch/index.ts) |
| `unavailable` | Service unavailable. | [teacher-prompt-dispatch/index](../../supabase/v2/functions/teacher-prompt-dispatch/index.ts) |
| `calendarRefreshFailed` | Calendar refresh failed. Retrying next tick. | [teacher-prompt-dispatch/local](../../supabase/v2/functions/teacher-prompt-dispatch/local.ts) |
| `workerFailed` | Worker failed. | [teacher-prompt-dispatch/local](../../supabase/v2/functions/teacher-prompt-dispatch/local.ts) |

## iOS app and shared router

Source: [PromptStrings.swift](ios/Sources/PromptRouter/PromptStrings.swift). All values
below are **stand-in copy; Edmund approval pending**. New native keys reuse existing
web copy where suitable. UI strings are never authored in view/service files.

| Key | Stand-in text | Approval |
|---|---|---|
| `title` | TAVA | Pending |
| `takeAttendance` | Take attendance | Pending |
| `snoozeTen` | Remind me in 10 | Pending |
| `confirmSnooze` | Remind you in 10 minutes? | Pending |
| `cancel` | Cancel | Pending |
| `signIn` | Sign in to view your lesson. | Pending |
| `unlock` | Unlock to view your lesson. | Pending |
| `loading` | Loading lesson. | Pending |
| `unavailable` | This lesson is not available. | Pending |
| `retry` | Try again | Pending |
| `chooseAccount` | Choose account | Pending |
| `todaysLessons` | Today's lessons | Pending |
| `pushUnavailable` | Open today's lessons to continue. | Pending |
| `storageUnavailable` | Open the lesson link again. | Pending |
| `demo` | Demo · fake data | Pending |
| `myLessons` | My lessons | Pending |
| `backlog` | Still to review | Pending |
| `outstanding` | to review | Pending |
| `empty` | No lessons for this date. | Pending |
| `noDevices` | Reminders are optional. Your lesson list always works. | Pending |
| `enableReminders` | Lesson reminders | Pending |
| `attendance` | Attendance | Pending |
| `notMarked` | Not Here Yet | Pending |
| `present` | Present | Pending |
| `late` | Late | Pending |
| `absent` | Absent | Pending |
| `informed` | Informed absence | Pending |
| `clear` | Clear | Pending |
| `allPresent` | All present | Pending |
| `confirmAndSubmit` | Confirm and submit | Pending |
| `allPresentReview` | Review these marks, make any adjustments, then confirm and submit. | Pending |
| `allPresentHelp` | Existing late and absent marks stay as they are. | Pending |
| `notes` | Lesson notes | Pending |
| `notesHelp` | Lesson notes only. Leave out personal details. | Pending |
| `saveNotes` | Save notes | Pending |
| `submit` | Submit lesson | Pending |
| `done` | Lesson submitted | Pending |
| `doneHelp` | Your register has been reviewed. | Pending |
| `readOnly` | This lesson is read-only. | Pending |
| `back` | Back to lessons | Pending |
| `snoozed` | Reminder moved by 10 minutes. | Pending |
| `networkError` | Something went wrong. Try again. | Pending |
| `stale` | This lesson changed. Review the latest register. Your unsaved notes are kept here. | Pending |
| `incomplete` | Mark every student before submitting. | Pending |
| `tooEarly` | This lesson has not started. | Pending |
| `tooOld` | Ask an admin to review this lesson. | Pending |
| `snoozeLimit` | No more reminders can be postponed. | Pending |
| `noPrompt` | There is no pending reminder. | Pending |
| `refreshLesson` | Refresh the lesson and try again. | Pending |
| `invalid` | Check the details and try again. | Pending |
| `disabled` | Lesson review is turned off. | Pending |
| `scheduled` | Scheduled | Pending |
| `inProgress` | In progress | Pending |
| `awaitingAttendance` | Ready for review | Pending |
| `overdue` | Needs review | Pending |
| `submitted` | Submitted | Pending |
| `cancelled` | Cancelled | Pending |
| `signOut` | Sign out | Pending |
| `demoClass` | Demo Mathematics | Pending |
| `demoTeacher` | Demo Teacher | Pending |
| `demoStudentPrefix` | Demo Student | Pending |
| `feedbackLimit` | Use 1000 characters or fewer. | Pending |
| `optional` | Optional | Pending |

`takeAttendance` and `snoozeTen` are lock-screen-visible action titles. Payload bodies remain in the dispatcher source above. Protocol action/category identifiers are not copy.
