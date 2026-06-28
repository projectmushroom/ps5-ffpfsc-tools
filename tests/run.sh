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
assert_contains "$TMP/plan.out" "playgo chunk: yes"
assert_contains "$TMP/plan.out" "compat: skipped (PS5_PLAN_COMPAT=0)"
assert_contains "$TMP/plan.out" "ps5-ffpfsc build"
assert_contains "$TMP/plan.out" "ps5-ffpfsc copy PPSA99999"

"$TOOL" doctor > "$TMP/doctor.out"
assert_contains "$TMP/doctor.out" "root:    $TMP/root"
assert_contains "$TMP/doctor.out" "not mounted: $TMP/ssd"

echo "fixture tests passed"
