# Shutting down an agent from the outside

*All output below is from a real run on 2026-09-30 against OCI Generative AI in us-chicago-1 (model `meta.llama-3.3-70b-instruct`), on a local OpenShell 0.1.2 gateway with the Docker driver.*

On September 28 NVIDIA launched the Open Agent Safety Platform, and most of the
coverage used two words: kill switch. The software half of that platform is
OpenShell, an open-source Rust runtime that sandboxes an agent at the kernel
and network layers and puts every control in the hands of an operator who is
not the agent. Oracle is one of the launch partners, and this week the first
Oracle Cloud Infrastructure pieces went into the OpenShell repository. So we
built the smallest possible demo of the claim: an agent doing real work
through OCI Generative AI, then being cut off in three escalating steps
without anyone touching the agent.

## The setup

The agent is a hundred lines of standard-library Python. It calls OCI
Generative AI through the OpenAI-compatible endpoint, and it runs inside an
OpenShell sandbox with the upstream `oci-genai` provider profile attached.
Three things follow from that profile alone:

- The API key lives in the gateway. The process sees a placeholder, and the
  sandbox proxy swaps in the real key on the way out.
- Egress is deny-by-default. The only allowed destination is the OCI GenAI
  host, and only `POST`, `GET`, and `DELETE` under `/openai/v1/`.
- The rules bind to a binary. Only the agent's Python interpreter may open
  those connections.

## Scene 1: what the agent can see

```text
OCI_GENAI_API_KEY as seen by the agent : open… (61 chars)
looks like a real OCI GenAI key         : no
SSL_CERT_FILE                           : /run/openshell-supervisor-ca/material/ca-bundle.crt
allowed upstream                        : inference.generativeai.us-chicago-1.oci.oraclecloud.com
```

The value is an OpenShell placeholder. It is useless anywhere but inside this
sandbox, and only for the allowed host.

## Scene 2: legitimate work

```text
$ agent ask "In one sentence, why should an autonomous agent run inside a sandbox?"
HTTP 200: An autonomous agent should run inside a sandbox to prevent potential security
risks and damage to the host system by isolating its execution and limiting its access.
```

The request left the sandbox, the proxy injected the key, OCI answered.

## Scene 3: the fence

```text
allowed : POST chat completions on the OCI GenAI host        -> HTTP 200
blocked : GET  an unlisted host (example.com)                -> DENIED  [Errno 13] Permission denied
blocked : PUT  on the OCI GenAI host (method not in policy)  -> DENIED  {"binary":"/usr/local/bin/python3.12",
                                                                "detail":"PUT /openai/v1/models not permitted by policy",
                                                                "error":"policy_denied"}
```

Two details matter here. The unlisted host is refused at connect time, before
a packet leaves, because there is no route for it. The disallowed method is
refused at the HTTP layer with a machine-readable reason that an agent can
read in its own transcript. Nothing in the agent's code decided any of this.

## Scene 4: the kill switch, three levels

A worker loop asks the model for a status line every five seconds, and a
second agent runs in its own sandbox on the same gateway so there is a fleet
to hit. Then the operator acts, from the gateway, while both run.

**Level 1, lockdown everything.** One command replaces the policy of every
sandbox on the gateway with a policy that has no network rules.

```text
$ openshell policy set --global --policy policies/lockdown.yaml --yes
✓ Global policy configured
  -> oci-agent   blocked after 2 s: [Errno 13] Permission denied
  -> oci-agent-2 blocked after 4 s: [Errno 13] Permission denied
```

The worker loop, which had been chatting happily, sees it too:

```text
[19:39:04] ok      #1: Everything is on track and going great!
[19:39:10] ok      #2: We're making great progress and on track to meet our goals!
[19:39:15] BLOCKED #3: URLError: <urlopen error [Errno 13] Permission denied>
[19:39:20] BLOCKED #4: URLError: <urlopen error [Errno 13] Permission denied>
```

