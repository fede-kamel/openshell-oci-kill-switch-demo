**1. Defects Fixed**
1. `codex/SPEC.md:25` and `codex/SPEC.md:26` omitted `</dev/null` in done criteria, despite `demo/demo.sh:87` and `examples/run-examples.sh:35` requiring closed stdin. Added it.

2. `codex/SPEC.md:38` and `codex/SPEC.md:65` made preflight run before knowing `TARGET`, but OCI/OpenRouter checks depend on it. Split target selection from target-specific preflight.

3. `codex/SPEC.md:65` said “fix” meant changing the machine without asking. Changed it to say what will change first; “ask” still requires explicit approval.

4. `codex/SPEC.md:46` said OCI compartment was needed when no key exists. The actual gating object is the provider. Changed it to “no `oci-genai-demo` provider exists yet.”

5. `codex/SPEC.md:49` said the API key was always needed. Fixed it so existing providers skip the secret step.

6. `codex/SPEC.md:73` did not distinguish Docker being down from Codex sandbox blocking Docker. Added that distinction.

7. `codex/SPEC.md:172` had provider-exists skipping too late in section 4.3. Moved it before profile import or key work.

8. `codex/SPEC.md:191` verified global profile import with `openshell provider profile list` but OpenShell 0.1.2 needs `--global` for platform-scoped profiles. Fixed to `openshell provider profile list --global`.

9. `codex/SPEC.md:223`, `codex/SPEC.md:228`, and `codex/SPEC.md:269` left room to invent OCI list commands. Verified with OCI help: `api-key list` and `model list` do not exist; the correct commands are `api-key-collection list-api-keys` and `model-collection list-models`. Made that explicit and added `--all`.

10. `codex/SPEC.md:181`, `codex/SPEC.md:235`, `codex/SPEC.md:249`, `codex/PROMPT.md:9`, `codex/README.md:31`, and `AGENTS.md:30` did not make the secret handoff airtight enough. Added explicit “reply `done`, do not paste output,” and clearer silent-read prompts.

11. `codex/PROMPT.md:1` was longer than needed and duplicated rules that belong in auto-loaded `AGENTS.md`. Shortened it to workflow only and moved durable safety wording into `AGENTS.md:19`.

12. `codex/PROMPT.md:9` was ambiguous about who imports profiles versus who runs secret-bearing commands. Fixed: agent imports the non-secret profile; operator runs provider create/update.

13. `codex/SPEC.md:274` and `codex/SPEC.md:319` listed both target commands without saying to run only one. Added “run only the chosen `TARGET`.”

14. `codex/SPEC.md:279` gave an incomplete timeout pattern. Replaced it with `timeout 900 env TARGET=<target> ./demo/demo.sh </dev/null`.

15. `codex/SPEC.md:361` hedged on `openshell provider profile delete`. Verified the command exists on OpenShell 0.1.2 and replaced it with `openshell provider profile delete --global <id>`.

16. `codex/SPEC.md:385` and `codex/SPEC.md:386` over-specified probe evidence compared with `demo/demo.sh:209` and `demo/agent/agent.py:125`. Relaxed to the actual checked strings: `DENIED` and `policy_denied`.

17. `codex/SPEC.md:426` through `codex/SPEC.md:450` paraphrased or omitted real abort strings from `demo/demo.sh:134` through `demo/demo.sh:235` and `examples/run-examples.sh:54` through `examples/run-examples.sh:70`. Added the missing exact patterns and actions.

18. `codex/SPEC.md:419`, `AGENTS.md:19`, and `codex/README.md:58` conflicted about gateway/provider changes. Fixed the boundary: profile import is allowed after notice; provider create/update stays with the operator; scripts own policy/sandbox changes.

19. `codex/README.md:48` said reruns need “no answers,” but they can still need non-secret context. Changed it to “no secret-bearing step.”

20. `codex/README.md:60` said the agent never changes providers, contradicting profile import. Fixed to distinguish provider profiles from provider credentials.

**2. Found But Not Changed**
1. I did not change `demo/`, `examples/`, or `tests/`, per the runbook integrity rule.

2. I did not run `demo/demo.sh`, `examples/run-examples.sh`, `tests/matrix.sh`, Docker build/run, or any mutating OpenShell command.

3. I verified only read-only CLI surfaces: `openshell provider profile --help`, `openshell provider profile list --help`, `openshell provider profile delete --help`, `openshell provider update --help`, and OCI Generative AI `--help` commands. The OpenShell commands called out by the prompt exist on this install.

4. `git diff --stat` is empty because these four files are untracked in this scratch repo; `git status --short` shows `?? AGENTS.md` and `?? codex/`.

**3. Exact `git diff --stat`**
```text
```