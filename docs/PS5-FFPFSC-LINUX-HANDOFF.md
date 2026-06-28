# PS5 `.ffpfsc` building — Linux handoff

Hand this whole file to Claude Code on the Linux box. It's the complete playbook
for turning a PS5 **game dump folder** into a console-readable `.ffpfsc` image for
**ShadowMountPlus (SMP)**. We figured this out on a Mac; this version is adapted
for Linux (more disk = better, this is the heavy part).

Read it, then act. Don't re-derive — we already paid for every mistake below.

---

## What we're doing & the tools

- **Goal:** `PPSAxxxxx-app/` (a dumped game folder) → `PPSAxxxxx.ffpfsc` that SMP
  auto-mounts on a jailbroken PS5.
- **The tool:** `mkpfs` from **https://github.com/PSBrew/MkPFS** (PyPI package
  `mkpfs`). We originally used **version 0.0.8** for the legacy nested
  `pfs_image.dat` flow. As of **0.0.9**, MkPFS also has a fused folder→exFAT-wrapped
  `.ffpfsc` flow that works with current ShadowMountPlus and avoids the huge
  intermediate `.dat` file.
- **The consumer:** ShadowMountPlus — https://github.com/drakmor/ShadowMountPlus —
  the payload that scans storage and mounts `.ffpfsc` containers on the console.
- The `.ffpfsc` is a **compressed PFS container** (outer, `img_type=0x02`) that
  wraps a single **uncompressed inner PFS image** (`img_type=0x82`). The console
  mounts the outer, decompresses it at the block layer, and mounts the inner image
  it finds inside. That inner image is the actual game filesystem.

## Setup on the Linux box

```bash
mkdir -p ~/ps5 && cd ~/ps5
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install mkpfs
.venv/bin/python -m mkpfs -V      # expect: MkPFS 0.0.x
```

From here on, `PY=~/ps5/.venv/bin/python` and you run `"$PY" -m mkpfs ...`.

### This box's helper scripts

```bash
pack_ffpfsc.sh "<PPSAxxxxx-app>" [level] [block_size] [mode]
ps5-ffpfsc status
ps5-ffpfsc scan
```

`pack_ffpfsc.sh` supports:
- `mode=auto` (default): use MkPFS 0.0.9 fused exFAT-wrapped builds when available,
  otherwise fall back to legacy two-pass.
- `mode=fused`: force 0.0.9 folder→`PPSAxxxxx.ffpfsc`; `tree` shows
  `PPSAxxxxx.exfat`.
- `mode=legacy`: force the old two-pass `pfs_image.dat` nested container; `tree`
  must show `pfs_image.dat`.

`ps5-ffpfsc` is the "no GUI, Codex is the UI" toolbox:
- `scan` — find app folders/images/archives under local Downloads and `/mnt/mac`.
- `status` / `ssd` — show outputs, mounted SSD contents, and space.
- `doctor` — check dependencies, MkPFS, scratch/output paths, optional tools, and
  SSD mount state.
- `updates` — check installed/latest MkPFS, ShadowMountPlus releases, and MkPFS
  upstream activity.
- `preflight <PPSAxxxxx-app>` — source/disk/SSD math + APR/AMPR + compatibility.
- `profile <PPSAxxxxx-app>` — scan file mix and recommend `fast`, `balanced`,
  `small`, or `legacy-safe`.
- `plan <PPSAxxxxx-app> [level] [mode]` — dry-run build plan with resolved title,
  paths, disk math, APR/AMPR, compatibility, and exact build/copy commands.
- `build <PPSAxxxxx-app> [level] [mode]` — default front door: preflight, AMPR
  index refresh if possible, build, fused→legacy fallback, history recording.
- `build-batch <folder> [level] [mode]` — process discovered `*-app` folders.
- `history` — recent build/copy records.
- `history --json` / `history --title PPSAxxxxx` — machine-readable or filtered
  local history.
- `inspect <file.ffpfsc>` — size + `mkpfs tree`.
- `verify <file.ffpfsc>` — full `mkpfs verify` + `tree` for local or copied files.
- `compat <title-or-path>` — query the public PS5-FFPFSC-PRO compatibility DB.
- `compat-cache [refresh|path|clear]` — manage a one-day local compatibility cache.
- `compat-submit <title> <status> [notes]` — submit only after on-console testing.
- `apr-check <PPSAxxxxx-app>` — check PlayGo/APR/AMPR markers before packing.
- `ampr-index <PPSAxxxxx-app>` — build `ampr_emu.index` only when the two AMPR
  SPRX files already exist.
