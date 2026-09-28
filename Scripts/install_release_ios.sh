#!/bin/zsh
# Builds a Release copy of main for iOS and installs it on Danny's iPhone and
# iPad mini: the iOS half of Scripts/install_release.sh. Run it after merging to
# main; until then the devices keep the code they were built from.
#
#   Scripts/install_release_ios.sh                    # build main, install on both
#   Scripts/install_release_ios.sh --only <udid>      # build main, install on that one
#   Scripts/install_release_ios.sh --archive <path>   # reinstall an existing archive
#   (--only repeats, and combines with --archive)
#
# - Builds main's last commit, never a working tree: a detached worktree of main
#   at .claude/worktrees/release-install-ios, removed afterwards.
# - Archives it (Release, generic iOS) through Scripts/locked_xcodebuild.sh. The
#   archive, dSYM included, stays in Xcode's Organizer
#   (~/Library/Developer/Xcode/Archives), so crash reports can be symbolicated.
# - Signs it the way the Debug builds are signed (Apple Development, automatic),
#   so the devices stay on the CloudKit Development environment like the Mac.
# - Installs over the existing app with devicectl, which keeps the app's data.
#   A device that is locked, asleep too long, or out of reach fails on its own
#   and the others still install; rerun with --archive to finish it without
#   building again.
# - Never registers a device. One missing from the team profile fails with a
#   provisioning error: registering uses a slot on the developer account, so
#   Danny decides (see the roll-out skill).
#
# BUILD_LOCK_WAIT   passed to Scripts/locked_xcodebuild.sh (default here 3600 s).

emulate -R zsh
setopt no_unset pipe_fail

me=${0:t}
die() { print -u2 "$me: $*"; exit 1 }

typeset -A device_names=(
  00008160-001C18C90CC00036 "Danny's iPhone (iPhone 18 Pro)"
  00008130-0009713E3E41001C "Danny's MiniPad (iPad mini A17 Pro)"
)
devices=()
archive=
while (( $# )); do
  case $1 in
    --archive) [[ -n ${2-} ]] || die "--archive needs a path"; archive=${2:A}; shift 2 ;;
    --only) [[ -n ${2-} ]] || die "--only needs a UDID"; devices+=($2); shift 2 ;;
    *) die "usage: $me [--only <udid>]… [--archive <path to .xcarchive>]" ;;
  esac
done
(( $#devices )) || devices=(00008160-001C18C90CC00036 00008130-0009713E3E41001C)

common=$(git -C ${0:A:h} rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "run it from a checkout of the Cosmic Daybook repository"
repo=${common:h}
app_name="Cosmic Daybook.app"
bundle_id=DanielSDeBerry.MariasNoteBook
worktree=$repo/.claude/worktrees/release-install-ios
derived=$HOME/Library/Developer/Xcode/DerivedData/CosmicDaybook-ReleaseInstall-iOS

if [[ -z $archive ]]; then
  sha=$(git -C $repo rev-parse --short main 2>/dev/null) || die "no main branch in $repo"
  print "Building a Release copy of main for iOS: $sha $(git -C $repo log -1 --format=%s main)"

  if [[ -e $worktree ]]; then
    git -C $repo worktree remove --force $worktree 2>/dev/null || die "cannot clear $worktree from an earlier run"
  fi
  git -C $repo worktree add --quiet --detach $worktree main || die "cannot create $worktree"
  trap 'git -C $repo worktree remove --force $worktree 2>/dev/null' EXIT

  archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Cosmic Daybook iOS $(date '+%Y-%m-%d %H%M') $sha.xcarchive"
  log=${TMPDIR:-/tmp}/cosmic-daybook-release-ios-$sha.log
  mkdir -p ${archive:h} || die "cannot create ${archive:h}"
  if ! (
    cd $worktree &&
    BUILD_LOCK_WAIT=${BUILD_LOCK_WAIT:-3600} Scripts/locked_xcodebuild.sh archive \
      -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath $derived -archivePath $archive \
      -allowProvisioningUpdates COMPILER_INDEX_STORE_ENABLE=NO
  ) > $log 2>&1; then
    tail -25 $log >&2
    die "the Release build failed (exit status 75 means it never got the build lock); full log: $log"
  fi
fi

app=$archive/Products/Applications/$app_name
[[ -d $app ]] || die "no $app_name in $archive"
codesign --verify --deep --strict $app 2>/dev/null || die "the new copy's signature does not verify: $app"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $app/Info.plist) == $bundle_id ]] \
  || die "the new copy is not $bundle_id: $app"
profile=$(security cms -D -i $app/embedded.mobileprovision 2>/dev/null)
expiry=$(print -r -- $profile | plutil -extract ExpirationDate raw -o - - 2>/dev/null)

failed=()
for udid in $devices; do
  name=${device_names[$udid]:-$udid}
  if ! print -r -- $profile | grep -q $udid; then
    print -u2 "✗ $name: not in the embedded provisioning profile (the device needs registering first)"
    failed+=($udid); continue
  fi
  print "Installing on $name…"
  if out=$(xcrun devicectl device install app --device $udid $app 2>&1); then
    print "✓ $name"
  else
    print -u2 "✗ $name"
    print -r -u2 -- ${out} | grep -iE 'error|unlock|not (connected|available|paired)' | head -5 | sed 's/^/    /' >&2
    [[ $out == *10003* || $out == *nlock* ]] && print -u2 "    Unlock the device, then rerun with --archive."
    failed+=($udid)
  fi
done

print "  archive with dSYM: $archive"
print "  development profile valid until ${expiry:-unknown}"
if (( $#failed )); then
  print -u2 "$me: not installed on ${#failed} device(s). Retry without rebuilding:"
  retry=(${failed/#/--only })
  print -u2 "  Scripts/install_release_ios.sh ${retry} --archive '$archive'"
  exit 2
fi
