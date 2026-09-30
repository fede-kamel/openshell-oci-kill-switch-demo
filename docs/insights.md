# Insights: how OpenShell controls an agent, and what we learned running it

Everything here was observed on OpenShell 0.1.2 (Homebrew gateway, Docker
driver on Rancher Desktop, macOS) on 2026-09-30, plus the source tree at
that date. Where a statement comes from the docs rather than observation, it
says so.

## 1. The control model in one picture

```
                 operator (CLI / API, mTLS to the gateway)
                              |
   +--------------------------v-----------------------------+
   |  gateway: policies, providers, credentials, settings   |
   |  - policy set/update (per sandbox)   - global policy   |
   |  - provider create/update/delete     - attach/detach   |
   |  - sandbox create/stop/start/delete                    |
   +----------------------+---------------------------------+
                          | config polls (~10 s), gRPC relay
   +----------------------v---------------------------------+
   | sandbox = supervisor + workload                        |
   |  supervisor: L4/L7 proxy, credential injection, DNS,   |
   |              OCSF events, policy reload, SSH relay     |
   |  workload:   Landlock + seccomp, no default egress,    |
   |              sees placeholders, CA bundle env vars     |
   +--------------------------------------------------------+
```

The agent's process never participates in enforcement. Everything it can do
is decided by the supervisor next to it and the gateway above it.

## 2. The kill switch ladder, measured

| Level | Command | Scope | Time to effect (observed) | Reversible |
|---|---|---|---|---|
| 0 | policy rules (`enforce`) | per request | immediate | n/a |
| 1 | `openshell policy set --global --policy lockdown.yaml --yes` | every sandbox on the gateway | 0 to 10 s after the command returns (docs: within about 10 s) | `openshell policy delete --global --yes`, 1 to 19 s |
| 2 | `openshell sandbox provider detach <sandbox> <provider> --wait` | one sandbox | 2 to 7 s, complete when `--wait` returns | `sandbox provider attach` |
| 3 | `openshell sandbox stop <sandbox>` | one sandbox | immediate | `sandbox start`, workspace preserved |
| 4 | `openshell sandbox delete <sandbox>` | one sandbox | immediate, cleanup pending | no |

Observations:

- Level 1 propagates through the supervisor's settings poll, so it lands
  within one poll interval. One dry run saw a 50 s lag on the lift; every
  other run was under 11 s.
- When policy changes, the proxy closes tunnels that were opened under the
  old rules (`L7 tunnel closed before inspection because policy changed:
  policy generation is stale`). An agent mid-request does not get to finish.
- `openshell provider delete` is refused while the provider is attached to
  any sandbox ("provider is attached to sandbox(es)"). Detach first, or use
  `provider update` to replace the credential. Revocation is therefore an
  explicit, auditable step.
- After detach, the sandbox has no allowed host left for that provider, so
  the failure mode is a connect-time denial, not an upstream 401.
- `sandbox stop` preserves the workspace (docs: filesystem persistence
  follows the compute driver). It is the right first move for forensics.

### Timed trials (added after the first run)

The "0 s" in the first run's level-2 output was measured from the moment the
command returned, which hides the wait itself. Three timed trials on a second
machine (WSL2, target OpenRouter), with an agent inside the sandbox making one
request per second — `demo/evidence/rerun-linux-2026-09-30/timing-trials.txt`:

| Switch | Trial 1 | Trial 2 | Trial 3 |
|---|---|---|---|
| `detach --wait`: time for the command to return | 1.9 s | 6.5 s | 6.4 s |
| `detach --wait`: running agent refused, after return | 0.8 s | 0.0 s | 0.3 s |
| `detach --wait`: fresh exec after return | refused | refused | refused |
| `policy set --global`: running agent refused, after return | 6.7 s | 9.1 s | 7.0 s |

So `--wait` really does wait for the supervisor to install the change (the
change lands on the same settings poll as a lockdown), and once it returns no
process in the sandbox, running or new, gets through. The `Persisted:`
timestamp in the detach receipt is when the gateway stored the change, not
when the command returned; do not measure from it.

## 3. What the agent actually sees

```
OCI_GENAI_API_KEY   = open… (60 chars)            placeholder, swapped by the proxy
SSL_CERT_FILE       = /run/openshell-supervisor-ca/material/ca-bundle.crt
CURL_CA_BUNDLE, REQUESTS_CA_BUNDLE = same bundle
NODE_EXTRA_CA_CERTS, DENO_CERT     = /run/openshell-supervisor-ca/material/ca.crt
```

