#!/bin/bash
#
# test-cosmic-daybook-mcp.sh — checks the launch decisions of the MCP bridge
# (cosmic-daybook-mcp, beside this file) without touching the real app.
#
# It runs a COPY of the bridge whose bundle id, port and ~/.cosmic-daybook
# directory are swapped for a fake bundle id, port 43199 and a temporary
# directory, with fake `lsappinfo` / `open` and dummy processes (sleep, nc -lk,
# kill -STOP) standing in for copies of the app. It never touches port 43117,
# the real bundle id, ~/.cosmic-daybook, LaunchServices or the app.
#
# usage: Scripts/mcp/test-cosmic-daybook-mcp.sh [bridge script] [label]
# Takes about a minute; prints one line per check and exits non-zero on a failure.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="${1:-$HERE/cosmic-daybook-mcp}"
LABEL="${2:-cosmic-daybook-mcp}"
TEST_PORT=43199
T="$(mktemp -d "${TMPDIR:-/tmp}/cosmic-daybook-mcp-test.XXXXXX")"
PASS=0
FAIL=0
CHILDREN=""

MAIN_PID=$$
cleanup() {
    # bash 3.2 runs this trap in pipeline subshells too; only the harness itself cleans up.
    [ "$(exec sh -c 'echo $PPID')" = "$MAIN_PID" ] || return 0
    for pid in $CHILDREN; do
        kill -CONT "$pid" 2>/dev/null
        kill "$pid" 2>/dev/null
    done
    if [ -f "$T/spawned" ]; then
        while read -r pid; do kill "$pid" 2>/dev/null; done < "$T/spawned"
    fi
    wait 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT

port_open() { /usr/bin/nc -z 127.0.0.1 "$TEST_PORT" >/dev/null 2>&1; }

# ---- fakes -----------------------------------------------------------------

# Fake lsappinfo: "running copies" are the live pids listed in $T/registry.
cat > "$T/fake-lsappinfo" <<EOF
#!/bin/bash
REG="$T/registry"
case "\$1" in
  find)
    [ "\$2" = "bundleid=test.fake.daybook" ] || exit 0
    [ -f "\$REG" ] || exit 0
    line=""
    while read -r pid; do
      [ -n "\$pid" ] && kill -0 "\$pid" 2>/dev/null && line="\$line ASN:0x0-0x\$(printf '%x' "\$pid")-\"Fake Daybook\":"
    done < "\$REG"
    echo "\${line# }"
    ;;
  info)
    asn="\$4"; hex="\${asn#ASN:0x0-0x}"; hex="\${hex%:}"
    printf '[ NULL ]  %s \n    pid = %d !cgsConnection\n' "\$asn" "\$((16#\$hex))"
    ;;
esac
EOF

# Fake open: records its arguments; with $T/open-starts-listener present it
# "launches the app": a dummy that starts listening a moment later.
cat > "$T/fake-open" <<EOF
#!/bin/bash
echo "\$*" >> "$T/open.log"
if [ -e "$T/open-starts-listener" ]; then
  ( sleep 1; exec /usr/bin/nc -lk 127.0.0.1 $TEST_PORT > "$T/received" 2>/dev/null ) &
  echo \$! >> "$T/registry"
  echo \$! >> "$T/spawned"
fi
exit 0
EOF
chmod +x "$T/fake-lsappinfo" "$T/fake-open"

# The copy under test: only these substitutions, checked below.
BRIDGE="$T/bridge"
sed -e 's|^BUNDLE_ID="DanielSDeBerry.MariasNoteBook"$|BUNDLE_ID="test.fake.daybook"|' \
    -e "s|^PORT=43117\$|PORT=$TEST_PORT|" \
    -e "s|^SUPPORT_DIR=\"\$HOME/.cosmic-daybook\"\$|SUPPORT_DIR=\"$T/support\"|" \
    -e "s|^TOKEN_FILE=\"\$HOME/.cosmic-daybook/mcp.token\"\$|TOKEN_FILE=\"$T/support/mcp.token\"|" \
    -e "s|/usr/bin/lsappinfo|$T/fake-lsappinfo|g" \
    -e "s|/usr/bin/open |$T/fake-open |g" \
    -e "s|    open -g -b |    $T/fake-open -g -b |" \
    "$SCRIPT_UNDER_TEST" > "$BRIDGE"
chmod +x "$BRIDGE"
echo "== $LABEL: substitutions in the test copy =="
diff "$SCRIPT_UNDER_TEST" "$BRIDGE" | grep '^[<>]' | sed 's/^/   /'

