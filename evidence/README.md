# Evidence

Transcripts behind every claim in the Codex entry-point material (`codex/`,
`videos/`, and the write-up built from this repository). All identifiers are
redacted; the placeholder `openshell:resolve:env:…` is a reference, not a
secret.

| File | What it proves |
|---|---|
| `codex-dryrun-report-2026-10-01.txt` | A fresh Codex session built this demo from the spec alone — 13/13 checks, examples 2/2, gateway left clean |
| `codex-review-findings-2026-10-01.md` | Codex reviewed its own spec as a stranger and fixed 20 defects before any blind run |
| `codex-customer-handoff-2026-10-02.md` | A first-time operator with no provider receives a correct, key-safe handoff |
| `codex-operator-run-2026-10-02.md` | Codex ran a sandbox create → task → stop → refused → start → delete, CLI only |
| `runbook-session-oci-2026-10-01.log` | A full `demo/demo.sh` session, `ALL 13 CHECKS PASSED` |
| `policy-conformance-2026-10-02.log` | The allow list answers 200; example.com, a disallowed method, and the Object Storage API all refuse |
| `iam-least-privilege-2026-10-02.log` | A compartment-pinned principal succeeds inside `codex-poc`; OCI refuses it outside and on ungranted families |
| `keyless-signing-kubernetes-2026-10-02.log` | Branch-build preview: a Kubernetes sandbox with placeholders only, proxy-signed requests — 5/5 |
| `poc/` | The scoped-resources proof of concept: the complete 11/11 run and the instructive first attempt |
