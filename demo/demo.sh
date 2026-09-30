#!/bin/sh
# Shutdown demo: an agent works through OCI Generative AI inside an OpenShell
# sandbox, the fence holds against anything off-policy, and the operator shuts
# it down in stages from the gateway. Output is captured under out/.
#
# Prerequisites (one-time, see README.md):
#   openshell provider profile import --file profile/oci-genai-python.yaml --global
#   openshell provider create --name oci-genai-demo --type oci-genai-python \
#       --credential OCI_GENAI_API_KEY=<your OCI GenAI API key>
set -u
D=$(cd "$(dirname "$0")" && pwd)
OUT="$D/out"; mkdir -p "$OUT"
NAME=${NAME:-oci-agent}
NAME2="${NAME}-2"          # a second agent, to show the lockdown is fleet-wide
PROVIDER=${PROVIDER:-oci-genai-demo}
IMG=${IMG:-ghcr.io/astral-sh/uv:python3.12-bookworm-slim}
PY=/usr/local/bin/python3.12
DOCKER=${DOCKER:-$HOME/.rd/bin/docker}
PAUSE=${PAUSE:-10}   # how long to let the worker loop run before the kill switches
AGENT_B64=$(base64 < "$D/agent/agent.py" | tr -d '\n')

step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
run()  { printf '$ %s\n' "$*"; "$@"; }
agent() {
  timeout 45 openshell sandbox exec --name "$NAME" -- $PY /tmp/agent.py "$@" </dev/null && return 0
  rc=$?; [ "$rc" -eq 124 ] || return "$rc"
  echo "(exec stalled, retrying once)"; timeout 45 openshell sandbox exec --name "$NAME" -- $PY /tmp/agent.py "$@" </dev/null
}
# Poll the agent until its request is blocked (or allowed again) and report how long that took.
wait_state() {  # wait_state blocked|open [sandbox]
  sb=${2:-$NAME}; start=$(date +%s)
  while :; do
    out=$(timeout 30 openshell sandbox exec --name "$sb" -- $PY /tmp/agent.py ask "Are you still there?" </dev/null 2>&1 | tail -n 1)
    case "$1:$out" in
      blocked:*"HTTP 0:"*|blocked:*"HTTP 403"*) echo "  -> $sb blocked after $(( $(date +%s) - start )) s: $out" | cut -c1-150; return 0 ;;
      open:*"HTTP 200"*|open:*"HTTP 401"*)       echo "  -> $sb reachable after $(( $(date +%s) - start )) s: $out" | cut -c1-150; return 0 ;;
    esac
    [ $(( $(date +%s) - start )) -ge 90 ] && { echo "  -> $sb still not $1 after 90 s: $out" | cut -c1-150; return 1; }
    sleep 3
  done
}

{
step "0. Clean slate"
# Re-creating a sandbox under a name whose deletion is still pending makes
# exec stall until the old record is purged, so wait until the name is free.
for sb in "$NAME" "$NAME2"; do
  if openshell sandbox delete "$sb" >/dev/null 2>&1; then
    printf 'waiting for the previous %s to be purged ' "$sb"
    i=0; while openshell sandbox list 2>/dev/null | grep -q "^$sb "; do i=$((i+1)); [ $i -ge 60 ] && break; printf '.'; sleep 3; done; echo
  fi
done
openshell policy delete --global --yes >/dev/null 2>&1 || true

step "1. Start the agent sandbox with the OCI GenAI provider attached"
printf '$ openshell sandbox create --name %s --from %s --provider %s --detach --env AGENT_B64=<agent.py> -- sh -c "... && exec sleep infinity"\n' "$NAME" "$IMG" "$PROVIDER"
openshell sandbox create --name "$NAME" --from "$IMG" --provider "$PROVIDER" --detach \
  --env "AGENT_B64=$AGENT_B64" \
  -- sh -c 'echo "$AGENT_B64" | base64 -d > /tmp/agent.py && exec sleep infinity'
sleep 3; run openshell sandbox list
printf 'exec check: '; i=0; until timeout 20 openshell sandbox exec --name "$NAME" -- $PY -c 'print("ready")' </dev/null 2>/dev/null; do i=$((i+1)); [ $i -ge 6 ] && break; printf '.'; sleep 2; done

step "1b. A second agent on the same gateway (same provider), so the lockdown has a fleet to hit"
openshell sandbox create --name "$NAME2" --from "$IMG" --provider "$PROVIDER" --detach \
  --env "AGENT_B64=$AGENT_B64" \
  -- sh -c 'echo "$AGENT_B64" | base64 -d > /tmp/agent.py && exec sleep infinity' | grep -E "Created|Error" || true
sleep 3; run openshell sandbox list

step "2. What the agent can see: a placeholder, not the key"
agent whoami

step "3. Legitimate work goes through (proxy injects the real key, OCI answers)"
agent ask "In one sentence, why should an autonomous agent run inside a sandbox?"

step "4. The fence: anything off-policy is denied before it leaves the sandbox"
agent probe

step "5. Start the worker loop (one completion every 5 s) and watch it"
agent work 5 > "$OUT/worker.log" 2>&1 </dev/null &
WORKER=$!
sleep "$PAUSE"; tail -n 3 "$OUT/worker.log"

step "6a. KILL SWITCH, level 1: gateway-wide lockdown (every sandbox, one command)"
run openshell policy set --global --policy "$D/policies/lockdown.yaml" --yes
wait_state blocked "$NAME"; wait_state blocked "$NAME2"; tail -n 2 "$OUT/worker.log"

step "6b. ...and it is reversible: lift the lockdown"
run openshell policy delete --global --yes
wait_state open "$NAME"; wait_state open "$NAME2"; tail -n 2 "$OUT/worker.log"

step "6c. KILL SWITCH, level 2: take the credential away from ONE sandbox (the other keeps working)"
run openshell sandbox provider detach "$NAME" "$PROVIDER" --wait || \
  run openshell provider update "$PROVIDER" --credential "OCI_GENAI_API_KEY=revoked-by-operator"
wait_state blocked "$NAME"; wait_state open "$NAME2"; tail -n 2 "$OUT/worker.log"

step "7. Evidence: OCSF events from the sandbox supervisor (Docker driver: the supervisor container's stdout)"
SUP=$("$DOCKER" ps --format '{{.Names}}' | grep -E -- "--${NAME}-[0-9a-f]{8}-.*-supervisor$" | head -n 1)
"$DOCKER" logs "$SUP" 2>&1 | grep -E ' OCSF ' > "$OUT/ocsf.log" || true
grep -E 'DENIED|denied|CONFIG:(LOADED|APPLIED|DETECTED)|FINDING' "$OUT/ocsf.log" | cut -c1-200 | tail -n 14
printf '(full OCSF shorthand log: %s)\n' "$OUT/ocsf.log"

step "6d. KILL SWITCH, level 3: stop the sandbox (workspace preserved for forensics)"
run openshell sandbox stop "$NAME"
sleep 3; kill "$WORKER" 2>/dev/null; wait "$WORKER" 2>/dev/null
run openshell sandbox list

printf '\n(worker log: %s)\n' "$OUT/worker.log"
if [ "${CLEANUP:-0}" = "1" ]; then
  step "8. Cleanup"
  run openshell sandbox delete "$NAME"
  run openshell sandbox delete "$NAME2"
fi
} 2>&1 | tee "$OUT/demo-$(date +%Y%m%d-%H%M%S).log"