# Never run a copy that could still reach the real app: if the bridge changed
# so that a substitution above no longer matches, stop here.
if grep -nE 'DanielSDeBerry|43117|HOME/\.cosmic-daybook|/usr/bin/open|/usr/bin/lsappinfo|(^|[;&|[:space:]])open ' "$BRIDGE" \
    | grep -v '^[0-9]*:[[:space:]]*#'; then
    echo "refusing to run: the test copy above still points at the real app, port or ~/.cosmic-daybook" >&2
    exit 2
fi

# ---- helpers ---------------------------------------------------------------

reset_case() {
    for pid in $CHILDREN; do kill -CONT "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; done
    if [ -f "$T/spawned" ]; then
        while read -r pid; do kill "$pid" 2>/dev/null; done < "$T/spawned"
    fi
    wait 2>/dev/null
    CHILDREN=""
    rm -rf "$T/support" "$T/registry" "$T/open.log" "$T/received" "$T/open-starts-listener" "$T/spawned" \
        "$T/out" "$T/err" "$T/feeder.pid"
    mkdir -p "$T/support"
    printf 'test-token\n' > "$T/support/mcp.token"
    touch "$T/registry"
    local deadline=$((SECONDS + 10))
    while port_open && [ $SECONDS -lt $deadline ]; do sleep 0.1; done
}

spawn() {  # spawn <command...>: background child, remembered for cleanup
    "$@" &
    CHILDREN="$CHILDREN $!"
    LAST=$!
}

is_stopped_pid() { case "$(/bin/ps -o stat= -p "$1" 2>/dev/null)" in *T*) return 0;; *) return 1;; esac; }

# stop_dummy <pid> <command>: kill -STOP a dummy once it is running <command>,
# then wait until ps reports it stopped. A STOP that lands before the forked
# shell has exec'd the command does not always stick (a few in 30 came back
# running), which made the stopped-copy checks flaky.
stop_dummy() {
    local deadline=$((SECONDS + 10))
    until case "$(/bin/ps -o comm= -p "$1" 2>/dev/null)" in *"$2") true;; *) false;; esac \
        || [ $SECONDS -ge $deadline ]; do sleep 0.05; done
    kill -STOP "$1"
    until is_stopped_pid "$1" || [ $SECONDS -ge $deadline ]; do sleep 0.05; kill -STOP "$1"; done
}

listener() {  # a dummy app listening on the test port now; what it receives goes to $T/received
    spawn bash -c "exec /usr/bin/nc -lk 127.0.0.1 $TEST_PORT > '$T/received' 2>/dev/null"
    local deadline=$((SECONDS + 10))
    until port_open || [ $SECONDS -ge $deadline ]; do sleep 0.1; done
}

run_bridge() {  # run_bridge [env...]: waits up to 30 s for the bridge to exit; sets RC (124 = still running) and ELAPSED
    local start=$SECONDS
    env "$@" "$BRIDGE" < /dev/null > "$T/out" 2> "$T/err" &
    local bridge=$!
    local deadline=$((SECONDS + 30))
    while kill -0 "$bridge" 2>/dev/null && [ $SECONDS -lt $deadline ]; do sleep 0.1; done
    if kill -0 "$bridge" 2>/dev/null; then
        pkill -P "$bridge" 2>/dev/null; kill "$bridge" 2>/dev/null; wait "$bridge" 2>/dev/null
        RC=124
    else
        wait "$bridge"; RC=$?
    fi
    ELAPSED=$((SECONDS - start))
}

relay_bridge() {  # starts the bridge relaying one line; waits up to 30 s for the listener to receive AUTH
    /bin/sh -c 'echo $$ > "$1"; printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"; exec sleep 60' \
        sh "$T/feeder.pid" | "$BRIDGE" > "$T/out" 2> "$T/err" &
    local bridge=$!
    local deadline=$((SECONDS + 30))
    until grep -q '^AUTH test-token$' "$T/received" 2>/dev/null || [ $SECONDS -ge $deadline ]; do sleep 0.1; done
    if grep -q '^AUTH test-token$' "$T/received" 2>/dev/null; then RELAYED=1; else RELAYED=0; fi
    kill "$(cat "$T/feeder.pid" 2>/dev/null)" 2>/dev/null
    pkill -P "$bridge" 2>/dev/null; kill "$bridge" 2>/dev/null; wait "$bridge" 2>/dev/null
}

opens() { [ -f "$T/open.log" ] && wc -l < "$T/open.log" | tr -d ' ' || echo 0; }

