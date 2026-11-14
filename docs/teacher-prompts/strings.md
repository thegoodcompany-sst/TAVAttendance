# Stand-in wording for Edmund

Every entry below is **pending Edmund’s approval**. This inventory starts from the
contract’s required wording and the available per-surface source files; it is a
review snapshot, not a second runtime strings source. The supervisor refreshes it
after integration and when wording changes. Keys must be changed in their owning
strings file and this inventory regenerated, never copied into components.

| Surface | Authoritative source | Scope |
|---|---|---|
| Web | [`lib/strings.ts`](../../prototypes/teacher-prompts/lib/strings.ts) | UI, errors, accessibility labels, identity labels, state/delivery labels, metadata; `s` export. |
| Push/dispatcher | [`prompt-strings.ts`](../../supabase/v2/functions/_shared/prompt-strings.ts) | Generic notification bodies/title and dispatcher response wording; `promptStrings` export. |
| iOS sketch | [`PromptStrings.swift`](ios/Sources/PromptRouter/PromptStrings.swift) | Native action labels, route/auth/error text; `PromptStrings` namespace. |

The four push bodies and action labels match the contract. No student, teacher or
class names, class labels, attendance counts/statuses, feedback or auth links may
be interpolated into push text. `TAVA_TEACHER_PROMPT`, `TAKE_ATTENDANCE`, `SNOOZE_10`
and route paths are protocol identifiers, not copy to translate.

Formatting placeholders (dates/times/counts), authenticated database class labels
and fake roster names are data, not extra component strings. Demo fixture children
are `Demo Student 01` through `Demo Student 30`; these invented seed labels are not
push copy. `locale` and `timezone` below are formatting settings, included so the
source inventory is complete. English/Mathematics/Reading/Science are fixture
class labels. No real names or school schedules are represented by those fixtures.

The contract describes “Still teaching” as optional explanatory copy for the same
snooze action; it is not a separate RPC or a required second button. No separate
source key exists for it at this snapshot. Additional strings introduced during
parallel work must be added by the supervisor’s final inventory refresh.

## Web

117 entries.

