#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

APP="$TMP/input/Tiny Game/PPSA99999-app"
mkdir -p "$APP/sce_sys" "$APP/fakelib" "$TMP/root" "$TMP/out" "$TMP/scratch" "$TMP/ssd/homebrew"
printf '{"titleId":"PPSA99999","titleName":"Tiny Fixture"}\n' > "$APP/sce_sys/param.json"
printf 'chunk\n' > "$APP/sce_sys/playgo-chunk.dat"
printf 'payload\n' > "$APP/eboot.bin"
printf 'archive\n' > "$TMP/input/PPSA99999.rar"

export PS5_ROOT="$TMP/root"
export PS5_OUT="$TMP/out"
export PS5_SCRATCH="$TMP/scratch"
export PS5_HISTORY="$TMP/root/history.jsonl"
export PS5_SCAN_ROOTS="$TMP/input"
export PS5_SSD="$TMP/ssd"
export PS5_SSD_HOME="$TMP/ssd/homebrew"
export PS5_PLAN_COMPAT=0
export PS5_BENCH_MB=1

TOOL="$ROOT/bin/ps5-ffpfsc"

assert_contains() {
  local file="$1"
  local text="$2"
  if ! grep -Fq "$text" "$file"; then
    echo "expected [$text] in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

"$TOOL" scan > "$TMP/scan.out"
assert_contains "$TMP/scan.out" "$APP"
assert_contains "$TMP/scan.out" "$TMP/input/PPSA99999.rar"

"$TOOL" plan "$APP" 1 auto > "$TMP/plan.out"
assert_contains "$TMP/plan.out" "=== plan: PPSA99999 ==="
assert_contains "$TMP/plan.out" "output: $TMP/out/PPSA99999.ffpfsc"
assert_contains "$TMP/plan.out" "preset: custom"
assert_contains "$TMP/plan.out" "playgo chunk: yes"
assert_contains "$TMP/plan.out" "compat: skipped (PS5_PLAN_COMPAT=0)"
assert_contains "$TMP/plan.out" "ps5-ffpfsc build"
assert_contains "$TMP/plan.out" "ps5-ffpfsc copy PPSA99999"

"$TOOL" plan "$APP" --preset small > "$TMP/plan-small.out"
assert_contains "$TMP/plan-small.out" "preset: small"
assert_contains "$TMP/plan-small.out" "compression level: 7"
assert_contains "$TMP/plan-small.out" "block size: auto-fit"
assert_contains "$TMP/plan-small.out" "ps5-ffpfsc build"

"$TOOL" profile "$APP" > "$TMP/profile.out"
assert_contains "$TMP/profile.out" "=== profile: PPSA99999 ==="
assert_contains "$TMP/profile.out" "recommended preset: small"
assert_contains "$TMP/profile.out" "ps5-ffpfsc build"

"$TOOL" doctor > "$TMP/doctor.out"
assert_contains "$TMP/doctor.out" "root:    $TMP/root"
assert_contains "$TMP/doctor.out" "not mounted: $TMP/ssd"

"$TOOL" doctor --fix > "$TMP/doctor-fix.out"
assert_contains "$TMP/doctor-fix.out" "fix hints"

printf 'ffpfsc fixture\n' > "$TMP/out/PPSA99999.ffpfsc"
cp "$TMP/out/PPSA99999.ffpfsc" "$TMP/ssd/homebrew/PPSA99999.ffpfsc"
"$TOOL" copied PPSA99999 > "$TMP/copied.out"
assert_contains "$TMP/copied.out" "=== copied: PPSA99999 ==="
assert_contains "$TMP/copied.out" "byte check: OK"

mkdir -p "$TMP/root/logs"
printf 'log\n' > "$TMP/root/logs/build_PPSA99999_fixture.log"
printf 'scratch\n' > "$TMP/scratch/PPSA99999.tmp"
"$TOOL" clean-local PPSA99999 > "$TMP/clean-dry.out"
assert_contains "$TMP/clean-dry.out" "dry-run; add --yes to delete"
assert_contains "$TMP/clean-dry.out" "$TMP/out/PPSA99999.ffpfsc"
"$TOOL" clean-local PPSA99999 --yes > "$TMP/clean-yes.out"
assert_contains "$TMP/clean-yes.out" "deleting"
[ ! -f "$TMP/out/PPSA99999.ffpfsc" ] || { echo "clean-local did not delete local output" >&2; exit 1; }

cat > "$TMP/root/history.jsonl" <<EOF
{"ts":"2026-01-01 00:00:00","event":"build","title":"PPSA99999","mode":"auto","layout":"PPSA99999.exfat","output":"$TMP/out/PPSA99999.ffpfsc","output_bytes":15}
{"ts":"2026-01-01 00:01:00","event":"copy","title":"PPSA99999","dst":"$TMP/ssd/homebrew/PPSA99999.ffpfsc","bytes":15}
EOF
"$TOOL" history --title PPSA99999 > "$TMP/history.out"
assert_contains "$TMP/history.out" "PPSA99999"
"$TOOL" history --title PPSA99999 --json > "$TMP/history.json"
assert_contains "$TMP/history.json" '"title": "PPSA99999"'

"$TOOL" runbook PPSA99999 "$TMP/runbook.md" > "$TMP/runbook.out"
assert_contains "$TMP/runbook.out" "$TMP/runbook.md"
assert_contains "$TMP/runbook.md" "# PS5 FFPFSC Runbook: PPSA99999"

"$TOOL" compat-cache path > "$TMP/compat-path.out"
assert_contains "$TMP/compat-path.out" "$TMP/root/cache/compat.json"
"$TOOL" compat-cache clear > "$TMP/compat-clear.out"
assert_contains "$TMP/compat-clear.out" "cleared"

"$TOOL" bench > "$TMP/bench.out" 2>&1
assert_contains "$TMP/bench.out" "=== bench ==="

echo "fixture tests passed"
