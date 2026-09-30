# The demo's base image plus two common agent libraries. Same interpreter
# (/usr/local/bin/python3.12), so the demo's provider profiles apply unchanged.
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
RUN pip install --no-cache-dir openai==3.22.1 langchain-openai==1.6.7
