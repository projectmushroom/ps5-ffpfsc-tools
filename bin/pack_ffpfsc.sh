#!/usr/bin/env bash
# pack_ffpfsc.sh — turn a PS5 dump folder into an SMP-ready .ffpfsc container.
#
# Usage:
#   pack_ffpfsc.sh <SRC_app_folder> [COMPRESSION_LEVEL] [BLOCK_SIZE] [MODE]
#     <SRC_app_folder>   path to the PPSAxxxxx-app dump folder
#     [COMPRESSION_LEVEL] zlib 0-9, default 1 (fast; pre-compressed AAA gains ~0%
#                         anyway, so low effort = near-identical size, way faster)
#     [BLOCK_SIZE]       PFS block size, default auto (65536). Use 16384 for
#                         small-file-heavy games when target storage is tight.
#     [MODE]             auto, fused, or legacy.
#                         auto uses fused on MkPFS >=0.0.9, legacy otherwise.
#                         fused = MkPFS 0.0.9 folder->exFAT-wrapped .ffpfsc.
#                         legacy = two-pass pfs_image.dat->.ffpfsc.
#
# Stops on any failure and NEVER deletes artifacts on error.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="${PS5_ROOT:-$HOME/ps5}"
PY="${PS5_PY:-$DEFAULT_ROOT/.venv/bin/python}"
DAT_DIR="${PS5_SCRATCH:-$DEFAULT_ROOT/scratch}"
OUT_DIR="${PS5_OUT:-$HOME/Downloads/ps5/out}"
LOG_DIR="${PS5_LOGS:-$DEFAULT_ROOT/logs}"
HISTORY_FILE="${PS5_HISTORY:-$DEFAULT_ROOT/history.jsonl}"

SRC="${1:?usage: pack_ffpfsc.sh <SRC_app_folder> [compression_level]}"
LEVEL="${2:-1}"
BLOCK_SIZE="${3:-auto}"
MODE="${4:-auto}"
SRC="${SRC%/}"                                   # strip trailing slash
BASE="$(basename "$SRC")"
TITLE="${BASE%-app}"                             # PPSAxxxxx-app -> PPSAxxxxx
CPU="$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))"     # leave 2 threads for the box

mkdir -p "$DAT_DIR" "$OUT_DIR" "$LOG_DIR"
DAT="$DAT_DIR/pfs_image.dat"                      # inner name MUST be exactly this
FFP="$OUT_DIR/$TITLE.ffpfsc"

report() { tr '\r' '\n' < "$1" | grep -iE 'Files:|Warnings:|Errors:|ratio' | tail -n 6; }
die()    { echo "!!! $* — keeping artifacts for inspection"; echo "=== ABORT ==="; exit 1; }
has_mkpfs_arg() { "$PY" -m mkpfs "$1" "$2" --help 2>&1 | grep -q -- "$3"; }
record_history() {
  local layout="$1"
  "$PY" - "$HISTORY_FILE" "$TITLE" "$SRC" "$FFP" "$MODE" "$LEVEL" "$BLOCK_SIZE" "$CPU" "$MKPFS_VER" "$layout" <<'PY'
import json, os, sys, time
hist, title, src, ffp, mode, level, block, cpu, mkpfs, layout = sys.argv[1:]
def size(path):
    try:
        if os.path.isfile(path):
            return os.path.getsize(path)
        total = 0
        for root, _, files in os.walk(path):
            for name in files:
                p = os.path.join(root, name)
                try:
                    total += os.path.getsize(p)
                except OSError:
                    pass
        return total
    except OSError:
        return None
row = {
    "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
    "event": "build",
    "title": title,
    "source": src,
    "output": ffp,
    "mode": mode,
    "level": int(level),
    "block_size": block,
    "cpu_count": int(cpu),
    "mkpfs": mkpfs,
    "layout": layout,
    "source_bytes": size(src),
    "output_bytes": size(ffp),
}
os.makedirs(os.path.dirname(hist), exist_ok=True)
with open(hist, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}

MKPFS_VER="$("$PY" -m mkpfs -V 2>/dev/null | awk '{print $2}')"
case "$MODE" in
  auto)
    case "$MKPFS_VER" in
      0.0.9|0.0.1[0-9]*|0.[1-9]*|[1-9]*) MODE="fused" ;;
      *) MODE="legacy" ;;
    esac
    ;;
  fused|legacy) ;;
  *) die "unknown mode [$MODE] (use auto, fused, or legacy)" ;;
esac

echo "=== $(date) START $TITLE  (mkpfs=$MKPFS_VER, mode=$MODE, level=$LEVEL, cpu=$CPU, block=$BLOCK_SIZE) ==="
echo "SRC=$SRC"; echo "DAT=$DAT"; echo "FFP=$FFP"
[ -d "$SRC" ] || die "source folder not found: $SRC"

# pre-flight: clean Mac cruft
find "$SRC" \( -name '.DS_Store' -o -name '._*' -o -name '.Spotlight-V100' \
  -o -name '.Trashes' -o -name '.fseventsd' -o -name '.TemporaryItems' \
  -o -name '.AppleDouble' \) -exec rm -rf {} + 2>/dev/null
echo "cruft cleaned"

# pre-flight: disk check — need ~3x source free (src + dat + ffpfsc coexist)
SRC_KB=$(du -sk "$SRC" | cut -f1)
FREE_KB=$(df -k --output=avail "$DAT_DIR" | tail -1 | tr -d ' ')
echo "source=$((SRC_KB/1024/1024))G  free=$((FREE_KB/1024/1024))G  need~$((SRC_KB*2/1024/1024))G more"
[ "$FREE_KB" -gt "$((SRC_KB*2))" ] || die "not enough free space (need ~2x source beyond the source itself)"

