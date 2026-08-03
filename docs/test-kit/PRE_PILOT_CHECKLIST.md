# Before we put real kids on the kiosk

You've had a few weeks with the app — screens, colours, where the buttons are.
Good. This is the part that matters next: **what actually has to work** before
we let a small batch of students sign in for real.

If something below still fails, we don't start the pilot. Better to slip a week
than discover it with a queue at the desk.

First time opening the app? Do the short walkthrough first:
[`TEST_SCRIPT.md`](TEST_SCRIPT.md). Day-to-day how-to:
[`STAFF_GUIDE.md`](STAFF_GUIDE.md).

---

## Where we are

| Stage | Honest version |
|---|---|
| **Just exploring** | You can find Sign In, Classes, and the website without help |
| **This checklist** | We've proven the full loop works with *our* classes and students |
| **Pilot** | Small group of real students on real class days. Paper still nearby. |
| **More classes later** | Only after the pilot stuff is solid |

Clicking around for a few weeks is not the same as ready. If we never checked
that the iPad, the server, and the website all show the same thing, we're still
exploring.

---

## What we're actually testing

### Yes — this is the job

On a normal class day (usually Mon / Thu):

1. Kids sign themselves in on the front-desk **iPad**
2. App marks them **green (on time)** or **orange (late)** from the class start time
3. Desk staff can fix mistakes when the PIN is unlocked (Not Here, late override, Absent)
4. Tutors open their roster, start today's class, mark anyone the kiosk missed
5. Someone checks the **website** and can export if needed
6. Everyone knows to fall back to **paper** if the net or app dies mid-session

### Not yet — don't wait on these

If I haven't switched something on, just assume **it's not ready**. Some of it
isn't fully built for us yet; some of it is sitting there off on purpose. Don't
block the pilot on any of this:

| Thing | Just so you know |
|---|---|
| Parent app / parent portal | Not ready for us yet |
| Push notifications / “safely home” | Not set up for live use |
| QR sign-in | Optional; we're using **tap name** for pilot |
| Awards | Nice later; not needed to take attendance |
| Study Space tool | Separate desk thing, not this pilot |
| Editing past sessions | Pilot is about **today** only |

If one of these shows up on a device and you weren't told, ping me before you
lean on it.

---

## Who does what

Write a real name. “Someone will check” is how things get missed.

| Role | Please own |
|---|---|
| **Admin / lead** | Student & class data is right; website matches; final go/no-go |
| **Desk** | iPad, PIN, kids signing in, fixes during the rush |
| **Tutors on pilot classes** | Roster, marking, history, the orange-dot offline bit |
| **Me (Edmund)** | Logins, demo data if we need it, what's switched on, app version |

---

## 1. Data first (before anyone taps)

Wrong names / missing enrolments is the boring way pilots fail.

### Students & classes

- [ ] Pilot kids are in the system, **names spelled the way people know them**
- [ ] Classes look right (subject / level / name)
- [ ] Right kids enrolled in the right classes for those days
- [ ] Schedule day is right (our usual Mon and/or Thu, or whatever we already use)
- [ ] Start times are real — late depends on this
- [ ] Right tutor is on each class (so they actually see it under Classes)
- [ ] Leavers are inactive so they don't clutter the kiosk
- [ ] No leftover **Demo …** kids or **ZZ Demo Class** from an old trial

### Logins & devices

- [ ] Kiosk iPad is on an **admin** account, not a tutor (tutor login only sees their own classes — kiosk will look wrong)
- [ ] Each pilot tutor can log in
- [ ] Someone can open **dash.thegoodcompanysg.dev** as admin
- [ ] App version on the iPad is the one we said (write it: ________)
- [ ] iPad has a passcode, is updated, and kids can't wander out of the app or read staff notifications
- [ ] Kiosk **PIN** is set and only staff know it (not `1234`)

### Quick “does today look right?”

On a real class day (or a dry run we pick):

- [ ] Expected classes show up (not “No Classes Today” when there *is* class)
- [ ] Expected kids show up
- [ ] No weird test classes confusing the desk

Empty kiosk on a class day = **stop**. Fix schedule / enrolment / admin login.
Don't put a tutor account on the kiosk as a hack.

---

## 2. Things that must pass

Use demo kids if they're still there, or a dry-run name we've agreed on.
Don't trash real kids' history if you don't have to.

Only tick when the device **and** the website agree (where it says so).

### Kiosk — basic path

| # | Do this | You should see | ✓ |
|---|---|---|---|
| K1 | Kid taps their card | Green (on time) or orange (late) | [ ] |
| K2 | Another kid taps | Same; both stay signed in | [ ] |
| K3 | After start time, someone new taps | Orange, not green | [ ] |
| K4 | Check website analytics / today | Same kids, same status as the iPad | [ ] |

### Kiosk — fixes (PIN unlocked)

