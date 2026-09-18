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
    "Cosmic Daybook/Backup2" \
    "Cosmic Daybook/AppCore/TodayView" \
    "Cosmic Daybook/ViewModels/Today" \
    "Cosmic Daybook/Components/Todo" \
    "Cosmic Daybook/Components/QuickNote" \
    "Cosmic Daybook/Components/Observations" \
    "Cosmic Daybook/Components/UnifiedNoteEditor" \
    "docs" \
    "Cosmic Daybook/Docs"
do
    if [ -e "$path" ]; then
        fail "legacy path still exists: $path"
    fi
done

for directory in \
    "Cosmic Daybook/Students" \
    "Cosmic Daybook/Work" \
    "Cosmic Daybook/Presentations" \
    "Cosmic Daybook Tests"
do
    loose_file=$(find "$directory" -maxdepth 1 -type f -name '*.swift' -print -quit)
    if [ -n "$loose_file" ]; then
        fail "Swift files must be grouped below $directory (found $loose_file)."
    fi
done

empty_directory=$(find "Cosmic Daybook" "Cosmic Daybook Tests" Documentation -type d -empty -print -quit)
if [ -n "$empty_directory" ]; then
    fail "empty source, test, or documentation directory found: $empty_directory"
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi

printf 'Repository structure checks passed.\n'
