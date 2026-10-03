#!/bin/zsh
# verify.sh — the "did I break anything?" gate for an efficiency pass.
#
# Builds everything that shares the touched code, through Scripts/locked_xcodebuild.sh
# (the Mac-wide build lock Tide's builds also take, so builds take turns):
#   - the app for the iOS simulator (build-for-testing, so the tests can run without rebuilding),
#   - the app for macOS,
#   - the Daybook Assistant, an iPhone/iPad app, for the same iOS simulator.
# Then runs the FULL test suite once on the iOS simulator with test-without-building
# (a test run compiles nothing, so it skips the lock) and reads the verdict, the totals
# and the failures from the .xcresult, because the xcodebuild log does not contain them.
#
# Usage:  [SIM_ID=<udid> | SIM_NAME='iPhone 17'] .claude/skills/efficiency-pass/scripts/verify.sh \
#           [--skip-tests] [--macos-tests]
#
#   --skip-tests   builds only (the quick loop while iterating; never for the final report)
#   --macos-tests  also run the suite on macOS. OFF by default: the macOS test host is the
#                  real app, whose startup runs launch repairs against Danny's LIVE store.
#                  Only pass it after a fresh backup.
#
# The default simulator is this checkout's own iPhone 17 from ~/.claude/bin/sim-lease (on a
# shared one, two sessions' runs kill each other's apps): the album semantic tests need its
# NaturalLanguage sentence model, which the iPhone Air / 17e simulators never load. In an agent worktree the build adds the prefix-mapping settings so it shares the
# compile cache with other worktrees (CLAUDE.md, "In an agent worktree").
#
# Env: BUILD_LOCK_WAIT (seconds to wait for the lock, default 3600), LOGDIR.
# Never pipe this script through `tail` or `head`; the exit code would be theirs.
# Rewritten 2026-09-27 from the gate the Energy Fifty waves used; the old version called
# xcodebuild directly (no lock) and built the Assistant for macOS, which it does not support.

emulate -R zsh
setopt no_unset pipe_fail

top=$(git rev-parse --show-toplevel 2>/dev/null) || { print "not in a git checkout"; exit 2 }
cd $top

# The project was renamed from "Maria's Notebook" to "Cosmic Daybook" on 2026-09-15; older
# worktrees still carry the old name, so derive it unless overridden.
if [[ -z ${PROJECT:-} ]]; then
  if [[ -d "Cosmic Daybook.xcodeproj" ]]; then PROJECT="Cosmic Daybook.xcodeproj"; APP_SCHEME="${APP_SCHEME:-Cosmic Daybook}"
  elif [[ -d "Maria's Notebook.xcodeproj" ]]; then PROJECT="Maria's Notebook.xcodeproj"; APP_SCHEME="${APP_SCHEME:-Maria's Notebook}"
  else print "no .xcodeproj found in $top"; exit 2; fi
fi
APP_SCHEME=${APP_SCHEME:-Cosmic Daybook}
COMPANION_SCHEME=${COMPANION_SCHEME:-Daybook Assistant}
LOGDIR=${LOGDIR:-${TMPDIR:-/tmp}/efficiency-pass-verify}
mkdir -p $LOGDIR

skip_tests=0 mac_tests=0
for a in "$@"; do
  case $a in
    --skip-tests) skip_tests=1 ;;
    --macos-tests) mac_tests=1 ;;
    *) print "unknown flag $a"; exit 2 ;;
  esac
done

# Simulator: SIM_ID is unambiguous; then the first available device with SIM_NAME, if given;
# otherwise this checkout's lease.
if [[ -n ${SIM_ID:-} ]]; then
  sim=$SIM_ID
elif [[ -z ${SIM_NAME:-} && -x ~/.claude/bin/sim-lease ]]; then
  sim=$(~/.claude/bin/sim-lease) || { print "sim-lease failed"; exit 2 }
else
  sim_name=${SIM_NAME:-iPhone 17}
  sim=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
ids = [d["udid"] for runtime, ds in devices.items() if "iOS" in runtime for d in ds if d["name"] == name]
print(ids[0] if ids else "")' $sim_name)
  [[ -n $sim ]] || { print "no available simulator named '$sim_name'; pass SIM_ID=<udid> (xcrun simctl list devices available)"; exit 2 }
fi
sim_dest="platform=iOS Simulator,id=$sim"

