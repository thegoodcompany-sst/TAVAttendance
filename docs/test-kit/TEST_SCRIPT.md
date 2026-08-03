# TAVA Attendance — 15-Minute Test Script

Follow these steps in order during your trial. Each step says what to do and
what you should see. Tick them off as you go. You need the **iPad** (kiosk) and
a **computer or phone** for the web dashboard.

Total time: about 15 minutes.

> Names shown below (Amira, etc.) are examples. Your screen will show the
> **Demo** students that were loaded for the trial (e.g. "Demo Alice Tan").

---

## Before you start (2 min)

<p align="center"><img src="img/01-login.png" width="480" alt="TAVA Attendance sign-in screen"></p>

1. Open **TAVA Attendance** on the iPad.
2. Sign in with the **admin** email and password. → You land on the **Sign In** tab.
   - *Expected:* a grid of student cards, all **grey** (nobody signed in yet).
   - *If it says "No Classes Today":* tell Edmund — the demo class may not be loaded.
   - *Safety check:* use demo-only records, confirm the iPad has an OS passcode,
     and do not expose production credentials to observers.

---

## Part A — Student sign-in on the kiosk (3 min)

3. Tap **Demo Alice Tan's** card.
   - *Expected:* the card turns **green** (**On Time**) if it's before class time, or **orange** (**Late**) if after.
4. Tap **Demo Ben Lim's** card.
   - *Expected:* it turns green or orange the same way.
5. Find a **green** card. **Press and hold** it.
   - *Expected:* a menu appears with **"Mark as Late"** and **"Mark as Not Here Yet"**.
6. Tap **"Mark as Late"**.
   - *Expected:* the card turns **orange**.
7. **Press and hold** that **orange** card → tap **"Mark as Not Here Yet"**.
   - *Expected:* its attendance row is cleared and the card goes **grey** again. The student is still listed, and the card is tappable.
8. Tap that **grey** card again.
   - *Expected:* it signs the student back in (green or orange). This proves a mistap can always be undone.

---

## Part B — Admin PIN lock and override (4 min)

9. Tap the **gear icon** → **Kiosk Settings** → **Set PIN** (use a temporary
   non-production PIN; do not use `1234` on a live kiosk) → **Lock Kiosk Now**.
   - *Expected:* the tab bar and gear disappear. Only the sign-in grid is left — this is what students see.
10. Tap the **lock icon** and enter your PIN.
    - *Expected:* an **ADMIN** badge appears in the header. You're unlocked.
11. Find an **orange (Late)** card and **tap it once**.
    - *Expected:* it flips to **green (On Time)** — an admin override.
12. **Press and hold** any signed-in card.
    - *Expected:* the menu now includes **"Mark as Absent"** (shown in red).
13. Tap the **gear** → **Lock Kiosk Now** again.
    - *Expected:* the ADMIN badge disappears; taps no longer override.

---

## Part C — Tutor roster (3 min)

*(Use the same iPad, or a phone signed in as a tutor if you have one.)*

14. Go to **Classes** → open the demo class → **Start Today's Class**.
15. Tap a student to mark them **Present**.
    - *Expected:* **"Marked HH:MM"** appears under their name.
16. Tap a student's **row** (not the mark button).
    - *Expected:* a profile sheet opens with their recent attendance.
17. **Turn off Wi-Fi** on the device, then mark another student.
    - *Expected:* the student is still marked, with a small **orange dot** next
      to the name. This means pending on this device, not saved to the server.
18. **Turn Wi-Fi back on**, wait a few seconds.
    - *Expected:* the orange dot disappears. Confirm the same record on the web
      dashboard before marking this step passed.
    - *If it remains:* do not sign out, clear app data, uninstall, or repeat the
      mark. Note the time and continue the test on paper.

---

## Part D — See it on the web dashboard (3 min)

19. On a computer or phone, open **dash.thegoodcompanysg.dev** and log in with the admin account.
20. Open the **Analytics / today's attendance** view.
    - *Expected:* the demo students you signed in appear, with the right status (on time / late / present).
21. Use the dashboard export for the demo data.
    - *Expected:* the downloaded file lists only the intended demo records.
      Delete the local test download after verification; do not email it or
      upload it to an unapproved drive.

If Part D matches what you did on the iPad, the full loop works: **iPad → server → dashboard.**

---

## If something goes wrong

1. Switch to the paper attendance fallback if a pending indicator does not
   clear. Do not claim the record is saved until the dashboard confirms it.
2. Note the time, step, device, signed-in role and what you tapped.
3. Screenshots can contain children's data. Crop/redact unrelated names and use
   only the centre's approved private support channel.
4. If another account's/child's data appears or compromise is suspected, stop
   syncing, secure the device and activate the breach-response escalation.
5. Do not uninstall, clear app data, change accounts or reset the device while
   attendance is pending.

_Operational script audited 2026-07-26._
