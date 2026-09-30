"""LangChain with a tool, unchanged, inside an OpenShell sandbox.

ChatOpenAI talks to any OpenAI-compatible endpoint. The model decides to call
the tool; the tool runs in the sandbox; nothing here knows about OpenShell.
"""
import os

from langchain_core.tools import tool
from langchain_openai import ChatOpenAI


@tool
def add(a: int, b: int) -> int:
    """Add two integers."""
    return a + b


llm = ChatOpenAI(
    base_url=os.environ["AGENT_BASE_URL"],
    api_key=os.environ[os.environ["AGENT_KEY_ENV"]],     # the placeholder, not the key
    model=os.environ["AGENT_MODEL"],
    max_tokens=120,
)
msg = llm.bind_tools([add]).invoke("Use the add tool to compute 1234 + 4321.")
calls = msg.tool_calls
print("langchain tool call ->", [(c["name"], c["args"]) for c in calls])
if calls:
    print("langchain tool result ->", add.invoke(calls[0]["args"]))
