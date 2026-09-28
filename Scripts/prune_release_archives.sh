#!/bin/zsh
# Keeps the newest three Release archives of each kind that the roll-out makes
# (Mac: "Cosmic Daybook <date> <sha>", iOS: "Cosmic Daybook iOS <date> <sha>") in
# ~/Library/Developer/Xcode/Archives and moves the older ones to the Trash, then
# removes date folders left empty. Other archives are never touched. Newest is by
# the archive's own CreationDate, not its name.
#
#   Scripts/prune_release_archives.sh
#
# KEEP_ARCHIVES  how many of each kind to keep (default 3).

emulate -R zsh
setopt no_unset pipe_fail null_glob extended_glob

me=${0:t}
root=$HOME/Library/Developer/Xcode/Archives
keep=${KEEP_ARCHIVES:-3}
[[ $keep == <1-> ]] || { print -u2 "$me: KEEP_ARCHIVES must be 1 or more, not '$keep'"; exit 64 }

# "<epoch> <path>" for each archive of one kind, newest first.
newest_first() {
  local a created
  for a in $@; do
    created=$(/usr/libexec/PlistBuddy -c 'Print :CreationDate' $a/Info.plist 2>/dev/null)
    created=$(date -j -f '%a %b %d %T %Z %Y' $created +%s 2>/dev/null) || created=$(stat -f %m $a)
    print -r -- "$created $a"
  done | sort -rn
}

trashed=0
for kind in mac ios; do
  if [[ $kind == ios ]]; then
    archives=($root/*/"Cosmic Daybook iOS "*.xcarchive)
  else
    archives=($root/*/"Cosmic Daybook "[0-9]*.xcarchive)
  fi
  (( $#archives > keep )) || continue
  newest_first $archives | tail -n +$(( keep + 1 )) | while read -r _ archive; do
    /usr/bin/trash $archive && (( ++trashed )) && print "trashed ${archive#$root/}"
  done
done

for dir in $root/*(N/); do
  rmdir $dir 2>/dev/null
done
print "$me: moved $trashed archive(s) to the Trash; kept the newest $keep Mac and $keep iOS"
