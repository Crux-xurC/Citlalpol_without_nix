# Citlalpol

Scope (what is promised, what is not): [docs/scope.md](docs/scope.md) · Design: [docs/design.md](docs/design.md) (the Japanese original
with its history: [docs/ja/](docs/ja/))

Citlalpol (`citl`) makes the network of a program you run while developing an exit only where it was declared. The program runs
inside the wall of [forbidden](https://github.com/Crux-xurC/forbidden), where the network is not there at all but for one door —
`127.0.0.1:4600` — and Citlalpol is what stands behind that door. Each connection names its destination (SOCKS5, or an HTTP proxy
request), and Citlalpol looks it up in the project's `access.json`:

- **pass** — on to the real destination (an API the program legitimately uses: it passes, and it is seen in the records); never
  to a local address
- **pass with `to`** — to a local address instead, where a [zoozve](https://github.com/Crux-xurC/zoozve) gate of this machine answers
  Citlalpol's challenge (in front of a database of the same version, a stub you run yourself). Making what answers is yours;
  Citlalpol only sends the connection there and records it — and nothing else on your machine's ports can be named by `to`
- **refuse** — with a reason
- **anything not in `access.json` is refused** — before its name is resolved, so a name cannot carry data out by itself

Programs that do not read the proxy settings are caught too: the door catches every TCP connection and DNS question in the wall
(nftables, set up by forbidden), and Citlalpol answers the wall's DNS — undeclared names do not resolve, declared ones get a fake
address that leads back to Citlalpol.

Every attempt is one JSON line in the records: when, which run (and the label set for it from outside the wall), which process inside the wall (forbidden's door tells it with
the PROXY protocol v2, which Citlalpol removes), where to, where it was actually sent, the request when it can be read
(`GET /ping`), and what happened. Values of a query, headers and the usual secret-bearing arguments of the command line are blanked
before anything is written. What is promised and what is not (programs that ignore the proxy, `localhost` inside the wall, TLS):
[docs/scope.md](docs/scope.md).

When you run contract tests with Citlalpol, run them inside forbidden (`citl run`) and check that they never go out unintentionally.
The same pair can be used to look at a program you do not trust: `citl run <name> --strict --dir ./the-tool -- …`.

The name: Citlalpol, the great star (the morning star), in Nahuatl, written without its long vowels.

## Use

```sh
nix develop                                  # Elixir/OTP pinned with tezcatl and Xipe Totec; bin/ on PATH
citl start                                   # citld, in the background (citl serve: in the foreground; citl stop)
citl setup                                   # forbidden's door "citlalpol" -> citld (catching all: needs nftables)
citl read ./access.json myapp                # check it and take a copy of it (the copy is what applies)
zoozve --port 55432 --to 127.0.0.1:3306      # a gate in front of a local server, for a `to`
citl run myapp -- mix test                   # forbidden run --door citlalpol, with myapp's access.json
citl log --since 10m                         # what was tried (--run <id>, --decision refuse, --json)
citl use myapp                               # what applies to `forbidden on --door citlalpol` in a terminal
citl label <run> row-12                      # from outside the wall: what the run is doing now (citl log --label row-12)
```

```json
{ "destinations": [
    { "host": "api.example.com", "port": 443, "do": "pass" },
    { "host": "db.example.com", "port": 3306, "do": "pass", "to": "127.0.0.1:55432" },
    { "host": "*.amazonaws.com", "do": "refuse", "why": "uploads never run while trying code" } ] }
```

`examples/demo/access.json` is one to try with zoozve's pong (`zoozve serve` with a gate at 55480 in front of
`examples/pong.py --port 18080`): `pong.citlalpol.test` goes to it, `example.com` to the real one, the rest is refused.

`access.json` goes with the project; it never names a program to start, and `to` may name only a local address. What is in force
is the copy `citl read` took: a change to the project's file counts only when you read it again, outside the wall, where the copies
and the records are hidden from the program. Records are in
`~/.local/share/citlalpol/records/`.

Needs: Elixir 1.18 / OTP 27 (`nix develop`; without Nix: [Citlalpol_without_nix](https://github.com/Crux-xurC/Citlalpol_without_nix)),
and forbidden (on PATH, beside this repository, or `CITLALPOL_FORBIDDEN`) with nftables for the catch-all; zoozve for a `to`
(`CITLALPOL_ZOOZVE` or on PATH for `test/run.sh`). `test/run.sh` checks the two together without reaching
the network (it also uses python3 and curl, both in `nix develop`).

**Version 0.1.0** (2026-11-25), a development release. **Status:** citld in Elixir: SOCKS5 and HTTP proxy requests (plain HTTP and CONNECT), programs that ignore the proxy
(the catch-all and the wall's DNS), pass / `to` / refuse, labels, the records. Planned: records of UDP / ICMP — see docs/scope.md.

## Where things live

- this repository: code and documents only
- a project's declared destinations: `access.json` in that project (committed with it)
- this machine's own (what is registered) and the records: `~/.config/citlalpol/`, `~/.local/share/citlalpol/`;
  the door and runs: `$XDG_RUNTIME_DIR/citlalpol/` (hidden inside the wall)
