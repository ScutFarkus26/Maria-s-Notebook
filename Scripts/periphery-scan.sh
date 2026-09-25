#!/bin/zsh
# Index the app, its tests and the Daybook Assistant for macOS and the iOS Simulator, then run
# Periphery over that index with the settings in .periphery.yml. Extra arguments go to
# `periphery scan` (e.g. `--format json --write-results /tmp/unused.json`).
#
# Both platforms go into one DerivedData folder so the index holds each platform's
# `#if os(...)` code; the builds go through Scripts/locked_xcodebuild.sh like every other
# command-line build (see CLAUDE.md). Set PERIPHERY_DERIVED_DATA to put the index somewhere else.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="${PERIPHERY_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/CosmicDaybook-Periphery}"

for destination in "platform=macOS" "generic/platform=iOS Simulator"; do
  Scripts/locked_xcodebuild.sh build-for-testing -quiet -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" \
    -destination "$destination" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=YES
done
Scripts/locked_xcodebuild.sh build -quiet -project "Cosmic Daybook.xcodeproj" -scheme "Daybook Assistant" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=YES

periphery scan --index-store-path "$derived/Index.noindex/DataStore" "$@"
