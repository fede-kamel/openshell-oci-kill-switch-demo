# The demo

`demo.sh` is the runbook. It creates two agent sandboxes with the OCI
Generative AI provider attached, shows what the agent can and cannot do, then
applies three levels of shutdown from the gateway and collects the evidence.

## Files

| File | Purpose |
|---|---|
| `agent/agent.py` | stdlib-only Python worker: `whoami`, `ask "<prompt>"`, `probe`, `work [seconds]` |
| `profile/oci-genai-python.yaml` | the upstream `oci-genai` profile with `binaries` set to the agent image's interpreter |
| `policies/lockdown.yaml` | `version: 1` with no network policies: no egress for any sandbox |
| `demo.sh` | the runbook; writes a session log, the worker log, and the OCSF log under `out/` |
| `evidence/` | logs from the real run on 2026-09-30 |

## Setup

```shell
openshell provider profile import --file profile/oci-genai-python.yaml --global
openshell provider create --name oci-genai-demo --type oci-genai-python \
  --credential OCI_GENAI_API_KEY=<your OCI GenAI API key>
```

The key is stored in the gateway only. The sandbox receives a placeholder.

## Run

```shell
./demo.sh                      # defaults: NAME=oci-agent, PROVIDER=oci-genai-demo
CLEANUP=1 ./demo.sh            # also delete both sandboxes at the end
PAUSE=20 ./demo.sh             # let the worker loop run longer before the kill switches
```

Environment: `NAME`, `PROVIDER`, `IMG` (default `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`),
`DOCKER` (path to the Docker CLI, used only to read the supervisor's OCSF log
with the Docker driver), `PAUSE`, `CLEANUP`.

## The scenes

1. Create `oci-agent` and `oci-agent-2` with the provider attached. The agent
   script is passed as a base64 environment variable and unpacked to `/tmp`.
2. `whoami`: the placeholder, the CA bundle the sandbox injects, the model, the allowed host.
3. `ask`: one real completion through the proxy.
4. `probe`: one allowed request and two that must be denied.
5. Start the worker loop in the background.
6. Kill switch: global lockdown (measured until both agents are blocked),
   lift (measured until both answer again), detach the credential from one
   agent (measured; the other must keep answering), stop that sandbox.
7. Evidence: OCSF events from the first sandbox's supervisor.

## Gotcha: `sandbox exec` from scripts

When stdin is not a terminal, `openshell sandbox exec` reads piped input to
EOF before it starts the remote command. In a script whose stdin is an open
pipe that never closes, the call blocks forever without contacting the
gateway. Every exec in `demo.sh` runs with `</dev/null`. Do the same in your
own automation, or pipe real input. Details in `../docs/upstream/findings.md`.

## Re-creating a sandbox under the same name

`demo.sh` deletes the previous sandboxes and waits until their names are gone
from `openshell sandbox list` before creating new ones.
