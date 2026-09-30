# OCI integration in OpenShell: status, design, verification

State as of 2026-09-30. All work by Federico Kamelhar from the fork
`fede-kamel/OpenShell`, following the precedents set by the AWS SigV4 and STS
contributions (#1631/#1638 and #1576/#1782).

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

## Phase 2: proxy-side request signing (PR open)

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
- Verified: unit and proxy-level tests with per-run generated keys; live
  signer tests against real OCI endpoints with both an API-key principal and
  a session-token principal; a full end-to-end run through a gateway and a
  supervisor image built from the branch, including Object Storage bucket
  and object lifecycle, native chat, and multimodal chat.
- Waiting on: a maintainer `/ok to test` and review.

## Phase 3: gateway-minted principals (draft PR open)

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

1. Watch #3962 for review; rebase both branches if the profile-schema
   refactors (#3442, #2330) land first.
2. When #3962 merges, rebase #3975 onto main and mark it ready.
3. Optional: a langchain-oci mode that uses the bearer API key, so
   `ChatOCIOpenAI` can run inside an OpenShell sandbox without a signer.
4. Optional: publish `oracle-openshell-guide.mdx` on the Oracle side.
