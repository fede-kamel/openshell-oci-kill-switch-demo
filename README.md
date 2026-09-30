# OpenShell + OCI: an agent kill switch you can run

A reproducible demo, the evidence, and everything learned while bringing
Oracle Cloud Infrastructure support to [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell),
the sandbox runtime at the core of NVIDIA's Open Agent Safety Platform
(launched 2026-09-28).

The demo runs a small agent that does real work through OCI Generative AI —
or, with one variable, through OpenRouter — from inside an OpenShell sandbox,
shows that the agent never holds a credential and cannot step outside its
policy, then shuts it down from the gateway in three escalating steps while a
second agent proves which controls are fleet-wide and which are surgical.

> **Personal work, personal resources.** Everything here was built and tested
> with my own accounts and machines. The OpenShell contributions are mine, made
> as an individual open-source contributor. This is not an Oracle publication,
> product commitment, or statement of Oracle's plans.

## Architecture

![Two agent sandboxes on one OpenShell gateway. Each agent talks only to its supervisor, which checks host, method, path and binary and swaps a placeholder for the real key; the only way out is through the supervisor, to OCI Generative AI or OpenRouter, chosen by one provider profile.](docs/figures/architecture.png)

The agent never participates in enforcement. The gateway holds the real key
and the policy; each sandbox's supervisor enforces both and swaps a
placeholder for the key on the way out. The upstream is whichever provider
profile is attached — `oci-genai-python` or `openrouter-python` — and nothing
else changes: same agent code, same fence, same three kill switches.
More figures in [`docs/figures/`](docs/figures/).

## Results

Three full runs on 2026-09-30, OpenShell 0.1.2 with the Docker driver:

| Scene | OCI, macOS (first run) | OCI, Linux (rerun) | OpenRouter, Linux (rerun) |
|---|---|---|---|
| What the agent sees | 60-char placeholder | 59-char placeholder | 61-char placeholder |
| Legitimate work | `HTTP 200` | `HTTP 200` | `HTTP 200` |
| Unlisted host | denied at connect | denied at connect | denied at connect |
| Disallowed method (`PUT`) | `403 policy_denied`, names the binary | same | same |
| Gateway-wide lockdown | both blocked, 2 s / 4 s | 6 s / 1 s | 6 s / 0 s |
| Lift lockdown | answering, 8 s / 4 s | 10 s / 5 s | 16 s / 2 s |
| Detach credential from one agent | blocked; other unaffected | blocked; other unaffected | blocked; other unaffected |
| Stop one sandbox | `Stopped` next to `Ready` | same | same |

Lockdown and lift times are from a fresh request after the command returned.
Three further timed trials against an agent that was already running show the
lockdown reaching it 7 to 9 s after the command, and `detach --wait` taking 2
to 7 s to return — by which point the running agent is already cut off. See
[`docs/insights.md`](docs/insights.md#timed-trials-added-after-the-first-run).

Every decision is an OCSF event. Evidence:
[`demo/evidence/`](demo/evidence/) (first run) and
[`demo/evidence/rerun-linux-2026-09-30/`](demo/evidence/rerun-linux-2026-09-30/)
(reruns and timing trials).

## Quick start

Requirements: an OpenShell gateway with the Docker driver (the Homebrew or
quickstart install with Docker Desktop or Rancher Desktop is enough), the
`openshell` CLI, and a key for one of the two targets.

**OCI Generative AI** — an API key in a compartment with Generative AI access
(create the IAM policy before the key; the profile header has the one line):

```shell
openshell provider profile import --file demo/profile/oci-genai-python.yaml --global
export OCI_GENAI_API_KEY=sk-...
openshell provider create --name oci-genai-demo --type oci-genai-python --credential OCI_GENAI_API_KEY
./demo/demo.sh                             # TARGET=oci is the default
```

**OpenRouter** — no Oracle Cloud account needed; a run costs a fraction of a cent:

```shell
openshell provider profile import --file demo/profile/openrouter-python.yaml --global
export OPENROUTER_API_KEY=sk-or-...
openshell provider create --name or-demo --type openrouter-python --credential OPENROUTER_API_KEY
TARGET=openrouter ./demo/demo.sh
```

`--credential NAME` with no value reads the key from your environment, so it
never appears on a command line. Level 1 sets a *global* policy: run the demo
on a gateway you own. Options and the one gotcha that will bite anyone
scripting the CLI are in [`demo/README.md`](demo/README.md).

## Repository layout

```
demo/                            the runbook, the agent, both profiles, the lockdown policy
demo/evidence/                   logs from the first run (OCI, macOS)
demo/evidence/rerun-linux-2026-09-30/   OCI and OpenRouter reruns, timing trials and their script
docs/figures/                    architecture, controls, request sequence, kill-switch ladder, OCI transports
docs/blog-draft.md               the first write-up, built from the first run
docs/insights.md                 everything learned: control model, timings, gotchas, environment recipe
docs/oci-integration-status.md   the three upstream phases, PR links, design decisions, what is verified
docs/upstream/findings.md        the two bugs found upstream (#3993, #3994), their causes and fixes
docs/launch-context.md           what was announced, what OpenShell is and is not, sources
docs/demo-talk-track.md          a 90-second recording script
docs/oracle-openshell-guide.mdx  the full OCI guide that was scoped out of the upstream docs
docs/pr-bodies/                  the bodies of the two open upstream pull requests
```

## Upstream work this builds on

| Phase | What it gives OpenShell users | Status |
|---|---|---|
| Bearer profile `oci-genai` | OCI Generative AI through the OpenAI-compatible endpoint with an injected API key | merged, [#3904](https://github.com/NVIDIA/OpenShell/pull/3904) |
| Proxy-side request signing `credential_signing: oci` | native OCI APIs (Object Storage, native Generative AI) with placeholders in the sandbox | open, [#3962](https://github.com/NVIDIA/OpenShell/pull/3962) |
| Gateway-minted principals | no long-lived key anywhere: instance, resource, and OKE workload principals | open draft, [#3975](https://github.com/NVIDIA/OpenShell/pull/3975) |

## License

Apache-2.0. `demo/profile/oci-genai-python.yaml` and
`demo/profile/openrouter-python.yaml` are derived from the `oci-genai` and
`openrouter` example profiles in NVIDIA/OpenShell (Apache-2.0) and keep their
headers; see `NOTICE`.
