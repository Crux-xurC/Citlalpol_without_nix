# Citlalpol — design

This is the English design document of the current design (v0.11 of the Japanese memo). **What is promised and what is not is
[scope.md](scope.md)**, which wins over this document. The Japanese original, with how the design came about, is
[ja/design-memo.md](ja/design-memo.md); its sections on stand-ins, `stages`, swallow and `verify` are history (see "What moved out").
How to use it: [../README.md](../README.md).

## What it is

Citlalpol (the command is `citl`) is **the far side of the door** of a tool that keeps a program you run while developing from going
out to the network by itself.

- **The wall is [forbidden](https://github.com/Crux-xurC/forbidden)'s.** forbidden starts the program in a new network namespace with
  nothing in it but its own loopback and one door, `127.0.0.1:4600`, which leads to a unix socket outside. Citlalpol's daemon, **citld**,
  is what stands there.
- **What it does.** For each connection that comes through the door it looks up the destination in the project's `access.json`:
  **pass** (to the real destination), **pass with `to`** (to a local server the person runs, behind a [zoozve](https://github.com/Crux-xurC/zoozve)
  gate), or **refuse**. **Whatever is not declared is refused**; no setting changes that default. Every attempt is recorded.
- **Declaring the destinations.** An application's destinations are known while it is being made. The person writes them in
  `access.json`, committed with the project, and `citl read` takes a copy of it; the copy is what applies.
- **The main use.** Xipe Totec evaluates the functions of a target repository inside forbidden's wall; Citlalpol records where each
  evaluation tried to go and where it stopped; a person loosens `access.json` one step at a time and evaluates again (below).
- **Another use: looking at a program you do not trust**: run it with `citl run <name> --strict --dir ./the-tool -- …` and read where it
  tried to go.
- **What it does not do.** The wall itself (forbidden); isolating files or outside state (a sandbox); confining hostile code; making
  what answers (stand-ins, recorded replies — the person runs those).
- **Platform.** Linux (forbidden uses network namespaces).

```
 inside forbidden's wall                             outside
┌──────────────────────────────────┐            ┌──────────────────────────────────────┐
│ the program (a test, a REPL,     │            │ citld                                │
│ a terminal)                      │            │   ├ the copy of access.json:         │
│   proxy variables → names its    │  unix      │   │   pass / pass with `to` / refuse │
│   destination at 4600            │  socket    │   │   (undeclared: refused)          │
│ 127.0.0.1:4600 (the door) ───────┼───────────▶│   ├ answers the wall's DNS           │
│ catch-all: other TCP and DNS ────┼───────────▶│   └ records every attempt            │
│ no other route                   │            │        │ pass        │ `to`          │
└──────────────────────────────────┘            │        ▼             ▼               │
                                                │   the real host   zoozve gate → your │
                                                │                   local server       │
                                                └──────────────────────────────────────┘
```

### Who does what

| | Takes care of |
| --- | --- |
| forbidden | the wall (no way out), the one door, the PROXY v2 header naming the process, the catch-all (nftables) |
| Citlalpol | behind the door: the decision per destination, the wall's DNS, the records, labels |
| zoozve | a gate in front of a local server: answers Citlalpol's challenge, then relays bytes untouched |

**The promise to write in documents**: "When you run contract tests with Citlalpol, run them inside forbidden (`citl run`), and check that
they never go out unintentionally."

## The door

- **Citlalpol is only behind the door.** Port 4600 is opened only inside the wall, so no other process on the machine can ask citld to
  "let me out".
- **What the door speaks.** SOCKS5 (`socks5h`: the name is resolved by Citlalpol, not by the program) and HTTP proxy requests (`CONNECT`,
  and plain HTTP with an absolute URL). Both **name the destination at the start of the connection**, so Citlalpol knows the name and
  the port for certain.
- **Programs that ignore the proxy variables** are caught by forbidden's catch-all door (`citl setup` makes it): their TCP connections
  arrive with where they were going (`via: redirect`), and every DNS question in the wall arrives too (`via: dns`).
- **Who has the power.** The one thing needed is "the wall's maker is the parent, and the only outside the program sees is the door" —
  forbidden's property. If the program kills the door's relay, the way out only disappears. The labels on the records are set from
  outside the wall, so the program cannot forge them.

### The PROXY protocol v2 header

forbidden's relay puts a PROXY v2 header in front of each connection. citld reads it **only on connections from the door's unix socket**
(`$XDG_RUNTIME_DIR/citlalpol/`, 0700, hidden inside the wall) and **removes it**: the destination sees the same bytes as without
Citlalpol. Its TLVs give the run id, the pid, command and executable of the process inside the wall, the mode (`normal` / `strict`) and `via`. All
connections inside the wall come from `127.0.0.1`; with the header the record says which run, which process, where.

## DNS and fake addresses

citld answers the wall's DNS:

- A name the applying `access.json` does not declare (or declares as `refuse`) gets **NXDOMAIN** and its own record (refused at the
  question). **No resolver outside ever hears it** — a name alone can carry data out (`<stolen data>.attacker.example`).
- A declared name gets a **fake address from `198.18.0.0/15`** (reserved for benchmarks; no real host has one) for A questions, no data
  for other types. citld remembers which name it gave each address, so a connection to that address is judged as the name, and the
  record keeps the fake `address`.
- The table lives in citld only: after citld restarts, a program that kept an old address is refused (it resolves again next time).

## `access.json`

Kept in the application's repository and committed with it: "where does this application go".

```json
{ "destinations": [
    { "host": "api.example.com", "port": 443, "do": "pass", "why": "the payment API; read-only calls in development" },
    { "host": "db.example.com", "port": 3306, "do": "pass", "to": "127.0.0.1:55432" },
    { "host": "*.amazonaws.com", "do": "refuse", "why": "uploads never run while trying code" } ] }
```

- `do`: `pass` or `refuse`. **An undeclared destination is refused.** `refuse` exists to write a refusal down, with its reason in `why`.
- `host` is a name (`*.` prefix allowed), or an IPv4 literal when a program connects to one on purpose; `port` is optional.
  `*.` is safe with `refuse`, however wide, and with `pass` + `to`; with a plain `pass` every name under it is resolved for real — see
  [scope.md](scope.md), "Outside the scope", the row on `*.` — so `citl digest` writes `*.` only with `refuse`.
- `to` (with `pass`) sends the connection to **a local address** instead of the real one. It may name only a loopback address — checked
  by `citl read` and again at each connection — and it reaches only a zoozve gate (below).
- `why` is for people; it is in the records too.
- **A program to start is never written in it.** `access.json` comes with someone's repository; it must not be able to make this machine
  run anything.

### What applies: the copy `citl read` took

```
citl read ./access.json myapp
```

1. checks the shape (unknown `do`, a `to` that is not local, a field that names a program — errors);
2. shows what passes, what goes where with `to`, and that everything else is refused;
3. takes **a copy** (`~/.config/citlalpol/access/<name>.json`, registered in `registered.json` with source, sha256 and time).

From then on `citl run myapp -- <command>` (or `citl use myapp` for a `forbidden on --door citlalpol` terminal) uses the copy. A change
to the project's file counts only when it is read again — and `citl read` refuses inside the wall: a program inside can write the
project, and loosening must stay a person's act. `citl status` says when the project's file differs from the copy.

### Hidden inside the wall

`citl setup` asks forbidden to hide Citlalpol's config (the copies, the zoozve key, `gates.json`) and its records inside the wall
(`forbidden hide add`); forbidden's own config is read-only there. The program being judged can neither change nor read them.

## `pass` and `to`

- **`pass` without `to`** goes to the real destination (an API the program legitimately uses: it passes, and it is seen). A name that
  resolves to a local address is refused: a committed file could otherwise point at this machine's own services.
- **`pass` with `to`** goes to the local address. At the head of the connection citld sends a **zoozve/2 challenge**
  (`ZOOZVE/2 <nonce>`) and relays only if the answer is `ZOOZVE/2 OK <HMAC-SHA256(key, "zoozve/2 <nonce> <address>:<port>")>` with this
  machine's key (`~/.config/citlalpol/zoozve.key`, made by `citl setup`, hidden inside the wall); `<address>:<port>` is where citld
  connected (`127.0.0.1:55432`, `[::1]:55432`), which is the gate's own end. Both are inside the HMAC, so a server on another port, or
  at another loopback address at the same port, that passes the challenge on to a real gate gets it wrong (zoozve/1, 2026-11-25, had
  the port only). What a gate proves, and what not: [zoozve's scope](https://github.com/Crux-xurC/zoozve/blob/main/docs/scope.md). Otherwise refused, and the record says why; `to_auth: "zoozve"`
  when it passed. **Behind the gate is whatever the person chose** — the same version of a database, a stub.
- **Never** tezcatl's pages, the relay, Emacs or Xipe Totec (`4001`, `4100`, `4000`, `4200` on loopback), not even with `to`: they can act
  outside the wall (the relay starts shells). More ports in `~/.config/citlalpol/never.json` (`{"ports": [...]}`).
- **Refusals** are quick, never a timeout: HTTP `403` with `X-Citlalpol: refused` and a one-line reason; SOCKS5 "not allowed" (0x02); a
  catch-all connection is closed at once (the reason is in the record).

### HTTPS

`CONNECT` is passed through without decrypting: Citlalpol sees the name and the bytes counted, never the request inside. A `to` server
over TLS must present a certificate the client trusts (or the client fails the handshake — a safe failure); otherwise have the program
talk plain HTTP to the local server.

## The records

citld appends one JSON line per attempt to `~/.local/share/citlalpol/records/<YYYY-MM-DD>.jsonl` (append only; one process writes, so
lines never interleave). A line holds: when; the run and its label; the process inside the wall (pid, command, executable, mode); `door`
(`proxy_v2` / `none`); `via` (`redirect` / `dns`); the protocol (`socks5`, `http`, `connect`, `tcp`, `dns`); the destination as named
(and the fake `address`); the request line of plain HTTP or the DNS question's type; the decision and the rule; `sent_to` (the address
actually connected to) or the DNS `answer`; bytes each way; time; and why, when refused. "Removed the header and sent it to X" is
readable from one line.

**What a record can be trusted for.** What Citlalpol decides or sees itself, and what is set outside the wall, holds: the time, `run`
and `label`, `mode`, `door`, `via`, the destination as named, the decision and its rule, `sent_to`, the bytes. What comes from inside is
the program's word: `cmd` is the process's command line, which it can rewrite (`exe`, the file the kernel runs, is harder to fake, but
an interpreter's for a script); `pid` is the first holder of the socket found; the request line is what the client sent. Read those as
hints about who tried.

**Secrets are blanked before anything is written**: a query's values (`/ping?token=…` keeps only the names), `Authorization` / `Cookie`
/ API-key headers, and the usual secret-bearing arguments of a command line (`user:password@`, `--password` / `--token` values,
`curl -u`). Best effort: a secret written some other way can stay — the records are this machine's own, outside git.

```
citl log [--run <id>] [--label <l>] [--since 10m] [--decision refuse|pass] [--json]
```

**The records are read only as files** (tezcatl's relay reads them for its Citlalpol panels). There is no query port on the door, and
tezcatl, Poca, Emacs and Xipe Totec are never run under Citlalpol: looking at the records must not make records.

### Labels: which evaluation made the attempt

From inside the wall one can tell the run, not which function was being evaluated. So **the one who started it, outside the wall**
(Xipe Totec), names what the run is doing now: `citl label <run> <label>` writes `labels/<run>` in the runtime directory the wall hides,
and citld reads it for each connection. Every attempt of that run carries the label until it changes. Nothing inside the wall can write
a label, so attempts cannot be put under another name; the labels survive a restart of citld.

## The loop with Xipe Totec (loosening the wall one step at a time)

The main use. The REPL goes inside the wall through Xipe Totec's `eval.wrap`; the labels per row are not wired yet:

```
 1. Xipe Totec evaluates the target's functions (its REPL started by `citl run` through eval.wrap; everything undeclared refused)
 2. citld records which evaluation tried to go where, how, and where it stopped
 3. a person approves a change to access.json from the records (one step looser):
       pass / pass with `to` (a local server) / stay refused
       — `citl swallow` gathers what was refused, `citl digest <id> …` writes the change (next section), `citl read` applies it
 4. Xipe Totec evaluates again → 1
```

- **Tie an attempt to the row being evaluated**: Xipe Totec sets the label (the row's id) before evaluating a row. Rows sent together
  run at the same time, so under Citlalpol it must either evaluate one row at a time or keep the label per pass (open).
- **Only a person loosens.** Like Xipe Totec's effect approval (an agent proposes; only what a person approves is evaluated), nothing
  makes `access.json` looser automatically — that is what keeps it a wall.
- **On Xipe Totec's side** (its promise of "not a sandbox" stays): a project's `eval.wrap` puts a command in front of the REPL's, so
  `xipe config 'eval.wrap=["citl","run","<name>","--"]'` starts the REPL inside the wall (Xipe Totec's D-eval-wrap, 2026-11-25; generic —
  Xipe Totec knows nothing of Citlalpol). Not yet: the label before each row; for a failed row, the reason from the records
  (`:nxdomain` or a TLS alert alone cannot tell "refused" from "really down"); a column of attempts per row in tezcatl's matrix
  (`citl log --json --label <row id>`).
- **Effects.** Under Citlalpol a function that writes to the network might look safe to evaluate, but **writes to files are not
  stopped**. The way is not to loosen Xipe Totec's `writes`, but to add a network axis to its effect classes (does not go out / goes only
  to declared destinations), with the records as evidence for a proposal.
- **In practice.** Do not wrap `nix develop` from outside (fetching the dev shell would fill the records): `nix develop -c citl run …`.
  Servers a test opens and connects to itself stay on the wall's own loopback. Running xipe_totec's own tests with everything refused
  and seeing **zero** attempts checks both Citlalpol and Xipe Totec's promise (an attempt would be a hole in that promise, or a tool going
  out by itself — dotnet telemetry, sbt's update check …).

## From the records to `access.json`: `swallow`, `digest`, `residual`

Step 3 of the loop above, made short. The names go on from swallow (once a separate tool that answered for the outside; see "What
moved out"): what was **swallowed** — the attempts that did not get out — is **digested** into `access.json`, and what is worth keeping is
the **residual**. Seldom used, so the words may be odd.

```
citl swallow [--run <id>] [--label <l>] [--since 10m]   # the refused attempts as a small table (default: the last run)
citl digest <ref> pass [--why "…"]                      # add a destination to the project's access.json
citl digest <ref> to <host>:<port> [--why "…"]          #   … sent to a zoozve gate
citl digest <ref> refuse [--why "…"]                    #   … refused on purpose, with a reason
citl residual <name>                                    # keep the last small table (no dot in the name)
```

**The small table.** `citl swallow` reads the records in the range, keeps only the refused attempts, and groups them by destination
(the name or IPv4 address, the port — `-` when it was stopped at the DNS question —, the protocol). One row a destination: an id (`1`,
`2` …), the destination, the port, the protocol, where it stopped (`dns` / `connect`), how many times, the `access.json` that applied
(by its name), the command that tried and its executable (the most frequent; the command is what the process said of itself — "The
records"), the last time, and why it was refused. It is printed and written to
`$XDG_RUNTIME_DIR/citlalpol/swallow/last.tsv`, replacing the one before: **temporary** — the next `citl swallow`, a logout or a reboot
takes it away. Tab-separated: a first line `# citl swallow run=<id> <time> …`, a line of column names, the rows. Read it with
`cat`; there is no command to show it again. UDP and ICMP are not in it while they are not in the records (planned, M6).

**`digest`.** `<ref>` is a row of the last small table (`3`), a row of a kept one (`<name>:3`), or a destination written directly
(`api.example.com`, `api.example.com:443`, `203.0.113.7`). What to do is always written: nothing undeclared is let through by default,
so a `digest` without a word would be a loosening by default. It changes **the project's `access.json` only** — the file `citl read`
registered for the row's `access` name (`--name <n>` when written directly and more than one is registered) — and never the copy in force: the person applies it
with `citl read` afterwards, as for any change, and `digest` says so and prints what it added. The new destination goes first (the first
destination that matches decides), as one line, the rest of the file as the person wrote it. It refuses:

- inside the wall (like `citl read`)
- when the project's file differs from the copy in force (`citl status` says so) by more than what `digest` itself wrote: what `citl read`
  takes in next must be only what was digested, not something a program inside wrote to the project meanwhile. So several `digest`s may
  come before one `citl read` (`digest` keeps the hash of what it wrote, `~/.local/share/citlalpol/swallow/digested.json`)
- when a destination of the file already matches the attempt: with `refuse`, a refusal someone wrote on purpose is changed by hand; with
  `pass`, the refusal had another reason (a `to` whose gate did not answer …), said in the row's `why`
- `to` outside the loopback, or to a port that is never reached — the same checks as `citl read`

**`residual <name>`.** Copies `last.tsv` to `~/.local/share/citlalpol/swallow/<name>.tsv` (letters, digits, `_`, `-`: no dot, so `<name>:3`
never looks like `host:port`); a kept one of the same name is replaced without asking. Kept tables are read with `cat` and named in `digest` as `<name>:<id>`; removing them is `rm`.

**What a table holds.** Only refused attempts, with the records' blanking already done — but **a name can itself carry data** (a
program that tries `<secret>.example.com` leaves that name, refused or not). Reading a table is the person's own business; before
showing a kept one to someone else, read it. The small tables live where the wall hides (the runtime directory and the state
directory, `citl setup`'s `forbidden hide add`): a program inside must not learn what was refused, to try something else.

## Looking at a program you do not trust

```
citl run <name> --strict --dir ./the-tool -- ./the-tool/install.sh
citl log --run <id>
```

The strength of the wall (files, sockets, processes, the terminal not shown) is forbidden's `--strict`. On Citlalpol's side: an undeclared
name is refused before it is resolved (always, not only here); it is advised **not to have any `pass`** (it would be the way out) — start
from an empty `access.json`; input from the door is read as untrusted (short, sturdy parsers with limits). The records are the result:
where the tool tried to go.

## How it is checked, in order

1. **forbidden alone**: inside `forbidden on`, `ping` and `curl` fail; after `off` they succeed.
2. **A small Citlalpol behind the door**: inside `forbidden on --door citlalpol`, `curl http://pong.citlalpol.test/ping` reaches the fake
   outside's pong through 4600; an undeclared destination does not.
3. **The ping steps** (an HTTP ping, since what passes the door is TCP that names its destination; that the wall stops ICMP is checked
   in 1):

| | Condition | Expected |
| --- | --- | --- |
| a | outside the wall | the pong answers on its local address (the program and server work) |
| b | inside, not declared | does not reach; refused at once, the record says "not declared" |
| c | declared with `to`, the local server (its gate) not running | does not reach; refused with why, recorded |
| d | declared with `to`, the zoozve gate and the pong running | reaches (`pong`); `sent_to` the gate, `to_auth: "zoozve"` |

A `to` at a local server without a gate, or a gate with another key, is refused too.

`test/run.sh` checks these and the rest of scope.md (62 checks) without reaching the network; `examples/demo/access.json` is the same
with zoozve's pong, to try by hand.

## Implementation

Elixir, no Mix (`main.exs` loads `lib/citlalpol/`); `bin/citl` is bash so that `citl run` can hand the terminal to forbidden itself.
Without Nix: [Citlalpol_without_nix](https://github.com/Crux-xurC/Citlalpol_without_nix) (a Mix project and a release).

| File | Role |
| --- | --- |
| `bin/citl` | the command; `run` prepares the run (`citl run-prepare`) and execs `forbidden run --door citlalpol` |
| `main.exs` | starts the Elixir side |
| `lib/citlalpol/cli.ex` | `start` / `stop` / `status` / `setup` / `read` / `use` / `label` / `log`; `swallow` / `digest` / `residual` go to `swallow.ex` |
| `lib/citlalpol/citld.ex` | citld: the door's unix socket, one process per connection under a Task.Supervisor |
| `lib/citlalpol/door.ex` | one connection: the PROXY v2 header, then SOCKS5, an HTTP proxy request or a catch-all connection; the decision; relaying |
| `lib/citlalpol/access.ex` | `access.json`: checking, copies, lookup |
| `lib/citlalpol/dns.ex`, `fake.ex` | the wall's DNS; fake addresses and their names |
| `lib/citlalpol/net.ex` | local addresses, resolving, connecting; the ports never reached |
| `lib/citlalpol/records.ex`, `redact.ex` | the records (one writer); blanking secrets |
| `lib/citlalpol/paths.ex`, `json.ex` | where things live; small JSON files |
| `lib/citlalpol/swallow.ex` | `swallow` / `digest` / `residual`: the small table from the records, the change to the project's `access.json` |

| Where | What |
| --- | --- |
| `$XDG_RUNTIME_DIR/citlalpol/` | the door's socket, citld's pid, `runs/`, `labels/`, `swallow/last.tsv` (hidden inside the wall) |
| `~/.config/citlalpol/` | `access/` (the copies), `registered.json`, `zoozve.key`, `gates.json`, `never.json` |
| `~/.local/share/citlalpol/records/` | the records |
| `~/.local/share/citlalpol/swallow/` | the small tables kept with `citl residual`; `digested.json` (what `digest` wrote last, per name) |

## What moved out

Earlier versions of the design (v0.2–v0.7, in the Japanese memo) had Citlalpol **start local programs** that answer for the outside
(stand-ins, `stand_ins.json`, passing the connection on stdin / an fd), with three **stages** — connect, what is sent, what should come
back — written by the designer in `access.json` (`stages`: `send` / `expect` / `reply` / `fire` / `verify`) and handled by
[swallow](https://github.com/Crux-xurC/swallow). Since v0.8 (2026-11-25) **making what answers is outside Citlalpol**: it only sends a
connection to a local address behind a zoozve gate, and records. swallow, as a tool that answers, was left with nothing to start it
and was given up (2026-11-27); its name went to `citl swallow`, which reads what was refused (above).

## Planned and open

- UDP and ICMP attempts in the records (now refused in the wall without a record), IPv6 through the catch-all
- Xipe Totec setting the label; whether to evaluate rows one at a time under Citlalpol
- how citld is started (a systemd user service, or by `citl` when needed)
- where `access.json` lives in a project (`.citlalpol/access.json`?)
- how long the records are kept; a limit on records per run when examining a program
- whether a refusal may be shown differently (refuse at once / keep waiting)
