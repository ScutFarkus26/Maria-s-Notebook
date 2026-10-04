# Release copy idle baseline (2026-09-27)

The first baseline on the Release copy after all five Energy Fifty waves (item 1): main
a3d90d81, installed to `/Applications/Cosmic Daybook.app` with `Scripts/install_release.sh` at
16:09. M4 MacBook Air (Mac16,12), macOS 27.0, on AC power, battery full.

## What was measured

The copy running was the MCP-only launch the bridge opens (`-CosmicDaybookMCPAutolaunch YES`, no
window, one MCP client connected), from 16:13:48 for 11 minutes. There was no windowed copy to
measure. Taken with `top -l 11 -s 60 -pid … -stats pid,command,cpu,idlew,power,mem,time`,
`footprint`, `heap -s` and `/usr/bin/log show`.

| Measure | Value |
|---|---|
| CPU while idle / CPU time in 11 min | 0.0% in every sample / 0.61 s, 0.55 s of it in the first minute (launch) |
| Idle wakeups | 0–2 per 60 s sample |
| Energy impact (`top` POWER) | 0.0 in every sample |
| `phys_footprint` (peak) | 31 MB at 1 min, 30 MB at 11 min (39.5 MB) |
| Live heap | 11.6 MB in 95k allocations |
| Largest heap groups | Swift metadata 0.9 MB; SwiftUI `PlatformItemList.Item` arrays 0.66 MB; 1,942 `Set<UUID>` 0.53 MB; one `[UUID: SearchResult]` 0.2 MB (an MCP search) |
| Log | 383 lines, almost all CloudKit launch sync (7 exports) and MCP connections; one `BGSystemTaskScheduler` Code=3 fault on the first export request at launch; no app errors |

## Against the wave-one "before" row

The 2026-09-25 row was Xcode's Debug build, windowed, 24 h under `debugserver` on battery:
115 MB footprint (148 MB peak), 68 MB live heap, 15.7 s CPU in 24 h. Today's copy has no window
and ran for 11 minutes, so these rows show what an MCP-only Release copy costs, not the
windowed day. Don't read 115 → 30 MB as the waves' saving.

## Still to take

The 24-hour windowed row on this copy: open the window, use the app as usual for a day, then
take the same five measures (`ps -o etime,time`, `footprint`, `heap -s`, `top` over 10 min,
`log show` repeats), on battery if possible.
