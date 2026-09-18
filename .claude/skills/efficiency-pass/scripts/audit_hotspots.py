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
]


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


def scan(root: str, only: set[str] | None, deep: bool = False) -> Report:
    report = Report(root=root)
    rules = [r for r in RULES if (not only or r.name in only) and (deep or not r.deep or (only and r.name in only))]
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
        for rule in rules:
            if rule.view_files_only and not is_view_file:
                continue
            if any(a in rel for a in ALLOWLIST.get(rule.name, [])):
                continue
            if rule.name == "fetch_no_batch_or_limit" and sets_batch:
                continue
            for i, ln in enumerate(lines, start=1):
                stripped = ln.strip()
                if stripped.startswith("//"):
                    continue
                if not rule.pattern.search(ln):
                    continue
                if rule.exclude_line and rule.exclude_line.search(ln):
                    continue
                if rule.body_needs is not None:
                    body = "".join(lines[i : i + 12])
                    if not rule.body_needs.search(body):
                        continue
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
