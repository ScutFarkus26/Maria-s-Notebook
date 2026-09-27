#!/usr/bin/env python3
"""Static scan for the energy / memory / heat anti-patterns that keep recurring
in Cosmic Daybook. Prints candidates grouped by rule, each as file:line so the
reader can open it. A hit is a *candidate*, not a verdict: every rule lists the
question to ask before touching the line.

Usage:
    python3 audit_hotspots.py [--root "Cosmic Daybook"] [--rule NAME ...] [--json]

Exit code is always 0; this is a reading aid, not a gate.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict

DEFAULT_ROOT = "Cosmic Daybook"

# Paths that are the sanctioned home of a pattern, or are known-good after review.
# Substring match against the path relative to --root.
ALLOWLIST = {
    "formatter_alloc": ["Utils/DateFormatters.swift", "Utils/AppLogging.swift"],
    "calendar_alloc": ["AppCore/AppCalendar.swift", "HebrewParshaService"],
    "image_decode_in_view": ["Components/CachedThumbnail.swift", "Components/AsyncCachedImage.swift"],
    "unconditional_sync_stamp": ["Services/EventKitMirror.swift"],  # stamps only rows that changed
    "ubiquity_container_lookup": ["Utils/UbiquityContainerCache.swift"],  # the off-main cache itself
}

VIEW_FILE_HINT = re.compile(r"(View|Card|Row|Cell|Sheet|Pill|Column|Tab|Section|Screen|Page)\b")


@dataclass
class Rule:
    name: str
    title: str
    why: str
    ask: str
    pattern: re.Pattern
    view_files_only: bool = False
    exclude_line: re.Pattern | None = None
    deep: bool = False  # only reported with --deep
    body_needs: re.Pattern | None = None  # for block-opening lines: the next lines must match
    # (pattern, lines before, lines after): the window around the hit, hit line included,
    # must / must not match. Lets a rule say "…with no autoreleasepool nearby".
    window_needs: tuple[re.Pattern, int, int] | None = None
    window_forbids: tuple[re.Pattern, int, int] | None = None
    file_needs: re.Pattern | None = None  # the whole file must match somewhere
    scan_comments: bool = False  # the pattern is meant to match a comment line
    block_needs: re.Pattern | None = None  # comment rules: the whole comment block must match


RULES: list[Rule] = [
    Rule(
        "formatter_alloc",
        "DateFormatter / NumberFormatter / ISO8601DateFormatter allocated inline",
        "Each formatter init loads ICU locale data; inside a view body or row builder it runs on every "
        "body pass, and SwiftUI re-runs bodies on every scroll, selection change, and Core Data merge.",
        "Is this on a per-row or per-body path? If yes, use a shared instance from Utils/DateFormatters.swift "
        "or a static let. A one-shot in an exporter or migration is fine.",
        re.compile(r"\b(DateFormatter|NumberFormatter|ISO8601DateFormatter|DateComponentsFormatter|RelativeDateTimeFormatter|MeasurementFormatter)\(\)"),
    ),
    Rule(
        "calendar_alloc",
        "Calendar(identifier:) or Calendar.current built inline",
        "Calendar construction is expensive (ICU). The app has AppCalendar.shared and the Hebrew "
        "calendars on HebrewParshaService for exactly this reason.",
        "Replace with the shared calendar unless the identifier genuinely differs.",
        re.compile(r"Calendar\(identifier:|Calendar\.current\b"),
    ),
    Rule(
        "image_decode_in_view",
        "Bitmap decoded from Data in a view file",
        "PlatformImage(data:)/UIImage(data:)/NSImage(data:) performs a full decode and allocates a bitmap. "
        "In a body it happens every pass and the previous bitmap is thrown away.",
        "Route through CachedThumbnail.image(from:cacheKey:) for Core Data blobs, or AsyncCachedImage for files.",
        re.compile(r"\b(PlatformImage|UIImage|NSImage)\(data:"),
        view_files_only=True,
    ),
    Rule(
        "fetchrequest_unpredicated",
        "@FetchRequest with no predicate (whole-table fetch per view instance)",
        "An unpredicated @FetchRequest loads and observes an entire table for the lifetime of the view. "
        "Inside a row or card that is instantiated per item, that is one table fetch per row.",
        "Is this view instantiated many times (row/card/pill)? If so, pass data in from the parent or a cache; "
        "if it is a single screen-level fetch it is usually fine. Also check the parent already passes a cache "
        "(cachedLessons:/cachedStudents:) that the child ignores when nil.",
        re.compile(r"@FetchRequest\((?![^)]*predicate)"),
        deep=True,
    ),
    Rule(
        "fetch_no_batch_or_limit",
        "NSFetchRequest executed without fetchBatchSize / fetchLimit / returnsObjectsAsFaults",
        "Materialising whole tables into memory is the main memory spike on this app, and most callers "
        "only read a handful of properties or count rows.",
        "Does the caller need every object? Prefer count(for:), dictionaryResultType, fetchLimit, or "
        "fetchBatchSize for scrolling. Files that set fetchBatchSize anywhere are skipped here; check the "
        "individual requests in files that never set it.",
        re.compile(r"\.fetch\((?!Request|Shares|History|Limit)"),
    ),
    Rule(
        "timer_without_tolerance",
        "Timer without tolerance",
        "Timers with zero tolerance wake the CPU at exact instants and prevent the kernel from coalescing "
        "wakeups; Apple asks for at least 10% tolerance for anything non-UI.",
        "Set .tolerance (Timer) or use Timer.publish(...).autoconnect with a coarse interval; for background "
        "maintenance prefer NSBackgroundActivityScheduler / BGTaskScheduler and consult EnergyPolicy.",
        re.compile(r"Timer\.(publish|scheduledTimer)|DispatchSource\.makeTimerSource"),
    ),
    Rule(
        "sleep_polling_loop",
        "while-loop polling with Task.sleep",
        "A sleep loop keeps a task alive and wakes on a schedule regardless of whether anything changed; "
        "an AsyncSequence / notification / continuation wakes only when there is work.",
        "Can this wait on a NotificationCenter.notifications(named:) sequence, an Observation change, or "
        "a continuation instead? If it must poll, is the interval coarse and bounded?",
        re.compile(r"^\s*(while|repeat)\b"),
    ),
    Rule(
        "repeat_forever_animation",
        "repeatForever animation",
        "A repeating animation forces the render server to redraw at frame rate for as long as the view is "
        "on screen, including when the window is behind another one on the Mac.",
        "Is it gated on visibility / reduceMotion / a finite state? (The 2026-09-10 audit verified the "
        "existing ones are gated; re-check only new ones.)",
        re.compile(r"repeatForever"),
    ),
    Rule(
        "high_priority_background_task",
        "Background work started at .userInitiated / .userInteractive / .high",
        "High QoS lets maintenance pre-empt the UI and runs on performance cores, which is exactly what "
        "heats the device. Work the guide did not ask for belongs at .utility or .background.",
        "Did the user tap something to start this? If not, lower it and gate on EnergyPolicy.shared.shouldDeferMaintenance.",
        re.compile(r"priority:\s*\.(userInitiated|userInteractive|high)|qos:\s*\.(userInitiated|userInteractive)"),
    ),
    Rule(
        "userdefaults_write_in_view",
        "UserDefaults write from a view file",
        "Each write is a plist serialisation plus a cfprefsd round trip; from a body or onChange it can run "
        "per keystroke.",
        "Debounce, or move the write into the model/service layer on a state transition.",
        re.compile(r"UserDefaults\.standard\.set\(|\.set\([^)]*forKey:"),
        view_files_only=True,
    ),
    Rule(
        "json_codec_inline",
        "JSONEncoder()/JSONDecoder() allocated inline",
        "Cheap individually, but SyncEventLogger used to encode 50 events per remote-change notification. "
        "Worth a look only on hot paths (sync handlers, per-save observers, per-row code).",
        "Is the enclosing function called per notification / per save / per row? If so, hoist and coalesce.",
        re.compile(r"\b(JSONEncoder|JSONDecoder|PropertyListEncoder|PropertyListDecoder)\(\)"),
        deep=True,
    ),
    Rule(
        "notification_observer_in_view",
        "NotificationCenter publisher / observer inside a view",
        "Every view instance subscribes; a per-row observer multiplies the work each notification triggers, "
        "and remote-change notifications arrive in bursts during sync.",
        "Is it debounced? Is the view a row? (RootView/StudentsView/WorksAgenda are already debounced.)",
        re.compile(r"NotificationCenter\.default\.(publisher|addObserver)|\.onReceive\(NotificationCenter"),
        view_files_only=True,
    ),
    Rule(
        "computed_property_in_view",
        "Computed properties in a view type (candidates for per-body recomputation)",
        "A `var x: T { ... }` in a View runs every time it is read, and body may read it several times. "
        "Filtering, sorting, grouping or date math here is the single most common CPU hot spot found in "
        "this app.",
        "Read the property body. If it filters/sorts/groups a collection or touches Calendar/formatters, "
        "hoist into a `let` at the top of body or precompute in the model. Trivial forwarding is fine. "
        "By default only properties read 3+ times in their file are listed (each read is a "
        "recomputation per body pass); --deep lists them all. The counter ignores same-named modifiers "
        "and labels but cannot see reads from a sibling `+Views.swift`, so treat the number as a hint.",
        re.compile(r"^\s*(private |fileprivate |internal )?var \w+\s*:\s*[\[\w<>?:, .\]]+\s*\{\s*$"),
        view_files_only=True,
        exclude_line=re.compile(r"some View|\bbody\b|@State|@Binding|@Environment|\bget\b|\bset\b"),
        body_needs=re.compile(r"\.(filter|sorted|sort|map|compactMap|flatMap|reduce|grouped|contains\(where|first\(where|allSatisfy)\b|Dictionary\(grouping|Calendar|Formatter|dateComponents|startOfDay|\.fetch\(|try\? .*fetch|\.count\b"),
    ),
    Rule(
        "task_without_id",
        ".task modifier without an id on a view with parameters",
        "A .task { } runs once per view identity; when the data it loads depends on a parameter that "
        "changes, it either reloads nothing (stale) or the view is rebuilt from scratch elsewhere. .task(id:) "
        "cancels and restarts only when the key changes.",
        "Does the loaded data depend on a value that can change while the view stays alive? Then use .task(id:).",
        re.compile(r"\.task\s*\{"),
        view_files_only=True,
        deep=True,
    ),
    Rule(
        "unbounded_cache",
        "Dictionary used as a long-lived cache",
        "Dictionaries never evict. Long-lived caches must be bounded and must drop under memory pressure "
        "(observe .memoryPressureDetected or be cleared from AppDependencies.handleMemoryPressure).",
        "Is this at type scope (static / stored on a singleton or @Observable service)? Then check it is "
        "bounded and hooked to memory pressure; NSCache is the easy answer for value blobs.",
        re.compile(r"^\s*(static\s+)?(private\s+)?var\s+\w*(cache|Cache)\w*\s*[:=]\s*\[?\["),
    ),
    # --- Added 2026-09-27 from the Energy Fifty audit and its five waves. Each was
    # checked against the commit before its fix (it flags the original) and against main.
    Rule(
        "contextmenu_builder_call",
        "Context-menu items built by a helper of the parent view",
        "`.contextMenu { … }` takes a non-escaping builder: it runs on every body pass of the view, not "
        "when the menu opens. A helper that fetches, follows relationships or looks names up runs per "
        "redraw (the Work card fetched by lessonID per card per redraw; the Week plan pill did 48 work "
        "resolutions and 24 name lookups per column redraw).",
        "Does the helper do any lookup? Move the lookups into a nested View whose body runs only when the "
        "menu is shown (SameWorkPeersMenu, WorkCardStatusMenu, WorkCheckPillStatusMenu). Plain Buttons are fine.",
        re.compile(r"\.contextMenu\s*(\(\s*menuItems:\s*)?\{\s*(?!(if|let|var|switch|for|guard)\b)[a-z_]\w*"),
    ),
    Rule(
        "offmain_claim_without_concurrent",
        "A comment says the work runs off the main thread, above an async func without @concurrent",
        "With SWIFT_APPROACHABLE_CONCURRENCY a `nonisolated async` function runs on its CALLER's actor, so "
        "called from main-actor code it runs on the main thread whatever its comment says. Only `@concurrent` "
        "leaves the main actor (2026-09-25: backup encode, encryption and verification all ran on main).",
        "Who calls it? If any caller is on the main actor and the work is CPU- or I/O-heavy, mark it "
        "`@concurrent` (Sendable arguments only), then check the comment is still true.",
        re.compile(r"^\s*//.*(off[- ]the[- ]main|off[- ]main\b|not (on )?the main (actor|thread)|global executor|on a background thread)", re.I),
        exclude_line=re.compile(r"@concurrent"),
        block_needs=re.compile(r"nonisolated async|so (it|this|that) runs|\b(it|which) runs (on|off)|runs (on the global executor|off[- ]the[- ]main)", re.I),
        window_needs=(re.compile(r"\bfunc\b[\s\S]{0,400}?\basync\b"), 0, 12),
        window_forbids=(re.compile(r"@concurrent|\.perform\s*\{|performBackgroundTask|Task\.detached"), 0, 12),
        scan_comments=True,
    ),
    Rule(
        "open_window_call",
        "openWindow(id:) on a WindowGroup, which opens a new window every call",
        "On a WindowGroup, openWindow(id:) creates another window each time; only a Window scene or a "
        "value-keyed WindowGroup brings an existing one forward. Called from a companion action or from a "
        "modifier every main window carries, it multiplies windows (2026-09-25: each companion action opened "
        "a full main window; 2026-09-27: ⌘/ opened one Keyboard Shortcuts window per main window).",
        "Should this bring an existing window forward (MainWindowRegistry.bringMostRecentForward)? Can "
        "several windows or views run it for one event (answer once: MainWindowRegistry.answersRequests)? "
        "Would a single `Window` scene be right?",
        re.compile(r"openWindow\(id:\s*\"(\w+)\"\s*\)"),
    ),
    Rule(
        "unconditional_sync_stamp",
        "A sync or import stamps a timestamp on each row it touches",
        "Every changed attribute is a CloudKit export here and an import on every other device, and it keeps "
        "the backup change gate open. A stamp nobody read, written on every row per sync, re-uploaded the "
        "whole calendar up to six times an hour (2026-09-25, EventKit mirrors).",
        "Does anything read this value? Is it written only for rows that were inserted or actually changed "
        "(assign fields only when they differ, as EventKitMirror does)?",
        re.compile(r"\.\w*([sS]ynced(At|On|Date)|[sS]yncDate|[iI]mported(At|On)|[lL]astSeen\w*)\s*=\s*(Date\(\)|\.?now\b)"),
        window_forbids=(re.compile(r"\bif\b.*(changed|didChange|isNew|inserted|isInserted|differ|!=)|guard\b.*(changed|differ)"), 4, 0),
    ),
    Rule(
        "shared_task_keyed_debounce",
        "One stored Task debounces calls made for different keys",
        "Cancelling the shared task for a call about key B drops the work still pending for key A: album ink "
        "drawn on one page, then on (or merely showing) another within 800 ms, was never saved "
        "(2026-09-27, fixed with a per-key debouncer).",
        "Do calls with different keys (page, id, album…) share this task? Key the pending work (a dictionary "
        "of tasks, or AlbumSaveDebouncer) and flush it on disappear and background.",
        re.compile(r"^\s*(self\.)?(\w+)\?\.cancel\(\)"),
    ),
    Rule(
        "model_built_in_view_init",
        "A view builds its model object in init",
        "SwiftUI re-runs a view's init on every parent redraw and keeps only the first @State value, so a "
        "model assigned in init is built and thrown away per redraw, observers and all (TodayView until "
        "2026-09-27).",
        "Is it a class / @Observable model? Create it once: an optional @State filled in onAppear/.task by "
        "the view that owns it (TodayRootView), or pass it in from a parent that already holds it.",
        re.compile(r"^\s*(self\.)?_?\w+\s*=\s*(State\((initialValue|wrappedValue):\s*)?[A-Z]\w*(ViewModel|Model|Store|Controller|Coordinator)\("),
        view_files_only=True,
        window_needs=(re.compile(r"^\s*(public |private |fileprivate |internal )?init\s*\(", re.M), 8, 0),
    ),
    Rule(
        "file_resolve_in_view",
        "A view resolves a file bookmark or stored path",
        "Resolving a bookmark or a relative path touches the file system (and, for the iCloud folder, the "
        "container lookup): 0.2 to 6 ms a call. In a computed property or helper that body reads, that is "
        "every redraw (Student Files cards, Book Club and Resource detail until 2026-09-27).",
        "It is read from body or a `some View` builder (so, per redraw). Resolve once per stored value "
        "(DocumentFileURLMemo in @State) and afresh only on tap.",
        re.compile(r"^\s*(private |fileprivate |internal )?(var \w+\s*:\s*URL\??\s*\{|func \w+\(\)\s*->\s*URL\??\s*\{)"),
        view_files_only=True,
        window_needs=(re.compile(r"resolvingBookmarkData|\.resolveURL\(|resolveBookmark\(|\.resolve\(relativePath|fileURL\(relativePath|url\(forUbiquityContainerIdentifier|fileExists\(atPath"), 0, 6),
    ),
    Rule(
        "ubiquity_container_lookup",
        "iCloud container lookup (url(forUbiquityContainerIdentifier:))",
        "Apple says not to call it on the main thread: with an account signed in it can take a long time.",
        "Is this on the main thread? Read UbiquityContainerCache instead (looked up off-main at launch and "
        "on account change, re-checked against the identity token on each read).",
        re.compile(r"url\(forUbiquityContainerIdentifier:"),
    ),
    Rule(
        "optionset_event_exact_switch",
        "A dispatch-source / option-set event matched by exact value",
        "Dispatch sources coalesce events, so `source.data` can hold several flags at once. A switch on exact "
        "values drops the merged event ([.warning, .critical] matched neither case in MemoryPressureMonitor "
        "until 2026-09-27).",
        "Can the value carry several members? Test with `contains`, most severe first.",
        re.compile(r"\bswitch\s+[\w.]*(event|Event|flags|Flags|mask|Mask|data)\s*\{"),
        file_needs=re.compile(r"DispatchSource|MemoryPressureEvent|FileSystemEvent|ProcessEvent|: OptionSet"),
        window_needs=(re.compile(r"case\s+\.\w+"), 0, 4),
    ),
    Rule(
        "numeric_vectors_as_json",
        "Numeric vectors written as JSON or a property list",
        "A float written as JSON text takes ~12-20 bytes and must be parsed back: the album vectors "
        "(746 x 1,024) were 9.4 MB of JSON and 330 ms to load, 3.1 MB and 2 ms as raw Float32 "
        "(2026-09-27, AlbumVectorCacheFile).",
        "Is this a cache of numeric arrays? Store raw little-endian Float32 behind a small versioned header, "
        "and convert an old cache once rather than rebuilding it.",
        re.compile(r"\b(JSONEncoder|PropertyListEncoder)\(\)"),
        file_needs=re.compile(r"\[\[Float\]\]"),
    ),
    Rule(
        "heavy_loop_without_pool",
        "A loop over PDF pages, embeddings or images with no autorelease pool",
        "PDFKit, NaturalLanguage and ImageIO hand back autoreleased objects; in a loop with no pool they "
        "pile up until the whole job ends (746 embeddings peaked at 130 MB, 27 MB with a pool per item). "
        "PDFKit also keeps every page's layout until its document closes (a 500-page extraction peaked at "
        "447 MB; reopening the document every 50 pages brought it to 82 MB, AlbumPageTextReader).",
        "Wrap each iteration in `autoreleasepool`; for long PDFs, reopen the document every N pages.",
        re.compile(r"^\s*for\b.*\bin\b.*\{\s*$|\.(map|compactMap|flatMap|forEach)\s*\{"),
        window_needs=(re.compile(r"\.page\(at:|vector\(for:|embeddingResult\(|CGImageSourceCreate|PDFDocument\(url:"), 0, 6),
        window_forbids=(re.compile(r"autoreleasepool"), 2, 3),
    ),
    Rule(
        "offset_paging",
        "Paging with fetchOffset",
        "With pending changes included, offset pages shift: an unsaved insert lands on every page and pushes "
        "a saved row off (the backup collector until 2026-09-26). An in-memory store pages an unsorted fetch "
        "wrongly. And a loop that stops on a short page of *results* (after filtering or transforming) ends "
        "early.",
        "Is `includesPendingChanges = false` set (with the context's inserts added once and deleted rows "
        "dropped)? Is the order stable (sorted, SQLite)? Does the loop stop on a short page of rows, not "
        "of results?",
        re.compile(r"\.fetchOffset\s*="),
        window_forbids=(re.compile(r"includesPendingChanges\s*=\s*false"), 15, 15),
    ),
]

# Rules whose check needs more than one line's regex, keyed by rule name.
KEYED_PARAM = re.compile(r"\bfunc\s+\w+\s*\([^)]*\b\w*(index|Index|id|ID|Id|key|Key|page|Page)\w*\s*:")


@dataclass
class Hit:
    rule: str
    file: str
    line: int
    text: str


@dataclass
class Report:
    root: str
    hits: dict[str, list[Hit]] = field(default_factory=dict)


def iter_swift_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".build", "DerivedData", "worktrees"}]
        for name in filenames:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def around(lines: list[str], i: int, before: int, after: int) -> str:
    """Lines around hit line `i` (1-based), the hit line included."""
    return "".join(lines[max(0, i - 1 - before) : i + after])


def window_group_ids(root: str) -> set[str]:
    """Scene ids of WindowGroups that take no value: openWindow(id:) opens a new one per call."""
    ids: set[str] = set()
    scene = re.compile(r"WindowGroup\s*\((?![^)]*\bfor:)[^)]*\bid:\s*\"(\w+)\"")
    for path in iter_swift_files(root):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                ids.update(scene.findall(fh.read()))
        except OSError:
            continue
    return ids


DECL = re.compile(r"^\s*(@\w+(\([^)]*\))?\s+)*((private|fileprivate|internal|public)\s+)?(static\s+)?(func|var)\s+(\w+)")


def read_from_view_builder(path: str, name: str) -> bool:
    """Whether `name` is read inside `body` or another `some View` builder of the
    same type (its own file plus the type's `+Topic.swift` siblings)."""
    folder, base = os.path.split(path)
    type_name = base.split("+")[0].removesuffix(".swift")
    ref = re.compile(rf"(?<![\w.]){re.escape(name)}\b|\bself\.{re.escape(name)}\b")
    for sibling in os.listdir(folder):
        if not (sibling == f"{type_name}.swift" or sibling.startswith(f"{type_name}+")):
            continue
        try:
            with open(os.path.join(folder, sibling), encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for n, ln in enumerate(lines):
            if not ref.search(ln) or ln.strip().startswith("//"):
                continue
            decl = DECL.match(ln)
            if decl and decl.group(7) == name:
                continue  # the declaration itself
            for back in range(n, max(-1, n - 80), -1):
                enclosing = DECL.match(lines[back])
                if enclosing:
                    if "some View" in lines[back] or enclosing.group(7) == "body":
                        return True
                    break
    return False


def keyed_debounce_hit(lines: list[str], i: int, ln: str) -> bool:
    """`task?.cancel()` followed by `task = Task` inside a func that takes a key parameter."""
    m = re.match(r"^\s*(self\.)?(\w+)\?\.cancel\(\)", ln)
    if not m:
        return False
    name = m.group(2)
    if not re.search(rf"\b{re.escape(name)}\s*=\s*Task\b", around(lines, i, 0, 4)):
        return False
    for back in range(i - 1, max(0, i - 12), -1):
        if re.search(r"\bfunc\b", lines[back - 1]):
            return bool(KEYED_PARAM.search("".join(lines[back - 1 : back + 2])))
    return False


MENU_LOOKUP = re.compile(
    r"\.(fetch|safeFetch|count)\(|\bsafeFetch\(|\bresolved\w*\(|\bgroup\(containing|\.first\(where|"
    r"\.filter\s*\{|\.rows\(|\.children\(|\blookup\w*\(|\bexistingObject\(|\bcatalog\.\w+\(|"
    r"\bfetchRequest\b|\bname\(for"
)


def view_builder_bodies(root: str) -> dict[str, list[str]]:
    """Bodies of `var x: some View { … }` and `func x(…) -> some View { … }`, by name."""
    bodies: dict[str, list[str]] = {}
    head = re.compile(r"\b(?:var|func)\s+(\w+)\b[^{]*some View")
    for path in iter_swift_files(root):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for n, ln in enumerate(lines):
            m = head.search(ln)
            if not m:
                continue
            depth, opened, body = 0, False, []
            for ln2 in lines[n : n + 150]:
                body.append(ln2)
                depth += ln2.count("{") - ln2.count("}")
                opened = opened or "{" in ln2
                if opened and depth <= 0:
                    break
            bodies.setdefault(m.group(1), []).append("".join(body))
    return bodies


def scan(root: str, only: set[str] | None, deep: bool = False) -> Report:
    report = Report(root=root)
    rules = [r for r in RULES if (not only or r.name in only) and (deep or not r.deep or (only and r.name in only))]
    group_ids = window_group_ids(root) if any(r.name == "open_window_call" for r in rules) else set()
    reported_blocks: set[tuple[str, str, int]] = set()
    menu_bodies = view_builder_bodies(root) if any(r.name == "contextmenu_builder_call" for r in rules) else {}
    for path in iter_swift_files(root):
        rel = os.path.relpath(path, root)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        is_view_file = bool(VIEW_FILE_HINT.search(os.path.basename(rel))) or any(
            "some View" in ln for ln in lines[:400]
        )
        sets_batch = any("fetchBatchSize" in ln or "fetchLimit" in ln or "returnsObjectsAsFaults" in ln for ln in lines)
        whole = "".join(lines)
        for rule in rules:
            if rule.view_files_only and not is_view_file:
                continue
            if any(a in rel for a in ALLOWLIST.get(rule.name, [])):
                continue
            if rule.name == "fetch_no_batch_or_limit" and sets_batch:
                continue
            if rule.file_needs is not None and not rule.file_needs.search(whole):
                continue
            for i, ln in enumerate(lines, start=1):
                stripped = ln.strip()
                if stripped.startswith("//") != rule.scan_comments:
                    continue
                if not rule.pattern.search(ln):
                    continue
                if rule.exclude_line and rule.exclude_line.search(ln):
                    continue
                if rule.block_needs is not None:
                    start, end = i, i
                    while start > 1 and lines[start - 2].strip().startswith("//"):
                        start -= 1
                    while end < len(lines) and lines[end].strip().startswith("//"):
                        end += 1
                    if (rule.name, rel, start) in reported_blocks:
                        continue
                    block = " ".join(ln2.strip().lstrip("/").strip() for ln2 in lines[start - 1 : end])
                    if not rule.block_needs.search(block):
                        continue
                    reported_blocks.add((rule.name, rel, start))
                if rule.body_needs is not None:
                    body = "".join(lines[i : i + 12])
                    if not rule.body_needs.search(body):
                        continue
                if rule.window_needs is not None:
                    pat, before, after = rule.window_needs
                    if not pat.search(around(lines, i, before, after)):
                        continue
                if rule.window_forbids is not None:
                    pat, before, after = rule.window_forbids
                    if pat.search(around(lines, i, before, after)):
                        continue
                if rule.name == "open_window_call":
                    m = rule.pattern.search(ln)
                    if not m or m.group(1) not in group_ids:
                        continue
                if rule.name == "shared_task_keyed_debounce" and not keyed_debounce_hit(lines, i, ln):
                    continue
                if rule.name == "file_resolve_in_view":
                    decl = DECL.match(ln)
                    if not decl or not read_from_view_builder(path, decl.group(7)):
                        continue  # resolved only on a tap or in an action: fine
                if rule.name == "contextmenu_builder_call":
                    m = re.search(r"\{\s*([a-z_]\w*)", ln[ln.index(".contextMenu"):])
                    helper = m.group(1) if m else ""
                    found = menu_bodies.get(helper, [])
                    if found and not any(MENU_LOOKUP.search(b) for b in found):
                        continue  # the helper only builds items; lookups, if any, live in a nested View
                    stripped = f"{stripped}   [helper {'not found' if not found else 'does lookups'}]"
                if rule.name == "sleep_polling_loop":
                    window = "".join(lines[i - 1 : i + 6])
                    if "Task.sleep" not in window and "sleep(" not in window:
                        continue
                text = stripped[:140]
                if rule.name == "computed_property_in_view":
                    m = re.search(r"var (\w+)\s*:", ln)
                    name = m.group(1) if m else ""
                    # Count reads, not the SwiftUI modifier of the same name
                    # (`.accessibilityLabel(...)` is not a read of `accessibilityLabel`)
                    # and not argument labels (`name:`). Reads from sibling files of the
                    # same type (`+Views.swift`) are not seen, so a low count can be wrong.
                    read_pat = re.compile(rf"(?<![.\w]){re.escape(name)}\b(?!\s*[:(])|\bself\.{re.escape(name)}\b(?!\s*[:(])")
                    refs = sum(len(read_pat.findall(other)) for other in lines) - 1 if name else 0
                    if refs < 3 and not deep:
                        continue
                    text = f"[{refs} reads in file] {text}"
                report.hits.setdefault(rule.name, []).append(Hit(rule.name, rel, i, text))
    if "computed_property_in_view" in report.hits:
        report.hits["computed_property_in_view"].sort(
            key=lambda h: -int(re.match(r"\[(\d+) reads", h.text).group(1)) if h.text.startswith("[") else 0
        )
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--rule", action="append", help="limit to these rule names (repeatable)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--deep", action="store_true", help="also report the low-signal rules (unpredicated @FetchRequest, inline JSON codecs, .task without id)")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args()

    if args.list_rules:
        for r in RULES:
            print(f"{r.name:32} {'[deep] ' if r.deep else ''}{r.title}")
        return 0

    if not os.path.isdir(args.root):
        # The app folder was renamed 2026-09-15; older worktrees still use the old name.
        legacy = "Maria's Notebook"
        if args.root == DEFAULT_ROOT and os.path.isdir(legacy):
            print(f"note: '{DEFAULT_ROOT}' not found, scanning legacy folder '{legacy}'\n", file=sys.stderr)
            args.root = legacy
        else:
            print(f"ROOT NOT FOUND: {args.root}. Run from the repo root or pass --root <app source folder>.", file=sys.stderr)
            return 2

    report = scan(args.root, set(args.rule) if args.rule else None, deep=args.deep)
    if args.json:
        print(json.dumps({k: [asdict(h) for h in v] for k, v in report.hits.items()}, indent=2))
        return 0

    total = sum(len(v) for v in report.hits.values())
    print(f"# Efficiency audit — {total} candidate(s) under {args.root}\n")
    print("A hit is a place to *read*, not a defect. Each rule ends with the question to answer first.\n")
    for rule in RULES:
        hits = report.hits.get(rule.name)
        if not hits:
            continue
        print(f"## {rule.title}  ({len(hits)})")
        print(f"Why: {rule.why}")
        print(f"Ask: {rule.ask}\n")
        for h in hits:
            print(f"  {h.file}:{h.line}  {h.text}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
