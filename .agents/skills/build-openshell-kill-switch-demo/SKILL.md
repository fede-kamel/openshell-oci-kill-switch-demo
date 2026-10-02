---
name: build-openshell-kill-switch-demo
description: Build and verify the OpenShell agent kill-switch demo (OCI Generative AI or OpenRouter) in the current environment by following codex/SPEC.md, with the API key handled by the operator in their own terminal. Use when asked to build, run, reproduce, verify, or demo the kill switch, the OpenShell OCI demo, or "the 13 checks".
---

# Build the OpenShell kill-switch demo

Read `codex/SPEC.md` in full and `AGENTS.md` before running anything, then
follow `codex/PROMPT.md`: preflight table (SPEC section 2), inputs (section 1),
provider setup with the secret handoff (section 4.3), the runbook and the
examples for the selected target only (sections 4.4 and 4.5), post-conditions
(section 5.3), report (section 9). Match any `ABORT:` against section 7 before
improvising.

Never ask for, echo, or store an API key. Never modify `demo/`, `examples/`, or
`tests/`. Never set or delete gateway policies, attach or detach providers, or
stop or delete sandboxes yourself; the scripts do that.
