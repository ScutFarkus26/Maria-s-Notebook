# Settings sync spinners kept redrawing after every sync (2026-09-28)

## Found

The Release copy in `/Applications` (main cfcf9043, installed 00:05), windowed, 1 h 39 min
after launch, nobody using it. The one window showed Settings → iCloud Sync, sitting in the
Stage Manager strip. M4 MacBook Air, macOS 27.0.

| Measure | Value |
|---|---|
| CPU (`top -l 13 -s 5 -pid …`) | 16.7–18.6% in every 5 s sample |
| Main thread (`sample … 10`) | about half the samples busy, all in `NSHostingView.layout` → `ViewGraphRootValueUpdater.render` → `DisplayList.ViewUpdater`, with `RepeatAnimation.animate` on the stack; almost no app code |

## Cause

`SyncStatusIndicator` and the Sync Now button in `CloudKitStatusSettingsView` each rotate an
icon with a `.linear(duration: 1).repeatForever(autoreverses: false)` animation keyed on a flag.
Once started, turning the flag off does not end a `repeatForever`: SwiftUI keeps running it (the
target angle is now 0, so nothing visibly moves) for as long as the view is on screen. One sync
while the pane was open was enough to leave both redrawing every frame from then on.
`SyncStatusIndicator` also never set its `isAnimating` back to false.

## Reproduction (standalone, `swiftc -O`, one 60 pt window, `top` 2 s samples after the flag turns off)

| Variant | CPU after "syncing" → "healthy" |
|---|---|
| Never synced | 0.0 / 0.0 / 0.0 |
| Current code | 1.9 / 2.7 / 3.0 |
| Current code + reset the flag with `.default` | 1.8 / 2.5 / 2.8 (does not stop it) |
| `.id(isSyncing)` on the icon | 1.1 / 1.2 / 0.0 |
| `.symbolEffect(.rotate, isActive:)` | 0.0 / 0.0 / 0.0 |
| `.spinning(while:)` (the fix: spinning view in its own branch) | 0.0 / 0.0 / 0.0 |

## Fix

`View.spinning(while:)` in `Components/Modifiers/AdaptiveAnimationModifier.swift`: same one turn a
second while active, no spin under Reduce Motion (as before, where the animation was nil), and
the spinning view leaves the hierarchy when the flag turns off. Both spinners use it.

## Still to take

The "after" row on the Release copy: reinstall (`Scripts/install_release.sh`), open Settings →
iCloud Sync, press Sync Now once, wait for it to finish, then `top -l 13 -s 5 -pid <pid> -stats
pid,cpu`. Expected: 0% once the sync ends.
