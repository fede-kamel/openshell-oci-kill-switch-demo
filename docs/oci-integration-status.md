# OCI integration in OpenShell: status, design, verification

State as of 2026-11-04 (first written 2026-09-30). All work by Federico
Kamelhar from the fork `fede-kamel/OpenShell`, following the precedents set by
the AWS SigV4 and STS contributions (#1631/#1638 and #1576/#1782).

## Where things stand (2026-11-04)

- Phase 1 is merged and shipped in OpenShell v0.1.3.
- Phases 2 and 3 wait on community acceptance. On 2026-10-01 a maintainer
  moved #3962 and #3975 to draft and asked for the two provider-specific
  additions to be presented in CNCF Slack `#openshell-dev` or at the weekly
  community call (Tuesdays 9:00 Pacific). The stale bot closed the tracking
  issues #3960 and #3961 on 2026-11-01; they are being reopened and the
  written proposal is going to the community.
- On 2026-11-04 #3962 was rebased onto current main (v0.1.7) and ported to
  the `openshell-crypto` facade that landed in October: no direct `aws-lc-rs`
  or `sha2` use, PKCS#1 keys wrapped into PKCS#8 before import, and a fixture
  test key instead of per-run generation, because the facade has no RSA key
  generation on every backend. #3975 follows once it is rebased on the new
  #3962.
- Also open: #3924 (Docker Desktop and WSL 2 supervisor endpoint), waiting on
  `/ok to test`; its accepted issue #3880 was marked stale on 2026-10-24.
- Six PRs merged in total: #3904, #4006, #3923 (v0.1.3), #3910 (v0.1.4),
  #3907 and #4063 (v0.1.6).

## Phase 1: bearer profile (merged)

- PR [#3904](https://github.com/NVIDIA/OpenShell/pull/3904), merged 2026-09-29.
- Adds `providers/oci-genai.yaml`: OCI Generative AI through the
  OpenAI-compatible endpoint, API key sent as a bearer token, `POST`/`GET`/
  `DELETE` under `/openai/v1/`, `enforce` mode, `curl` binaries.
- Import URL: `https://raw.githubusercontent.com/NVIDIA/OpenShell/main/providers/oci-genai.yaml`.
- Scoped down at maintainer request (issue #3906): example profiles must not
  need code or docs changes, so the telemetry bucket, provider table row, and
  docs page were dropped. The full docs page lives in this repository as
  `oracle-openshell-guide.mdx`.
- Verified live: chat completions, responses, streaming, tool calls, vision
  (Llama 4 Maverick, Gemini 2.5 Flash), embeddings, 263 KB bodies. The
  sandbox only ever saw a placeholder.

## Phase 2: proxy-side request signing (draft PR, pending community acceptance)

- Issue [#3960](https://github.com/NVIDIA/OpenShell/issues/3960), PR
  [#3962](https://github.com/NVIDIA/OpenShell/pull/3962).
- `credential_signing: oci` on an endpoint: the proxy strips the client's
  signing headers, resolves `OCI_KEY_ID` and `OCI_PRIVATE_KEY` from the
  endpoint-bound provider, and signs with OCI's RSA-SHA256 HTTP Signature
  scheme (`date (request-target) host`, plus `content-length content-type
  x-content-sha256` for `POST`/`PUT`/`PATCH`).
- `OCI_KEY_ID` is either `tenancy/user/fingerprint` (API key) or `ST$<token>`
  (security token). One signing path serves every OCI principal type.
- `OCI_PRIVATE_KEY` is a single base64 line of the PEM, because provider
  values cannot contain newlines. Base64 DER and `\n`-escaped PEM are also
  accepted; passphrase-protected keys are rejected with a clear message.
- Profiles: `oci.yaml` (endpointless, pairs with `credential_binding`),
  `oci-object-storage.yaml`, `oci-genai-native.yaml`.
- Verified: unit and proxy-level tests (a fixture test key since the
  2026-11-04 facade port, per-run generated keys before); live
  signer tests against real OCI endpoints with both an API-key principal and
  a session-token principal; a full end-to-end run through a gateway and a
  supervisor image built from the branch, including Object Storage bucket
  and object lifecycle, native chat, and multimodal chat.
- Waiting on: community acceptance (`state:accepted` on #3960), then a
  maintainer `/ok to test` and review.
- Follow-up agreed with the triage review: an `oci:no_body` mode mirroring
  `sigv4:no_body`, because the OCI SDKs omit the body headers for Object
  Storage `PutObject` and `UploadPart`.

## Phase 3: gateway-minted principals (draft PR, pending community acceptance)

- Issue [#3961](https://github.com/NVIDIA/OpenShell/issues/3961), PR
  [#3975](https://github.com/NVIDIA/OpenShell/pull/3975), stacked on #3962.
- Three refresh strategies: `oci_instance_principal` (federate the host's
  instance certificate at `auth.<region>.<realm>/v1/x509`),
  `oci_resource_principal` (republish the platform-rotated token and key),
  `oci_oke_workload_identity` (exchange the service-account token at the OKE
  proxymux on port 12250).
- Each mints `OCI_KEY_ID = ST$<token>` and co-mints `OCI_PRIVATE_KEY` as an
  ephemeral RSA session key through `additional_outputs`; expiry is the JWT
  `exp` capped by `max_lifetime_seconds`.
- Test-only loopback overrides for the identity endpoints exist under
  `cfg(test)`, and the configure API rejects those material keys, mirroring
  the STS precedent.
- Verified: wiremock tests that pin the OCI SDK wire shapes; full suites of
  six crates; Go SDK; profile lint against a branch-built gateway.
- Not verified: a live mint on OCI Compute, OKE, or Functions (the
  development gateway runs on a laptop). The token-plus-key transport it
  produces was proven live in phase 2.
- From the maintainers' triage review: endpoint material is already rejected
  by the configure API (CWE-918); the resource-principal file paths move from
  provider material to gateway configuration and a gateway-level opt-in for
  principal minting is added before the PR leaves draft; the
  resource-principal session key comes from the platform. Already done on
  2026-11-04: ephemeral RSA keys and all signing go through the crypto facade
  (RSA generation added to the AWS-LC backend).

## Design decisions worth remembering

- Follow the existing precedent exactly (SigV4 for signing, STS for
  refresh). Reviewers compare against it.
- Shared signing primitives live in `openshell-core` so the gateway and the
  sandbox proxy use one signer; the supervisor module is HTTP framing only.
- Adding proto enum values changes the pinned public and durable schema
  fingerprints in `storage_proto.rs`; re-pin them with a review comment.
- Example profiles carry their setup notes in header comments; user-facing
  docs for a vendor belong outside the repository or inline in the YAML.

## Process notes

- First-time contributors must be vouched (`/vouch` on a Vouch Request
  discussion, human-written). DCO sign-off on every commit, plus the DCO
  bot's attestation comment on the PR.
- CI on external PRs waits for a maintainer `/ok to test`.
- No AI attribution in commits; Conventional Commits; features must link an
  issue.

## Next steps

1. Present #3960 and #3961 in `#openshell-dev` and at the Tuesday community
   call; post the written proposal as a Design Discussion; ask for
   `state:accepted` on both and whether an RFC is wanted.
2. After acceptance: `/ok to test` and review on #3962; then rebase #3975
   onto the merged signing work and mark it ready.
3. Follow-up PR: `oci:no_body` for large Object Storage uploads.
4. Optional: a langchain-oci mode that uses the bearer API key, so
   `ChatOCIOpenAI` can run inside an OpenShell sandbox without a signer.
5. Optional: publish `oracle-openshell-guide.mdx` on the Oracle side.
