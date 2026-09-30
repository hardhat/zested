#!/bin/sh
# Runs the benchmark binary headless and prints "t-states  name" per measurement.
# With BUDGETS=tests/bench_budgets.txt (default if present) also fails when a result exceeds its
# budget: each budget line is "<max t-states> <name prefix>".
cd "$(dirname "$0")/.." || exit 1
BIN=${1:-tests/bench.bin}
TSTATES=${TSTATES:-4000000000}
BUDGETS=${BUDGETS:-tests/bench_budgets.txt}
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

timeout 600 zeal-native -n "$TSTATES" -u "$BIN" > "$OUT" 2>&1
python3 - "$OUT" "$BUDGETS" <<'EOF'
import re, sys
out, budgets = sys.argv[1], sys.argv[2]
name = None
rows = []
for line in open(out, errors='replace'):
    line = line.rstrip()
    m = re.search(r'BENCH (.*)$', line)
    if m:
        name = m.group(1)
        continue
    m = re.search(r'Counter 0: STOP - Total: (\d+) t-states', line)
    if m and name:
        rows.append((name, int(m.group(1))))
        name = None
for name, ts in rows:
    print("%10d  %s" % (ts, name))
if not rows:
    print("no benchmark results"); sys.exit(1)
try:
    lim = [l.split(None, 1) for l in open(budgets) if l.strip() and not l.startswith('#')]
except OSError:
    lim = []
bad = 0
for maxts, prefix in lim:
    for name, ts in rows:
        if name.startswith(prefix.strip()) and ts > int(maxts):
            print("OVER BUDGET: %s took %d > %s" % (name, ts, maxts)); bad = 1
sys.exit(bad)
EOF
