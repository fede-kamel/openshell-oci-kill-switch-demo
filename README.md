# OpenShell + OCI: an agent kill switch you can run

A reproducible demo, the evidence, and everything learned while bringing
Oracle Cloud Infrastructure support to [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell),
the sandbox runtime at the core of NVIDIA's Open Agent Safety Platform
(launched 2026-09-28).

The demo runs a small agent that does real work through OCI Generative AI
from inside an OpenShell sandbox, shows that the agent never holds a
credential and cannot step outside its policy, then shuts it down from the
gateway in three escalating steps while a second agent proves which controls
are fleet-wide and which are surgical.

## Results from the real run (2026-09-30)

| Scene | Outcome |
|---|---|
| What the agent sees | a 60-character placeholder, not the API key |
| Legitimate work | `HTTP 200` from `meta.llama-3.3-70b-instruct` through the OpenAI-compatible endpoint |
| Unlisted host | denied at connect, before a packet leaves |
| Disallowed method | denied at the HTTP layer with a `policy_denied` body naming the binary |
| Gateway-wide lockdown | both agents blocked after 2 s and 4 s |
| Lift lockdown | both answering again after 8 s and 4 s |
| Detach credential from one agent | blocked in 0 s; the other agent unaffected |
| Stop one sandbox | `Stopped` next to the other's `Ready`; workspace preserved |

Every decision is an OCSF event. See [`demo/evidence/`](demo/evidence/).

## Repository layout

```
demo/                 the runbook, the agent, the profile, the lockdown policy, real-run evidence
docs/blog-draft.md    the write-up, built from the real run
docs/insights.md      everything learned: control model, timings, gotchas, environment recipe
docs/oci-integration-status.md   the three upstream phases, PR links, design decisions, what is verified
docs/upstream/findings.md        candidate bugs and questions for the OpenShell maintainers, with evidence
docs/launch-context.md           what was announced, what OpenShell is and is not, sources
docs/demo-talk-track.md          a 90-second recording script
docs/oracle-openshell-guide.mdx  the full OCI guide that was scoped out of the upstream docs
docs/pr-bodies/                  the bodies of the two open upstream pull requests
```

## Quick start

Requirements: an OpenShell gateway (the Homebrew install with Docker or
Rancher Desktop is enough), the `openshell` CLI, and an OCI Generative AI
API key scoped to a compartment with Generative AI access.

```shell
openshell provider profile import --file demo/profile/oci-genai-python.yaml --global
openshell provider create --name oci-genai-demo --type oci-genai-python \
  --credential OCI_GENAI_API_KEY=<your key>
cd demo && ./demo.sh
```

Details, options, and the one gotcha that will bite anyone scripting the
CLI are in [`demo/README.md`](demo/README.md).

## Upstream work this builds on

| Phase | What it gives OpenShell users | Status |
|---|---|---|
| Bearer profile `oci-genai` | OCI Generative AI through the OpenAI-compatible endpoint with an injected API key | merged, [#3904](https://github.com/NVIDIA/OpenShell/pull/3904) |
| Proxy-side request signing `credential_signing: oci` | native OCI APIs (Object Storage, native Generative AI) with placeholders in the sandbox | open, [#3962](https://github.com/NVIDIA/OpenShell/pull/3962) |
| Gateway-minted principals | no long-lived key anywhere: instance, resource, and OKE workload principals | open draft, [#3975](https://github.com/NVIDIA/OpenShell/pull/3975) |

## License

Apache-2.0. `demo/profile/oci-genai-python.yaml` is derived from the
`oci-genai` example profile in NVIDIA/OpenShell (Apache-2.0) and keeps its
header; see `NOTICE`.