- `copy [--rsync] <PPSAxxxxx|file>` — copy local output to `/mnt/drive/homebrew`
  and `sync`; `--rsync` enables resumable progress copies.
- `copied <PPSAxxxxx> [--full-verify]` — confirm SSD copy exists and byte-matches
  local output; full verify is optional and slow.
- `clean-local <PPSAxxxxx> [--yes]` — dry-run title-specific local cleanup; add
  `--yes` to delete listed local output/log/scratch files.
- `runbook <title-or-app> [output.md]` — write a Markdown build/copy report.
- `bench` — quick scratch write/read and CPU/MkPFS summary.
- `ssd-rm <title...>` — delete only from the SSD homebrew folder.
- `clean-ssd` — remove AppleDouble/metadata cruft from SSD homebrew.
- `extract <archive>` — extract `.zip/.rar/.7z` to scratch and print found `*-app`
  roots.

---

## THE TWO RULES THAT MATTER (we broke both, twice)

These are **legacy two-pass rules**. They remain mandatory when building a nested
`pfs_image.dat` container. MkPFS 0.0.9 fused builds intentionally use a different
layout where `mkpfs tree` shows `PPSAxxxxx.exfat` inside the `.ffpfsc`.

### Rule 1 — Two-pass, never single-pass

You MUST build the uncompressed inner image first, then wrap it. The MkPFS README
calls this **Option 3**. Going folder → compressed image in one shot (**Option 4**)
**verifies fine but the console reads the files wrong** — the image is useless.
Why: the PS5 only decompresses at the *container* layer. Single-pass puts
compression at the *per-file* layer, which the console's game-file reader does not
decode. So:

1. `pack folder --no-compress` → uncompressed `.dat` (the inner PFS)
2. `pack file` → compressed `.ffpfsc` (wrapping a *file* adds the outer container)

### Rule 2 — The inner image MUST be named EXACTLY `pfs_image.dat`

