# Codex operating the gateway: create, task, stop, start, delete (2026-10-02)

1. Create sandbox  
Command: `openshell sandbox create --name codex-task --from ghcr.io/astral-sh/uv:python3.12-bookworm-slim --provider oci-genai-demo --detach -- sleep infinity`  
Result: `Created sandbox: codex-task`; image already present; sandbox started.

2. Wait for exec readiness  
Command: `deadline=$((SECONDS+180)); until openshell sandbox exec --name codex-task -- true </dev/null; do if [ "$SECONDS" -ge "$deadline" ]; then echo "timeout waiting for codex-task"; exit 1; fi; sleep 3; done; echo "exec-ready"`  
Result: `exec-ready`

3. Upload agent  
Command: `openshell sandbox upload codex-task demo/agent/agent.py /tmp/demo/agent.py`  
Result: `✓ Upload complete`  
The CLI created `/tmp/demo/agent.py/agent.py`, so I corrected the in-sandbox path:  
Command: `openshell sandbox exec --name codex-task -- sh -c 'mv /tmp/demo/agent.py/agent.py /tmp/demo/agent.py.tmp && rmdir /tmp/demo/agent.py && mv /tmp/demo/agent.py.tmp /tmp/demo/agent.py' </dev/null`  
Result: exit 0.

4. Give the sandbox a task  
Command: `openshell sandbox exec --name codex-task -- /usr/local/bin/python3.12 /tmp/demo/agent.py ask "In one sentence, what does an OpenShell sandbox protect?" </dev/null`  
Result: `HTTP 200: An OpenShell sandbox protects a system by isolating and restricting the execution of untrusted code or scripts, preventing them from accessing or modifying sensitive data or system resources.`

5. Stop the container, list, retry task  
Command: `openshell sandbox stop codex-task`  
Result: `✓ Stopped sandbox codex-task`  
Command: `openshell sandbox list`  
Result: `codex-task ... Stopped`  
Command: `openshell sandbox exec --name codex-task -- /usr/local/bin/python3.12 /tmp/demo/agent.py ask "In one sentence, what does an OpenShell sandbox protect?" </dev/null`  
Result: `sandbox 'codex-task' is not ready (phase: Stopped); wait for it to reach Ready state`

6. Start it again, wait, rerun task  
Command: `openshell sandbox start codex-task`  
Result: `✓ Started sandbox codex-task`  
Command: `deadline=$((SECONDS+180)); until openshell sandbox exec --name codex-task -- true </dev/null; do if [ "$SECONDS" -ge "$deadline" ]; then echo "timeout waiting for codex-task"; exit 1; fi; sleep 3; done; echo "exec-ready"`  
Result: `exec-ready`  
Command: `openshell sandbox exec --name codex-task -- /usr/local/bin/python3.12 /tmp/demo/agent.py ask "In one sentence, what does an OpenShell sandbox protect?" </dev/null`  
Result: `HTTP 200: An OpenShell sandbox protects a system from potentially malicious or unstable code by isolating it in a controlled environment, preventing it from accessing or modifying sensitive data or system resources.`

7. Delete sandbox and list  
Command: `openshell sandbox delete codex-task`  
Result: `✓ Sandbox codex-task deletion accepted; cleanup is pending`  
Command: `openshell sandbox list`  
Result: `No sandboxes found.`

The sandbox could be stopped, restarted, and deleted from here.