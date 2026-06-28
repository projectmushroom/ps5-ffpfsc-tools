---
name: ps5-ffpfsc
description: Compress a legal PS5 game dump folder into an SMP-ready .ffpfsc container on this Linux box. Use when the user wants to pack/compress/build a PS5 dump (PPSAxxxxx-app) into a .ffpfsc, or says something like "pack this game", "ffpfsc this dump", "ps5 compress". Checks tool repos for updates, asks which game, then runs the verified MkPFS build.
---

# ps5-ffpfsc — pack a PS5 dump into an SMP-ready .ffpfsc

You are the user's Linux buddy for turning PS5 **game dump folders**
(`PPSAxxxxx-app/`) into console-readable `PPSAxxxxx.ffpfsc` images for
**ShadowMountPlus (SMP)**. The full hard-won playbook lives at
`docs/PS5-FFPFSC-LINUX-HANDOFF.md` — read it if you need
the deep "why". This skill is the automated front door. Only legal, user-owned dumps.

Reusable build script:
`pack_ffpfsc.sh <SRC-app-folder> [level] [block_size] [mode]`.

Modes:
- `auto` (default): MkPFS >=0.0.9 uses the new fused folder→exFAT-wrapped
  `.ffpfsc` path; older MkPFS uses the legacy two-pass nested `pfs_image.dat` path.
- `fused`: force MkPFS 0.0.9 folder→`.ffpfsc`; `tree` should show
  `PPSAxxxxx.exfat`.
- `legacy`: force two-pass `pfs_image.dat`→`.ffpfsc`; `tree` must show
  `pfs_image.dat`.

Helper toolbox: `ps5-ffpfsc`.
Useful commands: `scan`, `status`, `doctor`, `updates`, `preflight <app-folder>`,
`profile <app-folder>`, `plan <app-folder>`, `build <app-folder>`,
`build-batch <folder>`, `history`, `inspect <file>`, `verify <file>`, `compat <title-or-path>`,
`compat-cache [refresh|path|clear]`, `compat-submit <title> <status> [notes]`,
`apr-check <app-folder>`, `ampr-index <app-folder>`, `copy [--rsync] <title-or-file>`,
`copied <title> [--full-verify]`, `clean-local <title> [--yes]`,
`runbook <title-or-app> [output.md]`, `bench`, `ssd`, `ssd-rm <title...>`,
`clean-ssd`, `extract <archive>`.

## Steps — do these in order

### 1. Check the tools for updates
- First run `ps5-ffpfsc doctor` so missing local dependencies, bad paths, or an
  unmounted SSD are obvious before a multi-hour job.
- mkpfs (the packer): compare installed vs latest.
  ```bash
  $PS5_ROOT/.venv/bin/python -m mkpfs -V
  $PS5_ROOT/.venv/bin/pip index versions mkpfs 2>/dev/null | head -3
  ```
  If a newer version exists, ask the user before upgrading
  (`$PS5_ROOT/.venv/bin/pip install -U mkpfs`). Current known-good:
  v0.0.9 for fused exFAT-wrapped builds; v0.0.8 legacy path remains documented.
  If the venv doesn't exist yet, create it: `python3 -m venv "$PS5_ROOT/.venv"`
  then `pip install mkpfs`.
- ShadowMountPlus (the console consumer) — informational only, it runs on the PS5:
  `gh release view -R drakmor/ShadowMountPlus 2>/dev/null` or
  WebFetch https://github.com/drakmor/ShadowMountPlus/releases . Mention if there's
  a new SMP release the user may want on the console, but it doesn't affect packing.
- Also glance at MkPFS upstream for relevant changes: https://github.com/PSBrew/MkPFS
  The shortcut is `ps5-ffpfsc updates`.

### 2. Ask which game
- Default dumps live under `$HOME/Downloads/ps5/dumps/`, but the connected
  Mac is often mounted at `/mnt/mac`. List candidate app folders/images/archives:
  `find $HOME/Downloads/ps5/dumps -maxdepth 3 -name '*-app' -type d`
  or just run:
  `ps5-ffpfsc scan`.
- Ask the user which one (or to paste a path). Confirm the resolved title
  (`PPSAxxxxx` from the folder name) and show source size + free disk.
- Before building, run the advisor and dry-run plan:
  ```bash
  ps5-ffpfsc profile "<SRC-app-folder>"
  ps5-ffpfsc plan "<SRC-app-folder>"
  ```
  `profile` recommends `fast`, `balanced`, `small`, or `legacy-safe` from the
  file mix. `plan` includes output/scratch paths, disk math, APR/AMPR detection,
  compatibility lookup, and exact build/copy commands without changing files.
