Build and verify this OpenShell agent kill-switch demo by following
`codex/SPEC.md` exactly. Read the spec in full before you run anything, and
obey `AGENTS.md`.

If I put an "Operator context" block above this prompt, use it as my answers.
Otherwise ask only for the inputs that SPEC section 1 requires and you cannot
detect. If I have no OCI tenancy, use `TARGET=openrouter`.

Show me the preflight table from SPEC section 2. For provider setup, follow
SPEC section 4.3: import only the non-secret profile yourself, hand me the
secret-bearing commands to run in my own terminal, and tell me to reply `done`
without pasting output. If the provider already exists with the right type,
skip setup.

Run only the selected target through SPEC sections 4.4 and 4.5, from the
repository root, foreground, with stdin from `/dev/null`. If a run prints
`ABORT:` or a check fails, match it against SPEC section 7 before doing
anything else, tell me what happened, and retry at most twice.

Verify SPEC section 5.3, then give me the report in SPEC section 9.
