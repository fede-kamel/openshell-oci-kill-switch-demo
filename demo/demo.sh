#!/usr/bin/env bash
# An agent kill switch you can run.
#
# An agent works through OCI Generative AI (TARGET=oci, the default) or
# OpenRouter (TARGET=openrouter) inside an OpenShell sandbox. The script shows
# that the agent never holds its key and cannot step outside its policy, then
# shuts it down from the gateway in three levels while a second agent shows
# which levels are fleet-wide and which are surgical. Every scene is checked,
# and the run ends with a PASS/FAIL summary and a matching exit code.
#
# One-time setup, per target (see README.md):
#   TARGET=oci         openshell provider profile import --file profile/oci-genai-python.yaml --global
#                      openshell provider create --name oci-genai-demo --type oci-genai-python \
#                          --credential OCI_GENAI_API_KEY
#   TARGET=openrouter  openshell provider profile import --file profile/openrouter-python.yaml --global
#                      openshell provider create --name or-demo --type openrouter-python \
#                          --credential OPENROUTER_API_KEY
#
# Safety: the script refuses to run if the gateway already has a global policy,
# if other sandboxes are running on it (the lockdown would hit them), or if
# sandboxes with its names exist. Whatever happens -- failure, Ctrl-C -- it
# lifts its own lockdown and deletes the sandboxes it created on the way out.
#
# Environment: TARGET, SANDBOX, PROVIDER, OCI_REGION, IMG, PAUSE, KEEP=1 (keep the
# sandboxes at the end), REPLACE=1 (delete existing sandboxes with the demo's
# names first), SHARED_GATEWAY_OK=1 (run even with other sandboxes running), and
# AGENT_BASE_URL / AGENT_MODEL / AGENT_KEY_ENV to point the agent elsewhere.
set -u
D=$(cd "$(dirname "$0")" && pwd)
OUT="$D/out"; mkdir -p "$OUT"
LOG="$OUT/demo-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

TARGET=${TARGET:-oci}
case "$TARGET" in
  oci)
    OCI_REGION=${OCI_REGION:-us-chicago-1}
    : "${SANDBOX:=oci-agent}" "${PROVIDER:=oci-genai-demo}" "${PROFILE_TYPE:=oci-genai-python}"
    : "${AGENT_BASE_URL:=https://inference.generativeai.$OCI_REGION.oci.oraclecloud.com/openai/v1}"
    : "${AGENT_MODEL:=meta.llama-3.3-70b-instruct}" "${AGENT_KEY_ENV:=OCI_GENAI_API_KEY}" ;;
  openrouter)
    : "${SANDBOX:=or-agent}" "${PROVIDER:=or-demo}" "${PROFILE_TYPE:=openrouter-python}"
    : "${AGENT_BASE_URL:=https://openrouter.ai/api/v1}"
    : "${AGENT_MODEL:=meta-llama/llama-3.3-70b-instruct}" "${AGENT_KEY_ENV:=OPENROUTER_API_KEY}" ;;
  *) echo "TARGET must be oci or openrouter" >&2; exit 2 ;;
esac
SANDBOX2="${SANDBOX}-2"    # a second agent, to show the lockdown is fleet-wide
IMG=${IMG:-ghcr.io/astral-sh/uv:python3.12-bookworm-slim}
PAUSE=${PAUSE:-10}         # how long the worker loop runs before the kill switches
PY=/usr/local/bin/python3.12
AGENT=/tmp/demo/agent.py   # where the agent lands inside each sandbox
# Only used to read the supervisor's OCSF log (Docker driver). Rancher Desktop
# puts its CLI in ~/.rd/bin; anything else, whatever `docker` is on PATH.
if [ -z "${DOCKER:-}" ]; then
  if [ -x "$HOME/.rd/bin/docker" ]; then DOCKER=$HOME/.rd/bin/docker; else DOCKER=docker; fi
fi

# `timeout` is GNU coreutils; macOS has it as gtimeout via Homebrew, or not at all.
if command -v timeout >/dev/null 2>&1; then T=timeout
elif command -v gtimeout >/dev/null 2>&1; then T=gtimeout
else T=; fi
t() { local s=$1; shift; if [ -n "$T" ]; then "$T" "$s" "$@"; else "$@"; fi; }