- If you need the older verbose report, run:
  ```bash
  ps5-ffpfsc preflight "<SRC-app-folder>"
  ```
  `ampr-index` can build `ampr_emu.index` only when required SPRX files already
  exist in `fakelib/`. Do not invent AMPR files. The actual AMPR
  emulator SPRX files are not bundled in PS5-FFPFSC-PRO and must already exist in
  the dump/fakelib or in a user-provided folder.

### 3. Run the build (background)
- Default compression level **1** (fast). With MkPFS 0.0.9 fused mode, large games
  can shrink substantially while avoiding the huge intermediate `pfs_image.dat`
  (GT7: 283.68 GB wrapped input → 173.55 GB final, 38.82% gain).
  Offer higher levels only if the user wants max compression and accepts longer
  runtimes.
- Use the profile recommendation when it is clear. `small` is intentionally slower:
  level 7 plus `auto-fit` blocks. Use it for smaller/raw-ish dumps, not giant
  pre-compressed AAA dumps unless the user accepts the time.
- Prefer the build tool build front door. It runs preflight, refreshes AMPR index
  when possible, builds, falls back from fused to legacy if needed, and records
  history:
  ```bash
  ps5-ffpfsc build "<SRC-app-folder>" 1 auto \
    > $PS5_ROOT/logs/skill_run.log 2>&1
  ```
  (run in the background for large games).
- After it spins up, sanity-check that the CPU is actually being used — this is the
  whole point. Workers should be busy and throughput should be hundreds of MB/s,
  not single digits:
  ```bash
  cat /proc/loadavg
  tr '\r' '\n' < $PS5_ROOT/logs/3_packfile.log | tail -2
  ```
  If you see ~7 MB/s and idle workers, the parallel path isn't engaging — check that
  `--use-spool` is present (see playbook "Why it was slow").

### 4. Report when done
- Confirm the layout based on mode:
  - fused 0.0.9: `mkpfs tree` should show `PPSAxxxxx.exfat`.
  - legacy: `mkpfs tree` must show `pfs_image.dat`.
  Relay the final `.ffpfsc` size vs source/wrapped size.
  Check `ps5-ffpfsc history` for the recorded build.
- For a full integrity check of a local or copied file, run
  `ps5-ffpfsc verify "<file.ffpfsc>"`. This can be slow on huge games, so ask
  before doing it after a copy.
- Remind the copy step (exFAT drive, shell `cp`, then `sync`):
  ```bash
  cp "$PS5_OUT/PPSAxxxxx.ffpfsc" /media/<you>/<drive>/homebrew/ && sync
  ```
  If the SSD is mounted at `/mnt/drive`, prefer:
  `ps5-ffpfsc copy PPSAxxxxx`.
- After copying, run `ps5-ffpfsc copied PPSAxxxxx` for a fast byte-size check.
  Use `--full-verify` only when the user accepts the wait.
- Use `ps5-ffpfsc runbook PPSAxxxxx` to write a small Markdown report after a
  build/copy/test session.
- Use `ps5-ffpfsc clean-local PPSAxxxxx` to preview reclaimable local files.
  Only pass `--yes` after confirming the listed paths are safe to remove.

## Hard rules (from the playbook — do not relearn these)
1. **Two-pass, never single-pass.** Folder → uncompressed inner, then wrap the file.
   Single-pass verifies fine but the console reads files wrong.
2. **Inner image MUST be named exactly `pfs_image.dat`** and you MUST pass
   `--no-rename-inner-image`. SMP silently skips any other name. `verify` does NOT
   catch a wrong inner name — `tree` is the readiness gate.
3. **No `--overwrite` flag** — `rm -f` stale targets first or pack hangs on a prompt.
4. **Never delete the `.dat`/`.ffpfsc` on failure** — keep them for inspection.
5. **Disk:** peak = source + `.dat` + `.ffpfsc` coexisting ≈ ~3x source. The script
   checks this; point scratch at the big volume (`$PS5_ROOT/scratch`).

## Useful extras from PS5-FFPFSC-PRO that we adopted
- Archive awareness via `ps5-ffpfsc extract <archive>` using `7z`; it extracts
  to scratch and prints discovered `*-app` roots. Keep compression itself folder-first.
- Pre-build intelligence: `apr-check` for PlayGo/APR/AMPR markers and `compat` for
  the public PS5-FFPFSC-PRO community compatibility DB.
- `preflight` and `build` now run these by default.
- `compat-submit` exists for after on-console testing only. Never submit a
  compatibility result before the user confirms the game status.
- `ampr-index` ports the public AMPRIDX3/FNV1a64 index builder; it only runs when
  the user already has `libSceAmpr.sprx` and `libScePlayGo.sprx` in `fakelib/`.
- SSD helpers: `ssd`, `ssd-rm`, `copy`, `clean-ssd`.
- MkPFS 0.0.9 fused exFAT-wrapped builds for large games where lower peak disk and
  zlib-ng performance are useful.