| Key | Stand-in value | Edmund approval |
|---|---|---|
| `s.title` | TAVA · Teacher prompts | Pending |
| `s.brand` | TAVA | Pending |
| `s.demo` | Demo · fake data | Pending |
| `s.today` | My lessons today | Pending |
| `s.backlog` | Still to review | Pending |
| `s.admin` | Missing submissions | Pending |
| `s.identity` | Choose an identity | Pending |
| `s.identityHelp` | Use a demo account to try a lesson. | Pending |
| `s.continue` | Continue | Pending |
| `s.switchAccount` | Switch account | Pending |
| `s.signOut` | Sign out | Pending |
| `s.signedOut` | Signed out | Pending |
| `s.light` | Light | Pending |
| `s.dark` | Dark | Pending |
| `s.theme` | Change appearance | Pending |
| `s.date` | Lesson date | Pending |
| `s.show` | Show lessons | Pending |
| `s.empty` | No lessons for this date. | Pending |
| `s.emptyBacklog` | You are up to date. | Pending |
| `s.outstanding` | to review | Pending |
| `s.teacher` | Teacher | Pending |
| `s.attendance` | Attendance | Pending |
| `s.review` | Review your lesson | Pending |
| `s.progress` | marked | Pending |
| `s.notMarked` | Not Here Yet | Pending |
| `s.present` | Present | Pending |
| `s.late` | Late | Pending |
| `s.absent` | Absent | Pending |
| `s.informed` | Informed absence | Pending |
| `s.clear` | Clear | Pending |
| `s.cycleHint` | Tap a status to change it. Clear returns it to Not Here Yet. | Pending |
| `s.allPresent` | Mark remaining present | Pending |
| `s.confirmAll` | Mark all unmarked students present? | Pending |
| `s.confirmAllHelp` | Existing late and absent marks stay as they are. | Pending |
| `s.confirm` | Confirm | Pending |
| `s.cancel` | Cancel | Pending |
| `s.notes` | Lesson notes | Pending |
| `s.optional` | Optional | Pending |
| `s.notesHelp` | Lesson notes only. Leave out personal details. | Pending |
| `s.saveNotes` | Save notes | Pending |
| `s.saved` | Saved | Pending |
| `s.submit` | Submit lesson | Pending |
| `s.remaining` | still to mark | Pending |
| `s.submitHelp` | Review every student before submitting. | Pending |
| `s.done` | Lesson submitted | Pending |
| `s.doneHelp` | Your register has been reviewed. | Pending |
| `s.readOnly` | This lesson is read-only. | Pending |
| `s.cancelled` | Lesson cancelled | Pending |
| `s.back` | Back to lessons | Pending |
| `s.ping` | Send me a ping now | Pending |
| `s.preview` | Demo notification · dry run | Pending |
| `s.takeAttendance` | Take attendance | Pending |
| `s.remind` | Remind me in 10 | Pending |
| `s.snoozed` | Reminder moved by 10 minutes. | Pending |
| `s.nextPrompt` | Next reminder | Pending |
| `s.noPrompt` | No pending reminder | Pending |
| `s.now` | now | Pending |
| `s.unavailable` | This lesson is not available. | Pending |
| `s.retry` | Try again | Pending |
| `s.error` | Something went wrong. Try again. | Pending |
| `s.stale` | This lesson changed. Review the latest register. Your unsaved notes are kept here. | Pending |
| `s.saving` | Saving… | Pending |
| `s.savedNotes` | Notes saved. | Pending |
| `s.from` | From date | Pending |
| `s.until` | Until date | Pending |
| `s.filter` | Apply dates | Pending |
| `s.noMissing` | No missing submissions in this range. | Pending |
| `s.delivery` | Demo delivery | Pending |
| `s.editSchedule` | Update schedule | Pending |
| `s.start` | Starts at | Pending |
| `s.end` | Ends at | Pending |
| `s.substitute` | Accountable teacher | Pending |
| `s.assign` | Assign teacher | Pending |
| `s.cancelLesson` | Cancel lesson | Pending |
| `s.confirmCancel` | Cancel this lesson? | Pending |
| `s.adminTools` | Lesson administration | Pending |
| `s.updated` | Lesson updated. | Pending |
| `s.pendingRoute` | Continue to the lesson after choosing an account. | Pending |
| `s.noDevices` | Reminders are optional. Your lesson list always works. | Pending |
| `s.demoAdmin` | Demo Admin | Pending |
| `s.demoA` | Demo Teacher A | Pending |
| `s.demoB` | Demo Teacher B | Pending |
| `s.demoC` | Demo Teacher C | Pending |
| `s.demoD` | Demo Teacher D | Pending |
| `s.demoParent` | Demo Parent | Pending |
| `s.selectIdentity` | Demo identity | Pending |
| `s.unavailableHelp` | Choose another account or return to your lessons. | Pending |
| `s.confirmSubmit` | Submit the reviewed register | Pending |
| `s.submitNotice` | Submission records a review, not a dismissal. | Pending |
| `s.close` | Close notification | Pending |
| `s.statusLabel` | Attendance status | Pending |
| `s.savedReadOnly` | Submitted register | Pending |
| `s.locale` | en-SG | Pending |
| `s.timezone` | Asia/Singapore | Pending |
| `s.noRole` | Choose an account to continue. | Pending |
| `s.states.scheduled` | Scheduled | Pending |
| `s.states.in_progress` | In progress | Pending |
| `s.states.awaiting_attendance` | Ready for review | Pending |
| `s.states.overdue` | Needs review | Pending |
| `s.states.submitted` | Submitted | Pending |
| `s.states.cancelled` | Cancelled | Pending |
| `s.deliveries.not_attempted` | Not attempted | Pending |
| `s.deliveries.accepted` | Accepted · dry run | Pending |
| `s.deliveries.failed` | Failed · dry run | Pending |
| `s.deliveries.no_devices` | No devices | Pending |
| `s.deliveries.pending` | Pending · dry run | Pending |
| `s.errors.TP_DISABLED` | This demo is turned off. | Pending |
| `s.errors.TP_NOT_AVAILABLE` | This lesson is not available. | Pending |
| `s.errors.TP_CONFLICT` | This lesson changed. Review the latest register. | Pending |
| `s.errors.TP_INCOMPLETE` | Mark every student before submitting. | Pending |
| `s.errors.TP_LOCKED` | This lesson is read-only. | Pending |
| `s.errors.TP_TOO_EARLY` | This lesson has not started. | Pending |
| `s.errors.TP_TOO_OLD` | Ask an admin to review this lesson. | Pending |
| `s.errors.TP_SNOOZE_LIMIT` | No more reminders can be postponed. | Pending |
| `s.errors.TP_NO_PENDING_PROMPT` | There is no pending reminder. | Pending |
| `s.errors.TP_MUTATION_REUSED` | Refresh the lesson and try again. | Pending |
| `s.errors.TP_INVALID_INPUT` | Check the details and try again. | Pending |

## Push and dispatcher

10 entries.

| Key | Stand-in value | Edmund approval |
|---|---|---|
| `promptStrings.title` | TAVA | Pending |
| `promptStrings.bodies.heads_up` | Your lesson ends soon. | Pending |
| `promptStrings.bodies.attendance` | Please take attendance. | Pending |
| `promptStrings.bodies.follow_up` | Please review your lesson. | Pending |
| `promptStrings.bodies.final` | Your lesson is waiting for review. | Pending |
| `promptStrings.methodNotAllowed` | Method not allowed. | Pending |
| `promptStrings.forbidden` | Not allowed. | Pending |
| `promptStrings.invalidRequest` | Invalid request. | Pending |
| `promptStrings.unavailable` | Service unavailable. | Pending |
| `promptStrings.workerFailed` | Worker failed. | Pending |

## iOS sketch

14 entries.

| Key | Stand-in value | Edmund approval |
|---|---|---|
| `PromptStrings.title` | TAVA | Pending |
| `PromptStrings.takeAttendance` | Take attendance | Pending |
| `PromptStrings.snoozeTen` | Remind me in 10 | Pending |
| `PromptStrings.confirmSnooze` | Remind you in 10 minutes? | Pending |
| `PromptStrings.cancel` | Cancel | Pending |
| `PromptStrings.signIn` | Sign in to view your lesson. | Pending |
| `PromptStrings.unlock` | Unlock to view your lesson. | Pending |
| `PromptStrings.loading` | Loading lesson. | Pending |
| `PromptStrings.unavailable` | This lesson is not available. | Pending |
| `PromptStrings.retry` | Try again | Pending |
| `PromptStrings.chooseAccount` | Choose account | Pending |
| `PromptStrings.todaysLessons` | Today's lessons | Pending |
| `PromptStrings.pushUnavailable` | Open today's lessons to continue. | Pending |
| `PromptStrings.storageUnavailable` | Open the lesson link again. | Pending |