check() {  # check <description> <condition...>
    local description="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "   ok   $description"
    else FAIL=$((FAIL + 1)); echo "   FAIL $description"; sed 's/^/        stderr: /' "$T/err" 2>/dev/null; fi
}

# ---- cases -----------------------------------------------------------------

echo "== 1. Port closed, no copy running, access on: launch once (MCP-only), then relay =="
reset_case
touch "$T/support/enabled" "$T/open-starts-listener"
: > "$T/received"
relay_bridge
check "opened the app exactly once (launches: $(opens))" [ "$(opens)" = 1 ]
check "with -g -b and the MCP-only arguments ($(cat "$T/open.log" 2>/dev/null))" \
    grep -qx -- '-g -b test.fake.daybook --args -CosmicDaybookMCPAutolaunch YES -ApplePersistenceIgnoreState YES' "$T/open.log"
check "relayed the AUTH line and the request" [ "$RELAYED" = 1 ]

echo "== 2. Port closed, no copy running, access off (no marker): no launch, today's message =="
reset_case
touch "$T/open-starts-listener"
run_bridge
check "exit status 1 (got $RC)" [ "$RC" = 1 ]
check "no launch (launches: $(opens))" [ "$(opens)" = 0 ]
check "says to enable access in Settings" grep -q 'enable Claude Desktop access in Settings' "$T/err"
check "answers at once (${ELAPSED}s)" [ "$ELAPSED" -le 2 ]

echo "== 3. Port closed, a copy running and still starting: no second launch, wait, then relay =="
reset_case
touch "$T/support/enabled" "$T/open-starts-listener"
: > "$T/received"
spawn bash -c "sleep 2; exec /usr/bin/nc -lk 127.0.0.1 $TEST_PORT > '$T/received'"
echo "$LAST" >> "$T/registry"
relay_bridge
check "no launch (launches: $(opens))" [ "$(opens)" = 0 ]
check "relayed once the running copy listened" [ "$RELAYED" = 1 ]

echo "== 4. Port closed, the only running copy is stopped (ps state T): clear message, no launch =="
reset_case
touch "$T/support/enabled" "$T/open-starts-listener"
spawn sleep 300
stop_dummy "$LAST" sleep
echo "$LAST" >> "$T/registry"
STOPPED=$LAST
run_bridge
check "the dummy copy was stopped throughout" is_stopped_pid "$STOPPED"
check "exit status 1 (got $RC)" [ "$RC" = 1 ]
check "no launch (launches: $(opens))" [ "$(opens)" = 0 ]
check "names the stopped pid" grep -q "(pid $STOPPED) is stopped" "$T/err"
check "answers at once (${ELAPSED}s)" [ "$ELAPSED" -le 2 ]

echo "== 5. Port open but its holder is stopped: clear message instead of a silent relay =="
reset_case
listener
HOLDER=$LAST
stop_dummy "$HOLDER" nc
run_bridge
check "the dummy holder was stopped throughout" is_stopped_pid "$HOLDER"
check "exit status 1 (got $RC)" [ "$RC" = 1 ]
check "names the stopped holder" grep -q "listening on 127.0.0.1:$TEST_PORT (pid $HOLDER) is stopped" "$T/err"
check "answers at once (${ELAPSED}s)" [ "$ELAPSED" -le 3 ]

echo "== 6. Port open, holder running: relay as before =="
reset_case
: > "$T/received"
listener
relay_bridge
check "no launch (launches: $(opens))" [ "$(opens)" = 0 ]
check "relayed the AUTH line" [ "$RELAYED" = 1 ]

echo "== 7. COSMIC_DAYBOOK_NO_AUTOLAUNCH=1, port closed, access on: no launch, fails at once =="
reset_case
touch "$T/support/enabled" "$T/open-starts-listener"
run_bridge COSMIC_DAYBOOK_NO_AUTOLAUNCH=1
check "exit status 1 (got $RC)" [ "$RC" = 1 ]
check "no launch (launches: $(opens))" [ "$(opens)" = 0 ]
check "answers at once (${ELAPSED}s)" [ "$ELAPSED" -le 2 ]

echo "== 8. Port closed, the running copy is quitting (exits during the wait): launch a fresh one =="
reset_case
touch "$T/support/enabled" "$T/open-starts-listener"
: > "$T/received"
spawn sleep 2
echo "$LAST" >> "$T/registry"
relay_bridge
check "launched once, after the old copy had gone (launches: $(opens))" [ "$(opens)" = 1 ]
check "relayed to the fresh copy" [ "$RELAYED" = 1 ]

echo "== $LABEL: $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ]