step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
run()  { printf '$ %s\n' "$*"; "$@"; }
die()  { printf '\n\033[31mABORT:\033[0m %s\n' "$*"; exit 1; }

RESULTS=(); FAILS=0
check() {  # check "<scene>" <0|1>
  if [ "$2" -eq 0 ]; then RESULTS+=("PASS  $1"); else RESULTS+=("FAIL  $1"); FAILS=$((FAILS + 1)); fi
}

# Every exec gets </dev/null: when stdin is not a terminal, `sandbox exec` reads
# it to EOF before starting the command, and an open pipe never reaches EOF.
ex()    { local sb=$1; shift; t 45 openshell sandbox exec --name "$sb" -- "$@" </dev/null; }
agent() { ex "$SANDBOX" "$PY" "$AGENT" "$@"; }

# --- cleanup: always lift our lockdown, stop the worker, remove our sandboxes ---
LOCKDOWN=0; WORKER=; CREATED=()
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [ "$LOCKDOWN" = 1 ]; then
    echo; echo "cleanup: lifting the global lockdown this run set"
    openshell policy delete --global --yes >/dev/null 2>&1 || echo "cleanup: WARNING could not delete the global policy; run: openshell policy delete --global --yes"
  fi
  [ -n "$WORKER" ] && kill "$WORKER" 2>/dev/null
  if [ "${KEEP:-0}" != 1 ]; then
    for sb in ${CREATED[@]+"${CREATED[@]}"}; do openshell sandbox delete "$sb" >/dev/null 2>&1 && echo "cleanup: deleted sandbox $sb"; done
  fi
  echo "(session log: $LOG)"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Poll a sandbox until its request is blocked (or allowed again); report how long that took.
wait_state() {  # wait_state blocked|open <sandbox>  -> returns 0 when reached
  local want=$1 sb=$2 start out; start=$(date +%s)
  while :; do
    out=$(ex "$sb" "$PY" "$AGENT" ask "Are you still there?" 2>&1 | tail -n 1)
    case "$want:$out" in
      blocked:*"HTTP 0:"*|blocked:*"HTTP 403"*) echo "  -> $sb blocked after $(( $(date +%s) - start )) s: $out" | cut -c1-150; return 0 ;;
      open:*"HTTP 200"*)                         echo "  -> $sb reachable after $(( $(date +%s) - start )) s: $out" | cut -c1-150; return 0 ;;
    esac
    [ $(( $(date +%s) - start )) -ge 90 ] && { echo "  -> $sb still not $want after 90 s: $out" | cut -c1-150; return 1; }
    sleep 2
  done
}

# ------------------------------------------------------------------------------
step "0. Preflight (target: $TARGET, provider: $PROVIDER, sandboxes: $SANDBOX, $SANDBOX2)"
command -v openshell >/dev/null 2>&1 || die "the openshell CLI is not on PATH"
openshell --version
t 20 openshell status >/dev/null 2>&1 || die "the gateway is not reachable: run 'openshell status' and start it first"
PLINE=$(openshell provider list 2>/dev/null | awk -v p="$PROVIDER" '$1 == p')
[ -n "$PLINE" ] || die "provider '$PROVIDER' does not exist on this gateway; see the setup lines at the top of this script"
case "$PLINE" in
  *" $PROFILE_TYPE "*) echo "provider $PROVIDER has type $PROFILE_TYPE" ;;
  *) echo "WARNING: provider $PROVIDER is not of type $PROFILE_TYPE; its binaries and rules may not match this agent: $PLINE" ;;
esac
# `policy get --global` also returns the last *deleted* revision, marked Superseded;
# only a revision in any other state is in force.
global_active() { local g; g=$(openshell policy get --global 2>/dev/null) && ! echo "$g" | grep -q "Status: *Superseded"; }
if global_active; then
  die "this gateway already has a global policy in force. The demo sets and deletes one; remove yours first or use another gateway"
