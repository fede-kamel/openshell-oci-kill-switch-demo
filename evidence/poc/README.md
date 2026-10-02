# Evidence

Reports and command lists from real runs against the free tier tenancy, with
OCIDs redacted. `attempt1` (run id 20261002-0901, 2026-10-02): preflight
passed, compartment, VCN and subnet were created, then `object put` failed with
`BucketNotFound` immediately after `bucket create` (propagation in a new
compartment), and Codex found that `verify.sh`/`teardown.sh` filtered bucket
tags without `--fields tags`, which the API requires. It did not modify the
scripts (as instructed), tore down, removed the one bucket by name, and proved
the root snapshot unchanged. Both defects were fixed before the next run.

`report-20261002-0911.md` and `commands-20261002-0911.txt` (run id
20261002-0911, 2026-10-02): the complete run. Compartment reused, VCN and
subnet created, bucket and object with matching digests, `VM.Standard.E2.1.Micro`
instance RUNNING in 59 s, stopped in 9 s, started in 5 s, teardown by tag in
72 s, root snapshot identical to preflight. 11 of 11 checks. One deviation
Codex reported: its own harness refused some `oci` write commands in headless
mode and it issued the identical commands through `env`; the OCI operations,
scope, shape, tags and cost were unchanged.
