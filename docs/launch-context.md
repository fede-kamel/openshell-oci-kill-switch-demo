# Launch context: the Open Agent Safety Platform

What was announced on 2026-09-28, and how this repository relates to it.
Facts below come from the sources listed at the end; verify before quoting.

## The two layers

- **OpenShell** (software): the open-source Rust runtime in
  [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell), Apache-2.0,
  version 0.1.2 went GA on launch day. Per-agent sandboxes with Landlock and
  seccomp, deny-by-default egress, an L7 proxy with credential injection, a
  gateway control plane, OCSF telemetry, a Z3-based policy prover. Everything
  in this repository runs on this layer.
- **Sentry** (hardware): a watchdog on BlueField-4 DPUs that observes the
  host from outside and can quarantine an agent. Not open source, not part
  of this repository, and not exercised by the demo.

Over one hundred partners were named at launch, Oracle among them. The OCI
work in this repository is what makes that partnership concrete in code.

## What the demo does and does not prove

Proves: the software kill switch, exercised through the public CLI, on a
real agent doing real work against a real cloud model, with evidence.

Does not prove: anything about the hardware layer, or about scale. The
gateway runs on a laptop with Docker.

## Sources

- https://dev.to/max_quimby/nvidia-openshell-ships-the-agent-kill-switch-4ajj
- https://agentconn.com/blog/nvidia-openshell-agent-sandbox-safety-infrastructure/
- https://gulfnews.com/technology/nvidia-builds-hardware-kill-switch-to-stop-ai-agents-that-go-rogue-1.500692624
- https://decrypt.co/379468/nvidia-kill-switch-ai-agents
- https://www.benzinga.com/markets/tech/26/09/62016478/nvidia-unveils-ai-safety-platform-to-keep-ai-agents-under-control-partners-with-anthropic
- https://www.artificialintelligence-news.com/news/nvidia-over-100-partners-launch-open-ai-agent-safety-platform/