# 0. remove stale targets (mkpfs has no --overwrite; it hangs on a Y/n prompt)
rm -f "$DAT" "$FFP" "$FFP.tmp"

BLOCK_ARGS=()
[ "$BLOCK_SIZE" = "auto" ] || BLOCK_ARGS=(--block-size "$BLOCK_SIZE")

if [ "$MODE" = "fused" ]; then
  echo "=== FUSED MODE: MkPFS folder -> exFAT-wrapped .ffpfsc ==="
  echo "=== STEP 1: pack folder --cpu-count $CPU --compression-level $LEVEL ==="
  "$PY" -m mkpfs pack folder --cpu-count "$CPU" --compression-level "$LEVEL" \
      "${BLOCK_ARGS[@]}" --temp-folder "$DAT_DIR" "$SRC" "$FFP" > "$LOG_DIR/1_fused_packfolder.log" 2>&1 \
      || die "fused pack folder FAILED"
  report "$LOG_DIR/1_fused_packfolder.log"

  echo "=== STEP 2: tree (layout check) ==="
  "$PY" -m mkpfs tree "$FFP" > "$LOG_DIR/2_fused_tree.log" 2>&1
  cat "$LOG_DIR/2_fused_tree.log"
  INNER="$("$PY" -m mkpfs tree "$FFP" 2>/dev/null | sed -n 's/.*-- //p' | tail -1 | tr -d ' ')"
  echo "INNER=[$INNER]"
  case "$INNER" in
    "$TITLE.exfat"|pfs_image.dat) ;;
    *) die "unexpected inner layout [$INNER]" ;;
  esac

  echo "=== SMP-READY: fused build complete; tree layout OK ==="
  record_history "$INNER"
  SRC_H=$(du -sh "$SRC" | cut -f1); FFP_H=$(du -h "$FFP" | cut -f1)
  echo "--- DONE: $TITLE  source=$SRC_H  ffpfsc=$FFP_H ---"
  ls -lh "$FFP"
  echo "Next: cp \"$FFP\" /media/<you>/<drive>/homebrew/ && sync"
  echo "=== $(date) DONE ==="
  exit 0
fi

# 1. folder -> uncompressed inner image (named exactly pfs_image.dat)
echo "=== STEP 1: pack folder --no-compress ==="
RAW_ARGS=()
has_mkpfs_arg pack folder --raw && RAW_ARGS=(--raw)
"$PY" -m mkpfs pack folder "${RAW_ARGS[@]}" --no-compress --no-adjust-output-file-extension \
    "${BLOCK_ARGS[@]}" --temp-folder "$DAT_DIR" "$SRC" "$DAT" > "$LOG_DIR/1_packfolder.log" 2>&1 \
    || die "inner pack folder FAILED"
report "$LOG_DIR/1_packfolder.log"

# 2. verify inner image (authoritative integrity gate)
echo "=== STEP 2: verify inner .dat ==="
"$PY" -m mkpfs verify "$DAT" > "$LOG_DIR/2_verifydat.log" 2>&1 || die "inner verify FAILED"
report "$LOG_DIR/2_verifydat.log"

# 3. wrap -> compressed container. KEY FLAGS:
#    --no-rename-inner-image  keep inner name == pfs_image.dat (SMP exact-match)
#    --use-spool              PARALLEL staged builder (default streaming path
#                             starves the workers -> single-core crawl)
#    --cpu-count N            use the whole CPU
#    --compression-level L    low = fast; AAA gains ~0% regardless
echo "=== STEP 3: pack file (--use-spool --cpu-count $CPU --compression-level $LEVEL) ==="
"$PY" -m mkpfs pack file --no-rename-inner-image --use-spool --cpu-count "$CPU" \
    --compression-level "$LEVEL" "${BLOCK_ARGS[@]}" --temp-folder "$DAT_DIR" "$DAT" "$FFP" > "$LOG_DIR/3_packfile.log" 2>&1
report "$LOG_DIR/3_packfile.log"

# 4. verify container integrity
echo "=== STEP 4: verify .ffpfsc ==="
"$PY" -m mkpfs verify "$FFP" > "$LOG_DIR/4_verifyffp.log" 2>&1; rc4=$?
report "$LOG_DIR/4_verifyffp.log"

# 5. validate inner name == pfs_image.dat (SMP readiness; verify can't catch this)
echo "=== STEP 5: tree (inner-name check) ==="
"$PY" -m mkpfs tree "$FFP" > "$LOG_DIR/5_tree.log" 2>&1
cat "$LOG_DIR/5_tree.log"
INNER="$("$PY" -m mkpfs tree "$FFP" 2>/dev/null | sed -n 's/.*-- //p' | tail -1 | tr -d ' ')"
echo "INNER=[$INNER]"

[ $rc4 -eq 0 ] || die "container verify FAILED (rc=$rc4)"
[ "$INNER" = "pfs_image.dat" ] || die "wrong inner name [$INNER] (must be pfs_image.dat)"

# 6. success — clean up the big intermediate
echo "=== SMP-READY: integrity OK and inner == pfs_image.dat ==="
record_history "$INNER"
rm -f "$DAT"
SRC_H=$(du -sh "$SRC" | cut -f1); FFP_H=$(du -h "$FFP" | cut -f1)
echo "--- DONE: $TITLE  source=$SRC_H  ffpfsc=$FFP_H ---"
ls -lh "$FFP"
echo "Next: cp \"$FFP\" /media/<you>/<drive>/homebrew/ && sync"
echo "=== $(date) DONE ==="
