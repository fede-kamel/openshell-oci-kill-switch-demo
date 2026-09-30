#!/usr/bin/env bash
# Test matrix for the hardened runbook.
R=$(cd "$(dirname "$0")/../../.." && pwd)   # repository root
M=${M:-$R/demo/out/matrix}; mkdir -p $M
cd $R
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
state() {
  g=$(openshell policy get --global 2>/dev/null); if [ -n "$g" ] && ! echo "$g" | grep -q "Status: *Superseded"; then echo "  gateway: GLOBAL POLICY IN FORCE"; else echo "  gateway: no global policy in force"; fi
  echo "  demo sandboxes left: $(openshell sandbox list 2>/dev/null | awk 'NR>1 && $1 ~ /-agent/ {print $1}' | tr '\n' ' ')"
}

for T in oci openrouter; do
  echo "### 1/2 full run TARGET=$T"
  TARGET=$T ./demo/demo.sh </dev/null 2>&1 | strip > $M/full-$T.log; echo "  exit=${PIPESTATUS[0]}"
  sed -n '/== Summary/,$p' $M/full-$T.log | grep -E "PASS|FAIL|CHECKS"
  state
done

echo "### 3 missing provider"
TARGET=openrouter PROVIDER=does-not-exist ./demo/demo.sh </dev/null 2>&1 | strip > $M/missing.log; echo "  exit=${PIPESTATUS[0]}"
grep -E "ABORT" $M/missing.log; state

echo "### 4 interrupt (SIGTERM) during the lockdown"
TARGET=openrouter ./demo/demo.sh </dev/null > $M/interrupt.raw 2>&1 &
P=$!
until grep -q "Global policy configured" $M/interrupt.raw 2>/dev/null; do sleep 0.5; kill -0 $P 2>/dev/null || { echo "  run ended before the lockdown"; break; }; done
sleep 1
openshell policy get --global 2>/dev/null | grep -q "Status: *Loaded" && echo "  lockdown is in force (Status: Loaded); sending SIGTERM"
kill -TERM $P; wait $P; echo "  exit=$?"
strip < $M/interrupt.raw | grep -E "cleanup:|session log" ; sleep 5; state
echo "matrix done"
