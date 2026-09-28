#!/bin/zsh
# Prints the roll-out timer estimates as "MAC_S IPHONE_S IPAD_S": the median
# length of past build logs in $TMPDIR (log created → last written), skipping
# runs over 20 min, which were waiting on the build lock. The iPhone figure adds
# a minute for the install. Falls back to 360 / 420 / 60 without history.

emulate -R zsh
setopt null_glob

median() {
  local -a d=(${(n)@})
  (( $#d )) && print ${d[$(( ($#d + 1) / 2 ))]}
}

durations() {
  local f b m
  for f in $@; do
    b=$(stat -f %B $f) m=$(stat -f %m $f)
    (( m - b > 60 && m - b < 1200 )) && print $(( m - b ))
  done
}

tmp=${TMPDIR:-/tmp}
mac=$(median $(durations $tmp/cosmic-daybook-release-[0-9a-f]*.log))
ios=$(median $(durations $tmp/cosmic-daybook-release-ios-*.log))
print ${mac:-360} $(( ${ios:-360} + 60 )) 60
