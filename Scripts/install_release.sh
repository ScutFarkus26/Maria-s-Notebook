#!/bin/zsh
# Builds a Release copy of main and installs it as /Applications/Cosmic Daybook.app:
# Danny's everyday copy, and the one the MCP bridge (Scripts/mcp/cosmic-daybook-mcp)
# launches for Claude when no copy is running. Run it after merging to main; until
# then the installed copy keeps the code it was built from.
#
#   Scripts/install_release.sh
#   Scripts/install_release.sh --quit       # quit a running installed copy instead of refusing
#   Scripts/install_release.sh --relaunch   # open the new copy once it is installed
#
# - Builds main's last commit, never a working tree: a detached worktree of main
#   at .claude/worktrees/release-install, removed afterwards, so uncommitted edits
#   and untracked files never ship.
# - Archives it (Release, this Mac's architecture only) through
#   Scripts/locked_xcodebuild.sh. The archive, dSYM included, stays in Xcode's
#   Organizer (~/Library/Developer/Xcode/Archives), so crash reports from the
#   installed copy can be symbolicated. Derived data is kept in
#   ~/Library/Developer/Xcode/DerivedData/CosmicDaybook-ReleaseInstall for the
#   next run.
# - Signs it the way the Debug builds are signed (Apple Development, automatic):
#   the same bundle id, sandbox container and CloudKit Development environment, so
#   it opens the same notebook. Distribution signing would move it to the
#   Production environment. The development profile expires; the script prints
#   the date, and any run before it renews it.
# - Refuses to replace the installed copy while it is running (it may be an
#   MCP-only copy with no window, launched by the bridge), unless --quit: then it
#   quits that copy right before the swap — a normal Quit, then SIGTERM after 15 s,
#   then SIGKILL after 10 more. The
#   replaced copy goes to the Trash as a zip.
# - Last, drops the LaunchServices registrations of the bundle id whose app is
#   gone from disk or in the Trash (every worktree build that has since been
#   removed leaves one), so Spotlight and Shortcuts have fewer stale copies to
#   pick from. Live Xcode builds stay registered; each build registers itself.
#
# BUILD_LOCK_WAIT  passed to Scripts/locked_xcodebuild.sh (default here 3600 s).

emulate -R zsh
setopt no_unset pipe_fail

me=${0:t}
die() { print -u2 "$me: $*"; exit 1 }

common=$(git -C ${0:A:h} rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "run it from a checkout of the Cosmic Daybook repository"
repo=${common:h}
app_name="Cosmic Daybook.app"
dest=/Applications/$app_name
bundle_id=DanielSDeBerry.MariasNoteBook
worktree=$repo/.claude/worktrees/release-install
derived=$HOME/Library/Developer/Xcode/DerivedData/CosmicDaybook-ReleaseInstall
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

force_quit=0 relaunch=0
for arg; do
  case $arg in
    --quit) force_quit=1 ;;
    --relaunch) relaunch=1 ;;
    *) die "usage: $me [--quit] [--relaunch]" ;;
  esac
done

# Stops here while the installed copy runs: replacing a running app's files can
# crash it, and it holds the notebook open. Matches the executable path exactly
# (`comm`), never a command line, which would find this awk itself.
installed_pids() {
  ps -axo pid=,comm= | awk -v exe="$dest/Contents/MacOS/Cosmic Daybook" \
    '{ pid = $1; sub(/^ *[0-9]+ +/, ""); if ($0 == exe) print pid }'
}

refuse_if_running() {
  local pids
  pids=$(installed_pids)
  [[ -z $pids ]] && return 0
  (( force_quit )) && return 0
  print -u2 "$me: $dest is running (pid ${pids//$'\n'/, }). It may be an MCP-only copy with no window."
  print -u2 "  Quit it (right-click its Dock icon ▸ Quit), then run this again."
  exit 1
}

refuse_if_running

sha=$(git -C $repo rev-parse --short main 2>/dev/null) || die "no main branch in $repo"
print "Building a Release copy of main: $sha $(git -C $repo log -1 --format=%s main)"

# A clean checkout of main's last commit, removed on the way out.
if [[ -e $worktree ]]; then
  git -C $repo worktree remove --force $worktree 2>/dev/null || die "cannot clear $worktree from an earlier run"
fi
git -C $repo worktree add --quiet --detach $worktree main || die "cannot create $worktree"
trap 'git -C $repo worktree remove --force $worktree 2>/dev/null' EXIT

archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Cosmic Daybook $(date '+%Y-%m-%d %H%M') $sha.xcarchive"
log=${TMPDIR:-/tmp}/cosmic-daybook-release-$sha.log
mkdir -p ${archive:h} || die "cannot create ${archive:h}"
if ! (
  cd $worktree &&
  BUILD_LOCK_WAIT=${BUILD_LOCK_WAIT:-3600} Scripts/locked_xcodebuild.sh archive \
    -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath $derived -archivePath $archive \
    ARCHS=$(uname -m) ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO
) > $log 2>&1; then
  tail -25 $log >&2
  die "the Release build failed (exit status 75 means it never got the build lock); full log: $log"
fi

app=$archive/Products/Applications/$app_name
[[ -d $app ]] || die "no $app_name in $archive"
codesign --verify --deep --strict $app 2>/dev/null || die "the new copy's signature does not verify: $app"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $app/Contents/Info.plist) == $bundle_id ]] \
  || die "the new copy is not $bundle_id: $app"
expiry=$(security cms -D -i $app/Contents/embedded.provisionprofile 2>/dev/null \
  | plutil -extract ExpirationDate raw -o - - 2>/dev/null)

# The bridge may have launched the installed copy while this was building.
refuse_if_running
if (( force_quit )) && [[ -n $(installed_pids) ]]; then
  pids=(${(f)"$(installed_pids)"})
  print "Quitting the installed copy (pid ${(j:, :)pids})"
  # A normal Quit first (the app saves and closes its windows), by pid so an
  # Xcode build with the same bundle id is left alone; then SIGTERM, then SIGKILL.
  for pid in $pids; do
    osascript -l JavaScript -e "ObjC.import('AppKit'); \
      $.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" >/dev/null 2>&1
  done
  for _ in {1..30}; do [[ -z $(installed_pids) ]] && break; sleep 0.5; done
  if [[ -n $(installed_pids) ]]; then
    print "  still running after 15 s; terminating it"
    kill -TERM ${(f)"$(installed_pids)"} 2>/dev/null
    for _ in {1..20}; do [[ -z $(installed_pids) ]] && break; sleep 0.5; done
  fi
  [[ -n $(installed_pids) ]] && kill -KILL ${(f)"$(installed_pids)"} 2>/dev/null && sleep 1
  [[ -z $(installed_pids) ]] || die "cannot quit the installed copy"
fi
staged="/Applications/.$app_name.installing"
rm -rf $staged
ditto $app $staged || die "cannot copy the new app into /Applications"
if [[ -e $dest ]]; then
  # The replaced copy goes to the Trash as a zip. An app bundle there is soon
  # registered with LaunchServices again (seen 2026-09-26, even after an
  # explicit unregister), and Spotlight or Shortcuts could then open the old
  # build. Every installed build is also inside its archive, which is not.
  trashed="$HOME/.Trash/Cosmic Daybook (replaced $(date '+%Y-%m-%d %H%M%S')).zip"
  ditto -c -k --keepParent $dest $trashed || {
    rm -rf $staged; die "cannot save the old copy to the Trash; nothing was replaced"
  }
  $lsregister -u $dest 2>/dev/null
  rm -rf $dest || die "cannot remove the old copy (saved as $trashed)"
fi
mv $staged $dest || die "cannot move the new copy into place${trashed:+; the old one is saved as $trashed}"
$lsregister -f $dest

# Registrations of the bundle id whose app no longer exists, or sits in the
# Trash (a DerivedData folder trashed after its worktree was removed, say).
pruned=0
$lsregister -dump 2>/dev/null \
  | awk '/^path:/ { p = $0 } /^identifier: *DanielSDeBerry\.MariasNoteBook$/ { print p }' \
  | sed -E 's/^path: *//; s/ \(0x[0-9a-f]+\)$//' | sort -u \
  | while IFS= read -r registered; do
      [[ -e $registered && $registered != "$HOME/.Trash/"* ]] && continue
      $lsregister -u $registered 2>/dev/null && (( ++pruned ))
    done

(( relaunch )) && open $dest && print "Reopened $dest"
print "Installed $dest"
print "  main $sha, $(uname -m), development profile valid until ${expiry:-unknown}"
print "  archive with dSYM: $archive"
print "  dropped $pruned stale LaunchServices registrations"
