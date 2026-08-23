# 15-minute try-out

Do these in order. Tick as you go. Need the **kiosk iPad** plus a phone or
computer for the website.

About 15 minutes. If something on the screen isn't in this list, I probably
haven't turned it on yet (or it isn't ready) — skip it.

Know the UI already and getting ready for real kids?
→ [`PRE_PILOT_CHECKLIST.md`](PRE_PILOT_CHECKLIST.md)

> Names below are **demo** names (e.g. Demo Alice Tan). Not real students.

---

## Before you start (~2 min)

<p align="center"><img src="img/01-login.png" width="480" alt="Sign-in screen"></p>

1. Open **TestFlight 1.1.3 build 8** on the iPad (not App Store build 3).
2. Admin email + password → you should land on **Sign In**.
   - Expect: grey cards (nobody in yet)
   - “No Classes Today” **after a successful load**? Tell me — demo class might
     not be loaded. A failed load should error and retry, not look like a day off.
   - Use demo kids only; Guided Access; Singapore timezone; Automatic Date &
     Time; auto-lock off; do **not** enable in-app Face ID on this iPad
   - Don't Start Class early if you want to see On Time vs Late (`startedAt`
     forces Late)

---

## A — Sign-in (~3 min)

3. Tap **Demo Alice Tan** → green (on time) or orange (late), depending on class time
4. Tap **Demo Ben Lim** → same idea
5. Hold a **green** card → menu with **Mark as Late** and **Mark as Not Here Yet**
6. **Mark as Late** → turns orange
7. Hold that orange → **Not Here Yet** → attendance row clears, card turns grey and stays tappable
8. Tap the grey card → signs back in
   (proves a mistap is fixable)

Wifi off on the kiosk: the tap should **fail**. Nothing sits pending. Paper if
this were a real class. Dual-enrolled kids: one card, marks every session.

---

## B — PIN & overrides (~4 min)

9. Gear → Kiosk Settings → Set PIN (temporary is fine; not `1234` on the live kiosk) → **Lock Kiosk Now**
   → only the grid left (what kids see). Search should be gone.
10. **Long-press** the lock icon + PIN → **ADMIN** badge
11. Tap an **orange** card once → should flip to **green**
12. Hold a signed-in card → menu includes **Mark as Absent** (red). Informed vs
    no notice both store Absent; parents never see the flag.
13. Gear → **Lock Kiosk Now** again → badge gone, taps don't override, search hidden

---

## C — Tutor roster (~3 min)

Same iPad, or a phone as a tutor. Don't End Class / sign out / hop accounts
while a mark is pending. Don't offline-mark a kid who already tapped the kiosk.

14. **Classes** → demo class → **Start Today's Class**
15. Mark someone Present → **Marked HH:MM** under the name
16. Tap the row (not just the mark) → profile + recent attendance
17. **Wi‑Fi off**, mark another → still marks, small **orange** pending dot
    (this is the roster, not the kiosk)
18. **Wi‑Fi on**, wait a few seconds → dot should go; check the **website** too
    If the dot sticks: don't sign out / clear / uninstall. Note the time, use paper.

---

## D — Website (~3 min)

19. **dash.thegoodcompanysg.dev** — admin login
20. Analytics / today's attendance → same demo kids, right statuses
21. **Skip Export** unless Edmund is present and will delete the file. The
    Export button is superadmin-only and downloads a **full operational ZIP**
    (every table we snapshot), not a demo-only CSV.

If D matches the iPad, the loop works: **iPad → server → website.**

---

## Something went wrong?

1. Kiosk wifi drop → paper. Tutor pending that won't clear → paper. Don't call
   it saved until the site agrees.
2. Time, step, device, role, what you tapped
3. Screenshots with names → private chat to me, crop extras
4. Wrong kid / other account / feels compromised → stop, secure device, tell me
5. No uninstall / clear data / account switch / reset while pending

That's it. Ping me if anything felt weird.
