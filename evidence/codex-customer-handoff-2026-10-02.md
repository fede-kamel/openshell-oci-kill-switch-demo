# Codex as a first-time customer with no provider: the handoff it produced (2026-10-02)

Headless `codex exec` in a fresh clone, operator context: TARGET=oci, provider name oci-genai-cust (does not exist), compartment OCID withheld, stop at the handoff. The OCI profile name is redacted below.

Stopped at the handoff as requested. I did not run the demo or examples.

**Preflight**

| Requirement | Result |
|---|---|
| OS | PASS: `Darwin arm64` |
| Docker | PASS: `29.5.2` |
| Bash | PASS: `5.3.3` |
| GNU timeout | PASS: `/opt/homebrew/bin/timeout` |
| git, curl | PASS |
| OpenShell CLI | PASS: `openshell 0.1.2` |
| Gateway | PASS: `Status: Connected` |
| Global policy | PASS: current global policy is `Status: Superseded` |
| Sandboxes | PASS: no sandboxes found |
| OCI CLI | PASS: `3.84.0` |
| OCI profile | PASS: `<profile>` is the only profile that passed `oci iam region list` |
| Provider profile | PASS: `oci-genai-python` already exists |
| Provider | STOP: `oci-genai-cust` does not exist yet |

What I still need from you: your OCI compartment OCID. Do not paste it here unless you want a later run to continue non-interactively; you can put it directly into the command below in your own terminal.

Run this in your own terminal. Do not paste command output back into chat. Reply only `done`.

```shell
export OCI_PROFILE='<profile>'
export OCI_REGION='us-chicago-1'
export PROVIDER_NAME='oci-genai-cust'
export COMPARTMENT_OCID='<your compartment OCID>'

oci iam policy list --compartment-id "$COMPARTMENT_OCID" --profile "$OCI_PROFILE" --all \
  --query 'data[].statements[]' --raw-output | grep -i 'generative-ai-family' | grep -i 'generativeaiapikey'
```

If that prints nothing, run this policy create command:

```shell
oci iam policy create --compartment-id "$COMPARTMENT_OCID" --profile "$OCI_PROFILE" \
  --name openshell-genai-apikey --description 'OpenShell demo: Generative AI API keys may use Generative AI' \
  --statements "[\"allow any-user to use generative-ai-family in compartment id $COMPARTMENT_OCID where ALL {request.principal.type='generativeaiapikey'}\"]"
```

Then verify the region returns models:

```shell
oci generative-ai model-collection list-models --compartment-id "$COMPARTMENT_OCID" \
  --region "$OCI_REGION" --profile "$OCI_PROFILE" --all
```

Then create the key and store it in OpenShell under `oci-genai-cust`:

```shell
oci generative-ai api-key create --compartment-id "$COMPARTMENT_OCID" --region "$OCI_REGION" --profile "$OCI_PROFILE" \
  --display-name openshell-demo --key-details '[{"keyName":"primary","timeExpiry":"2027-01-01T00:00:00Z"}]'
printf 'Paste OCI_GENAI_API_KEY from the command output above: ' >&2
IFS= read -rs OCI_GENAI_API_KEY && export OCI_GENAI_API_KEY
printf '\n' >&2
openshell provider create --name "$PROVIDER_NAME" --type oci-genai-python --credential OCI_GENAI_API_KEY
unset OCI_GENAI_API_KEY
unset COMPARTMENT_OCID OCI_PROFILE OCI_REGION PROVIDER_NAME
```

After this, reply exactly `done` and do not paste output.