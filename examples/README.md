# Your own agent in the sandbox

Nothing in an agent has to know about OpenShell. These examples run two common
libraries, unchanged, inside a sandbox with the demo's provider attached:

| File | What it shows |
|---|---|
| [`openai_sdk.py`](openai_sdk.py) | the official OpenAI Python SDK: one chat completion |
| [`langchain_agent.py`](langchain_agent.py) | LangChain's `ChatOpenAI` with a tool: the model calls `add`, the tool runs in the sandbox |
| [`Dockerfile`](Dockerfile) | the demo's base image plus `openai` and `langchain-openai`, same interpreter, so the demo's profiles apply |
| [`run-examples.sh`](run-examples.sh) | builds the image, creates a sandbox, runs both, and always deletes the sandbox |

Set up a provider first (step 3 of the top-level README), then from the
repository root:

```shell
TARGET=openrouter ./examples/run-examples.sh
TARGET=oci ./examples/run-examples.sh
```

The only configuration either library gets is a `base_url` and an API key
variable. Inside the sandbox that variable holds a placeholder, for example
`openshell:resolve:env:v6892894447447880484_OPENROUTER_API_KEY`; the proxy
swaps in the real key on the way out, for the provider's host only. From a run
on 2026-09-30:

```text
== OpenAI Python SDK
openai sdk -> A sandbox protects a system or environment from untested or potentially malicious code or activities.
PASS  openai sdk
== LangChain with a tool
langchain tool call -> [('add', {'a': 1234, 'b': 4321})]
langchain tool result -> 5555
PASS  langchain tool call
```

Both examples pass against OCI Generative AI and OpenRouter.

To use your own image, keep the provider profile's `binaries` in step with it:
the rules bind to the executable, and these profiles name
`/usr/local/bin/python3.12`.
