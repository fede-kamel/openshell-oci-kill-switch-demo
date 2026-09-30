# Findings for the OpenShell maintainers

Candidate issues observed on OpenShell 0.1.2 (Homebrew gateway, Docker
driver on Rancher Desktop, macOS 26) on 2026-09-30. Neither has been filed
yet. Each entry has the evidence collected and a proposed reproduction so it
can be filed with the repository's bug template (User Story, Problem
Statement, Impact, Acceptance Criteria, reproduction, environment).

## 1. `sandbox exec` blocks on stdin EOF before starting the command

**Severity:** medium (usability; hangs automation indefinitely).

**Observed.** With a non-terminal stdin that never reaches EOF, the CLI
blocks forever and never sends `ExecSandbox`:

- A stack sample of the hung CLI shows one thread parked in `read(2)`
  while the tokio workers idle.
- The gateway log shows `GetSandbox` for the call but no `ExecSandbox` or
  `RelayStream`.
- The supervisor log shows no `ssh relay open` for the call.
- The same command with `</dev/null` returns in 0.2 s; under `timeout 20`
  without it, the call is killed at 20 s every time.

The docs say the CLI "sends small piped input in one request" and streams
larger input; the implication that it must read to EOF before starting the
command is not stated.

**Proposed reproduction.**

```shell
# hangs (stdin is a pipe that never closes)
sleep 300 | openshell sandbox exec -n my-sandbox -- true
# returns immediately
openshell sandbox exec -n my-sandbox -- true </dev/null
```

**Suggested behavior.** Either start the command and stream stdin
concurrently (closing remote stdin at EOF, as the docs already describe for
large input), or add an explicit `--no-stdin` / `-i` model like `docker exec`
and `kubectl exec`, where stdin is only read when asked.

## 2. Attaching a provider to one sandbox reloads policy in another and closes its in-flight tunnel

**Severity:** low; needs confirmation.

**Observed once.** Sandbox A (`oci-agent`) was mid-request. Sandbox B
(`oci-agent-2`) was created with the same provider attached. A's supervisor
logged:

```
CONFIG:DETECTED Settings poll: config change detected [old_revision:X new_revision:X policy_changed:false provider_env_changed:true]
CONFIG:CONFIGURED OPA runtime binary identity mode configured
NET:OPEN [MED] DENIED inference.generativeai...:443 [reason:L7 tunnel closed before inspection because policy changed: policy generation is stale]
```

A's request failed with a closed connection although A's policy hash had
not changed. Closing tunnels on policy change is documented and correct;
the question is why B's attachment counted as a provider environment change
for A.

**Proposed reproduction.** Create sandbox A with provider P, start a slow
request from A, create sandbox B with provider P, observe A's supervisor
log for `provider_env_changed:true` and the stale-generation denial.

**Suggested outcome.** If provider handles are per gateway rather than per
sandbox, document that attachments elsewhere can bump a sandbox's
generation; otherwise scope the change detection per sandbox.

## Notes that are not bugs

- `openshell provider delete` is refused while attached. Good safety
  behavior; detach first.
- Global policy changes reach running sandboxes within one settings poll,
  as documented; one run saw ~50 s, the rest under 11 s.
- The installed CLI parses profiles client-side, so `provider profile lint`
  rejects profiles that use features the CLI does not know yet, even
  against a newer gateway. Expected for unreleased features.
- Adding protobuf enum values requires re-pinning the public and durable
  schema fingerprints in `storage_proto.rs`. Intentional gate.
