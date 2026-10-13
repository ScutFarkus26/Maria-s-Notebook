# ParentLocker

Attendance goes to the school's ParentLocker site (`yyli.parentlocker.com`) from the notebook and the Daybook Assistant. The plan, with every decision and why: <../Plans/Plan - ParentLocker attendance.md>. The code is `Cosmic Daybook/Attendance/ParentLocker/`, compiled into both apps (the Assistant by path in `project.pbxproj`, iOS 18 floor).

## What happens

- **Settings › Attendance to the School** picks ParentLocker or the front-desk email. It is shared through `CDAttendanceEmailSettings` (`sendMethodRaw`, `parentLockerSite`). Picking ParentLocker also turns `isEnabled` off, so Assistant builds older than schema 18 stop offering the email.
- **Close Arrival & Send** marks the rest absent and, once Close Arrival's Undo window has gone, sends the whole class in one save per ParentLocker class. Undo cancels it. The send is recorded as a `CDAttendanceEmailSend` with `channelRaw = "parentLocker"`, which drives the reminder and the "Sent to ParentLocker 8:47 AM by …" line.
- **After that, changes go live one child at a time:** after 4 s on the device that made the change, and as a 60-s backstop on the others. Nothing is sent before the day's send or before arrival closes.
- **Send Now** and MCP's `send_attendance_to_school(date?, preview?)` make a whole-class send by hand.

## The site's requests (read 2026-10-12 from the real page)

- **Course list:** `GET /sis/newattendance.php`, or `?date=YYYY-M-D` for another day (the page's own date picker does this; checked 2026-10-13, and a past day carries its own report ids while a future day shows today's). The page carries `var courses = [...]` and `var additional_courses = [...]`. Only daily-attendance classes are used, and `attendance_report_id` comes from here, sent back exactly as it came (a string). Status is `submitted`, `not_submitted` or `not_expected`.
- **A class:** `POST /sis/newattendance.php`, JSON `{action: "course_roster", course_id, period, date}`. Dates are `YYYY-M-D`, with no leading zeros.
- **Save:** `POST /sis/newattendance.php`, JSON `{action: "save", students: [the roster's attendance objects], attendance_report_id, date}`. Only `attendance_code`, `confirmed` and `comment` are changed. The reply carries `error`, `updated` and `conflicts`.
- **Marks** are looked up by their `type` (`present`, `late`, `absent`), never by id. A mark can be changed but never cleared. Rows "Locked by Admin" are never changed.
- **Sign-in:** `#login-form` → `POST /process.php` (`user`, `pass`, `remember=1`). The site keeps more than one sign-in at a time, and a browser session times out after a few hours.

## Rules

- **The password** lives only in the Keychain: an internet-password item, synchronizable, `AfterFirstUnlock`, data-protection keychain on the Mac. It is never in Core Data, backups, preferences, logs, status or error text, or MCP replies. It is passed to the sign-in page as a `callAsyncJavaScript` argument, and only on `https` and the exact site host.
- **A refused saved password is never retried by itself:** the refusal is remembered (by the password item's modification date) until a new password is saved, so a changed password can't lock the school account.
- **The site's cookies** are a `ThisDeviceOnly` Keychain item. Requests use an ephemeral `URLSession` with cookie handling off, and refuse any redirect to another host.
- **"Not matched" is stored** as `parentLockerID = "none"`; name matching never overrides it, and one ParentLocker child is never matched to two notebook children.
- **Days after today are never sent**, by any path.
- **A day ParentLocker isn't expecting** (every class `not_expected`) is recorded as a `CDAttendanceEmailSend` with `channelRaw = "notExpected"`, with no schema change. The reminder and the status line read it, on every device. `sends`, `latestSend`, the summaries, MCP and the "after" rule leave it out, so nothing ever shows it as sent. (Assistant builds older than schema 18 read it as an email that went, so every phone is updated before switching.)
- **Send Now with children unmarked** sends the marked ones and records nothing; the screens and the Shortcut ask first and name them. "Not matched" children never count as unmarked.
- **Settings reads the shared row** for the method and site. An edit writes only that field, and only from the person's own action. A device that's behind never pushes an old value; the launch seed is dated `.distantPast`.
- **Debug builds and test runs never save** to ParentLocker and never record a ParentLocker send (`ParentLockerSavePolicy`). Only Release and TestFlight builds do.
- **Never run a schema-18-or-later Debug build of the notebook on the Mac to check ParentLocker.** It opens the live notebook. Use the iPhone simulator: a Debug build launched with `-ParentLockerPreview YES` shows the sign-in sheet if needed, then today's preview, and saves nothing.

## When the page changes

ParentLocker can change its page at any time. When it does, sends fail with "ParentLocker's attendance page changed…", and the app says so plainly. To check the page:
1. Sign in at the site in a browser.
2. Open `/sis/newattendance.php` and confirm the `courses` global is still there, and that the page's own `save()` still posts `{action: "save", students, attendance_report_id, date}`.
3. Run the `-ParentLockerPreview` check on a simulator.
