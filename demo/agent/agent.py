#!/usr/local/bin/python3.12
"""Demo worker that does its job through OCI Generative AI from inside an
OpenShell sandbox.

The process never holds the real API key. OCI_GENAI_API_KEY contains a
placeholder that the sandbox proxy swaps for the real credential on the way
out, and only for the allowed host and paths. Everything else is denied by
the policy, and the operator can cut access at any moment from the gateway.

Commands:
  whoami            show what the process can see (placeholder, proxy env)
  ask "<prompt>"    one chat completion through OCI Generative AI
  probe             one allowed request and two that the fence must block
  work [seconds]    status loop: one short completion per interval, forever
"""
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

REGION = os.environ.get("OCI_GENAI_REGION", "us-chicago-1")
HOST = f"inference.generativeai.{REGION}.oci.oraclecloud.com"
BASE = f"https://{HOST}/openai/v1"
MODEL = os.environ.get("OCI_GENAI_MODEL", "meta.llama-3.3-70b-instruct")
KEY = os.environ.get("OCI_GENAI_API_KEY", "")


def ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    for var in ("SSL_CERT_FILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "NODE_EXTRA_CA_CERTS"):
        path = os.environ.get(var)
        if path and os.path.exists(path):
            ctx.load_verify_locations(cafile=path)
    return ctx


def request(method: str, url: str, body=None) -> tuple[int, str]:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"}
    for attempt in (1, 2):
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ssl_context(), timeout=60) as resp:
                return resp.status, resp.read().decode(errors="replace")
        except urllib.error.HTTPError as err:
            return err.code, err.read().decode(errors="replace")
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError) as err:
            # The proxy closes in-flight connections when the policy reloads; try once more.
            if attempt == 1:
                time.sleep(1)
                continue
            return 0, f"{type(err).__name__}: {err}"
        except Exception as err:  # connect refused by the sandbox, proxy gone, sandbox stopping
            name = type(err).__name__
            if "RemoteDisconnected" in repr(err) and attempt == 1:
                time.sleep(1)
                continue
            return 0, f"{name}: {err}"
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
        except (KeyError, IndexError, json.JSONDecodeError):
            return status, text[:200]
    return status, text[:200].replace("\n", " ")


def whoami() -> None:
    masked = f"{KEY[:4]}… ({len(KEY)} chars)" if KEY else "(unset)"
    print(f"OCI_GENAI_API_KEY as seen by the agent : {masked}")
    print(f"looks like a real OCI GenAI key         : {'no' if len(KEY) != 64 or not KEY.isalnum() else 'unknown'}")
    for var in sorted(os.environ):
        if var.upper().endswith("_PROXY") or "CERT" in var.upper() or "CA_BUNDLE" in var.upper():
            print(f"{var:<40}: {os.environ[var]}")
    print(f"model                                   : {MODEL}")
    print(f"allowed upstream                        : {HOST}")


def probe() -> None:
    checks = [
        (
            "allowed : POST chat completions on the OCI GenAI host",
            "POST",
            f"{BASE}/chat/completions",
            {"model": MODEL, "messages": [{"role": "user", "content": "Say OK."}], "max_tokens": 5},
        ),
        ("blocked : GET  an unlisted host (example.com)", "GET", "https://example.com/", None),
        ("blocked : PUT  on the OCI GenAI host (method not in policy)", "PUT", f"{BASE}/models", {}),
    ]
    for label, method, url, body in checks:
        status, text = request(method, url, body)
        if status == 403 or "Permission denied" in text:
            verdict = "DENIED"
        elif status == 0:
            verdict = "DROPPED"  # connection closed, not a policy verdict
        else:
            verdict = f"HTTP {status}"  # 401 with a fake key still means it reached OCI
        print(f"{label:<60} -> {verdict:<8} {text[:110].replace(chr(10), ' ')}")


def work(interval: float) -> None:
    n = 0
    while True:
        n += 1
        status, text = ask(f"Status report {n}. Reply with one short upbeat line.")
        stamp = time.strftime("%H:%M:%S")
        if status == 200:
            print(f"[{stamp}] ok      #{n}: {text}", flush=True)
        else:
            print(f"[{stamp}] BLOCKED #{n}: {text}", flush=True)
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
        work(float(argv[2]) if len(argv) > 2 else 5.0)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
