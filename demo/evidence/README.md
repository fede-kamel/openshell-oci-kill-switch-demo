# Evidence

Logs from the runs behind the results in the top-level README and the blog
post. Two things to know when comparing them with your own output:

- **They were post-processed.** ANSI colour codes are stripped, and absolute
  paths on the machines that produced them are replaced with relative ones
  (`./out`, `./policies`). Nothing else was edited.
- **They span three versions of the runbook.** The script changed as the demo
  was hardened, so step names and some lines differ from what the current
  `demo.sh` prints.

| Files | What produced them |
|---|---|
| `real-run-*.log` | The first run: OCI Generative AI, macOS, the original runbook (agent passed in an environment variable). The blog's scenes are from here. |
| `rerun-linux-2026-09-30/oci-*.log`, `openrouter-session.log` | Reruns on Linux (WSL 2) with the first generalised runbook, against OCI Generative AI and OpenRouter. |
| `rerun-linux-2026-09-30/timing-trials.txt`, `running-agent-requests.log`, `timing.sh` | Three timed trials of each kill switch against an agent making a request every second. `timing.sh` is kept exactly as it ran: it predates the upload approach (it passes the agent in an environment variable, which the current, larger agent exceeds) and has no cleanup trap, so treat it as a record, not a tool. |
| `rerun-linux-2026-09-30/hardened-*`, `certify-fresh-clone-*`, `test-matrix.sh` | The hardened runbook: full runs on both providers, the preflight and signal tests, and a certification from a fresh clone of the public repository following the README. |
| `matrix-*` | `tests/matrix.sh` against the current runbook and examples. |
