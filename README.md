# Citlalpol without Nix

[Citlalpol](https://github.com/Crux-xurC/Citlalpol) — declared exits only, behind [forbidden](https://github.com/Crux-xurC/forbidden)'s
wall, every attempt recorded — made a Mix project, so that it runs without Nix. What Citlalpol is and does: `README.citlalpol.md`,
`docs/scope.md` and `docs/design.md` (Citlalpol's own, brought here by `sync/`).

**Version 0.1.0**: Citlalpol 0.1.0 (2026-11-25, a development release); this repository takes upstream's version.

## Use

```sh
bin/release                 # once: needs Elixir 1.18+ and Erlang/OTP 27+; builds _build/prod/rel/citlalpol (Erlang's runtime included)
bin/citl setup              # then as in README.citlalpol.md: citl start, citl read, citl run ...
```

`bin/citl` runs the release when it is built — then neither Elixir nor Erlang needs to be on `PATH` — and otherwise
`elixir main.exs`, as Citlalpol itself does. Put `bin/citl` on your `PATH` (a symlink is fine). forbidden (with nftables for the
catch-all) and [zoozve](https://github.com/Crux-xurC/zoozve) (for a `to`) are separate programs, also without Nix.

`bin/test` runs Citlalpol's acceptance (`test/run.sh`) with this `bin/citl`: it needs forbidden and zoozve, unprivileged user
namespaces, nftables, python3 and curl, and reaches no network.

This repository follows Citlalpol (`sync/README.md`): change Citlalpol, then sync here.
