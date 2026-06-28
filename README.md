# ps5-ffpfsc-tools

Small Linux/macOS helper repo for turning legal PS5 `PPSAxxxxx-app/` game dump
folders into ShadowMountPlus-ready `.ffpfsc` containers with MkPFS.

This is the repeatable version of the workflow: local diagnostics, update checks,
source scanning, preflight disk math, APR/AMPR checks, community compatibility
lookup, MkPFS packing, build history, SSD copy helpers, and a Codex skill so the
assistant can act as the UI.

Only use this with game dumps you legally own and are allowed to handle.

## Install

```bash
git clone https://github.com/projectmushroom/ps5-ffpfsc-tools.git
cd ps5-ffpfsc-tools
./install.sh
```

The installer creates `~/ps5/.venv`, installs/updates `mkpfs`, links:

```text
~/.local/bin/ps5-ffpfsc
~/.local/bin/pack_ffpfsc.sh
```

and installs the bundled Codex skill to `~/.codex/skills/ps5-ffpfsc` by default.

Optional config:

```bash
cp config.example.env .env
. ./.env
```

## Common Flow

```bash
ps5-ffpfsc doctor
ps5-ffpfsc updates
ps5-ffpfsc scan
ps5-ffpfsc profile "/path/to/PPSAxxxxx-app"
ps5-ffpfsc plan "/path/to/PPSAxxxxx-app"
ps5-ffpfsc build "/path/to/PPSAxxxxx-app" --preset balanced
ps5-ffpfsc inspect "$HOME/Downloads/ps5/out/PPSAxxxxx.ffpfsc"
ps5-ffpfsc copy PPSAxxxxx
ps5-ffpfsc copied PPSAxxxxx
ps5-ffpfsc runbook PPSAxxxxx
```

`build` runs preflight, checks APR/AMPR indicators, looks up compatibility data,
refreshes `ampr_emu.index` only when the required SPRX files already exist, then
packs with MkPFS. On MkPFS `0.0.9+`, `auto` uses the fused exFAT-wrapped path
first and falls back to the legacy two-pass path if needed.

`profile` scans the file mix and recommends a preset before you build. `plan` is
the dry-run front door. It prints the resolved title, output path,
scratch path, disk math, APR/AMPR state, compatibility lookup, and exact build/copy
commands without changing files.

Presets:
- `fast`: level 1, fused/auto mode; best for large dumps dominated by likely
  pre-compressed assets.
- `balanced`: current default tradeoff.
- `small`: level 7 and `auto-fit` blocks; slower, for smaller/raw-ish dumps.
- `legacy-safe`: level 1 legacy two-pass layout.

## Commands

```text
scan
status
doctor
updates
inspect <file.ffpfsc>
verify <file.ffpfsc>
compat <title-or-path>
compat-cache [refresh|path|clear]
compat-submit <title> <status> [notes]
apr-check <PPSAxxxxx-app-folder>
ampr-index <PPSAxxxxx-app-folder>
preflight <PPSAxxxxx-app-folder>
profile <PPSAxxxxx-app-folder>
plan <PPSAxxxxx-app-folder> [level] [mode] [--preset preset]
build <PPSAxxxxx-app-folder> [level] [mode] [--preset preset]
build-batch <folder> [level] [mode]
history [--json] [--title PPSAxxxxx]
copy [--rsync] <title-or-file>
copied <title> [--full-verify]
clean-local <title> [--yes]
runbook <title-or-app> [output.md]
bench
ssd
ssd-rm <title...>
clean-ssd
extract <archive>
```

## Notes

- `docs/PS5-FFPFSC-LINUX-HANDOFF.md` is the full playbook and postmortem.
- `skills/ps5-ffpfsc/SKILL.md` is the assistant workflow trigger.
- `bin/pack_ffpfsc.sh` is the lower-level verified packer.
- `bin/ps5-ffpfsc` is the front-door toolbox.
- `scripts/check.sh` runs syntax checks and ShellCheck when available.
- `tests/run.sh` creates a tiny fake app fixture and checks scan/plan/doctor.

`clean-local` is dry-run by default. It only deletes title-specific local output,
logs, and scratch matches when `--yes` is supplied.

## Credits

Built around [PSBrew/MkPFS](https://github.com/PSBrew/MkPFS) and
[drakmor/ShadowMountPlus](https://github.com/drakmor/ShadowMountPlus).

Compatibility lookup and APR/AMPR ideas were informed by
[KINGDKAK/PS5-FFPFSC-PRO](https://github.com/KINGDKAK/PS5-FFPFSC-PRO). This repo
does not bundle proprietary game files or AMPR SPRX files.

## License

MIT. See [LICENSE](LICENSE).
