"""The official OpenAI Python SDK, unchanged, inside an OpenShell sandbox.

The only configuration is where to send requests and which variable holds the
key. Inside the sandbox that variable holds a placeholder; the proxy swaps in
the real key on the way out, for this host only.
"""
import os

from openai import OpenAI

client = OpenAI(
    base_url=os.environ["AGENT_BASE_URL"],               # OCI Generative AI or OpenRouter
    api_key=os.environ[os.environ["AGENT_KEY_ENV"]],     # the placeholder, not the key
)
reply = client.chat.completions.create(
    model=os.environ["AGENT_MODEL"],
    messages=[{"role": "user", "content": "In one short sentence: what does a sandbox protect?"}],
    max_tokens=60,
)
print("openai sdk ->", reply.choices[0].message.content.strip())
