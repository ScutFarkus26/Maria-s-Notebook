# Energy Fifty, wave three (2026-09-26)

Wave three of the Energy Fifty audit (private artifact "Daybook Energy Fifty"; earlier waves in
`2026-09-25-energy-fifty-wave1.md` and `…-wave2.md`): memory that stays resident, plus the
remaining hidden iPad tabs. Four agents worked in parallel worktrees off 49179a46; the merged
branch passed the iOS build-for-testing, macOS and Daybook Assistant builds and the full iOS
suite on the iPhone 17 simulator (1,557 tests: 1,556 passed, 1 skipped) before landing.

| # | Change | Before → after | How measured |
|---|---|---|---|
| 5 | Idle trim of the album library's rebuildable caches (image cache left alone) | covers, folded text and query models held for the session → released on iOS background / after 10 min inactive on the Mac / when the last main window closes | `IdleMemoryTrimPolicyTests`, static |
| 47a | UIKit memory warning routed into the warning path | signals reaching the warning handler on iOS: 1 → 2, one shared 30 s throttle | `MemoryPressureMonitorTests` |
| 37 | Album covers kept as the rendered bitmap (sRGB-tagged on iOS) | iOS: 9 covers held 9.5 MB → 1.9 MB; Mac: held bytes unchanged, footprint −1.2 to −2.7 MB while encoding | `AlbumCoverTests` (byte-equal pixels), probes |
| 38 | Album PDFs open on demand and close in memory trims | PDFs open after the library loads: 9 → 0; after reading all nine and a trim: 9 → 0 | `AlbumDocumentReleaseTests` |
| 39 | Album query model released 5 min after the last search | ~40 MB resident held indefinitely → released after 5 min (17.7 MB resident returned) | `IdleCountdownTests`, probe |
| 45 | Empty Pencil canvases dropped as album pages scroll away (iPad) | 300 pages read: 300 canvases → 1 | `AlbumInkCanvasTests` |
| 40 | Photo attach through ImageIO | Mac, 48 MP HEIC: peak 861 → 385 MB, held 663 → 12 MB; 12 MP JPEG: 216 → 94 MB peak, 170 → 2 MB held; saved files byte-identical | `NotePhotoAttachmentTests`, probes |
| 41 | Photo cache 100 → 32 MB, disk hits decoded off main, no TIFF writes | main-thread disk decodes: all → none | `NotePhotoImageCacheTests` |
| 44 | Student Files grid: cached first-page thumbnails with a drawn shadow (Danny's choice) | 15 PDFs: 15 PDFDocuments + 15 PDFViews → 0/0 | `StudentFileThumbnailTests` |
| 46 | Remaining hidden iPad tabs gated | per save/import while hidden: Today ~12 fetches, Observations 1 reload, notes timeline 5 fetches, days-since up to 3 full reads, Lessons up to 3 re-derives → 0, one catch-up on return; planner/history whole-table live fetches → `count(for:)` | `HiddenTabChangeCountsTests`, static |
| 47b | Presentations doesn't refill its cache on memory pressure while hidden | 1 full refetch per warning while hidden → 0 | static |

Not done or for Danny: the album ink debounce bug (one save task for all pages) is pre-existing
and separate; `SmallSequencePlannerView` may lack its own `NavigationStack` on iPad (pre-existing);
a dispatch memory event that merges warning and critical still matches no level (pre-existing).
