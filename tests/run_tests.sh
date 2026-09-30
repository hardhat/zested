#!/bin/sh
# Runs a zested test binary headless in zeal-native.
# Passes only if the emulator exits with status 0 and the binary reported ALL TESTS PASSED
# (a hung or crashed test hits the T-state limit and has no such line).
#
# ROM: optional OS image to boot instead of ~/.zeal8bit/roms/default.img. The image must have
# the host file system (drive H:) enabled, which the file tests need.
cd "$(dirname "$0")/.." || exit 1
BIN=${1:-tests/test_core.bin}
TSTATES=${TSTATES:-3000000000}
ROM=${ROM:-}
HOSTDIR=$(mktemp -d)
OUT="$HOSTDIR/.console.txt"
trap 'rm -rf "$HOSTDIR"' EXIT

ROMARG=""
[ -n "$ROM" ] && ROMARG="-r $ROM"

# shellcheck disable=SC2086
timeout 300 zeal-native -n "$TSTATES" -H "$HOSTDIR" $ROMARG -u "$BIN" > "$OUT" 2>&1
RC=$?
grep -v -e '^\[CONFIG\]' -e '^\[SNES\]' -e '^\[FLASH\]' -e '^\[HostFS\]' -e 'No device replied' \
	-e '^(I) ' -e '^(W) ' -e '^Kernel ready' -e '^Loading A:' -e '^Zeal 8-bit OS' -e '^Build time' -e '^$' "$OUT"

if [ "$RC" -ne 0 ]; then
	echo "test run failed: zeal-native exit status $RC"
	exit 1
fi
if ! grep -q 'ALL TESTS PASSED' "$OUT"; then
	echo "test run failed: no ALL TESTS PASSED line (crash or timeout?)"
	exit 1
fi

# Verify what the editor wrote to the host file system.
python3 - "$HOSTDIR" "${2:-core}" <<'EOF' || exit 1
import os, sys
d = sys.argv[1]
def check(name, expected):
    path = os.path.join(d, name)
    if not os.path.exists(path):
        print("host check failed: %s missing" % name); sys.exit(1)
    data = open(path, "rb").read()
    if data != expected:
        print("host check failed: %s has %d bytes, expected %d (or wrong content)" % (name, len(data), len(expected)))
        sys.exit(1)
blk = bytes(range(1, 252))
if sys.argv[2] == "core":
    check("zested_small.txt", b"12ab345")
    check("zested_big.bin", (blk * 160))
    check("zested_bank.bin", (blk * 65) + blk[:69])
    check("zested_empty.bin", b"")
elif sys.argv[2] == "editor":
    check("zested_ed.txt", b"one\nthree\n")
    check("zested_ed_big.bin", (blk * 160))
print("host file checks passed")
EOF
