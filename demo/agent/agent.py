#!/usr/local/bin/python3.12
"""A small agent that does its job through an OpenAI-compatible API from
inside an OpenShell sandbox.

The process never holds the real API key. The key variable contains a
placeholder that the sandbox proxy swaps for the real credential on the way
out, and only for the allowed host and paths. Everything else is denied by
the policy, and the operator can cut access at any moment from the gateway.

Standard library only. Defaults to OCI Generative AI; point it at OpenRouter
(or any OpenAI-compatible endpoint) with three environment variables, which
demo.sh sets from TARGET=oci|openrouter:

  AGENT_BASE_URL  https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1
  AGENT_MODEL     meta.llama-3.3-70b-instruct
  AGENT_KEY_ENV   OCI_GENAI_API_KEY    (the variable the provider injects)

Commands:
  whoami            show what the process can see (placeholder, proxy env)
  ask "<prompt>"    one chat completion
  probe             one allowed request and two that the fence must block
  work [s] [max]    status loop: one short completion every s seconds, for at most max seconds
"""
import http.client
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get(
    "AGENT_BASE_URL", "https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1"
).rstrip("/")
HOST = urllib.parse.urlparse(BASE).hostname
MODEL = os.environ.get("AGENT_MODEL", "meta.llama-3.3-70b-instruct")
KEY_ENV = os.environ.get("AGENT_KEY_ENV", "OCI_GENAI_API_KEY")
KEY = os.environ.get(KEY_ENV, "")


def ssl_context() -> ssl.SSLContext:
    # The sandbox terminates TLS with its own CA and advertises it through the
    # usual variables; load it explicitly so any Python build trusts it.
    ctx = ssl.create_default_context()
    for var in ("SSL_CERT_FILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "NODE_EXTRA_CA_CERTS"):
        path = os.environ.get(var)
        if path and os.path.exists(path):
            ctx.load_verify_locations(cafile=path)
    return ctx


def request(method: str, url: str, body=None) -> tuple[int, str]:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if urllib.parse.urlparse(url).hostname == HOST:  # the credential only ever goes to its own host
        headers["Authorization"] = f"Bearer {KEY}"
    for attempt in (1, 2):
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ssl_context(), timeout=60) as resp:
                return resp.status, resp.read().decode(errors="replace")
        except urllib.error.HTTPError as err:
            return err.code, err.read().decode(errors="replace")
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, http.client.IncompleteRead) as err:
            # The proxy closes in-flight connections when the policy reloads; try once more.
            if attempt == 1:
                time.sleep(1)
                continue
            return 0, f"{type(err).__name__}: {err}"
        except Exception as err:  # connect refused by the sandbox, proxy gone, sandbox stopping
            dropped = "RemoteDisconnected" in repr(err) or isinstance(getattr(err, "reason", None), ConnectionError)
            if dropped and not isinstance(getattr(err, "reason", None), PermissionError) and attempt == 1:
                time.sleep(1)
                continue
            return 0, f"{type(err).__name__}: {err}"
    return 0, "unreachable"


def ask(prompt: str) -> tuple[int, str]:
    status, text = request(
        "POST",
        f"{BASE}/chat/completions",
        {"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": 60},
    )
    if status == 200:
        try:
            return status, json.loads(text)["choices"][0]["message"]["content"].strip()
        except (KeyError, IndexError, TypeError, json.JSONDecodeError):
            return status, text[:200]
    return status, text[:200].replace("\n", " ")


PLACEHOLDER_PREFIX = "openshell:resolve:"  # what OpenShell puts where a credential would be


def whoami() -> None:
    # A placeholder is a reference, not a secret, so it is printed in full; anything
    # else is treated as a possible real key and never printed beyond four characters.
    if KEY.startswith(PLACEHOLDER_PREFIX):
        shown, verdict = KEY, "no — an OpenShell placeholder"
    elif KEY:
        shown, verdict = f"{KEY[:4]}… ({len(KEY)} chars)", "YES — stop and check the provider"
    else:
        shown, verdict = "(unset)", "no — the variable is empty"
    print(f"{KEY_ENV + ' as seen by the agent':<40}: {shown}")
    print(f"{'looks like a real API key':<40}: {verdict}")
    for var in sorted(os.environ):
        if var.upper().endswith("_PROXY") or "CERT" in var.upper() or "CA_BUNDLE" in var.upper():
            print(f"{var:<40}: {os.environ[var]}")
    print(f"{'model':<40}: {MODEL}")
    print(f"{'allowed upstream':<40}: {HOST}")


def probe() -> None:
    checks = [
        (f"allowed : POST chat completions on {HOST}", "POST", f"{BASE}/chat/completions",
         {"model": MODEL, "messages": [{"role": "user", "content": "Say OK."}], "max_tokens": 5}),
        ("blocked : GET  an unlisted host (example.com)", "GET", "https://example.com/", None),
        (f"blocked : PUT  on {HOST} (method not in policy)", "PUT", f"{BASE}/models", {}),
    ]
    for label, method, url, body in checks:
        status, text = request(method, url, body)
        if status == 403 and "policy_denied" in text:
            verdict = "DENIED policy_denied"  # refused at the HTTP layer, with a reason
        elif status == 403 or "Permission denied" in text:
            verdict = "DENIED"
        elif status == 0:
            verdict = "DROPPED"  # connection closed, not a policy verdict
        else:
            verdict = f"HTTP {status}"
        print(f"{label:<58} -> {verdict:<20} {text[:110].replace(chr(10), ' ')}")


def work(interval: float, max_seconds: float) -> None:
    n, end = 0, time.monotonic() + max_seconds
    while time.monotonic() < end:
        n += 1
        status, text = ask(f"Status report {n}. Reply with one short upbeat line.")
        stamp = time.strftime("%H:%M:%S")
        if status == 200:
            print(f"[{stamp}] ok      #{n}: {text[:90]}", flush=True)
        else:
            print(f"[{stamp}] BLOCKED #{n}: {text[:90]}", flush=True)
        time.sleep(interval)


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "whoami"
    if cmd == "whoami":
        whoami()
    elif cmd == "ask":
        status, text = ask(" ".join(argv[2:]) or "Say hello in five words.")
        print(f"HTTP {status}: {text}")
        return 0 if status == 200 else 1
    elif cmd == "probe":
        probe()
    elif cmd == "work":
        work(float(argv[2]) if len(argv) > 2 else 5.0, float(argv[3]) if len(argv) > 3 else 300.0)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