**And it is reversible.** Deleting the global policy hands control back.

```text
$ openshell policy delete --global --yes
  -> oci-agent   reachable after 8 s: HTTP 200: Yes, I am still here. Is there anything I can help you with?
  -> oci-agent-2 reachable after 4 s: HTTP 200: Yes, I am still here. Is there anything I can help you with?
```

**Level 2, take the credential away.** Detaching the provider from the
sandbox revokes the credential live. The proxy no longer has anything to
inject, and the host is no longer allowed.

```text
$ openshell sandbox provider detach oci-agent oci-genai-demo --wait
oci-agent / oci-genai-demo: revoked
  Installed: credentials=true, policy=true, future process environment=true
  -> oci-agent   blocked after 0 s: [Errno 13] Permission denied
  -> oci-agent-2 reachable after 2 s: HTTP 200: Yes, I am still here.
```

Level 1 is fleet-wide; level 2 is surgical. The second agent never noticed.

OpenShell refuses to delete a provider that is still attached to a running
sandbox, so revocation is an explicit, auditable step rather than a side
effect.

**Level 3, freeze it.** Stopping the sandbox ends the process and keeps the
workspace for forensics.

```text
$ openshell sandbox stop oci-agent
✓ Stopped sandbox oci-agent
NAME         PHASE
oci-agent    Stopped
oci-agent-2  Ready
```

## The evidence

Every decision above is an OCSF event from the sandbox supervisor, ready for
a SIEM:

```text
OCSF NET:OPEN  [INFO] ALLOWED /usr/local/bin/python3.12(0) -> inference.generativeai.us-chicago-1.oci.oraclecloud.com:443 [policy:_provider_oci_genai_demo engine:opa]
OCSF HTTP:POST [INFO] ALLOWED POST .../openai/v1/chat/completions [policy:_provider_oci_genai_demo engine:l7]
OCSF NET:OPEN  [MED]  DENIED /usr/local/bin/python3.12(0) -> example.com:443 [reason:transparent_tcp_policy_denied]
OCSF HTTP:PUT  [MED]  DENIED PUT .../openai/v1/models [policy:_provider_oci_genai_demo engine:l7] [reason:L7_REQUEST deny PUT]
OCSF CONFIG:LOADED [INFO] Policy reloaded successfully (global) [policy_hash:1b621527d93a...]
OCSF NET:OPEN  [MED]  DENIED inference.generativeai.us-chicago-1.oci.oraclecloud.com:443 [reason:L7 tunnel closed before inspection because policy changed: policy generation is stale]
OCSF NET:OPEN  [MED]  DENIED /usr/local/bin/python3.12(0) -> inference.generativeai.us-chicago-1.oci.oraclecloud.com:443 [reason:transparent_tcp_policy_denied]
```

Note the one in the middle: when a policy changes, the proxy closes tunnels
that were opened under the old rules rather than letting them finish. An
agent mid-request during a lockdown does not get to complete the request.

## Why the OCI part matters

Today the demo uses a Generative AI API key sent as a bearer token, which is
what the merged `oci-genai` profile supports. Two open pull requests extend
the same model to the rest of OCI. Proxy-side request signing lets the same
sandboxed agent call native OCI APIs such as Object Storage while holding
only placeholders. Gateway-minted principals remove long-lived keys
entirely: a gateway on OCI Compute or OKE mints short-lived security tokens
from its own platform identity. The kill switch does not change. Lockdown,
detach, and stop work the same way whatever the credential is.

## What this does not show

The hardware half of the platform, the DPU-hosted watchdog, is not part of
this demo. The gateway here runs on a laptop with Docker. And OpenShell's
`audit` enforcement mode only logs; every rule in this demo runs in `enforce`.

## Reproduce it

The runbook, the agent, the profile, and the lockdown policy are in the demo
folder. You need an OpenShell gateway, the CLI, and an OCI Generative AI API
key. Import the profile, store the key in the gateway, run `./demo.sh`.