This is the one that cost us hours. SMP only mounts a nested image whose filename
is **exactly `pfs_image.dat`** (SMP README: "A nested `pfs_image.dat` file inside a
PFSC container is treated as a PFS image" — exact-name match, not any `.dat`).

mkpfs derives the inner name from the **basename of the file you wrap**, and by
default (`--rename-inner-image`) it also title-IDs the stem. So if you wrap
`PPSA01289.pfs_image.dat`, the inner name becomes `PPSA01289.pfs_image.dat` and
**SMP silently skips it.** The container on disk is `PPSA01289.ffpfsc` (correct),
but what's *inside* must be `pfs_image.dat`. Two-part fix, both required:

1. Name the intermediate file literally `pfs_image.dat` (NOT `<title>.pfs_image.dat`).
2. Pass `--no-rename-inner-image` on the `pack file` step.

**`mkpfs verify` does NOT catch a wrong inner name** — it only checks integrity. The
real readiness check is `mkpfs tree`, see Validation below.

---

## The exact commands

```bash
PY=~/ps5/.venv/bin/python
SRC="/path/to/PPSA01289-app"          # the dump folder
TITLE="PPSA01289"                      # folder name minus a trailing -app
DAT_DIR="/path/with/space"             # scratch dir (big disk)
OUT_DIR="/path/for/output"
DAT="$DAT_DIR/pfs_image.dat"           # <-- inner name MUST be this exact basename
FFP="$OUT_DIR/$TITLE.ffpfsc"

# 0. remove stale artifacts (mkpfs has NO --overwrite; it hangs on a Y/n prompt otherwise)
rm -f "$DAT" "$FFP"

# 1. folder -> uncompressed inner image
"$PY" -m mkpfs pack folder --no-compress --no-adjust-output-file-extension \
    --temp-folder "$DAT_DIR" "$SRC" "$DAT"

# 2. verify the inner image (do NOT delete anything if this fails)
"$PY" -m mkpfs verify "$DAT"

# 3. wrap the inner image into the compressed container (keep the exact inner name)
#    --use-spool + --cpu-count + low --compression-level = use the WHOLE cpu (see Performance below)
CPU="${PS5_CPU_COUNT:-$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))}"
"$PY" -m mkpfs pack file --no-rename-inner-image --use-spool --cpu-count "$CPU" \
    --compression-level 1 --temp-folder "$DAT_DIR" "$DAT" "$FFP"

# 4. verify the container (integrity)
"$PY" -m mkpfs verify "$FFP"

# 5. VALIDATE inner name (SMP-readiness — the file under / must be exactly pfs_image.dat)
"$PY" -m mkpfs tree "$FFP"

# 6. clean up the intermediate
rm -f "$DAT"
```

`PPSA20396-app` → title `PPSA20396` → container `PPSA20396.ffpfsc`, inner
`pfs_image.dat`.

### One-command shortcut (this Linux box)

We wrote a reusable wrapper that does the whole verified pipeline (cruft clean →
disk check → pack folder → verify → parallel pack file → verify → tree → cleanup),
stopping without deleting anything on failure:

```bash
pack_ffpfsc.sh "<PPSAxxxxx-app folder>" [compression_level] [block_size] [mode]
# e.g.  pack_ffpfsc.sh "$HOME/Downloads/ps5/dumps/Game/PPSA02015-app" 1
```

Preferred higher-level command:

```bash
ps5-ffpfsc doctor
ps5-ffpfsc updates
ps5-ffpfsc profile "<PPSAxxxxx-app folder>"
ps5-ffpfsc plan "<PPSAxxxxx-app folder>" 1 auto
ps5-ffpfsc build "<PPSAxxxxx-app folder>" --preset balanced
```

That runs preflight, compatibility lookup, APR/AMPR checks, AMPR index refresh
when the required files are already present, the build itself, fused→legacy
fallback if needed, and local history recording.

There's also a Claude Code skill `/ps5-ffpfsc` that checks the repos for updates,
asks which game, and runs this for you.

---

## Performance — USE THE WHOLE CPU (this cost us a scare)

**Symptom:** `pack file` crawled at ~7 MB/s with an ETA of ~6 HOURS for a 159 GB
game (Death Stranding 2, `PPSA02015`), while an M4 Max had done a 280 GB game in
~5 min. It looked like the old Intel i9 was just slow.

**It wasn't the CPU.** The box was 90% idle: load average ~1.7 on 16 threads. The
mkpfs **default "direct-to-image streaming" builder serializes through one main
process and starves the worker pool** — the 8 compression workers sat at ~5% CPU
each while the main process pegged ~130%. Throughput is gated by that one core.

**Fix — three flags on the `pack file` step:**
- `--use-spool` — force the **legacy staged/spool builder, which actually
  parallelizes** compression across workers. This is the single biggest lever.
- `--cpu-count N` — default auto-caps at **8**; pass `nproc-2` to use the whole CPU.
- `--compression-level 1` (default is 7) — pre-compressed AAA assets (`.forge`)
  gain ~0% no matter what, so low zlib effort gives a **near-identical size** while
  the doomed compression *attempts* run far faster. Use level 7 only for genuinely
  compressible games (Minecraft-class).

**Result on the same 159 GB game / same machine:**

| | default streaming | `--use-spool --cpu-count 14 --compression-level 1` |
|---|---|---|
| Throughput | ~7 MB/s | **~270–295 MB/s** (~40x) |
| ETA | ~6 hours | **~9 minutes** |
| Workers | ~5% each (starved) | actually fed |

The remaining gap to the M4 Max is normal generational difference (and a pure-store
pass on incompressible data runs near disk speed). Diagnose with
`cat /proc/loadavg` + `ps -o pid,pcpu -p <pids>`: if the box is idle and one process
hogs a core, you're on the serial path — add `--use-spool`.

Other useful `pack file` knobs: `--max-compressed-ratio` (default 95 — blocks that
don't shrink below this are stored), `--min-compress-size`, `--skip-executable-compression`,
`--threshold-gain`, `--block-size`. Defaults are fine; the three above are what matter.

### MkPFS 0.0.9 fused path

0.0.9 changed `pack folder` defaults: folder input now builds an exFAT-wrapped
`.ffpfsc` directly. This was worth trying for Gran Turismo 7:

```bash
"$PY" -m mkpfs pack folder --cpu-count 14 --compression-level 1 \
  --temp-folder $PS5_ROOT/scratch \
  "/mnt/mac/Downloads/Gran Turismo 7/PPSA01317-app" \
  "$PS5_OUT/PPSA01317.ffpfsc"
```

Result: wrapped input **283.68 GB** → final **173.55 GB**, **38.82% gain**,
throughput ~105 MB/s, and `mkpfs tree` shows:

```text
/
`-- PPSA01317.exfat
```

That is expected for the 0.0.9 fused layout. For older SMP or if this layout ever
fails on-console, force the legacy path:

```bash
pack_ffpfsc.sh "<PPSAxxxxx-app>" 1 auto legacy
```

---

## Pre-flight

1. **Clean cruft** in the source tree before packing (dumps often come from
   Mac/zip and carry junk):
   ```bash
   find "$SRC" \( -name '.DS_Store' -o -name '._*' -o -name '.Spotlight-V100' \
     -o -name '.Trashes' -o -name '.fseventsd' -o -name '.TemporaryItems' \
     -o -name '.AppleDouble' \) -exec rm -rf {} + 2>/dev/null
   ```
   (On a real Linux box `.DS_Store` won't regenerate the way it does on macOS, so
   one clean pass is enough. On Mac it kept reappearing between cleanup and pack —
   not your problem here.)
2. **Check disk space.** Peak usage = source + `.dat` + `.ffpfsc` coexisting before
   the final `rm`. Game assets that are already compressed (`.forge`, most AAA)
   give ~0% gain, so assume both the `.dat` and `.ffpfsc` are ≈ source size →
   **~3× source total**. Point `--temp-folder` and `$DAT` at the big volume.
3. **Check APR/AMPR and compatibility before packing:**
   ```bash
   ps5-ffpfsc profile "$SRC"
   ps5-ffpfsc plan "$SRC"
   ```
   PS5-FFPFSC-PRO's AMPR detection/index code is public, but the actual
   `libSceAmpr.sprx` and `libScePlayGo.sprx` files are **not** bundled. If a game
   needs them, they must already be in `fakelib/` or come from a user-provided AMPR
   folder. Don't fabricate or download them. `ps5-ffpfsc ampr-index "$SRC"`
   can rebuild `ampr_emu.index` only when those two files already exist.

Compatibility DB reads are fine before building. `compat-submit` is for after
on-console testing only.

Run `ps5-ffpfsc doctor` when a path, mount, Python environment, or optional tool
looks suspicious. It is cheap and catches the boring stuff before the expensive
packing starts.

## Validation = the readiness gate

A container is SMP-ready ONLY if **both** pass:
- `mkpfs verify "$FFP"` → `Warnings: 0  Errors: 0` (integrity)
- `mkpfs tree "$FFP"` → the single file under `/` is **exactly** `pfs_image.dat`

For MkPFS 0.0.9 fused builds, `tree` should instead show `PPSAxxxxx.exfat`.

Quick one-liner to assert the inner name in a script:
```bash
INNER="$("$PY" -m mkpfs tree "$FFP" 2>/dev/null | sed -n 's/.*-- //p' | tail -1 | tr -d ' ')"
[ "$INNER" = "pfs_image.dat" ] && echo "SMP-ready" || echo "BAD inner name: $INNER"
```

---

## Gotchas (all learned the hard way)

1. **No `--overwrite` flag.** If the output `.dat`/`.ffpfsc` exists, `pack` stops at
   an interactive `Overwrite? [Y/n]` and hangs forever in a non-interactive run.
   Always `rm -f` the targets first.
2. **Transient pack-time `Errors: 1` that `verify` doesn't confirm = re-pack once.**
   We saw `pack folder` report 1 error / exit 1 while a standalone `verify` of the
   same `.dat` was clean. The standalone `verify` is authoritative. Re-pack; if it
   reproduces, investigate before wrapping.
3. **mkpfs spams `\r` progress bars** that overflow logs. Redirect each step to a
   file and read the report lines:
   `cmd > log 2>&1; tr '\r' '\n' < log | grep -iE 'Files:|Warnings:|Errors:' | tail`
4. **Compression reality:** non-pre-compressed games shrink a lot (Minecraft ~78%,
   Sackboy ~43%); `.forge`/AAA shrink ~0%. Plan disk for the worst case.

## Fixing an already-built `.ffpfsc` with the WRONG inner name (no source needed)

If you find old containers named `<title>.pfs_image.dat` inside (run `mkpfs tree`
to check), you don't need the source folder — recover the inner image from the
container itself:

```bash
TMP=/big/scratch/_fix
rm -rf "$TMP"; mkdir -p "$TMP"
"$PY" -m mkpfs unpack --overwrite "BAD.ffpfsc" "$TMP"   # -> $TMP/<title>.pfs_image.dat
mv "$TMP"/*.pfs_image.dat "$TMP/pfs_image.dat"
"$PY" -m mkpfs pack file --no-rename-inner-image --no-adjust-output-file-extension \
    --temp-folder "$TMP" "$TMP/pfs_image.dat" "FIXED.ffpfsc"
"$PY" -m mkpfs tree "FIXED.ffpfsc"     # confirm inner == pfs_image.dat
"$PY" -m mkpfs verify "FIXED.ffpfsc"   # confirm integrity, then replace the original
rm -rf "$TMP"
```

---

## Getting the file onto the PS5 drive

- The PS5 game drive is typically **exFAT**. exFAT has no practical file-size limit.
  If a copy of a >4 GB file fails, the drive is **FAT32** (4 GB cap) — reformat to
  exFAT.
- SMP scans a `homebrew/` folder on the drive (that's where ours live:
  `/<drive>/homebrew/PPSAxxxxx.ffpfsc`). Confirm your SMP scan paths/config.
- Copy from the shell, not a file manager, and **flush before unplugging**:
  ```bash
  cp "PPSAxxxxx.ffpfsc" "/media/<you>/<drive>/homebrew/" && sync
  ```
  (On Linux use whatever exFAT driver is installed — kernel `exfat` or
  `exfatprogs`/`fuse-exfat`. The `sync` matters; eject/unmount cleanly.)
- **Mac-only note (FYI, doesn't apply on Linux):** macOS Sequoia's new FSKit exFAT
  driver silently drops large files copied via Finder. We had to use
  `cp -X <file> /Volumes/<drive>/homebrew/ && sync` from Terminal. If you ever copy
  from the Mac instead, that's the workaround.
- After copying, the helper performs a fast byte-count check. For a full integrity
  check on the drive, run `ps5-ffpfsc verify "/mnt/drive/homebrew/PPSAxxxxx.ffpfsc"`
  and expect it to take a while on huge games.

---

## What we've already built (reference)

| Game     | Title      | Source | `.ffpfsc` | Notes |
|----------|------------|--------|-----------|-------|
| Minecraft| PPSA17221  | 1.3 GB | 798 MB    | ~78% smaller |
| Sackboy  | PPSA01289  | 56 GB  | 32 GB     | ~43% smaller |
| Death Stranding 2 | PPSA02015 | 159 GB | 107 GB | legacy two-pass, level 1, ~33% smaller |
| Gran Turismo 7 | PPSA01317 | 281 GB | 174 GB | MkPFS 0.0.9 fused exFAT layout, ~39% smaller |

Both were initially built with the wrong inner name and **would not mount**; we
fixed them with the unpack→rename→re-wrap recipe above. Don't repeat that mistake —
name the intermediate `pfs_image.dat` and pass `--no-rename-inner-image` from the
start, then `mkpfs tree` to confirm before you copy anything to the console.

---

## TL;DR for the Linux box

1. `pip install mkpfs` in a venv.
2. Clean cruft, check you have ~3× the game's size free on a big volume.
3. `ps5-ffpfsc doctor`, then `ps5-ffpfsc updates` if starting a new session.
4. `rm -f` stale targets, then: pack folder (`--no-compress`, inner file named
   `pfs_image.dat`) → verify → pack file (`--no-rename-inner-image` **+ `--use-spool
   --cpu-count $(nproc-2) --compression-level 1`** so it uses the whole CPU) → verify.
5. `mkpfs tree` MUST show `pfs_image.dat`. If it doesn't, it won't mount — fix it.
6. `cp` to the drive's `homebrew/` folder, `sync`, eject cleanly.

Or just run `pack_ffpfsc.sh "<...-app>"` (or the `/ps5-ffpfsc` skill).
