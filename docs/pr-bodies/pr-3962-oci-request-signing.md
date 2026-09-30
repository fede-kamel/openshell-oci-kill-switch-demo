## Summary
Add proxy-side Oracle Cloud Infrastructure request signing as `credential_signing: oci`, a sibling of the SigV4 modes. When an endpoint sets it, the sandbox proxy strips the client's signing headers, resolves `OCI_KEY_ID` and `OCI_PRIVATE_KEY` from the endpoint-bound provider, and signs the request with OCI's RSA-SHA256 HTTP `Signature` scheme before forwarding. The sandbox never holds the key, and one signing path serves every OCI principal type because `OCI_KEY_ID` is either an API-key triple or an `ST$` security token.

## Related Issue
Closes #3960. Phase 2 of #3879; the bearer-only `oci-genai` profile landed in #3904. Mirrors the SigV4 precedent (#1631, #1638).

## Changes
- `crates/openshell-supervisor-network/src/oci_signature.rs` (new): header stripping, request parsing, RFC 7231 date, body hashing, the SDK-ordered signing string (`date (request-target) host`, plus `content-length content-type x-content-sha256` for POST/PUT/PATCH), RSA PKCS#1 v1.5 SHA-256 via `aws-lc-rs`, and `Authorization` assembly in the OCI SDK's parameter order. Accepts unencrypted PKCS#1 and PKCS#8 keys as single-line base64 of the PEM (recommended), base64 DER, or `\n`-escaped PEM, since provider credential values cannot contain newlines. Rejects passphrase-protected keys with a clear message. `Debug` never prints the key id.
- `crates/openshell-supervisor-network/src/l7/mod.rs`: `CredentialSigning::Oci`, `is_oci()`, `signs_requests()`, parser arm for `oci`; `signing_service` stays SigV4-only.
- `crates/openshell-supervisor-network/src/l7/rest.rs`: strips OCI headers before the fail-closed placeholder scan; new signing branch that buffers and hashes POST/PUT/PATCH bodies under the same 10 MiB ceiling as SigV4, rejects chunked bodies for those methods, streams other methods' bodies through, honours `Expect: 100-continue`, re-checks the policy generation after buffering, and emits an OCSF traffic event without the key id.
- `crates/openshell-policy/src/lib.rs`: accepts `oci`; `MissingSigningService` applies to the `sigv4` modes only.
- `crates/openshell-server/src/grpc/policy.rs`: the signing credential-source check picks required keys by scheme (`OCI_KEY_ID`/`OCI_PRIVATE_KEY` for `oci`) and names the vendor in its `FAILED_PRECONDITION` message.
- `providers/oci.yaml`, `providers/oci-object-storage.yaml`, `providers/oci-genai-native.yaml`: example profiles following the `aws.yaml` / `aws-s3.yaml` shape, with setup notes inlined in the headers per #3906.
- Docs: `credential_signing` field table, signing paragraphs in the profiles page, capability row in the providers overview, and the policy-generation skill.
- `Cargo.toml`/`Cargo.lock`: `aws-lc-rs` becomes a direct dependency of the supervisor network crate (already in the graph via rustls; `ring` stays banned).

## Testing
- [x] Unit tests (`oci_signature`): date formatting, method classification, header stripping (including non-UTF-8 fail-closed), SDK-ordered signing string for POST and GET, default `content-type`, buffered-body requirement, host header signed as sent, encrypted/garbage key rejection, every single-line key form yields the same deterministic signature, `Debug` redaction. Keys are generated per run; no key material is committed.
- [x] Proxy-level tests (`l7::rest`): GET replaces the client's placeholder signature and verifies cryptographically against the public key; POST buffers the body, consumes `Expect`, hashes into `x-content-sha256`, and verifies; chunked PUT is rejected; missing credentials fail closed.
- [x] Policy tests: `oci` accepted without `signing_service`; unknown values still rejected. Server tests: an endpointless OCI profile bound via `credential_binding` satisfies an `oci` endpoint; an AWS profile does not and the error names `OCI_KEY_ID and OCI_PRIVATE_KEY`. Provider listing and example-catalog validation cover the three new profiles.
- [x] Live interop (`tests/oci_signature_live.rs`, `#[ignore]`, `OCI_TEST_*` env): a proxy-shaped signed `GET /n/` on Object Storage, a signed text `POST /20231130/actions/chat`, and a signed multimodal chat carrying a base64 PNG in the hashed body (Llama 4 Maverick identified the image) all returned `200` from real OCI endpoints in `us-chicago-1`, once with an API-key principal (`keyId` = tenancy/user/fingerprint) and once with a security-token principal from `oci session authenticate` (`keyId` = `ST$<token>` plus the session key), so both `keyId` forms are covered.
- [x] `cargo fmt --all --check`; `cargo clippy --all-targets -D warnings` on the policy, supervisor-network, and server crates; license headers; markdownlint; `fern check`; `openshell provider profile lint` on the three profiles against a 0.1.2 gateway.
- [x] Full end-to-end on a local Docker gateway built from this branch, with a supervisor image cross-compiled from this branch (`cargo zigbuild`, linux/arm64) and the rolling `sandbox:dev` runtime. Sandboxes from `quay.io/curl/curl` saw only placeholders in `OCI_KEY_ID` and `OCI_PRIVATE_KEY` and, through the proxy against real OCI in `us-chicago-1`:
  - `oci-genai-native` profile: native `POST /20231130/actions/chat` returned `200` with the requested text; `PUT` on that path and the `/openai/v1` path were denied `403 policy_denied`; an unlisted host was refused at connect.
  - `oci-object-storage` profile: `GET /n/` `200`, `POST` create bucket `200`, `PUT` object `200`, `GET` object `200` with the uploaded body; `DELETE` denied `403` by the `read-write` preset as documented; chunked `PUT` rejected.
  - endpointless `oci` profile bound from a sandbox policy via `credential_binding` to both hosts: bucket create, object `PUT`/`GET`/`HEAD`, object `DELETE` `204`, bucket `DELETE` `204`, bucket then `404 BucketNotFound`, plus native chat `200` from the same sandbox.
  - Negative control: the stock rolling supervisor image, which lacks this change, never brought a sandbox with an `oci` endpoint to Ready.
- [ ] E2E tests added to the repository: not in this PR; the proxy-level tests exercise the relay path with an in-process upstream, and the live tests above are reproducible with `OCI_TEST_*`.

## Checklist
- [x] Follows [Conventional Commits](https://www.conventionalcommits.org/)
- [x] Commits are signed off (DCO)
- [ ] Architecture docs updated (if applicable): `architecture/` was removed upstream in #3799; the field-level docs above are updated instead.
