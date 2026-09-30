#!/usr/bin/env bash
# Test matrix for demo/demo.sh and the examples. Needs both providers set up
# (see the README) and a gateway you own: it sets and lifts global policies.
#
#   ./tests/matrix.sh            # everything
#
# Cases:
#   1. full run, TARGET=oci                                     -> 13/13, exit 0
#   2. full run, TARGET=openrouter, pure-bash timeout fallback  -> 13/13, exit 0
#   3. missing provider                                         -> ABORT at preflight, nothing touched
#   4. SIGTERM to the whole process group during the lockdown   -> lockdown lifted, sandboxes deleted
#   5. examples (OpenAI SDK, LangChain + tool) on both targets  -> all pass
# After every case: no global policy in force, no demo sandboxes, no worker process left.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
M=${M:-$R/demo/out/matrix}; mkdir -p "$M"
cd "$R" || exit 1
export NO_COLOR=1
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
FAILS=0
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
state() {
  local g; g=$(openshell policy get --global 2>/dev/null)
  if [ -n "$g" ] && ! echo "$g" | grep -q "Status: *Superseded"; then bad "a global policy is still in force"; else ok "no global policy in force"; fi
  local left; left=$(openshell sandbox list 2>/dev/null | awk 'NR > 1 && ($1 ~ /-agent(-2)?$/ || $1 ~ /^examples-/) {print $1}' | tr '\n' ' ')
  if [ -n "$left" ]; then bad "sandboxes left: $left"; else ok "no demo sandboxes left"; fi
  if pgrep -f "agent.py work" >/dev/null; then bad "a worker process is still running"; else ok "no worker process left"; fi
}

echo "### 1. full run, TARGET=oci"
TARGET=oci ./demo/demo.sh </dev/null 2>&1 | strip > "$M/full-oci.log"; rc=${PIPESTATUS[0]}
grep -q "ALL 13 CHECKS PASSED" "$M/full-oci.log" && [ "$rc" = 0 ] && ok "13/13, exit 0" || bad "exit $rc: $(grep -E 'FAIL|ABORT' "$M/full-oci.log" | head -3)"
state

echo "### 2. full run, TARGET=openrouter, pure-bash timeout fallback (as on macOS without coreutils)"
DEMO_BASH_TIMEOUT=1 TARGET=openrouter ./demo/demo.sh </dev/null 2>&1 | strip > "$M/full-openrouter-bash-timeout.log"; rc=${PIPESTATUS[0]}
grep -q "ALL 13 CHECKS PASSED" "$M/full-openrouter-bash-timeout.log" && [ "$rc" = 0 ] && ok "13/13, exit 0" || bad "exit $rc: $(grep -E 'FAIL|ABORT' "$M/full-openrouter-bash-timeout.log" | head -3)"
state

echo "### 3. missing provider"
TARGET=openrouter PROVIDER=does-not-exist ./demo/demo.sh </dev/null 2>&1 | strip > "$M/missing-provider.log"; rc=${PIPESTATUS[0]}
grep -q "ABORT: provider 'does-not-exist' does not exist" "$M/missing-provider.log" && [ "$rc" = 1 ] && ok "aborted at preflight, exit 1" || bad "exit $rc"
state

echo "### 4. SIGTERM to the whole process group during the lockdown"
setsid bash -c 'TARGET=openrouter ./demo/demo.sh </dev/null > "$0" 2>&1' "$M/pgroup-term.raw" &
P=$!
until grep -q "Global policy configured" "$M/pgroup-term.raw" 2>/dev/null; do
  sleep 0.5; kill -0 $P 2>/dev/null || { bad "run ended before the lockdown"; break; }
done
sleep 1
if openshell policy get --global 2>/dev/null | grep -q "Status: *Loaded"; then
  PG=$(ps -o pgid= -p $P | tr -d ' ')
  kill -TERM -- "-$PG"; wait $P 2>/dev/null
  ok "lockdown was in force; sent SIGTERM to process group $PG"
fi
for _ in $(seq 1 30); do pgrep -f "demo/demo.sh" >/dev/null || break; sleep 1; done
strip < "$M/pgroup-term.raw" | grep -E "^cleanup:" | sed 's/^/    /'
state

echo "### 5. examples on both targets"
for T in oci openrouter; do
  TARGET=$T ./examples/run-examples.sh </dev/null 2>&1 | strip > "$M/examples-$T.log"; rc=${PIPESTATUS[0]}
  grep -q "ALL EXAMPLES PASSED ($T)" "$M/examples-$T.log" && [ "$rc" = 0 ] && ok "examples pass on $T" || bad "examples on $T: exit $rc"
done
state

echo
[ "$FAILS" -eq 0 ] && echo "MATRIX PASSED" || echo "MATRIX: $FAILS FAILURE(S)"
[ "$FAILS" -eq 0 ]
