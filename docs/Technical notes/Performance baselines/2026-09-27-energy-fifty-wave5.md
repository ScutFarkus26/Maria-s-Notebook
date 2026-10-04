# Energy Fifty, wave five (2026-09-27)

Wave five of the Energy Fifty audit (private artifact "Daybook Energy Fifty"; earlier waves in the
`2026-09-25/26-energy-fifty-wave*.md` files): item 42, the remaining halves of 25 and 43, and six
bugs noticed during the audit. Four agents in parallel worktrees off 3035fa87, merged into
`efficiency/wave5`, then gated together (iOS build-for-testing, macOS and Daybook Assistant builds,
full iOS suite on the iPhone 17 simulator) before landing.

## Efficiency items

| # | Change | Before → after | How measured |
|---|---|---|---|
| 42 | Album vectors cached as raw Float32 (`AlbumVectorCacheFile`); legacy JSON converted once | on disk 9,385,777 → 3,056,012 bytes; load of 9 albums 323–331 → 1.4–2.1 ms; peak during load 13.5–13.9 → 6.1–6.2 MB | synthetic April-shaped library (9 albums, 746 lessons, 512 + 512 floats), separate processes; rankings bit-identical vs the old code kept in `LegacyAlbumIndex.swift` |
| 42 | Fold built on first search, off the main actor, once per album (`AlbumTextFolds`) | longest main-thread stall at first search 171–177 → ~1.2 ms (probe resolution); the fold (29–32 ms) runs off-main; the same stall after every idle trim is gone | 2,400 pages across 9 albums, 1 ms heartbeat, iPhone 17 sim |
| 42 | Page text read through a fresh PDF opening every 50 pages (`AlbumPageTextReader`) | 500-page text-heavy PDF: peak 446–448 → 79–84 MB; text byte-identical | separate processes; 260-page generated album vs legacy extraction |
| 42 | `autoreleasepool` per page / text in extraction and embedding | extraction 484 → 444 MB (before the reopen above); embedding 746 bodies 129–132 → 27 MB | peak sampler |
| 25 | Today's whole-record index read and folded on a background context (`readInBackground`), published under a rebuild number | main-thread time per rebuild 37.1 → 4.2 ms at April scale (the 34.8 ms read runs off-main); queue published ~41 ms after the rebuild starts | SQLite split store, iOS 27 sim, Debug, medians of 21, old/new interleaved |
| 43 | Restore imports from the payload's only copy, deduplicating each type in place and freeing it once imported | restore peak heap 54.4 → 28.2 MB; main-thread import 868 → 947 ms in the same run (spread 1,002 vs 1,057 across runs) | 44,318-row store, medians of 6, on-request `BackupRestorePeakMemoryTests` |

A fully streamed restore (decode each type inside the import) was built first: 33.2 MB but 1.9 s of
main-thread import, because the import must stay one uninterrupted main-actor turn. It was replaced
by the version above.

## Bugs fixed

1. **Album ink could be lost.** One save task served every page; drawing on another page — or merely
   showing a new page, whose first canvas reported its saved drawing as a change — within 800 ms
   cancelled the first page's save. Now per page (`AlbumSaveDebouncer`), flushed on disappear and
   background; showing a page no longer counts. The reading position also saves on iOS background.
2. **Presentation quick actions skipped the save.** Early `return`s inside the optional "plan the next
   lesson" / "follow-up draft" blocks left the presentation unsaved and the sheet open (e.g. no children
   attached). Logic now in `PresentationQuickActionsSave`; each guard skips only its own plan.
3. **Group Planner had no navigation stack** — on iPad (no title, lesson cards dead) and on the Mac too
   (the split view's detail column is not a stack). It owns one now.
4. **Merged memory-pressure events were dropped** (`[.warning, .critical]` matched no exact case).
5. **Every main window answered every window request**, so Keyboard Shortcuts (a `WindowGroup` with no
   value) opened one copy per open main window; the value-keyed detail windows were merged by SwiftUI.
   Now only the main window `MainWindowRegistry.answersRequests(in:)` picks responds, for all four requests.
6. **Energy leaks:** Student Files cards, the Book Club Open PDF button and Resource detail resolved their
   file on every redraw (now `DocumentFileURLMemo`: 50 card redraws 6.33 → 0.15 ms; Book Club "file gone"
   6.37 → 0.0006 ms per redraw); `TodayView` built a throwaway `TodayViewModel` on every parent redraw (now
   `TodayRootView`); the Week plan check-in pill's menu did 48 work resolutions + 24 name lookups per
   column redraw (now `WorkCheckPillStatusMenu`, only when the menu opens); the iCloud container lookup ran
   on the main thread on every `directory()` call (now `UbiquityContainerCache`, 0.57 → 0.16 ms).

Also fixed on the way: a merge restore that failed part-way left half a restore pending for the next
save anywhere (edits pending before the restore are now saved first, and a failure discards only the
restore's changes); exports of in-memory stores dropped rows past 1,000 (read in one fetch now).

## The gate

First run: all builds clean (iOS, macOS, Daybook Assistant); 1,696 tests, 1,690 passed, 0 failed,
6 skipped (the known crash probe, the contextual-model test, and on-request peak-memory measurements).
Each branch had also run its own suites and the full suite on its own simulator before merging.

## Found on the way (not fixed)

- Book Club packet editor saves on every keystroke (a save and a CloudKit export per character; Orders
  debounces 800 ms).
- `BackupFolderStorage` still calls `url(forUbiquityContainerIdentifier:)` directly (one-line switch to
  `UbiquityContainerCache`).
- `ResourceDetailView` sorts the whole lesson catalog several times per redraw and opens the PDF on the
  main thread in its appearance task. `AlbumPageNotesPanel` fetches every note and filters in Swift.
- Restore into a local-only store waits 30 s for a CloudKit export (`isCloudKitMirrored` treats any SQLite
  store as synced); "Restoring data…" never shows on success and, on a failed restore's rollback, tears
  down Settings with its error message.
- Merge restore of a record the guide had deleted without saving: the delete is now saved first and the
  restore recreates the record from the backup (backup wins); before, importers were handed the deleted
  object.
- Under More on iPhone, screens that own a stack (Settings, Ask AI, This Week's Parsha, the Group Planner)
  show two stacked bars. Pressing ⌘/ twice still opens a second Keyboard Shortcuts window (a single-window
  `Window` scene would fix it).
- On the Mac, quitting with a page turn still waiting can lose the last 1.5 s of album paging (the
  background save is iOS-only). An older build run after the vector conversion re-embeds once and leaves a
  JSON cache until that album's PDF changes.
- Today's queue engine step (~3.1 ms) still runs on the main thread; back-to-back rebuilds each start
  their own background read (older results are dropped, not coalesced).
