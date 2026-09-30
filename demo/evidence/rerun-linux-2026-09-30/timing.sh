#!/bin/bash
# How long does a RUNNING agent keep access after each kill switch, versus a fresh exec?
set -u
D=$(cd "$(dirname "$0")/../.." && pwd)   # the demo/ directory
LOG=${LOG:-running-agent-requests.log}
SB=ks-timing; P=or-demo; PY=/usr/local/bin/python3.12
IMG=ghcr.io/astral-sh/uv:python3.12-bookworm-slim
B64=$(base64 < "$D/agent/agent.py" | tr -d '\n')
now() { date +%s.%N | cut -c1-14; }
ex() { timeout 30 openshell sandbox exec --name $SB -- $PY /tmp/agent.py "$@" </dev/null 2>&1 | tail -n1; }

openshell sandbox delete $SB >/dev/null 2>&1; while openshell sandbox list 2>/dev/null | grep -q "^$SB "; do sleep 2; done
openshell sandbox create --name $SB --from $IMG --provider $P --detach --env "AGENT_B64=$B64" \
  -- sh -c 'echo "$AGENT_B64" | base64 -d > /tmp/agent.py && exec sleep infinity' | grep -E "Created|rror"
until timeout 20 openshell sandbox exec --name $SB -- $PY -c 'print(1)' </dev/null >/dev/null 2>&1; do sleep 2; done

# the running agent: one request per second, epoch-stamped
timeout 600 openshell sandbox exec --name $SB -- $PY -c '
import sys, time; sys.argv=["a"]; exec(open("/tmp/agent.py").read().split("if __name__")[0])
while True:
    s, t = ask("Say ok.")
    print(f"{time.time():.1f} {s}", flush=True); time.sleep(1)
' </dev/null > "$LOG" 2>&1 &
W=$!
sleep 8

first_refusal_after() {  # first non-200 line after t
  awk -v t="$1" '$1 > t && $2 != 200 {print $1; exit}' "$LOG"
}
last_ok_after() {
  awk -v t="$1" '$1 > t && $2 == 200 {x=$1} END {print x}' "$LOG"
}

for trial in 1 2 3; do
  # --- level 2: detach
  t0=$(now); openshell sandbox provider detach $SB $P --wait >/dev/null 2>&1; t1=$(now)
  fresh=$(ex ask hi); t2=$(now)
  sleep 15
  r=$(first_refusal_after "$t1"); ok=$(last_ok_after "$t1")
  printf 'detach  trial %s: --wait took %.1fs | fresh exec: %s (%.1fs) | running agent: last ok %+.1fs, first refused %+.1fs after --wait returned\n' \
    $trial "$(echo "$t1-$t0" | bc)" "$(echo "$fresh" | cut -c1-40)" "$(echo "$t2-$t1" | bc)" \
    "$( [ -n "$ok" ] && echo "$ok-$t1" | bc || echo 0)" "$( [ -n "$r" ] && echo "$r-$t1" | bc || echo -1)"
  openshell sandbox provider attach $SB $P --wait >/dev/null 2>&1
  until [ "$(ex ask hi | cut -c1-8)" = "HTTP 200" ]; do sleep 2; done; sleep 12

  # --- level 1: global lockdown
  t0=$(now); openshell policy set --global --policy "$D/policies/lockdown.yaml" --yes >/dev/null 2>&1; t1=$(now)
  sleep 20
  r=$(first_refusal_after "$t1")
  printf 'lockdown trial %s: running agent first refused %+.1fs after the command returned\n' $trial "$( [ -n "$r" ] && echo "$r-$t1" | bc || echo -1)"
  openshell policy delete --global --yes >/dev/null 2>&1
  until [ "$(ex ask hi | cut -c1-8)" = "HTTP 200" ]; do sleep 2; done; sleep 12
done
kill $W 2>/dev/null
openshell sandbox delete $SB >/dev/null 2>&1
echo done
