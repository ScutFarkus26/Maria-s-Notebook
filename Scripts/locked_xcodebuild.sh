#!/bin/zsh
# Runs xcodebuild, with the arguments given, under the Mac-wide build lock that
# Tide's Scripts/build also takes, so command-line builds from either project take
# turns instead of sharing ten cores: on 2026-09-23 a 48 s clean build took 255 s
# beside a Tide build. The build runs at `nice -n 10`, leaving the performance cores
# to Danny's own Xcode builds.
#
#   Scripts/locked_xcodebuild.sh [xcodebuild arguments…]
#
# BUILD_LOCK_WAIT  seconds to wait for the lock before giving up with exit status
#                  75. Unset (the default), a build waits as long as it takes:
#                  a wait means another build is running (Danny, 2026-10-05).
# BUILD_NICE       niceness for the build (default 10; 0 for timing baselines).
# BUILD_LOCK_FILE  the lock (default ~/Library/Caches/xcodebuild.lock, Tide's);
#                  override only to test this script.
#
# Builds take turns in the order they arrived when ~/.claude/bin/build-turn is
# installed: it queues on numbered tickets, then takes this same lock, so
# builds through it and through the code below still exclude each other. A
# bare flock hands the lock to whichever waiter wins the wake-up instead: on
# 2026-09-30 a build that had waited 5 min went ahead of one that had waited 27.

emulate -R zsh
setopt no_unset pipe_fail no_bg_nice   # BG_NICE would add +5 to the backgrounded build
zmodload zsh/system

me=${0:t}
lock=${BUILD_LOCK_FILE:-$HOME/Library/Caches/xcodebuild.lock}
wait_limit=${BUILD_LOCK_WAIT:-}
niceness=${BUILD_NICE:-10}

[[ -z $wait_limit || $wait_limit == <-> ]] || { print -u2 "$me: BUILD_LOCK_WAIT must be whole seconds, not '$wait_limit'"; exit 64 }
[[ $niceness == <0-20> ]] || { print -u2 "$me: BUILD_NICE must be 0–20, not '$niceness'"; exit 64 }

turn=$HOME/.claude/bin/build-turn
[[ -x $turn ]] && exec $turn ${wait_limit:+--wait} $wait_limit --nice $niceness xcodebuild "$@"

[[ -e $lock ]] || : >> $lock || exit 73

# Everything with the lock file open — the holder and any other build waiting.
# lsof cannot say which one holds it, and a waiter can be the oldest.
show_lock_users() {
  local -a pids
  pids=(${(f)"$(lsof -t -- $lock 2>/dev/null)"})
  pids=(${pids:#$$})
  (( $#pids )) || return 0
  print -u2 "  processes with the lock open (holder and waiters; ELAPSED PID COMMAND):"
  ps -o etime=,pid=,command= -p ${(j:,:)pids} 2>/dev/null | cut -c1-170 | sed 's/^/    /' >&2
}

# The lock belongs to this shell's open file, which zsh closes on exec: xcodebuild
# and the build service it starts never inherit it, and it is released when this
# script exits — so the script must not `exec` xcodebuild.
#
# The wait blocks in the kernel, as Scripts/build's does. `zsystem flock -t` would
# poll once a second instead, and a poller loses every hand-off to a blocked waiter:
# on 2026-09-25 a build waiting that way sat 36 min while Tide builds that queued
# after it took the lock. A one-process timer (zselect, so no stray `sleep`)
# interrupts the wait with SIGALRM when BUILD_LOCK_WAIT runs out; with no
# BUILD_LOCK_WAIT there is no timer.
if ! zsystem flock -t 0 $lock 2>/dev/null; then
  print -u2 "$me: another build holds $lock — waiting${wait_limit:+ up to ${wait_limit}s}"
  show_lock_users
  timer=
  if [[ -n $wait_limit ]]; then
    ( zmodload zsh/zselect; zselect -t $(( wait_limit * 100 )); kill -ALRM $$ ) &
    timer=$!
  fi
  stop_timer() { [[ -n $timer ]] && { kill $timer 2>/dev/null; wait $timer 2>/dev/null }; return 0 }
  TRAPALRM() {
    print -u2 "$me: still locked after ${wait_limit}s; not building (exit 75). Kill the stuck build or raise BUILD_LOCK_WAIT."
    show_lock_users
    exit 75
  }
  trap 'stop_timer; exit 130' INT
  trap 'stop_timer; exit 143' TERM
  trap 'stop_timer; exit 129' HUP
  zsystem flock $lock 2>/dev/null || { stop_timer; print -u2 "$me: could not lock $lock"; exit 73 }
  stop_timer
  unfunction TRAPALRM
  trap - INT TERM HUP
  print -u2 "$me: got the lock; building"
fi

# Run the build as a child and forward INT/TERM/HUP to it, then keep waiting until
# it has really exited: releasing the lock while xcodebuild still runs would let the
# next build start on top of it.
nice -n $niceness xcodebuild "$@" &
child=$!
trap 'kill -TERM $child 2>/dev/null' INT TERM HUP
wait $child
build_status=$?
while kill -0 $child 2>/dev/null; do
  wait $child
  build_status=$?
done
exit $build_status
