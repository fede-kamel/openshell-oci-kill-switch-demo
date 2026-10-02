Clone `https://github.com/fede-kamel/openshell-oci-kill-switch-demo` into the
current directory and change into it. Read `AGENTS.md` and then `codex/SPEC.md`
in full, and obey both for the rest of this session even though they were not
loaded when it started. Then build and verify the OpenShell agent kill-switch
demo by following the spec exactly.

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
anything else, tell me what happened, and retry at most twice. Verify SPEC
section 5.3, then give me the report in SPEC section 9.

Until the clone exists these rules apply in place of `AGENTS.md`: never ask
for, echo, log, or store an API key; never modify `demo/`, `examples/`, or
`tests/`; never set or delete gateway policies, attach or detach providers, or
stop or delete sandboxes yourself; never touch anything on the gateway or in
Docker that the demo did not create.
