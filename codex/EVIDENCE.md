# Evidence: Codex reviewed this directory and a fresh Codex session built the demo from it

Both runs on 2026-10-01, Codex CLI 0.159.3, model gpt-5.5, reasoning effort
high, on macOS arm64 with Docker 29.5.2 and OpenShell 0.1.2 (Docker driver),
against a laptop gateway that already held the `oci-genai-demo` provider.

## 1. Review pass

Codex was given `SPEC.md`, `PROMPT.md`, `README.md` and `AGENTS.md`, told to
read them as a fresh executor on an unknown machine, check every claim against
the scripts and the installed `openshell` and `oci` help output, and fix what
it found in place. It fixed 20 defects. The ones that would have broken a
stranger's run: two OCI CLI commands that do not exist (`api-key list` and
`model list`; the real ones are `api-key-collection list-api-keys` and
`model-collection list-models`), a profile listing that needed `--global`, a
preflight ordered before `TARGET` was known, `ABORT:` messages paraphrased
instead of quoted from the scripts, and a secret handoff that did not tell the
operator to reply `done` without pasting output. It ran only `--help`,
`openshell status`, `openshell provider list`, `openshell provider profile
list`, `openshell sandbox list` and `openshell policy get --global`.

## 2. Dry run by a fresh session

A new `codex exec` session was started in a fresh copy of this repository with
nothing but `PROMPT.md` and this operator-context block in front of it:

```text
TARGET=oci. The provider oci-genai-demo (type oci-genai-python) already exists;
skip SPEC section 4.3 after verifying it. Region us-chicago-1. No consent flags:
stop if preflight finds another global policy or other sandboxes. No teardown.
```

Codex sandbox: `workspace-write`, network enabled, `~/.config/openshell`,
`~/.docker` and `~/.rd` writable; approvals forced to on-request by managed
settings, which a headless run cannot answer, so every command had to fit the
sandbox. It did. The session ran the preflight commands exactly as section 2
lists them, confirmed the provider and skipped 4.3, ran
`TARGET=oci ./demo/demo.sh </dev/null` and then
`TARGET=oci ./examples/run-examples.sh </dev/null`, verified section 5.3, and
returned this report (paths shortened):

```text
Environment : Darwin arm64, Docker 29.5.2, OpenShell 0.1.2, driver Docker
Repository  : dcbd4ac Thu Oct 1 17:30:12 2026 -0400
Target      : oci, provider oci-genai-demo, model meta.llama-3.3-70b-instruct, region us-chicago-1

Scene                                   Result
What the agent sees in its key variable  placeholder
A real request                           HTTP 200
An unlisted host                         refused at connect
A method the policy does not allow       403 policy_denied
Lock down every sandbox                  both blocked in 3 s and 0 s
Lift the lockdown                        both answering in 17 s and 1 s
Take the credential from one agent       cut off in 0 s; the other kept working
Stop one sandbox                         Stopped next to Ready
OpenAI SDK, LangChain + tool             pass, pass
Automated checks                         13 / 13, examples 2 / 2

Post-conditions : global policy none, demo sandboxes none, worker none inferred from no sandboxes/no demo containers, key material none
Logs            : demo/out/demo-20261001-173123-7520.log, demo/out/worker.log, demo/out/ocsf.log

Skipped or changed: skipped provider setup because oci-genai-demo already existed with type oci-genai-python; skipped OCI CLI profile checks because no OCI commands were needed for an existing provider; skipped teardown per operator instruction. The runbook's session log path exists but is empty because the local command sandbox blocked /dev/fd process-substitution logging; worker and OCSF logs were written, and the runbook output passed. Direct pgrep/ps process checks were blocked by this environment, so worker cleanup was verified by gateway/Docker state instead.
```

It changed no file in the repository and asked for nothing. An independent
check after the run found no global policy, no sandboxes, no worker process,
the provider unchanged, and no key material in the clone's output or in the
Codex transcript. The two things the sandbox blocked are now covered in
`SPEC.md` sections 4.6, 5.3 and 7 and in `README.md`.

## 3. Customer simulation: no provider yet (2026-10-02)

A headless `codex exec` in a fresh clone, with an operator-context block
saying: `TARGET=oci`, use the provider name `oci-genai-cust` (which did not
exist), compartment OCID withheld, stop at the handoff. Codex produced the
preflight table (every row `PASS`, the provider row `STOP`), confirmed the
profile was already imported, and wrote the handoff for the operator: the
compartment goes into a shell variable so it never enters the chat, then the
IAM policy check, the policy create if nothing matched, the model listing, the
key creation, `read -rs`, `provider create` under the custom name, and `unset`
of every variable. It ran read-only commands plus the allowed profile import,
changed no file, and did not run the runbook. One deviation became a spec
change: to find a working OCI CLI profile it probed every profile in
`~/.oci/config` with `oci iam region list`. SPEC section 1 now says to ask
which profile to use and verify only that one.

## 4. Wrong-key path (2026-10-02)

A provider named `oci-genai-cust` was created with an invalid value, and the
runbook was run against it: `PROVIDER=oci-genai-cust TARGET=oci ./demo/demo.sh
</dev/null`. Preflight passed, both sandboxes were created, the agent was
verified by SHA-256, the placeholder check passed, and the first request
returned `HTTP 401 … INVALID_AUTHENTICATION_INFO`. The runbook printed
`ABORT: the upstream rejected the key (401). Check the provider credential; on
OCI, the IAM policy must exist before the key`, deleted both sandboxes, and
exited 1. Afterwards: no global policy, no sandboxes, no worker. This is the
row in SPEC section 7, verbatim. The test provider was then deleted.

## Also added after these tests

- SPEC section 4.3 and section 7: what to do when the operator cannot create
  the IAM policy (hand the statement to a tenancy administrator).
- SPEC section 8: `PROVIDER=<name>` for a custom provider name.
- `.agents/skills/build-openshell-kill-switch-demo/SKILL.md`, so Codex
  discovers the task inside the clone without the prompt being pasted, and
  `CLAUDE.md` pointing at `AGENTS.md` for Claude Code users.

## 5. Codex as the operator: task, stop, start, delete (2026-10-02)

A headless `codex exec` was asked to operate the gateway directly through the
CLI: create a sandbox `codex-task` from the demo image with `oci-genai-demo`
attached, wait for exec, upload `demo/agent/agent.py`, run the agent's `ask`
inside it, stop the sandbox, try the task again, start it, run the task again,
delete it. Every step succeeded: the task returned `HTTP 200` from OCI through
the placeholder before and after the stop; while stopped the task was refused
with `sandbox 'codex-task' is not ready (phase: Stopped)`; `sandbox list` was
empty at the end, the provider and global policy untouched. Codex used
`--help` once for `create` and once for `upload`, and noticed on its own that
`upload <file> /tmp/demo/agent.py` treats the destination as a directory,
then fixed the path. So "give a task to OpenShell from Codex" and "stop an
OpenShell container from Codex" both work with nothing but the CLI, and the
public `openshell-cli` skill is the natural way to hand Codex that knowledge.
