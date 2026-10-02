# Videos

## The real Codex UI operating OpenShell (recommended)

A real recording of the OpenAI Codex terminal UI operating an OpenShell gateway
from one plain-language instruction: create a sandbox, give it a task against
OCI Generative AI, stop it, restart it, delete it. This is the "from the Codex
UI, operate" view. Recorded 2026-10-02; Codex worked for about 1m46s.

| File | Use | Length |
|---|---|---|
| `focus2-codex-ui.mp4` | real time | 155s |
| `focus2-codex-ui-2x.mp4` | 2x speed, for quick viewing | 78s |
| `focus2-codex-ui-teaser.gif` | opening: banner, the instruction, Codex's plan | 14s |

It shows the Codex banner, the operator's instruction in the prompt box,
Codex's plan, its `Ran openshell sandbox ...` cards with results (HTTP 200 via
the placeholder, `Stopped`, refused-while-stopped, restarted, deleted), and the
final summary. The session ran in the demo worktree with `--approve-for-me` so
Codex auto-approved its own commands through review; no manual approvals.

## The real Codex UI provisioning scoped OCI resources (Focus 3)

A real recording of the Codex UI standing up a bounded test harness on Oracle
Cloud from the proof-of-concept prompt: preflight, create a compartment, network, bucket and an
Always Free VM, verify, stop and start the VM, then tear down by tag. Recorded
2026-10-02 against a free-tier tenancy. The instance reached RUNNING in 65s and
all seven creation checks passed; stop and start both verified.

| File | Use | Length |
|---|---|---|
| `focus3-codex-ui.mp4` | real time | 316s |
| `focus3-codex-ui-2x.mp4` | 2x speed | 158s |
| `focus3-codex-ui-3x.mp4` | 3x speed, for quick viewing | 105s |
| `focus3-codex-ui-teaser.gif` | opening: banner, the instruction, Codex's plan | 14s |

The VHS recording window ended while the tagged teardown was still running, so
the clip shows the run through "running the tagged teardown now". Teardown then
completed off camera; it was finished and verified by hand with
`scripts/teardown.sh 20261002-1224`, leaving the compartment empty and the rest
of the tenancy unchanged. That interrupted-then-recovered teardown is itself a
demonstration that the teardown-by-tag guardrail is safe.

## Styled replays of the three focuses

Deterministic replays built from the real evidence, paced for watching. These
show the commands and outputs, not the Codex UI; use the recording above for
the UI. MP4 for slides, GIF for inline.

| File | Focus | Length | Source evidence |
|---|---|---|---|
| `focus1.mp4` / `.gif` | Codex builds safe, controlled sandboxes (13/13) | 37s | `../evidence/codex-dryrun-report-2026-10-01.txt` |
| `focus2.mp4` / `.gif` | Codex operates an OpenShell sandbox (replay) | 64s | `../evidence/codex-operator-run-2026-10-02.md` |
| `focus3.mp4` / `.gif` | Codex provisions scoped OCI resources (11/11) | 33s | `../evidence/poc/report-20261002-0911.md` |
| `focus4.mp4` / `.gif` | the safety net, both sides, plus the keyless branch preview | ~30s | `../evidence/policy-conformance-…`, `iam-least-privilege-…`, `keyless-signing-kubernetes-…` |
| `codex-oci-reel.mp4` | all three replays in sequence | 133s | the three above |

## Regenerate

Needs `vhs`, `ttyd`, `ffmpeg` (Homebrew). The styled replays come from the
`scene*.txt` scripts via `play.sh` and the `.tape` files. The real UI recording
comes from `focus2-codex-ui.tape`, which drives `codex --approve-for-me` against
the gateway; `/tmp/operate_prompt.txt` holds the instruction it types.
