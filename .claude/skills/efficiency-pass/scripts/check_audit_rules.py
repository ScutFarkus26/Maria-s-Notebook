#!/usr/bin/env python3
"""Regression check for audit_hotspots.py's rules.

Each case names a rule, a commit from before the fix that rule was written for, and the
file (optionally `file|text in the hit line`) it must flag there. `after` is a commit where
the fix had landed: a case marked fixed must no longer flag that file there. Run from the
repo root after adding or changing a rule, and add a case for any new rule:

    python3 .claude/skills/efficiency-pass/scripts/check_audit_rules.py [--keep]

The commits' app folders are exported with `git archive` into a temporary directory
(removed afterwards unless --keep). Exits non-zero if any case fails.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "audit_hotspots.py")
APP = "Cosmic Daybook"
AFTER = "20e21cbd"  # main after wave five of the Energy Fifty (2026-09-27)

# (rule, commit before the fix, "file[|text]", fixed on AFTER?)  None = still flagged on purpose
CASES = [
    ("contextmenu_builder_call", "9b10bf8e", "Work/WorkCard/WorkCard+Grid.swift", True),
    ("contextmenu_builder_call", "3035fa87", "Presentations/Planning/WeekDayColumn+Bands.swift", True),
    ("offmain_claim_without_concurrent", "8396f391", "Backup/Archive/BackupWriter.swift", True),
    ("offmain_claim_without_concurrent", "8396f391", "Backup/Archive/BackupImporter.swift", True),
    ("open_window_call", "8396f391", "AppCore/RootView/DesktopNotebookCompanionView.swift", None),
    ("open_window_call", "3035fa87", "Components/OpenWindowOnNotificationModifier.swift", None),
    ("unconditional_sync_stamp", "8396f391", "Services/CalendarSyncService.swift", True),
    ("unconditional_sync_stamp", "8396f391", "Services/ReminderSyncService+Sync.swift", True),
    ("shared_task_keyed_debounce", "3035fa87", "Albums/AlbumDetailView.swift", True),
    ("model_built_in_view_init", "3035fa87", "Today/Views/TodayView.swift", True),
    ("file_resolve_in_view", "3035fa87", "Students/Files/DocumentCard.swift", True),
    ("file_resolve_in_view", "3035fa87", "BookClub/Packets/BookClubPacketDetailView.swift", True),
    ("file_resolve_in_view", "3035fa87", "Resources/ResourceDetailView.swift", True),
    ("ubiquity_container_lookup", "3035fa87", "Utils/ManagedPDFFileStorage.swift", True),
    ("optionset_event_exact_switch", "3035fa87", "Services/MemoryPressureMonitor.swift", True),
    ("numeric_vectors_as_json", "3035fa87", "Albums/AlbumSemanticIndex.swift", True),
    ("heavy_loop_without_pool", "3035fa87", "Albums/AlbumLibrary.swift|0..<doc.pageCount", True),
    ("heavy_loop_without_pool", "3035fa87", "Albums/AlbumSemanticIndex.swift", True),
    ("offset_paging", "196babd3", "Backup/BackupService+DataCollection.swift", True),
    # Fixed after AFTER (2026-09-28), so it is not checked there.
    ("repeat_forever_animation", "cfcf9043", "Settings/CloudKitStatusSettingsView.swift", None),
]


def export(commit: str, dest: str) -> str:
    root = os.path.join(dest, commit)
    if not os.path.isdir(root):
        os.makedirs(root)
        archive = subprocess.run(["git", "archive", commit, APP], capture_output=True, check=True)
        subprocess.run(["tar", "-x", "-C", root], input=archive.stdout, check=True)
    return os.path.join(root, APP)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--keep", action="store_true", help="keep the exported trees")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="audit-rules-")
    cache: dict[tuple[str, str], list[dict]] = {}

    def hits(commit: str, rule: str) -> list[dict]:
        if (commit, rule) not in cache:
            out = subprocess.run([sys.executable, AUDIT, "--root", export(commit, tmp), "--rule", rule, "--json"],
                                 capture_output=True, text=True, check=True).stdout
            cache[(commit, rule)] = json.loads(out).get(rule, [])
        return cache[(commit, rule)]

    def matching(commit: str, rule: str, target: str) -> list[dict]:
        path, _, text = target.partition("|")
        return [h for h in hits(commit, rule) if h["file"] == path and text in h["text"]]

    failures = 0
    try:
        for rule, before, target, fixed in CASES:
            found = matching(before, rule, target)
            after = bool(matching(AFTER, rule, target))
            ok = bool(found) and (fixed is None or after != fixed)
            failures += not ok
            lines = ",".join(str(h["line"]) for h in found) or "-"
            print(f"{'ok  ' if ok else 'FAIL'} {rule:34} {before}: {'flagged' if found else 'MISSED'} (line {lines})"
                  f"   {AFTER}: {'still flagged' if after else 'clean'}   {target}")
    finally:
        if args.keep:
            print(f"\ntrees kept in {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{len(CASES) - failures} of {len(CASES)} cases pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