| # | Do this | You should see | ✓ |
|---|---|---|---|
| C1 | Lock with PIN | Only the sign-in grid | [ ] |
| C2 | Unlock with PIN | **ADMIN** badge | [ ] |
| C3 | Hold green → Mark as Late | Orange | [ ] |
| C4 | Hold orange → Not Here | Grey again; tappable | [ ] |
| C5 | Tap that grey card | Signs in again | [ ] |
| C6 | Tap an orange card once (admin) | Flips to green | [ ] |
| C7 | Hold signed-in → Absent | Red; kid can't undo by tapping | [ ] |
| C8 | Lock again | Badge gone; kids can't override | [ ] |
| C9 | Website after all that | Final statuses match | [ ] |

### Tutor roster

| # | Do this | You should see | ✓ |
|---|---|---|---|
| T1 | Classes → class → Start Today's Class | Roster loads | [ ] |
| T2 | Mark Present | Marked time under the name | [ ] |
| T3 | Open a student row | History loads (not a blank nothing) | [ ] |
| T4 | Mark someone the kiosk missed | Shows on website after a bit | [ ] |
| T5 | Wi‑Fi off, mark one | Still marks; **orange pending** dot | [ ] |
| T6 | Wi‑Fi back on | Dot clears **and** website has it | [ ] |

If T5/T6 leave the orange dot forever, don't pass it. That's a real problem on
bad Wi‑Fi days.

### Website

| # | Do this | You should see | ✓ |
|---|---|---|---|
| W1 | Log in at dash.thegoodcompanysg.dev | Dashboard loads | [ ] |
| W2 | Today / analytics after kiosk work | Matches the iPad | [ ] |
| W3 | Export for the pilot window | CSV has the people you expect | [ ] |
| W4 | Peek one student | History matches today | [ ] |

Delete test downloads with kids' names when you're done. Don't WhatsApp
attendance files around.

---

## 3. How we run the day

- [ ] Paper sheet printed for each pilot class, on the desk
- [ ] Everyone knows: **orange pending ≠ saved**. Saved when the website agrees (or paper if we had to fall back)
- [ ] Wrong kid's data / weird account mix-up → **stop**, secure the device, tell me. Don't keep tapping
- [ ] While something is pending: no uninstall, no clear data, no account-hopping, no reset
- [ ] Screenshots with names stay in our private staff chat only
- [ ] Named desk lead each session (PIN + who pings me)
- [ ] Named person for short notes after class (“what confused people?”)
- [ ] Busy arrival: short queue, unlock only when staff need it, lock again after

---

## Colours (so we all mean the same thing)

| Looks like | Means | Kid can tap? |
|---|---|---|
| Grey | Not in yet | Yes |
| Green | On time | No (staff only) |
| Orange | Late | No (staff can flip to on time) |
| Grey after Not Here | Soft undo | Yes — try again |
| Red | Absent (staff decided) | No |
| Purple | Dismissed early (was present) | No |

**Not Here** = “oops, try again.” **Absent** = we meant it.

---

## Rough timeline

| When | What |
|---|---|
| **~1 week out** | Finish data checks; fix enrolments / times |
| **~3 days out** | Run the must-pass list (kiosk + tutor + web) |
| **Day before** | “Does today look right?” PIN, paper, app version |
| **15 min before kids** | Admin on kiosk, lock it, website open on a staff phone |
| **After first pilot class** | Five minutes: what broke, what confused people |

If the 3-day run fails anything important, we move the pilot. No “hope for the best.”

---

## If something breaks, write this down

1. Date & time
2. Which device (kiosk / phone / browser)
3. Admin or tutor?
4. Which kid / class (first name is fine in private notes)
5. What you tapped and what you expected
6. What actually happened
7. Did you use paper?

Send it to me on our private channel. No kid names in group chats that aren't ours.

---

## Go or not

We only go live with real kids when all of this is honestly true:

- [ ] Data ready for the pilot batch
- [ ] Kiosk happy path + website match
- [ ] Corrections + PIN work
- [ ] Tutor path works (including offline clear + website confirm)
- [ ] Website path works
- [ ] Paper / pending / stop rules briefed to everyone on duty
- [ ] “Not yet” list understood — we won't depend on those
- [ ] Dates, classes, who: _______________________

| | Name | Date |
|---|---|---|
| Desk lead | | |
| Tutor lead | | |
| Final go/no-go | | |
| Edmund | | |

**☐ GO** on ________ **☐ NOT YET** — fix: ________

---

## After the pilot (short)

- [ ] What actually blocked attendance vs “would be nice”
- [ ] No demo junk left skewing percentages
- [ ] More kids/classes, or hold and fix first?
- [ ] Keep paper until busy days feel boring

---

| Need | Open |
|---|---|
| Everyday use | [`STAFF_GUIDE.md`](STAFF_GUIDE.md) |
| First 15 minutes | [`TEST_SCRIPT.md`](TEST_SCRIPT.md) |
| This | Ready / not ready for real kids |
