# The demo

`demo.sh` is the runbook. It creates two agent sandboxes with one provider
attached — OCI Generative AI (`TARGET=oci`, the default) or OpenRouter
(`TARGET=openrouter`) — shows what the agent can and cannot do, then
applies three levels of shutdown from the gateway and collects the evidence.

## Files

| File | Purpose |
|---|---|
| `agent/agent.py` | stdlib-only Python worker for any OpenAI-compatible endpoint: `whoami`, `ask "<prompt>"`, `probe`, `work [seconds]` |
| `profile/oci-genai-python.yaml` | the upstream `oci-genai` profile with `binaries` set to the agent image's interpreter |
| `profile/openrouter-python.yaml` | the upstream `openrouter` profile, bound to the same interpreter and narrowed to `POST`/`GET` under `/api/v1/` |
| `policies/lockdown.yaml` | `version: 1` with no network policies: no egress for any sandbox |
| `demo.sh` | the runbook; writes a session log, the worker log, and the OCSF log under `out/` |
| `evidence/` | logs from the first run on 2026-09-30 (OCI, macOS) |
| `evidence/rerun-linux-2026-09-30/` | the OCI and OpenRouter reruns, the timing trials, and `timing.sh` |

## Setup

OCI Generative AI:

```shell
openshell provider profile import --file profile/oci-genai-python.yaml --global
openshell provider create --name oci-genai-demo --type oci-genai-python \
  --credential OCI_GENAI_API_KEY          # read from your environment
```

OpenRouter:

```shell
openshell provider profile import --file profile/openrouter-python.yaml --global
openshell provider create --name or-demo --type openrouter-python \
  --credential OPENROUTER_API_KEY
```

The key is stored in the gateway only. The sandbox receives a placeholder.

## Run

```shell
./demo.sh                          # TARGET=oci: sandboxes oci-agent / oci-agent-2, provider oci-genai-demo
TARGET=openrouter ./demo.sh        # sandboxes or-agent / or-agent-2, provider or-demo
KEEP=1 ./demo.sh                   # keep both sandboxes at the end (the stopped one for forensics)
PAUSE=20 ./demo.sh                 # let the worker loop run longer before the kill switches
```

Every scene is checked. The run ends with a summary like this, and the exit
code is non-zero if any check failed:

```text
PASS  the agent holds a placeholder, not the key
PASS  a real request succeeds through the proxy
PASS  the allowed request is allowed
PASS  an unlisted host is refused at connect
PASS  a disallowed method gets 403 policy_denied
PASS  lockdown blocks oci-agent
...
ALL 13 CHECKS PASSED
```

## Safety

The runbook changes gateway-wide state, so it guards against doing harm:

- **Preflight refuses to start** if the gateway is unreachable, the provider
  is missing, a global policy is already in force (the demo sets and deletes
  one), other sandboxes are running (the lockdown would cut them off too; set
  `SHARED_GATEWAY_OK=1` to accept that), or sandboxes with the demo's names
  exist (set `REPLACE=1` to delete them).
- **It always cleans up after itself.** On success, failure, Ctrl-C or a
  termination signal — including one sent to its whole process group by a CI
  cancel or `timeout` — it lifts the lockdown first if it set one, stops the
  worker, and deletes the sandboxes it created (unless `KEEP=1`). Only
  `kill -9` can defeat that; see Troubleshooting in the top-level README.
- **It stops at the first thing that would make the rest meaningless**: a
  sandbox that will not start, an agent that does not match `agent/agent.py`
  (checked by SHA-256 after upload), an agent that can see something that
  looks like a real key, or an upstream that rejects the first request.
- **No secret is ever printed.** The key lives in the gateway and the agent
  only ever sees a placeholder (`openshell:resolve:env:…`), which `whoami`
  prints in full because it is a reference, not a secret. Anything else in the
  key variable is treated as a possible real key: only four characters are
  shown and the run stops. The agent sends the credential only to its own
  host, never to the probe's unlisted host.

The agent is uploaded with `openshell sandbox upload` rather than passed in
an environment variable, because the gateway caps each environment value at
8 KiB.

Environment: `TARGET`, `SANDBOX`, `PROVIDER`, `OCI_REGION` (default
`us-chicago-1`), `IMG` (default `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`),
`PAUSE`, `KEEP`, `REPLACE`, `SHARED_GATEWAY_OK`, and `AGENT_BASE_URL` /
`AGENT_MODEL` / `AGENT_KEY_ENV` to point the agent at any other
OpenAI-compatible endpoint. `DOCKER` is the Docker CLI used only to read the
supervisor's OCSF log with the Docker driver (default: Rancher Desktop's
`~/.rd/bin/docker` if present, else `docker`). The sandbox variable is
`SANDBOX`, not `NAME`, because many shells already export `NAME`.
Requires bash (3.2 or later) and, for timeouts, `timeout` or `gtimeout`.

## The scenes

0. Preflight: gateway, provider, no global policy in force, no other running
   sandboxes, no name clashes.
1. Create the two sandboxes with the provider attached, upload the agent to
   `/tmp/demo/agent.py`, and verify it by SHA-256.
2. `whoami`: the placeholder, the CA bundle the sandbox injects, the model, the allowed host.
3. `ask`: one real completion through the proxy.
4. `probe`: one allowed request and two that must be denied.
5. Start the worker loop (one completion every 5 s, for at most 10 minutes)
   and wait until it has done real work.
6. Kill switch, level 1: global lockdown, measured until both agents are
   refused with a real denial; then lift it, measured until both answer.
6c. Kill switch, level 2: detach the credential from one agent; the other must
   keep answering.
7. Evidence: OCSF events from the first sandbox's supervisor, read before
   level 3 stops it.
8. Kill switch, level 3: stop that sandbox; the other stays `Ready`.

## Gotcha: `sandbox exec` from scripts

When stdin is not a terminal, `openshell sandbox exec` reads piped input to
EOF before it starts the remote command. In a script whose stdin is an open
pipe that never closes, the call blocks forever without contacting the
gateway. Every exec in `demo.sh` runs with `</dev/null`. Do the same in your
own automation, or pipe real input. Details in `../docs/upstream/findings.md`.

## Re-creating a sandbox under the same name

A sandbox whose deletion is still pending makes `exec` stall if a new one is
created under the same name. `demo.sh` deletes its own sandboxes on exit, so
reruns start clean; with `REPLACE=1` it deletes existing ones first and waits
until their names are gone from `openshell sandbox list`.
