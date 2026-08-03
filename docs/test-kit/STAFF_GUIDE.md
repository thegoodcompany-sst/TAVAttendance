# How we take attendance

Short guide. Keep it on your phone if it helps.

If I haven't turned a feature on, **it's not ready** — ignore it for now.
Some things just aren't built far enough yet.

Want a timed first try? → [`TEST_SCRIPT.md`](TEST_SCRIPT.md)
Ready to pilot with real kids? → [`PRE_PILOT_CHECKLIST.md`](PRE_PILOT_CHECKLIST.md)

---

## The idea

- **iPad at the front desk** = kiosk. Kids tap their own name.
- **Tutors** mark their class on phone/iPad if the kiosk missed someone.
- **Website** is where admin checks reports and downloads the spreadsheet.

If the internet drops, a mark can sit pending for a bit. **Don't trust it** until
the little pending indicator is gone *and* the website shows the same thing.

---

## 1. Kiosk iPad

<p align="center"><img src="img/01-login.png" width="520" alt="Sign-in screen"></p>

1. Open the app.
2. Sign in with the **admin** login I gave you.

> **Please:** always leave the kiosk on an **admin** account.
> Tutor logins only see their own classes, so half the kids would be missing.
> Empty-looking kiosk? Check you're not signed in as a tutor.

3. Stand it where kids can reach it.
4. iPad should have a passcode, be updated, and not let kids wander into other apps or read staff notifications.

---

## 2. Kids signing in

**Sign In** tab = a card per kid with class today.

- **Tap** → signed in
  - **Green** = on time
  - **Orange** = late (after class start time)
- Wrong mark? Unlock with the PIN, set **Not Here Yet** (grey again). This clears the attendance row, and they can tap again.

Grey = not here yet. Green = on time. Orange = late.

### Lock it when kids are around

- Gear → Kiosk Settings → Set PIN → **Lock Kiosk Now**
  (use a real PIN, not something dumb from a test)
- Locked = only the grid. No settings, no overrides.
- Staff need to fix something → lock icon + PIN → **ADMIN** badge
- Hold a card to: fix late → on time, mark **Absent** (red), or **Not Here Yet**
- Lock again when you're done

---

## 3. Tutors

1. **Classes** → your class → **Start Today's Class**
2. Tap kids **Present** — you should see a marked time under the name
3. Tap the row for history / profile
4. **No Wi‑Fi?** You can still mark for a short while. Orange dot = only on *this* device, not saved yet. Get online again, same account, wait for the dot to clear, then check the website before you relax. Old sessions, week-old marks, switching accounts, or a broken queue can reject pending stuff.

---

## 4. Website (admin)

**dash.thegoodcompanysg.dev** with your admin login.

- **Analytics** — today, trends, kids to watch
- **Export** — spreadsheet for records

If the iPad said one thing and the site says another, believe the mismatch and sort it — don't assume.

---

## If something's off

- Note time, device, who was signed in, what you tapped
- Screenshots can have kids' names — private staff chat to me only, crop extras
- Wrong kid's data, weird other-account stuff, possible compromise → stop, don't switch users, secure the device, tell me
- Normal net flake: paper if the pending won't clear. Reconcile paper + device + site before you leave
- Don't uninstall / clear data / hop accounts / reset while something's still pending

Questions → me. Don't guess on attendance.
