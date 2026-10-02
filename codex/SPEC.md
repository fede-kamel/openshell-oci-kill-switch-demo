# Specification: build "an agent kill switch you can run" in your own environment

Version 1, 2026-10-01. Companion to the blog post
[An agent kill switch you can run](https://blog.kamelhar.net/an-agent-kill-switch-on-oracle-cloud/)
and to this repository. It is written for an AI coding agent (OpenAI Codex)
that executes in the reader's environment, and it is complete enough for a
person to follow by hand. The prompt that drives an agent through it is
[`PROMPT.md`](PROMPT.md).

Everything the agent needs to decide is in this file. Where this file and the
blog post differ, this file wins; where this file and the scripts in `demo/`
or `examples/` differ, the scripts win, and the difference is a bug to report.

## 0. What is being built, and what "done" means

Two sandboxed agents run on a local NVIDIA OpenShell gateway and do real
inference through OCI Generative AI or OpenRouter without ever holding the API
key. An operator then shuts them down from the gateway in three escalating
levels. A runbook verifies every scene and prints a 13-line pass/fail summary;
a second script proves the OpenAI Python SDK and LangChain run unchanged in
the same sandbox.

Done means all of the following are true:

1. `TARGET=<target> ./demo/demo.sh </dev/null` ended with `ALL 13 CHECKS PASSED` and exit code 0.
2. `TARGET=<target> ./examples/run-examples.sh </dev/null` ended with `ALL EXAMPLES PASSED (<target>)` and exit code 0.
3. Post-conditions hold (section 5.3): no global policy in force, no demo sandboxes left, no key in any log or in the agent's conversation.
4. The operator has the report described in section 9.

Out of scope: the hardware layer of the NVIDIA platform (Sentry, BlueField),
compute drivers other than Docker, the two unmerged OCI phases
([#3962](https://github.com/NVIDIA/OpenShell/pull/3962),
[#3975](https://github.com/NVIDIA/OpenShell/pull/3975)), multi-user gateways,
and production hardening.

## 1. Inputs the operator supplies

The agent asks for `TARGET` before target-specific preflight checks. It asks
for the remaining unknown inputs in one message after the target is known.
Nothing else requires operator input unless a preflight or runbook check asks
for consent.

| Input | Values | Needed when | How the agent gets it |
|---|---|---|---|
| `TARGET` | `oci` or `openrouter` | always | use an operator context block if present; otherwise ask; suggest `openrouter` if the operator has no OCI tenancy |
| OCI compartment OCID | `ocid1.compartment.oc1..…` or `ocid1.tenancy.oc1..…` | `TARGET=oci` and no `oci-genai-demo` provider exists yet | ask; check the prefix |
| OCI region | an OCI region identifier, default `us-chicago-1` | `TARGET=oci` | ask, offer the default |
| OCI CLI profile | a `[section]` name in `~/.oci/config` | `TARGET=oci` and the agent runs `oci` commands | list the section names in `~/.oci/config` and ask which one to use; verify only that one with `oci iam region list --profile <profile>`. Do not probe the other profiles |
| The API key | OCI Generative AI key (`sk-…`) or OpenRouter key (`sk-or-…`) | only when the selected provider does not already exist | never through the agent; see section 4.3 |
| Consent flags | `SHARED_GATEWAY_OK=1`, `REPLACE=1`, `KEEP=1` | only when preflight or the operator asks | ask, and explain what each one does |

The secret rule. The agent never asks for, receives, prints, logs, or stores
the API key. The operator types it into their own terminal, into a command
that does not echo it (`read -rs`), and the OpenShell gateway stores it. The
sandboxed agents only ever see a placeholder. This mirrors the point of the
demo: nothing that can be compromised holds the key, and that includes the
coding agent. Do not export the key in the shell that starts the agent: by
default Codex passes its own environment to every command it runs
(`shell_environment_policy.inherit = "all"`; the `*KEY*`, `*SECRET*`, `*TOKEN*`
exclusions apply only when `ignore_default_excludes = false` is set). Run the
secret-bearing lines in a separate terminal and `unset` the variable after.

## 2. Prerequisites and preflight

The agent runs the target-independent checks first, asks for `TARGET`, then
runs the target-specific checks. It shows the operator a table of results
before continuing. "Fix" means the agent may do the straightforward repair
after saying what it will change; "ask" means it explains and waits for an
explicit answer.

| Requirement | Check | Passes when | If it fails |
|---|---|---|---|
| Linux, macOS on Apple Silicon, or WSL 2 | `uname -sm` | `Linux x86_64`, `Linux aarch64`, or `Darwin arm64` | ask: the demo is not tested elsewhere |
| Docker is running and visible to Codex | `docker info --format '{{.ServerVersion}}'` | prints a version | ask the operator to start Docker Desktop, or `sudo systemctl start docker` on Linux. If Docker works in their terminal but not in Codex, fix Codex sandbox access before running the scripts |
| bash 3.2 or later | `bash --version \| head -1` | version 3.2 or later | fix: install bash |
| GNU `timeout` | `command -v timeout \|\| command -v gtimeout` | one is found | macOS: fix with `brew install coreutils`. The runbook has a pure-bash fallback, so this is a warning, not a stop |
| git and curl | `git --version && curl --version \| head -1` | both print | fix: install them |
| OpenShell CLI 0.1.2 | `openshell --version` | prints `openshell 0.1.2` | fix: section 4.1 |
| Gateway connected | `openshell status` | contains `Status: Connected` | fix: section 4.1, "the gateway is not running" |
| No global policy in force | `openshell policy get --global` | prints nothing, an error, or a revision marked `Status: Superseded` | ask: someone set a lockdown on this gateway; the demo refuses to start until it is removed |
| No other sandboxes running | `openshell sandbox list` | no row other than the demo's names is `Ready` | ask: the level-1 lockdown would cut them off too. Proceed only with `SHARED_GATEWAY_OK=1` and the operator's explicit yes |
| `TARGET=oci`: OCI CLI configured | `oci --version` and `oci iam region list --profile <profile>` | both succeed | ask the operator to configure the CLI ([OCI docs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)) |
| `TARGET=openrouter`: credit on the account | none; the first request answers | HTTP 200 | an empty account gets HTTP 402; add credit or use a free model, section 8 |

The compute driver must be Docker for the OCSF evidence scene. The installer
picks Docker when Docker is present. There is no CLI command that prints the
driver; the test is that after section 4.4 creates a sandbox, `docker ps`
lists a container whose name ends in `-supervisor`. If it does not, the 13
checks still run and scene 7 prints a note instead of events.

## 3. Architecture

The gateway holds the real key and the policy. Each sandbox has a supervisor
next to it that enforces both and swaps a placeholder for the key on the way
out, for the provider's host only. The agent process takes part in none of
this. Figures are in [`../docs/figures/`](../docs/figures/).

Three words the rest of this file uses:

- **Provider**: a credential stored in the gateway under a name. It is attached to a sandbox; the agent never receives it.
- **Profile**: the rules that come with a provider: which hosts, which methods and paths, and which program inside the sandbox may use it.
- **Placeholder**: what the agent finds in its key variable, `openshell:resolve:env:…`. The proxy swaps it for the real key toward the provider's host only. Stolen, it is worthless.

Everything that gets created, by exact name:

| Piece | `TARGET=oci` | `TARGET=openrouter` | Defined in |
|---|---|---|---|
| Provider profile (type) | `oci-genai-python` | `openrouter-python` | `demo/profile/*.yaml` |
| Provider (credential) | `oci-genai-demo` | `or-demo` | created in section 4.3 |
| Credential variable | `OCI_GENAI_API_KEY` | `OPENROUTER_API_KEY` | the profile |
| Allowed host | `inference.generativeai.<region>.oci.oraclecloud.com` | `openrouter.ai` | the profile |
| Allowed methods and paths | `POST`, `GET`, `DELETE` under `/openai/v1/**` | `POST`, `GET` under `/api/v1/**` | the profile |
| Allowed binary | `/usr/local/bin/python3.12` | same | the profile |
| Sandboxes | `oci-agent`, `oci-agent-2` | `or-agent`, `or-agent-2` | `demo/demo.sh` |
| Sandbox image | `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` | same | `demo/demo.sh` (`IMG`) |
| Model | `meta.llama-3.3-70b-instruct` | `meta-llama/llama-3.3-70b-instruct` | `demo/demo.sh` (`AGENT_MODEL`) |
| The agent | `demo/agent/agent.py`, standard-library Python, uploaded to `/tmp/demo/agent.py` and verified by SHA-256 | same | `demo/demo.sh` |
| Fleet-wide kill switch | `demo/policies/lockdown.yaml`: `version: 1`, `network_policies: {}` | same | applied with `openshell policy set --global` |
| Examples sandbox | `examples-oci` | `examples-openrouter` | `examples/run-examples.sh` |
| Examples image | `openshell-demo-agents:local`, built from `examples/Dockerfile` | same | `examples/run-examples.sh` |

The three kill-switch levels, what each does, and how it is undone:

| Level | Command | Scope | Expected time to effect | Undo |
|---|---|---|---|---|
| 1 | `openshell policy set --global --policy demo/policies/lockdown.yaml --yes` | every sandbox on the gateway | 0 to 10 s after the command returns | `openshell policy delete --global --yes`, 1 to 19 s |
| 2 | `openshell sandbox provider detach <sandbox> <provider> --wait` | one sandbox | complete when the command returns, 2 to 7 s | `openshell sandbox provider attach` |
| 3 | `openshell sandbox stop <sandbox>` | one sandbox | immediate; files kept | `openshell sandbox start` |

The runbook issues these commands. The agent executing this specification
does not issue them itself (section 6).

## 4. Build steps

Run every command from the repository root. Each step has a checkpoint; do
not continue past a failed checkpoint without resolving it (section 7).

### 4.1 Install OpenShell

```shell
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION=v0.1.2 sh
```

The installer sets up the `openshell` CLI and a local gateway: a user service
on Linux, a `brew services` entry on macOS. The demo parses the 0.1.2 CLI's
table output, so pin that version. Then:

```shell
openshell --version
openshell status
```

Checkpoint: `openshell 0.1.2` and `Status: Connected`.

If the gateway is not running: on Linux `systemctl --user start
openshell-gateway`; on macOS `brew services start nvidia/openshell/openshell`.
If the installer chose a runtime other than Docker, see the
[gateway configuration docs](https://docs.nvidia.com/openshell/latest/how-it-works/gateways/configuration).

### 4.2 Get the code

```shell
git clone https://github.com/fede-kamel/openshell-oci-kill-switch-demo
cd openshell-oci-kill-switch-demo
git log -1 --format='%H %cd'
```

Checkpoint: the clone exists and the commit hash is recorded for the report.
If the agent is already inside a clone, record the hash and skip the clone.

### 4.3 Set up a provider (the operator handles the secret)

Only one provider is needed. First check whether it already exists:

```shell
openshell provider list
```

If `oci-genai-demo` has type `oci-genai-python`, or `or-demo` has type
`openrouter-python`, skip this whole step and say so. Otherwise the agent does
the parts that involve no secret; the operator runs the lines that do, in their
own terminal, then tells the agent to continue. The operator must reply only
`done`, not paste command output.

**Both targets, agent:** import the profile.

```shell
openshell provider profile import --file demo/profile/oci-genai-python.yaml --global      # TARGET=oci
openshell provider profile import --file demo/profile/openrouter-python.yaml --global     # TARGET=openrouter
```

Checkpoint: the command reports the imported profile, and `openshell provider
profile list --global` includes `oci-genai-python` or `openrouter-python`.

**`TARGET=oci`, agent:** make sure the IAM policy exists before any key is
created. A key created first can stay unauthorized after the policy lands,
and OCI returns the same 401 for an unknown key and an unauthorized one.
List the policies in the compartment and look for the two markers:

```shell
oci iam policy list --compartment-id <compartment-ocid> --profile <profile> --all \
  --query 'data[].statements[]' --raw-output | grep -i 'generative-ai-family' | grep -i 'generativeaiapikey'
```

If nothing matches, show the operator this statement and the command to
create it, and run the command only after an explicit yes (it changes IAM in
their tenancy):

```text
allow any-user to use generative-ai-family in compartment id <compartment-ocid>
  where ALL {request.principal.type='generativeaiapikey'}
```

```shell
oci iam policy create --compartment-id <compartment-ocid> --profile <profile> \
  --name openshell-genai-apikey --description 'OpenShell demo: Generative AI API keys may use Generative AI' \
  --statements '["allow any-user to use generative-ai-family in compartment id <compartment-ocid> where ALL {request.principal.type='"'"'generativeaiapikey'"'"'}"]'
```

Creating an IAM policy needs rights that many users do not have. If the
command is refused (`NotAuthorizedOrNotFound`, or a 404 on the compartment),
do not retry with other compartments: hand the statement above to a tenancy
administrator, wait until they confirm it exists, then continue. Policies take
up to a minute to propagate. Also check that the region serves Generative AI:

```shell
oci generative-ai model-collection list-models --compartment-id <compartment-ocid> \
  --region <region> --profile <profile> --all
```

It must return models. The OCI CLI list commands for this service are
collection commands: use `api-key-collection list-api-keys` and
`model-collection list-models`, not `api-key list` or `model list`.

**`TARGET=oci`, operator:** create the key and store it. The `sk-…` secret is
shown once, in the operator's terminal only. The agent prints these lines,
with the placeholders filled in, and waits.

```shell
oci generative-ai api-key create --compartment-id <compartment-ocid> --region <region> --profile <profile> \
  --display-name openshell-demo --key-details '[{"keyName":"primary","timeExpiry":"2027-01-01T00:00:00Z"}]'
printf 'Paste OCI_GENAI_API_KEY from the command output above: ' >&2
IFS= read -rs OCI_GENAI_API_KEY && export OCI_GENAI_API_KEY
printf '\n' >&2
openshell provider create --name oci-genai-demo --type oci-genai-python --credential OCI_GENAI_API_KEY
unset OCI_GENAI_API_KEY
```

**`TARGET=openrouter`, operator:** get a key at
[openrouter.ai](https://openrouter.ai) on an account with a little credit,
then:

```shell
printf 'Paste OPENROUTER_API_KEY: ' >&2
IFS= read -rs OPENROUTER_API_KEY && export OPENROUTER_API_KEY
printf '\n' >&2
openshell provider create --name or-demo --type openrouter-python --credential OPENROUTER_API_KEY
unset OPENROUTER_API_KEY
```

`--credential <NAME>` without `=<value>` reads the value from the environment
of the `openshell` process, so the key never appears on a command line or in
`ps` output.

**Both targets, agent:** verify, without touching the secret.

```shell
openshell provider list
```

Checkpoint: a row named `oci-genai-demo` with type `oci-genai-python`, or
`or-demo` with type `openrouter-python`. For OCI, `oci generative-ai
api-key-collection list-api-keys --compartment-id <compartment-ocid> --region <region> --profile <profile> --all`
shows the key as `ACTIVE`; that listing contains metadata only.

### 4.4 Run the demo

```shell
TARGET=oci ./demo/demo.sh </dev/null
TARGET=openrouter ./demo/demo.sh </dev/null
```

Run only the line for the chosen `TARGET`, exactly like that: from the
repository root, with stdin from `/dev/null`, in the foreground. Do not wrap it
in anything that can send `SIGKILL`; if a bound is needed, use
`timeout 900 env TARGET=<target> ./demo/demo.sh </dev/null`. `timeout` sends
`SIGTERM`, and the runbook's cleanup still lifts the lockdown and deletes the
sandboxes.
The first run pulls the sandbox image and can take several minutes; later
runs take two to three.

The runbook prints numbered scenes and ends with the summary:

```text
== Summary (oci) ==
PASS  the agent holds a placeholder, not the key
PASS  a real request succeeds through the proxy
PASS  the allowed request is allowed
PASS  an unlisted host is refused at connect
PASS  a disallowed method gets 403 policy_denied
PASS  lockdown blocks oci-agent
PASS  lockdown blocks oci-agent-2
PASS  lifting restores oci-agent
PASS  lifting restores oci-agent-2
PASS  detach blocks oci-agent
PASS  detach leaves oci-agent-2 working
PASS  stop leaves oci-agent Stopped
PASS  stop leaves oci-agent-2 Ready
ALL 13 CHECKS PASSED
```

Checkpoint: `ALL 13 CHECKS PASSED` and exit code 0. Record the lines that
start with `  -> ` (they carry the measured seconds for each kill-switch
level) and the path printed after `(session log:`.

The runbook refuses to start, with a line beginning `ABORT:`, if the gateway
is unreachable, the provider is missing, a global policy is in force, other
sandboxes are running, or sandboxes with its names exist. Section 7 maps
every `ABORT:` message to an action.

### 4.5 Run the examples

```shell
TARGET=oci ./examples/run-examples.sh </dev/null
TARGET=openrouter ./examples/run-examples.sh </dev/null
```

Run only the line for the chosen `TARGET`.

This builds `openshell-demo-agents:local` with `docker build` (the demo's
base image plus `openai` and `langchain-openai`), creates one sandbox, runs
both examples, and deletes the sandbox on the way out.

Checkpoint:

```text
PASS  openai sdk
PASS  langchain tool call
ALL EXAMPLES PASSED (oci)
```

and exit code 0. If `docker build` fails behind a corporate proxy, the
`pip install` inside the build needs the proxy variables passed with
`--build-arg`; report that rather than editing the Dockerfile.

### 4.6 Collect the evidence

The runbook writes under `demo/out/`, which is git-ignored:

| File | Content |
|---|---|
| `demo/out/demo-<timestamp>-<pid>.log` | the whole session, scene by scene |
| `demo/out/worker.log` | the worker loop: `ok` lines before each kill switch, `BLOCKED` lines after |
| `demo/out/ocsf.log` | OCSF shorthand events from the first sandbox's supervisor (Docker driver only) |

Confirm no secret leaked into any of them:

```shell
grep -rEl 'sk-(or-)?[A-Za-z0-9_-]{20,}' demo/out && echo "SECRET FOUND" || echo "no key material in demo/out"
```

Checkpoint: `no key material in demo/out`. The placeholder
`openshell:resolve:env:…` is expected and is not a secret.

If the agent runs under a restricted command sandbox, the session log can be
empty: the runbook writes it through a process substitution
(`exec > >(tee …)`) that some sandboxes cannot open. The same output is in the
agent's transcript, and `worker.log` and `ocsf.log` are written directly, so
the run still counts. To keep a file in that case, run
`set -o pipefail; TARGET=<target> ./demo/demo.sh </dev/null 2>&1 | tee demo/out/session-$(date +%Y%m%d-%H%M%S).log`
on the next run; the exit code is the runbook's.

### 4.7 Teardown (ask first)

Only if the operator wants the environment returned to how it was. The operator
runs these commands, or explicitly asks the agent to run the non-secret ones:

```shell
openshell provider delete oci-genai-demo        # or or-demo
openshell provider profile delete --global oci-genai-python   # or openrouter-python
docker rmi openshell-demo-agents:local
```

Then, for OCI, disable the key with `oci generative-ai api-key
set-api-key-state` or let it expire. Uninstalling OpenShell itself is out of
scope; say how (`brew uninstall`, or the user service) and stop.

## 5. Acceptance criteria

### 5.1 The 13 runbook checks

| # | Check | Scene | What proves it |
|---|---|---|---|
| 1 | the agent holds a placeholder, not the key | 2 `whoami` | the key variable starts with `openshell:resolve:env:` |
| 2 | a real request succeeds through the proxy | 3 `ask` | `HTTP 200` and a model answer |
| 3 | the allowed request is allowed | 4 `probe` | `POST` chat completions on the allowed host returns `HTTP 200` |
| 4 | an unlisted host is refused at connect | 4 `probe` | `GET https://example.com/` prints `DENIED`; the usual detail is `[Errno 13] Permission denied` before any packet leaves |
| 5 | a disallowed method gets 403 policy_denied | 4 `probe` | `PUT /openai/v1/models` (or `/api/v1/models`) returns `403`; the body contains `policy_denied` and `/usr/local/bin/python3.12` |
| 6, 7 | lockdown blocks both sandboxes | 6a | after `policy set --global`, both agents fail with `Permission denied` within 90 s (expected 0 to 10 s) |
| 8, 9 | lifting restores both sandboxes | 6b | after `policy delete --global`, both agents get `HTTP 200` again within 90 s (expected 1 to 19 s) |
| 10 | detach blocks the first sandbox | 6c | after `sandbox provider detach --wait`, the first agent fails with `Permission denied` |
| 11 | detach leaves the second sandbox working | 6c | the second agent still gets `HTTP 200` |
| 12 | stop leaves the first sandbox `Stopped` | 8 | `openshell sandbox list` shows `Stopped` |
| 13 | stop leaves the second sandbox `Ready` | 8 | `openshell sandbox list` shows `Ready` |

### 5.2 The examples

| Check | What proves it |
|---|---|
| `openai sdk` | the OpenAI Python SDK, given only `base_url` and the placeholder, prints a one-sentence answer |
| `langchain tool call` | LangChain's `ChatOpenAI` calls the `add` tool and prints `langchain tool result -> 5555` |

### 5.3 Post-conditions

| Condition | Check |
|---|---|
| no global policy in force | `openshell policy get --global` prints nothing or a `Status: Superseded` revision |
| no demo sandboxes left | `openshell sandbox list` has no `oci-agent`, `oci-agent-2`, `or-agent`, `or-agent-2`, `examples-*` rows (unless the operator asked for `KEEP=1`) |
| no worker process left | `pgrep -f "agent.py work"` finds nothing. If `pgrep` is blocked in the agent's sandbox, no demo sandboxes in `openshell sandbox list` is sufficient: the worker is an `exec` into a sandbox that no longer exists |
| no key material anywhere | the grep in section 4.6 finds nothing; the agent's own conversation contains no key |

## 6. Rules for the agent executing this specification

1. Never ask for, echo, log, or store an API key. If a value that looks like one appears anywhere, stop and tell the operator; never repeat it.
2. Do not modify anything under `demo/`, `examples/`, or `tests/`. The runbook verifies the uploaded agent by SHA-256 and the scripts carry their own safety. If a change seems necessary, explain why and stop.
3. Do not set, change, or delete gateway policies, attach or detach providers, or stop or delete sandboxes yourself. Only the scripts do that. The exceptions are the recovery commands in section 7, and only after a run was killed hard and the operator agreed.
4. Do not touch sandboxes, containers, images, providers, or policies that the demo did not create. The gateway may be shared.
5. Run the scripts as written: from the repository root, in the foreground, with `</dev/null`. Bound them with `timeout` (SIGTERM) only, never `kill -9`.
6. Before improvising on any failure, match the message against section 7. Retry a step at most twice; then report.
7. Prefer the repository's scripts over hand-rolled command sequences. When a CLI detail is unclear, `openshell <group> <command> --help` is authoritative for the installed version.
8. Tell the operator before every step that changes their tenancy (IAM policy) or their gateway (provider profile, provider), and what it will create. The agent may import the demo provider profile after that notice. The operator runs every provider create or update command because those commands consume a secret.
9. Record what you measure. The report in section 9 needs the timing lines, the log paths, the commit hash, and the environment.

## 7. Known behaviour on OpenShell 0.1.2 and what to do

| Message or symptom | Cause | Action |
|---|---|---|
| `ABORT: the openshell CLI is not on PATH` | OpenShell is not installed or not on `PATH` | install it (section 4.1), open a new shell if needed, and rerun |
| `ABORT: the gateway is not reachable: run 'openshell status' and start it first` | the gateway service is down | start it (section 4.1) and rerun |
| `ABORT: provider '…' does not exist on this gateway; see the setup lines at the top of this script` | section 4.3 not done for this `TARGET` | do section 4.3 |
| `WARNING: provider … is not of type …` | the provider name exists but has the wrong profile type | stop and use the expected provider name/type. Do not attach a mismatched provider |
| `ABORT: this gateway already has a global policy in force. The demo sets and deletes one; remove yours first or use another gateway` | a lockdown is set on this gateway | ask the operator. Remove it only if they set it: `openshell policy delete --global --yes` |
| `ABORT: sandbox(es) already exist: … Set REPLACE=1 to delete them, or SANDBOX=<other name>` | a previous run was killed hard, or names clash | ask. `REPLACE=1` deletes those demo-named sandboxes first, or `SANDBOX=<other-name>` avoids them |
| `ABORT: … was not purged after 3 minutes` | a deleted sandbox name is still present | stop and report; do not create a replacement under that name |
| `ABORT: other sandboxes are running on this gateway (…); the level-1 lockdown would cut them off too. Set SHARED_GATEWAY_OK=1 if that is acceptable` | the gateway has other work | ask. Proceed only with `SHARED_GATEWAY_OK=1` and an explicit yes |
| `ABORT: could not create sandbox …` | image pull, provider attach, or gateway create failed | read `demo/out/create-<sandbox>.txt`, fix the named cause, and retry |
| `ABORT: … did not become ready in 5 minutes (the first run pulls the image)` | image pull or sandbox start took too long | check Docker and gateway status; retry once after the pull finishes |
| `ABORT: could not upload the agent to …` | sandbox upload failed | check gateway status and retry once |
| `ABORT: the agent in … does not match agent/agent.py (sha256 …)` | upload corruption or a changed runbook asset | stop; do not edit `demo/` |
| `ABORT: the value in … inside the sandbox looks like a real key. Stopping here: check the provider and profile` | the sandbox received a key instead of a placeholder | stop. Delete or update that provider only through the operator's terminal |
| `ABORT: the upstream rejected the key (401). Check the provider credential; on OCI, the IAM policy must exist before the key` | OCI: the IAM policy did not exist before the key was created, or the key is wrong. OpenRouter: wrong key | OCI: create the policy, then a new key, then have the operator run `openshell provider update oci-genai-demo --credential OCI_GENAI_API_KEY` with the new key in their environment. OpenRouter: check the key the same way |
| `ABORT: the first request did not succeed; nothing after this would mean anything` | upstream request failed for a reason other than the mapped 401 | inspect the preceding `HTTP ...` line. Fix the target, model, region, credit, or provider before retrying |
| `ABORT: the worker loop did not complete a request in 60 s` | the first long-running worker request never succeeded | inspect `demo/out/worker.log`; fix the same causes as the first request |
| `ABORT: could not set the global policy` | the runbook could not apply `demo/policies/lockdown.yaml` | check gateway status and permissions; verify no other policy appeared |
| `ABORT: could not detach the provider` | level 2 could not detach the provider from the first sandbox | check that the sandbox and provider names still match the run |
| examples: `ABORT: the gateway is not reachable: run 'openshell status'` | the gateway service is down | start it (section 4.1) and rerun the examples |
| examples: `ABORT: provider '…' does not exist; see the README setup for TARGET=…` | section 4.3 not done for this `TARGET` | do section 4.3 |
| examples: `ABORT: sandbox … already exists; delete it or set SANDBOX=<other name>` | a previous examples sandbox or name clash exists | ask before deleting; otherwise set `SANDBOX=<other-name>` |
| examples: `ABORT: docker build failed` | Docker build failed, often proxy or registry access | if behind a corporate proxy, report that `pip install` needs proxy build args; do not edit the Dockerfile |
| examples: `ABORT: could not create sandbox …` | image, provider, or gateway create failed | fix the named cause and retry |
| examples: `ABORT: … did not become ready` | sandbox start timed out | check Docker and gateway status; retry once |
| examples: `ABORT: upload failed` | uploading example files failed | check gateway status and retry once |
| the session log under `demo/out/` is empty after a run | a restricted command sandbox blocked the runbook's `tee` process substitution (`/dev/fd`) | the output is in the agent's transcript; `worker.log` and `ocsf.log` are intact. Optional: rerun piped through `tee` as in section 4.6 |
| `pgrep` or `ps` fail inside the agent's sandbox | process listing is blocked by the sandbox | use `openshell sandbox list`: with no demo sandboxes left there is no worker |
| `oci iam policy create` fails with `NotAuthorizedOrNotFound` or a 404 | the operator's OCI user cannot create policies in that compartment | stop; give the operator the policy statement from section 4.3 to hand to a tenancy administrator, then continue once it exists |
| `HTTP 402` from OpenRouter | no credit | add credit, or `AGENT_MODEL=<model>:free` |
| `HTTP 404 Entity with key <model> not found` from OCI | the model is not served on this endpoint in this region | pick a listed model (`oci generative-ai model-collection list-models`) and pass `AGENT_MODEL=` |
| `exec` never returns | `openshell sandbox exec` reads piped stdin to EOF before starting; an open pipe never ends | always `</dev/null`; fixed upstream by [#4006](https://github.com/NVIDIA/OpenShell/pull/4006) ([#3993](https://github.com/NVIDIA/OpenShell/issues/3993)) |
| a connection closed without a response about 10 s after a sandbox started | first settings poll reloads the supervisor and closes tunnels | the agent retries once; fixed on `main` by #3819 ([#3994](https://github.com/NVIDIA/OpenShell/issues/3994)) |
| `docker pull` fails for the image | Docker Hub blocked by a proxy | the image is on `ghcr.io`; check the proxy allows `ghcr.io` |
| `provider delete` refused: `provider is attached to sandbox(es)` | by design | detach first, or delete the sandboxes |
| `profile lint` or `import` rejects a profile | the 0.1.2 CLI parses profiles client-side and does not know newer fields | use the profiles in `demo/profile/` unchanged |
| macOS: `timeout: command not found` | no GNU coreutils | `brew install coreutils`; the runbook falls back to pure bash |
| Rancher Desktop instead of Docker Desktop | the gateway needs the socket and a callback address | `DOCKER_HOST=unix://$HOME/.rd/docker.sock`, and in `gateway.toml` `grpc_endpoint = "https://host.docker.internal:17670"`; details in `docs/insights.md` |
| a run was killed with `kill -9` | the cleanup trap never ran | with the operator's yes: `openshell policy delete --global --yes` and `openshell sandbox delete <name>` for each demo sandbox |

## 8. Variations

Each of these is an environment variable on `demo/demo.sh` and
`examples/run-examples.sh`; none needs a code change.

| Want | Set |
|---|---|
| another OCI region | `OCI_REGION=<region>` |
| another model | `AGENT_MODEL=<model id in the provider's form>` |
| another provider name | `PROVIDER=<name>` on both scripts, and the same `--name <name>` in the section 4.3 `provider create` line; the profile type stays `oci-genai-python` or `openrouter-python` |
| different sandbox names | `SANDBOX=<name>`; the second is `<name>-2` |
| a longer worker loop before the kill switches | `PAUSE=<seconds>` (default 10) |
| keep the sandboxes afterwards (the stopped one for forensics) | `KEEP=1` |
| another OpenAI-compatible endpoint | `AGENT_BASE_URL`, `AGENT_KEY_ENV`, `AGENT_MODEL`, plus a copied profile whose `host`, `env_vars` and `binaries` match |
| your own agent image | keep the profile's `binaries` equal to the interpreter path in your image; rules bind to the executable |

## 9. Report

When done, the agent gives the operator this, filled in from the run:

```text
Environment : <OS and arch>, Docker <version>, OpenShell <version>, driver <Docker|other>
Repository  : <commit hash> <commit date>
Target      : <oci|openrouter>, provider <name>, model <model>, region <region or n/a>

Scene                                   Result
What the agent sees in its key variable  placeholder
A real request                           HTTP 200
An unlisted host                         refused at connect
A method the policy does not allow       403 policy_denied
Lock down every sandbox                  both blocked in <a> s and <b> s
Lift the lockdown                        both answering in <c> s and <d> s
Take the credential from one agent       cut off in <e> s; the other kept working
Stop one sandbox                         Stopped next to Ready
OpenAI SDK, LangChain + tool             pass, pass
Automated checks                         13 / 13, examples 2 / 2

Post-conditions : global policy none, demo sandboxes none, worker none, key material none
Logs            : <session log>, <worker log>, <ocsf log or "not collected: driver is not Docker">
Skipped or changed: <anything not done exactly as this specification says, and why>
```

## 10. References

- Blog post: [An agent kill switch you can run](https://blog.kamelhar.net/an-agent-kill-switch-on-oracle-cloud/)
- This repository: [fede-kamel/openshell-oci-kill-switch-demo](https://github.com/fede-kamel/openshell-oci-kill-switch-demo); scene-by-scene details in [`../demo/README.md`](../demo/README.md), measurements and gotchas in [`../docs/insights.md`](../docs/insights.md)
- NVIDIA OpenShell: [repository](https://github.com/NVIDIA/OpenShell), [documentation](https://docs.nvidia.com/openshell/latest/)
- The upstream OCI profile this demo copies: [`providers/oci-genai.yaml`](https://github.com/NVIDIA/OpenShell/blob/main/providers/oci-genai.yaml), merged in [#3904](https://github.com/NVIDIA/OpenShell/pull/3904)
- The next two OCI phases: request signing [#3962](https://github.com/NVIDIA/OpenShell/pull/3962), gateway-minted principals [#3975](https://github.com/NVIDIA/OpenShell/pull/3975)
- OCI Generative AI: [API keys and IAM policies](https://docs.oracle.com/en-us/iaas/Content/generative-ai/iam-policies.htm), [OpenAI-compatible endpoint](https://docs.oracle.com/en-us/iaas/Content/generative-ai/openai-compatible.htm)
