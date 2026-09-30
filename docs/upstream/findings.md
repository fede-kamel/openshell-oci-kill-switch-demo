# Findings for the OpenShell maintainers

Issues observed on OpenShell 0.1.2 (Homebrew gateway, Docker driver on
Rancher Desktop, macOS 26) on 2026-09-30, probed with dedicated sandboxes,
and filed upstream the same day:

| Finding | Upstream issue |
|---|---|
| `sandbox exec` reads piped stdin to EOF before starting the command | [NVIDIA/OpenShell#3993](https://github.com/NVIDIA/OpenShell/issues/3993), fix in [PR #4006](https://github.com/NVIDIA/OpenShell/pull/4006) |
| First settings poll after start always reports `provider_env_changed:true` and can drop an in-flight request | [NVIDIA/OpenShell#3994](https://github.com/NVIDIA/OpenShell/issues/3994) |

## 1. `sandbox exec` blocks on stdin EOF before starting the command

**Severity:** medium (usability; hangs automation indefinitely). Filed as #3993.

**Root cause (source).** `crates/openshell-cli/src/run.rs`, `sandbox_exec_grpc`:
when stdin is not a terminal, a `spawn_blocking` task does `read_to_end` on
stdin (capped at 4 MiB) and only then is the `ExecSandbox` request built.
The comment explains the intent: keep a unary request for small pipes so
older gateways, whose interactive RPC closes the SSH channel at stdin EOF,
keep working. `--no-tty` does not bypass it.

**Probe results (2026-09-30, sandbox `probe-a`).**

```
never-closing pipe as stdin            -> hang (killed by timeout)
same with --no-tty                     -> hang
stdin closed (</dev/null)              -> 0.1 s
echo hi | exec -- cat                  -> prints hi, 0.1 s
EOF delivered after 5 s                -> command starts 5 s later (waits for EOF)
gateway ExecSandbox RPCs               -> only for the three non-hanging cases
```

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

## 2. First settings poll after start always reports `provider_env_changed:true` and can drop an in-flight request

**Severity:** low. Filed as #3994.

**What it looked like at first.** Sandbox A (`oci-agent`) was mid-request
when sandbox B (`oci-agent-2`) was created with the same provider, and A's
supervisor logged a provider environment change and a stale-generation
denial. The probe showed the correlation with B was a coincidence.

**What it is.** Every supervisor reports `provider_env_changed:true` on its
first settings poll, exactly 10 s after start, with the config revision
unchanged, and even with no provider attached (4 of 4 sandboxes, one without
providers). The reload advances the policy generation and closes tunnels
opened before it. In the real run, A's first-poll reload landed at
start + 10.9 s while a request was in flight.

**Likely cause (source).** `crates/openshell-supervisor/src/lib.rs`:
`current_provider_env_revision` is seeded from the local credential
snapshot's revision, which never equals the server-computed
`provider_env_revision`, so the first comparison in the poll loop is always
unequal (or `provider_readiness.needs_environment` is true for the initial
identity).

**Original observation.** A's supervisor logged:

```
CONFIG:DETECTED Settings poll: config change detected [old_revision:X new_revision:X policy_changed:false provider_env_changed:true]
CONFIG:CONFIGURED OPA runtime binary identity mode configured
NET:OPEN [MED] DENIED inference.generativeai...:443 [reason:L7 tunnel closed before inspection because policy changed: policy generation is stale]
```

A's request failed with a closed connection although A's policy hash had
not changed. Closing tunnels on policy change is documented and correct;
the defect is that nothing had changed.

**Reproduction.** Create any sandbox, read its supervisor log, observe the
detection at start + 10 s. To see the drop, run a request loop from the
moment the sandbox is Ready and watch for the stale-generation denial.

**Suggested fix.** Seed the initial revision from the server's value, or
treat the first observation as the baseline; add a test for the first poll.
Until then, clients should retry once on a closed connection.

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
