#!/usr/bin/env bash
# Run the OpenAI SDK and LangChain examples inside an OpenShell sandbox.
#
#   TARGET=oci ./examples/run-examples.sh          # provider oci-genai-demo
#   TARGET=openrouter ./examples/run-examples.sh   # provider or-demo
#
# Uses the same providers as demo/demo.sh (see the README for setup). Builds a
# local image with the two libraries, creates one sandbox, runs both examples,
# and always deletes the sandbox on the way out.
set -u
trap '' PIPE
export NO_COLOR=1
E=$(cd "$(dirname "$0")" && pwd)
TARGET=${TARGET:-oci}
case "$TARGET" in
  oci)
    OCI_REGION=${OCI_REGION:-us-chicago-1}
    : "${PROVIDER:=oci-genai-demo}"
    : "${AGENT_BASE_URL:=https://inference.generativeai.$OCI_REGION.oci.oraclecloud.com/openai/v1}"
    : "${AGENT_MODEL:=meta.llama-3.3-70b-instruct}" "${AGENT_KEY_ENV:=OCI_GENAI_API_KEY}" ;;
  openrouter)
    : "${PROVIDER:=or-demo}"
    : "${AGENT_BASE_URL:=https://openrouter.ai/api/v1}"
    : "${AGENT_MODEL:=meta-llama/llama-3.3-70b-instruct}" "${AGENT_KEY_ENV:=OPENROUTER_API_KEY}" ;;
  *) echo "TARGET must be oci or openrouter" >&2; exit 2 ;;
esac
SANDBOX=${SANDBOX:-examples-$TARGET}
IMG=${IMG:-openshell-demo-agents:local}
DOCKER=${DOCKER:-docker}
PY=/usr/local/bin/python3.12

if command -v timeout >/dev/null 2>&1; then T=timeout
elif command -v gtimeout >/dev/null 2>&1; then T=gtimeout
else T=; fi
ex() { if [ -n "$T" ]; then "$T" 120 openshell sandbox exec --name "$SANDBOX" -- "$@" </dev/null
       else openshell sandbox exec --name "$SANDBOX" -- "$@" </dev/null; fi; }
die() { printf 'ABORT: %s\n' "$*"; exit 1; }

CREATED=
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ -n "$CREATED" ]; then
    openshell sandbox delete "$SANDBOX" >/dev/null 2>&1 && echo "cleanup: deleted sandbox $SANDBOX" \
      || echo "cleanup: WARNING could not delete sandbox $SANDBOX; run: openshell sandbox delete $SANDBOX"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

openshell status >/dev/null 2>&1 || die "the gateway is not reachable: run 'openshell status'"
openshell provider list 2>/dev/null | awk -v p="$PROVIDER" '$1 == p' | grep -q . \
  || die "provider '$PROVIDER' does not exist; see the README setup for TARGET=$TARGET"
openshell sandbox list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$SANDBOX" \
  && die "sandbox $SANDBOX already exists; delete it or set SANDBOX=<other name>"

echo "== building $IMG (openai + langchain-openai on the demo's base image)"
"$DOCKER" build -q -t "$IMG" "$E" >/dev/null || die "docker build failed"

echo "== creating sandbox $SANDBOX with provider $PROVIDER"
CREATED=yes
openshell sandbox create --name "$SANDBOX" --from "$IMG" --provider "$PROVIDER" --detach \
  --env "AGENT_BASE_URL=$AGENT_BASE_URL" --env "AGENT_MODEL=$AGENT_MODEL" --env "AGENT_KEY_ENV=$AGENT_KEY_ENV" \
  -- sleep infinity >/dev/null 2>&1 || die "could not create sandbox $SANDBOX"
i=0; until ex true >/dev/null 2>&1; do i=$((i + 1)); [ $i -ge 150 ] && die "$SANDBOX did not become ready"; sleep 2; done
openshell sandbox upload "$SANDBOX" "$E/openai_sdk.py" /tmp/examples </dev/null >/dev/null 2>&1 || die "upload failed"
openshell sandbox upload "$SANDBOX" "$E/langchain_agent.py" /tmp/examples </dev/null >/dev/null 2>&1 || die "upload failed"

FAILS=0
echo "== what the libraries are given"
ex "$PY" -c 'import os; k=os.environ[os.environ["AGENT_KEY_ENV"]]; print(os.environ["AGENT_KEY_ENV"], "=", k if k.startswith("openshell:resolve:") else "NOT A PLACEHOLDER")' 2>&1 | tail -n 1
echo "== OpenAI Python SDK"
OUT1=$(ex "$PY" /tmp/examples/openai_sdk.py 2>&1 | tail -n 3); echo "$OUT1"
echo "$OUT1" | grep -q "^openai sdk -> ." && echo "PASS  openai sdk" || { echo "FAIL  openai sdk"; FAILS=$((FAILS + 1)); }
echo "== LangChain with a tool"
OUT2=$(ex "$PY" /tmp/examples/langchain_agent.py 2>&1 | tail -n 3); echo "$OUT2"
echo "$OUT2" | grep -q "langchain tool result -> 5555" && echo "PASS  langchain tool call" || { echo "FAIL  langchain tool call"; FAILS=$((FAILS + 1)); }
[ "$FAILS" -eq 0 ] && echo "ALL EXAMPLES PASSED ($TARGET)" || echo "$FAILS EXAMPLE(S) FAILED ($TARGET)"
[ "$FAILS" -eq 0 ]
