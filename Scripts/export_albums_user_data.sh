#!/bin/bash
# Exports the standalone Albums app's annotations to JSON for import into
# Maria's Notebook (Albums → Library Options → Import Albums App Data…).
#
# The notebook is sandboxed and can't read another app's container, so this
# script does the reading and writes a file you then pick in the app.
#
# Run the standalone Albums app once before this, and quit it: that pulls
# anything created on an iPhone or iPad down from iCloud into the local store.
#
# Usage: Scripts/export_albums_user_data.sh [output.json]

set -euo pipefail

OUTPUT="${1:-$HOME/Desktop/albums-export.json}"

# The app has run under both its real bundle id and Xcode's dev placeholder.
CANDIDATE_DIRS=(
    "$HOME/Library/Containers/DanielSDeBerry.Albums/Data/Library/Application Support"
    "$HOME/Library/Containers/devplaceholder.A91C9D9M.Albums/Data/Library/Application Support"
    "$HOME/Library/Application Support"
)

find_store() {
    for dir in "${CANDIDATE_DIRS[@]}"; do
        local store="$dir/default.store"
        if [[ -s "$store" ]]; then
            echo "$store"
            return 0
        fi
    done
    return 1
}

find_legacy_json() {
    for dir in "${CANDIDATE_DIRS[@]}"; do
        local json="$dir/AlbumsUserData.json"
        if [[ -s "$json" ]]; then
            echo "$json"
            return 0
        fi
    done
    return 1
}

# Core Data stores dates as seconds since 2001-01-01; JSONDecoder's default
# strategy reads seconds since 2001 too, so the raw column value carries over.
export_store() {
    local store="$1"
    echo "Reading SwiftData store: $store" >&2
    echo "Tables found: $(sqlite3 "$store" '.tables' | tr -s ' ')" >&2

    sqlite3 "$store" <<'SQL' > "$OUTPUT"
.mode json
.once /dev/stdout
SELECT json_object(
    'bookmarks', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX,
            'lessonTitle', ZLESSONTITLE, 'created', ZCREATED))
        FROM ZBOOKMARK
    ),
    'notes', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX,
            'lessonTitle', ZLESSONTITLE, 'text', ZTEXT,
            'created', ZCREATED, 'modified', ZMODIFIED))
        FROM ZPAGENOTE
    ),
    'recents', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX,
            'lessonTitle', ZLESSONTITLE, 'date', ZDATE))
        FROM ZRECENTVISIT
    ),
    'readingPositions', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX, 'updated', ZUPDATED))
        FROM ZREADINGPOSITION
    ),
    'highlights', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX,
            'lessonTitle', ZLESSONTITLE, 'text', ZTEXT,
            'colorName', ZCOLORNAME, 'created', ZCREATED))
        FROM ZHIGHLIGHT
    ),
    'ink', (
        SELECT json_group_array(json_object(
            'albumID', ZALBUMID, 'pageIndex', ZPAGEINDEX,
            'drawingData', ZDRAWINGDATA, 'modified', ZMODIFIED))
        FROM ZPAGEINK
    )
);
SQL
}

if store_path="$(find_store)"; then
    # Table names differ if the SwiftData model was renamed; show them above and
    # fall back to the JSON file if the query fails.
    if export_store "$store_path" 2>/dev/null && [[ -s "$OUTPUT" ]]; then
        echo "Wrote $OUTPUT" >&2
        echo >&2
        echo "Note: highlight rectangles and Pencil ink are stored as binary" >&2
        echo "blobs and are NOT carried by this query — bookmarks, notes," >&2
        echo "recents, and reading positions are." >&2
        exit 0
    fi
    echo "Store query failed (table names may differ); falling back to JSON." >&2
fi

if legacy_json="$(find_legacy_json)"; then
    echo "Using legacy export: $legacy_json" >&2
    cp "$legacy_json" "$OUTPUT"
    echo "Wrote $OUTPUT" >&2
    exit 0
fi

echo "Found no Albums data. Looked for default.store and AlbumsUserData.json in:" >&2
printf '  %s\n' "${CANDIDATE_DIRS[@]}" >&2
echo >&2
echo "Open the standalone Albums app once (so iCloud syncs down), quit it," >&2
echo "then run this again." >&2
exit 1