# Builds go through the lock when the script is there (it is on main since 2026-09-24).
if [[ -x Scripts/locked_xcodebuild.sh ]]; then build_cmd=(Scripts/locked_xcodebuild.sh)
else build_cmd=(xcodebuild); print "note: Scripts/locked_xcodebuild.sh not found; building without the lock"; fi
flags=(COMPILER_INDEX_STORE_ENABLE=NO)
if [[ $(git rev-parse --path-format=absolute --git-dir) != $(git rev-parse --path-format=absolute --git-common-dir) ]]; then
  flags+=(SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES CLANG_ENABLE_PREFIX_MAPPING=YES)
fi
print "project: $PROJECT   simulator: $sim   logs: $LOGDIR"

verify_status=0

locked() {  # locked <log> <xcodebuild arguments…>: retries while the lock was never obtained (75)
  local log=$1; shift
  local rc=0
  for attempt in 1 2 3; do
    BUILD_LOCK_WAIT=${BUILD_LOCK_WAIT:-3600} $build_cmd "$@" > $log 2>&1
    rc=$?
    (( rc == 75 )) || return $rc
    print "  (never got the build lock; retrying)"
  done
  return $rc
}

build_step() {  # build_step <label> <log name> <xcodebuild arguments…>
  local label=$1 name=$2; shift 2
  local log=$LOGDIR/$name.log
  print "\n=== $label"
  if locked $log "$@"; then
    print "ok"
    local timing others
    timing=$(grep -c "took [0-9]*ms to type-check" $log)
    others=$(grep "warning:" $log | grep -v "to type-check" | grep -v appintentsmetadataprocessor | sort -u)
    [[ -n $others ]] && { print "  warnings:"; print -r -- $others | head -10 | sed 's/^/    /' }
    (( timing > 0 )) && print "  note: $timing type-check timing warnings (wall-clock, heat-dependent; confirm with Scripts/typecheck_timing.py before acting)"
  else
    print "FAILED — errors (full log: $log):"
    grep -E "error:" $log | sort -u | head -20 | sed 's/^/  /'
    verify_status=1
  fi
}

build_step "$APP_SCHEME for the iOS simulator (build-for-testing)" app-ios \
  build-for-testing -project $PROJECT -scheme $APP_SCHEME -destination $sim_dest $flags
build_step "$APP_SCHEME for macOS" app-macos \
  build -project $PROJECT -scheme $APP_SCHEME -destination "platform=macOS" $flags
build_step "$COMPANION_SCHEME for the iOS simulator" assistant-ios \
  build -project $PROJECT -scheme $COMPANION_SCHEME -destination $sim_dest $flags

if (( verify_status != 0 )); then print "\nStopping before tests: a build failed.\nVERIFY FAILED"; exit 1; fi
if (( skip_tests )); then print "\nBuilds green; tests skipped by flag."; exit 0; fi

report_result() {  # report_result <xcresult>
  xcrun xcresulttool get test-results summary --path $1 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("  (could not read the result bundle:", e, ")"); sys.exit(0)
print("  totals: {} tests, {} passed, {} failed, {} skipped".format(
    d.get("totalTestCount"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests")))
for f in d.get("testFailures", []):
    print("  FAIL", f.get("testName"), "|", (f.get("failureText") or "").replace("\n", " ")[:300])'
}

run_suite() {  # run_suite <label> <name> <xcodebuild arguments…>
  local label=$1 name=$2; shift 2
  local log=$LOGDIR/$name.log result=$LOGDIR/$name.xcresult
  print "\n=== $label"
  rm -rf $result
  "$@" -resultBundlePath $result > $log 2>&1
  local rc=$?
  local verdict=$(grep -oE '\*\* TEST (EXECUTE )?(SUCCEEDED|FAILED) \*\*' $log | tail -1)
  print "  ${verdict:-no verdict line (did anything run? see $log)}"
  report_result $result
  if (( rc != 0 )) || [[ $verdict != *SUCCEEDED* ]]; then verify_status=1; print "  log: $log"; fi
}

run_suite "Full suite on the iOS simulator" tests-ios \
  nice -n 10 xcodebuild test-without-building -project $PROJECT -scheme $APP_SCHEME \
  -destination $sim_dest -collect-test-diagnostics never
if (( mac_tests )); then
  run_suite "Full suite on macOS (live-store warning acknowledged)" tests-macos \
    $build_cmd test -project $PROJECT -scheme $APP_SCHEME -destination "platform=macOS" $flags \
    -collect-test-diagnostics never
fi

print
if (( verify_status == 0 )); then print "VERIFY PASSED"; else print "VERIFY FAILED"; fi
exit $verify_status