Python's `urllib` needs no configuration: the supervisor's CA is injected
through the standard environment variables, TLS is terminated by the proxy
(ephemeral CA per sandbox), and the placeholder is replaced only for the
allowed host and paths. Provider credential values cannot contain CR, LF,
or NUL, which is why the OCI private key format for the signing work is a
single base64 line.

## 4. Denials, as the agent and the operator see them

| Attempt | Agent side | Supervisor OCSF event |
|---|---|---|
| unlisted host | `[Errno 13] Permission denied` at connect | `NET:REFUSE DENIED example.com [reason:policy_dns_ineligible]` then `NET:OPEN [MED] DENIED python3.12 -> example.com:443 [reason:transparent_tcp_policy_denied]` |
| disallowed method on allowed host | `HTTP 403 {"binary":"/usr/local/bin/python3.12","detail":"PUT /openai/v1/models not permitted by policy","error":"policy_denied"}` | `HTTP:PUT [MED] DENIED ... [reason:L7_REQUEST deny PUT]` |
| allowed request | `HTTP 200` | `NET:OPEN [INFO] ALLOWED ... [policy:_provider_oci_genai_demo engine:opa]` and `HTTP:POST [INFO] ALLOWED` |
| request during lockdown | `Permission denied` at connect | `NET:OPEN [MED] DENIED ... [reason:transparent_tcp_policy_denied]` |
| request in flight during a reload | connection closed without response | `NET:OPEN [MED] DENIED ... [reason:L7 tunnel closed before inspection because policy changed]` |

The 403 body is written for an agent to read in its own transcript. The
connect-time denial carries no explanation to the agent; the reason lives
only in the supervisor log.

## 5. Where the evidence lives

- Docker driver: the supervisor container is
  `openshell-default--<sandbox>-<uuid>-supervisor`; its stdout carries the
  OCSF shorthand (`docker logs`). The workload container has only lifecycle
  events. Logs do not survive a stop/start cycle, so capture before stopping.
- The docs describe `/var/log/openshell*.log` inside the sandbox and an
  `ocsf_json_enabled` setting for JSONL export; in this build the workload's
  view of `/var/log` had no such files. Use the supervisor stdout or the
  gateway's `[openshell.gateway.ocsf_log]` collector.
- `openshell sandbox logs` does not exist in 0.1.2.

## 6. Gotchas that cost time

1. `openshell sandbox exec` reads piped stdin to EOF before sending the exec
   request when stdin is not a terminal. Under a harness whose stdin is an
   open pipe, it hangs forever without contacting the gateway. Always
   `</dev/null` for non-interactive execs. (See `upstream/findings.md`.)
2. Creating a second sandbox with the same provider made the first sandbox's
   supervisor reload (`provider_env_changed:true`) and drop an in-flight
   request. Retry once on a closed connection. (Also in findings.)
3. `openshell provider create --credential` takes the environment variable
   name (`OCI_GENAI_API_KEY=...`), not the profile's credential name.
4. A profile's `binaries` must name the interpreter in your image. The
   upstream `oci-genai` profile lists curl; the demo copies it with
   `/usr/local/bin/python3.12`.
5. The installed 0.1.2 CLI parses profiles client-side, so profiles using
   unreleased features fail `provider profile lint` even against a newer
   gateway.
6. Docker Hub pulls fail behind some corporate proxies; `ghcr.io`, `quay.io`,
   and `gcr.io` work. The default sandbox image has no curl or Python.
7. On Rancher Desktop the gateway needs `DOCKER_HOST` pointing at
   `~/.rd/docker.sock`, a `gateway.toml` with `[openshell] version = 2`,
   and `grpc_endpoint = "https://host.docker.internal:17670"` so supervisors
   inside the VM can call back.
8. Two attached OCI profiles cannot both expose `OCI_KEY_ID` in one sandbox:
   one signing profile per sandbox, or an endpointless profile bound through
   `credential_binding`.

## 7. OCI transports, and what each lets an agent do

| Transport | Credential in gateway | What the agent can reach | Sandbox holds | Status |
|---|---|---|---|---|
| Bearer API key (`oci-genai`) | Generative AI API key | OpenAI-compatible endpoint: chat, responses, embeddings, vision, tools | placeholder | upstream, merged |
| Proxy-side signing (`credential_signing: oci`) | API key triple or `ST$` session token + private key | any OCI API host you list: Object Storage, native Generative AI, more | placeholders | PR open |
| Gateway-minted principals | none long-lived; instance, resource, or OKE workload identity | same as signing | placeholders | PR open, draft |

The kill switch ladder is identical across the three. Only the answer to
"what secret would leak if the sandbox were breached" changes: a scoped API
key, a session token with a bounded lifetime, or nothing.
