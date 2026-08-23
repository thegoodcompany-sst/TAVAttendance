# How we take attendance

Short guide. Keep it on your phone if it helps.

If I haven't turned a feature on, **it's not ready** — ignore it for now.
Some things just aren't built far enough yet.

Want a timed first try? → [`TEST_SCRIPT.md`](TEST_SCRIPT.md)
Ready to pilot with real kids? → [`PRE_PILOT_CHECKLIST.md`](PRE_PILOT_CHECKLIST.md)

---

## The idea

- **iPad at the front desk** = kiosk. Kids tap their own name. **Online only.**
- **Tutors** mark their class on phone/iPad if the kiosk missed someone. This
  path can queue offline.
- **Website** is where admin checks reports. Believe the website.

| Surface | Wifi drops | Saved when |
|---|---|---|
| Kiosk iPad | Use **paper**. Taps do not sit pending. | Website shows the mark |
| Tutor roster | Orange dot = only on *this* device | Dot gone **and** website agrees |

The product is not magically offline-proof. Paper stays on the desk.

---

## 1. Kiosk iPad

<p align="center"><img src="img/01-login.png" width="520" alt="Sign-in screen"></p>

1. Open **TestFlight 1.1.3 build 8** (not the App Store build).
2. Sign in with the **admin** login I gave you.

> **Please:** always leave the kiosk on an **admin** account.
> Tutor logins only see their own classes, so half the kids would be missing.

3. Stand it where kids can reach it.

| Check | Why |
|---|---|
| PIN set and locked | Kids only see the grid |
| Guided Access on | They can't leave the app |
| Singapore timezone, Automatic Date & Time | Late depends on this |
| Auto-lock off | Screen stays up during the rush |
| In-app Face ID **off** | Anyone enrolled on the iPad could unlock admin |
| Long-press the lock to unlock | Tap is not enough |
| Search hidden while locked | Search is admin-only |

---

## 2. Kids signing in

**Sign In** tab = a card per kid with class today. Dual-enrolled kids get
**one card**; a tap marks every session they have today.

- **Tap** → signed in
  - **Green** = on time
  - **Orange** = late (after class start time)
- Wrong mark? Long-press lock + PIN, set **Not Here Yet** (grey again). This
  clears the attendance row, and they can tap again.

Grey = not here yet. Green = on time. Orange = late. Red = Absent (staff).
Absent can be **informed** or **no notice**; both count as Absent. Parents
never see that flag.

### Lock it when kids are around

- Gear → Kiosk Settings → Set PIN → **Lock Kiosk Now**
  (use a real PIN, not something dumb from a test)
- Locked = only the grid. No settings, no search, no overrides.
- Staff need to fix something → **long-press** the lock icon + PIN → **ADMIN** badge
- Hold a card to: fix late → on time, mark **Absent** (red), or **Not Here Yet**
- Lock again when you're done

Wifi drops on the kiosk: **paper**. Don't wait for a pending dot; there isn't one.

### Empty grid

- **“No Classes Today”** after a successful load = nothing scheduled, or
  enrolment/login is wrong. On a real class day: stop. Fix schedule / enrolment
  / admin login.
- Failed load (error / spinner that never finishes): **retry**. That is not a
  day off.

---

## 3. Tutors

1. **Classes** → your class → **Start Today's Class**
   - Don't start early if you care about On Time vs Late. Starting the class
     forces later kiosk taps to Late.
2. Tap kids **Present** — you should see a marked time under the name
3. Tap the row for history / profile
4. **No Wi‑Fi?** You can still mark for a short while. Orange dot = only on
   *this* device, not saved yet. Same account, get online, wait for the dot to
   clear, then check the **website** before you relax.

Do **not**:

- End Class, sign out, uninstall, or hop accounts while anything is pending
- Offline-mark kids who already tapped the kiosk (you'll fight the desk mark)

Old sessions, week-old marks, switching accounts, or a broken queue can reject
pending stuff. Website wins.

---

## 4. Website (admin)

**dash.thegoodcompanysg.dev** with your admin login.

- **Analytics** — today, trends, kids to watch
- **Export** — superadmin only; full operational ZIP, not a demo CSV. Skip
  unless Edmund will delete the file.

If the iPad said one thing and the site says another, believe the mismatch and
sort it — don't assume.

---

## If something's off

- Note time, device, who was signed in, what you tapped
- Screenshots can have kids' names — private staff chat to me only, crop extras
- Wrong kid's data, weird other-account stuff, possible compromise → stop, don't
  switch users, secure the device, tell me
- Kiosk net flake: **paper**. Tutor pending that won't clear: paper, then
  reconcile paper + device + site before you leave
- Don't uninstall / clear data / hop accounts / reset while something's still
  pending

Questions → me. Don't guess on attendance.