fi
EXISTING=$(openshell sandbox list 2>/dev/null | awk -v a="$SANDBOX" -v b="$SANDBOX2" 'NR > 1 && ($1 == a || $1 == b) {print $1}')
if [ -n "$EXISTING" ]; then
  [ "${REPLACE:-0}" = 1 ] || die "sandbox(es) already exist: $(echo $EXISTING). Set REPLACE=1 to delete them, or SANDBOX=<other name>"
  for sb in $EXISTING; do
    openshell sandbox delete "$sb" >/dev/null 2>&1
    printf 'waiting for %s to be purged ' "$sb"
    i=0; while openshell sandbox list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$sb"; do
      i=$((i + 1)); [ $i -ge 60 ] && die "$sb was not purged after 3 minutes"; printf '.'; sleep 3; done; echo
  done
fi
OTHERS=$(openshell sandbox list 2>/dev/null | awk -v a="$SANDBOX" -v b="$SANDBOX2" 'NR > 1 && $1 != a && $1 != b && $NF == "Ready" {print $1}')
if [ -n "$OTHERS" ] && [ "${SHARED_GATEWAY_OK:-0}" != 1 ]; then
  die "other sandboxes are running on this gateway ($(echo $OTHERS)); the level-1 lockdown would cut them off too. Set SHARED_GATEWAY_OK=1 if that is acceptable"
fi
command -v "$DOCKER" >/dev/null 2>&1 || echo "note: '$DOCKER' not found; step 7 (OCSF evidence) will be skipped"
echo "preflight ok"

step "1. Two agent sandboxes on one gateway, one provider attached to both ($TARGET)"
for sb in "$SANDBOX" "$SANDBOX2"; do
  printf '$ openshell sandbox create --name %s --from %s --provider %s --detach -- sleep infinity\n' "$sb" "$IMG" "$PROVIDER"
  openshell sandbox create --name "$sb" --from "$IMG" --provider "$PROVIDER" --detach \
    --env "AGENT_BASE_URL=$AGENT_BASE_URL" --env "AGENT_MODEL=$AGENT_MODEL" --env "AGENT_KEY_ENV=$AGENT_KEY_ENV" \
    -- sleep infinity >"$OUT/create-$sb.txt" 2>&1 || { cat "$OUT/create-$sb.txt"; die "could not create sandbox $sb"; }
  CREATED+=("$sb")
done
for sb in "$SANDBOX" "$SANDBOX2"; do
  printf 'waiting for %s ' "$sb"; i=0
  until ex "$sb" true >/dev/null 2>&1; do
    i=$((i + 1)); [ $i -ge 45 ] && die "$sb did not become ready in 90 s"; printf '.'; sleep 2
  done; echo "ready"
  # Upload the agent rather than passing it in an environment variable: the
  # gateway caps each environment value at 8 KiB, and a file has no such limit.
  t 60 openshell sandbox upload "$sb" "$D/agent/agent.py" /tmp/demo </dev/null >/dev/null 2>&1 || die "could not upload the agent to $sb"
  want=$( { sha256sum "$D/agent/agent.py" 2>/dev/null || shasum -a 256 "$D/agent/agent.py"; } | cut -d' ' -f1)
  got=$(ex "$sb" "$PY" -c 'import hashlib;print(hashlib.sha256(open("'"$AGENT"'","rb").read()).hexdigest())' 2>/dev/null | tail -n 1)
  [ "$want" = "$got" ] || die "the agent in $sb does not match agent/agent.py (sha256 $got, expected $want)"
done
echo "agent uploaded and verified in both sandboxes (sha256 ${want:0:12}…)"
run openshell sandbox list

step "2. What the agent can see: a placeholder, not the key"
WHO=$(agent whoami 2>&1); echo "$WHO"
if echo "$WHO" | grep -q "looks like a real API key *: no"; then check "the agent holds a placeholder, not the key" 0
else
  check "the agent holds a placeholder, not the key" 1
  die "the value in $AGENT_KEY_ENV inside the sandbox looks like a real key. Stopping here: check the provider and profile"
fi

step "3. Legitimate work goes through (the proxy injects the real key)"
ASK=$(agent ask "In one sentence, why should an autonomous agent run inside a sandbox?" 2>&1); echo "$ASK"
case "$ASK" in
  "HTTP 200"*) check "a real request succeeds through the proxy" 0 ;;
  "HTTP 401"*) check "a real request succeeds through the proxy" 1
               die "the upstream rejected the key (401). Check the provider credential; on OCI, the IAM policy must exist before the key" ;;
  *)           check "a real request succeeds through the proxy" 1
               die "the first request did not succeed; nothing after this would mean anything" ;;
