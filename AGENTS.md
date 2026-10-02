# Agent instructions

This repository is a runnable demo of an agent kill switch on NVIDIA OpenShell
with OCI Generative AI or OpenRouter, with the evidence from every run. The
specification for building it in a new environment is `codex/SPEC.md`; the
prompt that drives an agent through it is `codex/PROMPT.md`. Read the
specification before running anything.

## Hard rules

- Secrets. Never ask for, echo, log, or store an API key. The operator stores
  it in the gateway from their own terminal (`read -rs`, then `openshell
  provider create --credential <NAME>`). Anything that looks like a key in an
  output is a stop condition, not something to repeat. The placeholder
  `openshell:resolve:env:…` is not a secret.
- Runbook integrity. Do not modify `demo/`, `examples/`, or `tests/`. The
  runbook verifies the agent it uploads by SHA-256 and carries its own
  preflight and cleanup. If a change seems necessary, explain why and stop.
- Gateway hygiene. Do not set, change, or delete policies, attach or detach
  providers, or stop or delete sandboxes yourself; only the scripts do. You may
  import the demo provider profile after telling the operator. The operator
  runs provider create or update commands from their own terminal because those
  commands consume the key. Do not touch anything on the gateway or in Docker
  that the demo did not create.
- Scripts run from the repository root, in the foreground, with `</dev/null`.
  Bound them with `timeout` (SIGTERM) if you must, never `kill -9`; the
  cleanup trap is what lifts the lockdown.
- `openshell sandbox exec` on 0.1.2 reads piped stdin to EOF before it starts
  the command. Every non-interactive exec needs `</dev/null`.
- Secret handoff. When you print commands for the operator's terminal, tell
  them to reply `done` and not paste command output back into the chat.

## Where things are

| Path | Purpose |
|---|---|
| `demo/demo.sh` | the runbook: `TARGET=oci` or `TARGET=openrouter`, 13 checks, pass/fail summary, exit code |
| `demo/agent/agent.py` | the agent: standard-library Python against any OpenAI-compatible API |
| `demo/profile/` | one provider profile per upstream; `binaries` names the image's interpreter |
| `demo/policies/lockdown.yaml` | the fleet-wide kill switch: `version: 1`, `network_policies: {}` |
| `demo/out/` | run output, git-ignored |
| `demo/evidence/` | logs from the published runs |
| `examples/` | OpenAI SDK and LangChain in a sandbox, with `run-examples.sh` and a Dockerfile |
| `tests/matrix.sh` | the full test matrix; needs both providers and a gateway you own |
| `codex/` | the specification, prompt, and bootstrap prompt for building this elsewhere |
| `docs/` | insights, upstream status, findings, figures |

## Verifying

- `TARGET=<target> ./demo/demo.sh </dev/null` must end with `ALL 13 CHECKS PASSED`, exit 0.
- `TARGET=<target> ./examples/run-examples.sh </dev/null` must end with `ALL EXAMPLES PASSED (<target>)`, exit 0.
- Afterwards: `openshell policy get --global` shows nothing or `Status: Superseded`; `openshell sandbox list` has no demo sandboxes; `pgrep -f "agent.py work"` finds nothing.
  If `pgrep` is blocked in your sandbox, no demo sandboxes left means no worker.

## Writing

Prose in this repository follows the style of the existing documents: active
voice, short sentences, commands in `shell` fences, no filler. Keep the
disclaimer that this is personal work with personal resources. Never mention
accounts, tenancy OCIDs, or key values.
