#!/bin/zsh
# Index the app, its tests and the Daybook Assistant for macOS and the iOS Simulator, then run
# Periphery over that index with the settings in .periphery.yml. Extra arguments go to
# `periphery scan` (e.g. `--format json --write-results /tmp/unused.json`).
#
# Both platforms go into one DerivedData folder so the index holds each platform's
# `#if os(...)` code; the builds go through Scripts/locked_xcodebuild.sh like every other
# command-line build (see CLAUDE.md). Set PERIPHERY_DERIVED_DATA to put the index somewhere else.
#
# These builds run WITHOUT the shared compilation cache (~/.claude/xcode-compilation-cache.xcconfig,
# applied through XCODE_XCCONFIG_FILE). Its prefix mapping records every source file in the index
# as `/^src/…` instead of its real path, so Periphery matches nothing and reports `[]` with exit 0
# — it did exactly that, silently, from 2026-09-27 (when the cache went in) until 2026-09-30. The check after the builds
# refuses to scan such an index rather than print another empty result.
set -euo pipefail
cd "$(dirname "$0")/.."
unset XCODE_XCCONFIG_FILE

derived="${PERIPHERY_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/CosmicDaybook-Periphery}"

for destination in "platform=macOS" "generic/platform=iOS Simulator"; do
  Scripts/locked_xcodebuild.sh build-for-testing -quiet -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" \
    -destination "$destination" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=YES
done
Scripts/locked_xcodebuild.sh build -quiet -project "Cosmic Daybook.xcodeproj" -scheme "Daybook Assistant" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=YES

units="$derived/Index.noindex/DataStore/v5/units"
if grep -rlqa -- '/^src/' "$units" 2>/dev/null; then
  print -u2 "periphery-scan: the index at $derived holds prefix-mapped (/^src/) paths, so Periphery would report nothing."
  print -u2 "  Delete $derived/Index.noindex and run again."
  exit 1
fi

periphery scan --index-store-path "$derived/Index.noindex/DataStore" "$@"