esac

step "4. The fence: anything off-policy is denied before it leaves the sandbox"
PROBE=$(agent probe 2>&1); echo "$PROBE"
echo "$PROBE" | grep "^allowed" | grep -q "HTTP 200";               check "the allowed request is allowed" $?
echo "$PROBE" | grep "unlisted host" | grep -q "DENIED";             check "an unlisted host is refused at connect" $?
echo "$PROBE" | grep "method not in policy" | grep -q "DENIED policy_denied"; check "a disallowed method gets 403 policy_denied" $?

step "5. Start the worker loop (one completion every 5 s)"
t 900 openshell sandbox exec --name "$SANDBOX" -- "$PY" "$AGENT" work 5 </dev/null > "$OUT/worker.log" 2>&1 &
WORKER=$!
sleep "$PAUSE"; tail -n 3 "$OUT/worker.log"

step "6a. KILL SWITCH, level 1: gateway-wide lockdown (every sandbox, one command)"
LOCKDOWN=1
run openshell policy set --global --policy "$D/policies/lockdown.yaml" --yes || die "could not set the global policy"
wait_state blocked "$SANDBOX";  check "lockdown blocks $SANDBOX" $?
wait_state blocked "$SANDBOX2"; check "lockdown blocks $SANDBOX2" $?
tail -n 2 "$OUT/worker.log"

step "6b. ...and it is reversible: lift the lockdown"
run openshell policy delete --global --yes && LOCKDOWN=0
wait_state open "$SANDBOX";  check "lifting restores $SANDBOX" $?
wait_state open "$SANDBOX2"; check "lifting restores $SANDBOX2" $?
tail -n 2 "$OUT/worker.log"

step "6c. KILL SWITCH, level 2: take the credential away from ONE sandbox"
run openshell sandbox provider detach "$SANDBOX" "$PROVIDER" --wait || die "could not detach the provider"
wait_state blocked "$SANDBOX"; check "detach blocks $SANDBOX" $?
wait_state open "$SANDBOX2";   check "detach leaves $SANDBOX2 working" $?
tail -n 2 "$OUT/worker.log"

step "7. Evidence: OCSF events from the first agent's supervisor"
SUP=$("$DOCKER" ps --format '{{.Names}}' 2>/dev/null | grep -E -- "--${SANDBOX}-[0-9a-f]{8}-.*-supervisor$" | head -n 1)
if [ -n "$SUP" ]; then
  "$DOCKER" logs "$SUP" 2>&1 | grep -E ' OCSF ' > "$OUT/ocsf.log" || true
  grep -E 'DENIED|CONFIG:(LOADED|DETECTED)|FINDING' "$OUT/ocsf.log" | cut -c1-200 | tail -n 12
  printf '(%s events; full log: %s)\n' "$(wc -l < "$OUT/ocsf.log" | tr -d ' ')" "$OUT/ocsf.log"
else
  echo "(no Docker supervisor container found; with other drivers, read the supervisor log there)"
fi

step "6d. KILL SWITCH, level 3: stop the sandbox (workspace kept for forensics)"
run openshell sandbox stop "$SANDBOX"
sleep 3; kill "$WORKER" 2>/dev/null; wait "$WORKER" 2>/dev/null; WORKER=
LIST=$(openshell sandbox list 2>/dev/null); echo "$LIST"
echo "$LIST" | awk -v s="$SANDBOX" '$1 == s' | grep -q "Stopped";  check "stop leaves $SANDBOX Stopped" $?
echo "$LIST" | awk -v s="$SANDBOX2" '$1 == s' | grep -q "Ready";   check "stop leaves $SANDBOX2 Ready" $?
printf '\n(worker log: %s)\n' "$OUT/worker.log"

step "Summary ($TARGET)"
printf '%s\n' ${RESULTS[@]+"${RESULTS[@]}"}
if [ "$FAILS" -eq 0 ]; then echo "ALL ${#RESULTS[@]} CHECKS PASSED"; else echo "$FAILS of ${#RESULTS[@]} CHECKS FAILED"; fi
[ "$FAILS" -eq 0 ]
