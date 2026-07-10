#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

failed=0

fail() {
    printf 'Repository check failed: %s\n' "$1" >&2
    failed=1
}

if git ls-files | grep '/xcuserdata/' >/dev/null 2>&1; then
    fail "tracked Xcode user data was found."
fi

for path in \
    "Maria's Notebook/Backup2" \
    "Maria's Notebook/AppCore/TodayView" \
    "Maria's Notebook/ViewModels/Today" \
    "Maria's Notebook/Components/Todo" \
    "Maria's Notebook/Components/QuickNote" \
    "Maria's Notebook/Components/Observations" \
    "Maria's Notebook/Components/UnifiedNoteEditor" \
    "docs" \
    "Maria's Notebook/Docs"
do
    if [ -e "$path" ]; then
        fail "legacy path still exists: $path"
    fi
done

for directory in \
    "Maria's Notebook/Students" \
    "Maria's Notebook/Work" \
    "Maria's Notebook/Presentations" \
    "Maria's Notebook Tests"
do
    loose_file=$(find "$directory" -maxdepth 1 -type f -name '*.swift' -print -quit)
    if [ -n "$loose_file" ]; then
        fail "Swift files must be grouped below $directory (found $loose_file)."
    fi
done

empty_directory=$(find "Maria's Notebook" "Maria's Notebook Tests" Documentation -type d -empty -print -quit)
if [ -n "$empty_directory" ]; then
    fail "empty source, test, or documentation directory found: $empty_directory"
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi

printf 'Repository structure checks passed.\n'
