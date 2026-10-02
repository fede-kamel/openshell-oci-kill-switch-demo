# Build this with Codex

This directory makes the demo reproducible by an AI coding agent in your own
environment, so that the agent, not you, learns the OpenShell and OCI command
lines.

| File | What it is |
|---|---|
| [`SPEC.md`](SPEC.md) | the specification: inputs, prerequisites, every build step with its checkpoint, the acceptance checks, the rules the agent follows, known 0.1.2 behaviour, and the report format |
| [`PROMPT.md`](PROMPT.md) | the prompt that drives Codex through the specification from inside a clone; plain text, paste it or pipe it |
| [`BOOTSTRAP.md`](BOOTSTRAP.md) | the same, for an empty directory: Codex clones the repository first |
| [`../AGENTS.md`](../AGENTS.md) | what Codex loads automatically in this repository: the hard rules and where things are |

## Use it

**Watch it happen first:** [the Codex UI operating a sandbox, 78 s](../videos/focus2-codex-ui-2x.mp4) · [all recordings](../videos/).


Install [Codex](https://developers.openai.com/codex) (`npm install -g
@openai/codex`) and sign in. Do not export your API key in the shell you start
Codex from; Codex passes its environment to the commands it runs, and the
prompt hands you the one secret-bearing step to run in another terminal.
Then, with Docker running:

```shell
git clone https://github.com/fede-kamel/openshell-oci-kill-switch-demo
cd openshell-oci-kill-switch-demo
codex -c sandbox_workspace_write.network_access=true \
  --add-dir ~/.config/openshell --add-dir ~/.docker \
  "$(cat codex/PROMPT.md)"
```

Or start `codex` with the same flags and paste `PROMPT.md`. Or, with no clone
at all, start `codex` in an empty directory and paste `BOOTSTRAP.md`.

Codex checks your machine, asks which upstream you want (OCI Generative AI or
OpenRouter), imports the non-secret provider profile if needed, hands you the
step that involves your API key, runs the runbook and the examples, and ends
with a report. Reply `done` after the secret-bearing terminal step; do not
paste that terminal's output into Codex. A run takes a few minutes after the
image is pulled.

About the Codex sandbox. Codex's default `workspace-write` mode blocks network
access and writes outside the repository, and both are needed: the CLI talks
to the gateway and keeps state under `~/.config/openshell`, Docker keeps state
under `~/.docker` (Rancher Desktop also uses `~/.rd`, so add that too). The
flags above grant exactly those; `[sandbox_workspace_write] network_access =
true` in `~/.codex/config.toml` makes the network part permanent. This is also
the mode to use when your organisation's managed Codex settings forbid
`--sandbox danger-full-access`. A headless `codex exec` cannot grant approval
requests, so the run has to fit inside the sandbox; the flags above are enough
for every command the spec issues. Two things a restricted sandbox may still
block, neither of which affects a check: the runbook's session log, which is
written through a process substitution and comes out empty, and `pgrep`, in
which case the agent verifies the worker is gone from gateway state. The spec
covers both.

## Reruns without a conversation

Once the provider exists on the gateway, the run needs no secret-bearing step.
Put them in a file and pipe both into a non-interactive session:

```shell
cat > operator-context.md <<'EOF2'
Operator context. TARGET=oci. The provider oci-genai-demo already exists; skip SPEC section 4.3 after verifying it. No consent flags: stop if preflight finds another global policy or other sandboxes. Do not do section 4.7.
EOF2
{ cat operator-context.md; echo; cat codex/PROMPT.md; } | codex exec \
  -c sandbox_workspace_write.network_access=true \
  --add-dir ~/.config/openshell --add-dir ~/.docker -
```

## What the agent never does

The agent never sees the API key and never edits the runbook. It may import the
demo's non-secret provider profile after telling you. You run provider create
or update commands from your own terminal, because those commands consume the
key. Gateway policies, provider attachments and sandboxes are changed only by
the runbook, with its own preflight and cleanup. This is the same arrangement
the demo shows for the sandboxed agent, applied one level up.
