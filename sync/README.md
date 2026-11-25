# sync

This repository is [Citlalpol](https://github.com/Crux-xurC/Citlalpol) made a Mix project, to run without Nix. Almost every file
comes from Citlalpol through `sync/sync.sh` (see its header for what it changes); the files that came are listed in
`.upstream-files`, and the Citlalpol commit in `sync/UPSTREAM`. Do not edit those here: change Citlalpol and sync again.

This repository's own files:

| File | What |
|---|---|
| `mix.exs` | the Mix project (no Hex package) and its release |
| `app/main.ex` | the release's entry: what upstream's `main.exs` does, for `bin/citlalpol eval` |
| `bin/citl` | replaces upstream's (`sync/replaced.txt`): the release when it is built, else `elixir main.exs` |
| `bin/release`, `bin/test` | building the release; Citlalpol's acceptance (`test/run.sh`) with this `bin/citl` |
| `README.md` | the entrance (upstream's README is `README.citlalpol.md`) |
| `sync/` | this, the script, `gitignore.extra`, `replaced.txt` (upstream's versions in `sync/upstream/`), `UPSTREAM` (the upstream commit) and `UPSTREAM_TREE` (its tree) |
| `.github/workflows/test.yml` | CI without Nix: compiles with warnings as errors, builds the release and runs citl's commands that need no wall |

To update: `sync/sync.sh ~/path/to/Citlalpol`, review `git diff`, `bin/release`, `bin/test`, commit with the upstream commit in
the message.
