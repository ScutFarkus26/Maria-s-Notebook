#!/bin/zsh
# Archives the Daybook Assistant for TestFlight. Upload it from Xcode's Organizer
# (Distribute App ▸ TestFlight & App Store), which signs it for distribution.
#
#   Scripts/archive_assistant_testflight.sh
#
# - The build number is the time of the archive, YYYYMMDDHHMM in UTC
#   (CURRENT_PROJECT_VERSION on the command line), so every upload is higher than
#   the last without anyone editing the project. The project keeps 1, which only
#   development builds on devices use. The version (MARKETING_VERSION) is set in
#   the project as usual.
# - Archives the checkout's last commit, so it refuses while tracked files have
#   uncommitted edits, or while the Daybook Assistant folder holds files git
#   doesn't track (the folder is synchronized, so Xcode bundles every file in
#   it): what goes to TestFlight is always a commit you can find.
# - The build number is taken in UTC, so the night the clocks go back can't
#   give a later archive a lower number.
# - Exit status 75 means the build lock was busy and nothing was archived.
# - The archive is named "Daybook Assistant TestFlight <date> <HHMM> <commit>" and
#   stays in Xcode's Organizer with its dSYM.
# - A signed build: run it outside Claude's sandbox.
#
# BUILD_LOCK_WAIT  passed to Scripts/locked_xcodebuild.sh (default here 3600 s).

emulate -R zsh
setopt no_unset pipe_fail

me=${0:t}
die() { print -u2 "$me: $*"; exit 1 }

root=$(git -C ${0:A:h} rev-parse --show-toplevel 2>/dev/null) \
  || die "run it from a checkout of the Cosmic Daybook repository"
cd $root || exit 1

git diff --quiet HEAD -- || die "tracked files have uncommitted edits; commit them first"
stray=$(git status --porcelain --untracked-files=all --ignored -- "Daybook Assistant" \
  | grep -v '/\.DS_Store$')
[[ -z $stray ]] || die "files git doesn't track would be bundled; move them out first:
$stray"

build=$(date -u +%Y%m%d%H%M)
commit=$(git rev-parse --short HEAD)
archive="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/Daybook Assistant TestFlight $(date +%F) $(date +%H%M) $commit.xcarchive"

print "$me: archiving $commit as build $build"
BUILD_LOCK_WAIT=${BUILD_LOCK_WAIT:-3600} Scripts/locked_xcodebuild.sh \
  -project "Cosmic Daybook.xcodeproj" -scheme "Daybook Assistant" -configuration Release \
  -destination generic/platform=iOS -archivePath $archive -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION=$build archive
case $? in
  0) ;;
  75) print -u2 "$me: the build lock stayed busy; nothing was archived"; exit 75 ;;
  *) die "archive failed" ;;
esac

plist="$archive/Products/Applications/Daybook Assistant.app/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $plist)
print "$me: Daybook Assistant $version ($build) from $commit"
print "  $archive"
print "  Upload it from Xcode ▸ Window ▸ Organizer ▸ Distribute App ▸ TestFlight & App Store."
