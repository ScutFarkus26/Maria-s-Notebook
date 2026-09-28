---
name: roll-out
description: Build Release copies of Cosmic Daybook's main branch and install them on all of Danny's devices — the Mac (/Applications), his iPhone and his iPad mini. Use when Danny says "roll out", "roll it out", "ship it to my devices", "install the release build", "put this on my phone/iPad/Mac", "update my devices", or asks which build his devices are running after merging work to main.
---

# Roll out

Danny's everyday copies are development-signed **Release** builds of `main`: same bundle
id, sandbox container and CloudKit **Development** environment as his Xcode builds, so
they open the same notebook. Two scripts do the work; this skill sequences them and
reports.

| Target | Script | Installs to |
|---|---|---|
| Mac | `Scripts/install_release.sh` | `/Applications/Cosmic Daybook.app` (old copy zipped into the Trash) |
| iPhone 18 Pro `00008160-001C18C90CC00036` + iPad mini A17 Pro `00008130-0009713E3E41001C` | `Scripts/install_release_ios.sh` | over the existing app via `devicectl` (data kept) |

Both build **main's last commit** in a throwaway detached worktree, never the working
tree, and both archive through `Scripts/locked_xcodebuild.sh` (the Mac-wide build lock),
so they run one after the other anyway. Archives with dSYMs stay in
`~/Library/Developer/Xcode/Archives`.

## Steps

Don't ask questions before starting — Danny's standing instructions:

1. **Build main's last commit as is.** Assume it's what he means; don't check whether
   branch work or uncommitted changes are missing, and don't offer to merge.
2. **Quit the Mac copy without asking, and reopen it.** `install_release.sh --quit
   --relaunch` quits a running `/Applications` copy right before the swap, after the
   build — a normal Quit first (so it saves), SIGTERM after 15 s, SIGKILL after 10
   more — then opens the new copy. Avoid the cosmic-daybook MCP tools during the roll-out; a
   call relaunches the app.
3. **Order: Mac, then iPhone, then iPad.** Run each in the background
   (`run_in_background`), wait for its completion notification, then start the next —
   no polling loops. Tell Danny at the start to unlock his iPhone and iPad and keep them
   nearby (`devicectl` refuses a device not unlocked recently, CoreDeviceError 10003).
   ```
   Scripts/install_release.sh --quit --relaunch
   Scripts/install_release_ios.sh --only 00008160-001C18C90CC00036
   Scripts/install_release_ios.sh --only 00008130-0009713E3E41001C --archive <archive the iPhone run printed>
   ```
   The iPhone run builds the iOS archive; the iPad run reuses it (no second build).
   Each build takes ~5 min plus any wait for the build lock. Exit status 75 = never got
   the lock (the script prints who holds it). On a build failure the script prints its
   log path — read the tail and report the actual compiler error. If the Mac build
   fails, still go on to the devices, and vice versa.
4. **Show the timers.** Right after starting the Mac step, show Danny a countdown
   widget: call `mcp__visualize__read_me` (module `interactive`) silently, then
   `mcp__visualize__show_widget` with `assets/timer-widget.html` (next to this file),
   placeholders filled in:
   - `__MAC_S__ __IPHONE_S__ __IPAD_S__` ← the three numbers
     `scripts/estimate.sh` prints (median of past build logs; lock waits skipped).
   - `__START_MS__` ← when the first unfinished step started, in epoch ms (`date +%s`
     × 1000 when you launch it).
   - `__MAC_DONE__ __IPHONE_DONE__` ← `false` / `true`.
   When a step finishes, show it again with that step `true` and `__START_MS__` = now,
   so the next countdown starts from the real time. The widget has no live feed —
   it only counts down estimates; your messages say what actually happened.
5. **A device that failed** (locked, asleep, out of range): tell Danny to unlock it and
   rerun that device's line with `--archive`; nothing needs rebuilding.
6. **Prune archives.** Last, run `Scripts/prune_release_archives.sh`: keeps the newest
   three Mac and three iOS roll-out archives and moves older ones to the Trash (other
   archives untouched).
7. **Report** in a short table: Mac / iPhone / iPad, ✓/✗, `main <sha>`, and the profile
   expiry the scripts print. Then update the `release-builds-on-devices` memory with the
   date and sha installed.

## Don't

- **Don't register a new device.** If a device is missing from the provisioning
  profile, the iOS script says so and skips it. Registering uses a slot on the
  developer account — ask Danny. If he says yes: build (not archive) with
  `-destination "id=<UDID>" -allowProvisioningUpdates -allowProvisioningDeviceRegistration`
  to register it and refresh the profile, then rerun the script. `archive` alone
  never registers.
- Don't install on Mom's iPad or any other paired device unless Danny names it
  (`--only <udid>`; `xcrun devicectl list devices` shows UDIDs).
- Don't use distribution signing / TestFlight — that moves the app to CloudKit
  Production, where the newest schema may not be deployed.
- Don't `clean` or delete the release DerivedData folders
  (`CosmicDaybook-ReleaseInstall`, `…-iOS`); they keep the next roll-out fast.
