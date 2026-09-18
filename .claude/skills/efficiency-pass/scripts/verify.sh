#!/bin/zsh
# verify.sh — the "did I break anything?" gate for an efficiency pass.
#
# Builds every target that shares the touched code, then runs the FULL test
# suite on the iOS simulator, serially (two xcodebuilds at once lock the build
# database). Prints the real verdict line and pulls failure messages out of the
# .xcresult, because the xcodebuild log does not contain them.
#
# Usage:  [SIM_ID=<udid> | SIM_NAME='iPhone 17 Pro'] [PROJECT=… APP_SCHEME=…] \
#           .claude/skills/efficiency-pass/scripts/verify.sh [--skip-tests] [--macos-tests]
#
#   --skip-tests   build only (quick loop while iterating)
#   --macos-tests  also run the suite on macOS. OFF by default: the macOS test
#                  host launches the real app, whose startup runs the launch
#                  repairs against Danny's LIVE store. Only pass this after a
#                  fresh backup.
#
# Never pipe this script through `tail` or `head`; the exit code would be tail's.

set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

# The project was renamed from "Maria's Notebook" to "Cosmic Daybook" on 2026-09-15;
# older worktrees still carry the old name, so derive it unless overridden.
if [ -z "${PROJECT:-}" ]; then
  if [ -d "Cosmic Daybook.xcodeproj" ]; then PROJECT="Cosmic Daybook.xcodeproj"; APP_SCHEME="${APP_SCHEME:-Cosmic Daybook}"
  elif [ -d "Maria's Notebook.xcodeproj" ]; then PROJECT="Maria's Notebook.xcodeproj"; APP_SCHEME="${APP_SCHEME:-Maria's Notebook}"
  else echo "no .xcodeproj found in $(pwd)"; exit 2; fi
fi
APP_SCHEME="${APP_SCHEME:-Cosmic Daybook}"
COMPANION_SCHEME="${COMPANION_SCHEME:-Daybook Assistant}"
# Simulator: SIM_ID=<UDID> is unambiguous (this Mac has two devices named "iPhone 17" and two
# "iPhone 17 Pro"; `xcrun simctl list devices available`). SIM_NAME is the fallback.
if [ -n "${SIM_ID:-}" ]; then SIM_DEST="platform=iOS Simulator,id=${SIM_ID}"
else SIM_NAME="${SIM_NAME:-iPhone 17}"; SIM_DEST="platform=iOS Simulator,name=${SIM_NAME},OS=27.0"; fi
MAC_DEST="platform=macOS"
LOGDIR="${TMPDIR:-/tmp}/efficiency-pass-verify"
mkdir -p "$LOGDIR"

SKIP_TESTS=0; MAC_TESTS=0
for a in "$@"; do
  case "$a" in
    --skip-tests) SKIP_TESTS=1 ;;
    --macos-tests) MAC_TESTS=1 ;;
    *) echo "unknown flag $a"; exit 2 ;;
  esac
done

verify_status=0
step() { echo; echo "=== $1"; }

run_build() { # scheme dest logname
  local log="$LOGDIR/$3.log"
  xcodebuild build -project "$PROJECT" -scheme "$1" -destination "$2" -quiet > "$log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "BUILD FAILED ($1, $2) — errors:"; grep -E "error:" "$log" | head -30
    verify_status=1
  else
    echo "build ok ($1, $2)"
    local warn; warn=$(grep -cE "warning: .*(took|expression|main actor|Sendable)" "$log")
    [ "$warn" -gt 0 ] && echo "  note: $warn isolation/type-check warnings, see $log"
  fi
}

step "Build $APP_SCHEME (iOS simulator)";   run_build "$APP_SCHEME" "$SIM_DEST" app-ios
step "Build $APP_SCHEME (macOS)";           run_build "$APP_SCHEME" "$MAC_DEST" app-macos
step "Build $COMPANION_SCHEME (macOS)";     run_build "$COMPANION_SCHEME" "$MAC_DEST" companion-macos

if [ $verify_status -ne 0 ]; then echo; echo "Stopping before tests: a build failed."; exit 1; fi
if [ $SKIP_TESTS -eq 1 ]; then echo; echo "Builds green; tests skipped by flag."; exit 0; fi

run_tests() { # dest logname
  local log="$LOGDIR/$2.log"
  local before; before=$(ls -dt ~/Library/Developer/Xcode/DerivedData/*/Logs/Test/*.xcresult 2>/dev/null | head -1)
  xcodebuild test -project "$PROJECT" -scheme "$APP_SCHEME" -destination "$1" > "$log" 2>&1
  local rc=$?
  local verdict; verdict=$(grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" "$log" | tail -1)
  # XCTest prints "Executed N tests"; Swift Testing prints "Test run with N tests passed/failed".
  local executed; executed=$(grep -E "Executed [0-9]+ tests?|Test run with [0-9]+ tests? (passed|failed)" "$log" | tail -2 | tr '\n' ' ')
  echo "${verdict:-no verdict line found} — ${executed:-no test-count line found (suspicious: did anything run?)}"
  local newest; newest=$(ls -dt ~/Library/Developer/Xcode/DerivedData/*/Logs/Test/*.xcresult 2>/dev/null | head -1)
  if [ $rc -ne 0 ] || [ -z "$verdict" ] || echo "$verdict" | grep -q FAILED; then
    verify_status=1
    if [ -n "$newest" ] && [ "$newest" != "$before" ]; then
      echo "Failures from $newest:"
      xcrun xcresulttool get test-results tests --path "$newest" --compact 2>/dev/null \
        | python3 -c 'import json,sys
def walk(n):
    if isinstance(n,dict):
        if n.get("result")=="Failed" and n.get("nodeType")=="Test Case":
            print(" -",n.get("name"))
            for c in n.get("children",[]):
                if c.get("nodeType")=="Failure Message": print("     ",c.get("name"))
        for c in n.get("children",[]): walk(c)
    elif isinstance(n,list):
        for c in n: walk(c)
try: walk(json.load(sys.stdin))
except Exception as e: print("   (could not parse xcresult:",e,")")'
    fi
    echo "Full log: $log"
  fi
}

step "Test suite (iOS simulator)"; run_tests "$SIM_DEST" tests-ios
if [ $MAC_TESTS -eq 1 ]; then step "Test suite (macOS — live-store warning acknowledged)"; run_tests "$MAC_DEST" tests-macos; fi

echo
if [ $verify_status -eq 0 ]; then echo "VERIFY PASSED"; else echo "VERIFY FAILED"; fi
exit $verify_status
