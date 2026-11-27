# Scope

What Citlalpol promises to work, what happens outside that, and what a person does there. Each promise has one sentence of why.
The design: [design.md](design.md); how it came about, in Japanese: [ja/design-memo.md](ja/design-memo.md), [ja/idea.md](ja/idea.md). The wall itself is
[forbidden](https://github.com/Crux-xurC/forbidden)'s, with its own scope.

**Status (2026-11-25).** citld and `citl` are in Elixir (`main.exs`, `lib/citlalpol/`; `bin/citl` hands the terminal to forbidden
for `citl run`) and do what the rows below promise; `test/run.sh` checks them (62 checks, no network; zoozve has its own). Rows marked *(planned)* are not
done yet. (A first plain version in python3, with stand-ins, came before; it is not kept.)

## How to read it (for people and AI reviewing or verifying)

- Something **inside the scope** that does not work is a bug: report it with steps to reproduce
- Something **outside the scope** that happens as written below is not a bug. Report it only if
  1. something other than what is written happens,
  2. a connection reaches a destination that `access.json` does not name, or
  3. an attempt to go out leaves no record although it came through the door (a silent pass or a silent refusal)
- A boundary not in these tables: ask whether it is inside or outside before reporting it as a bug; once decided, add a row here
- When the scope changes (something outside comes inside, or the reverse), change this document

## What Citlalpol is for

A program being developed or evaluated (a REPL under Xipe Totec, a test run, a program one does not trust) should not go out to the
network by itself. forbidden turns "an exit anyone can take" into "no exit but one door"; Citlalpol stands behind that door and turns it
into "an exit only where it was declared", writing down every attempt. **Preparing what answers on the other side is not Citlalpol's
job**: a destination is either the real one or a local server the person runs themselves (the same version of a database, a stub),
and Citlalpol only sends the connection there and records it.

## Inside the scope

| Promise | Why (one sentence) |
|---|---|
| **The development release** runs with Nix: `nix develop` gives Elixir/OTP from a pinned nixpkgs (the same revision as tezcatl and Xipe Totec); forbidden is the person's own (on `PATH`, beside this repository, or `CITLALPOL_FORBIDDEN`). Without Nix: [Citlalpol_without_nix](https://github.com/Crux-xurC/Citlalpol_without_nix) | A contract test should start from a fixed environment, the same for everyone who runs it. |
| Citlalpol answers **only what comes through forbidden's door** (`127.0.0.1:4600` inside the wall, a unix socket outside): SOCKS5 (CONNECT) and HTTP proxy requests (`http://` URLs and `CONNECT`) | The client names its destination itself, so no DNS trick is needed to know where it wanted to go. |
| **Programs that ignore the proxy settings** (most database drivers, many CLIs, a `curl --noproxy`) are judged the same way: `citl setup` makes the door one that catches all (forbidden's `--catch-all`, nftables), so their TCP connections (IPv4) come to citld with where they were going and who opened them, and every DNS question in the wall (UDP or TCP port 53, to any server) comes to citld too | A program should not get out, or go unseen, just because it does not read the proxy variables. |
| **citld answers the wall's DNS**: a name `access.json` does not declare (or declares as `refuse`) gets NXDOMAIN and is recorded as refused, never asked of a real resolver; a declared name gets a fake address from `198.18.0.0/15` for A (no data for other types), and a connection to that address is judged as the name — `pass`, `to`, `refuse` as above — with the fake address kept in the record (`address`) | The name is the thing declared, and asking a resolver outside would already send it out. |
| **Whatever `access.json` does not name is refused**, before the name is resolved; there is no setting that changes this default | A name sent to a resolver can carry data out by itself. |
| **What is in force is the copy `citl read` took** (`~/.config/citlalpol/access/<name>.json`), never the project's file: a change to the project's `access.json` counts only when it is read again, from outside the wall (`citl read` refuses inside); `citl status` says when the project's file differs from what was read | A program inside the wall can write the project, and loosening must stay a person's act. |
| Inside the wall **Citlalpol's own config and records are hidden** (`citl setup` asks forbidden to: `forbidden hide add`), and forbidden's config is read-only there | The copies, the labels and the records must be neither changed nor read by the program they judge. |
| `pass` without `to` goes to the **real destination** (e.g. an API the program legitimately uses: it passes, and it is seen in the records) | Ordinary traffic need not be restricted further, only made visible. |
| `pass` with `to: "<host>:<port>"` goes to **that local address** instead; `to` may name only a local address (loopback), checked by `citl read` and again at each connection | `access.json` is committed with the project, and a `to` pointing anywhere outside would be an undeclared exit. |
| **A `to` reaches only a [zoozve](https://github.com/Crux-xurC/zoozve) gate of this machine**: at the head of each connection citld sends a challenge (zoozve/2) and relays only when the answer is HMAC-SHA256 of this machine's key (`~/.config/citlalpol/zoozve.key`, made by `citl setup`, hidden inside the wall) over the nonce and the address and port citld connected to (so a server elsewhere passing the challenge on to a real gate is refused); otherwise refused, and the record says why (`to_auth: "zoozve"` when it passed). Behind the gate is any server the person chose; what a gate proves and what not is [zoozve's scope](https://github.com/Crux-xurC/zoozve/blob/main/docs/scope.md) | The address in a committed file must not be able to reach whatever happens to listen on this machine (a database, a development server, a daemon's API); a gate is the person's own "this may answer for the outside". |
| `pass` to a destination that resolves to a local address is refused (`allow_local` is gone); a local server is reached only with `to` | A committed file could otherwise point at the machine's own services. |
| **Never** to tezcatl's pages, the relay, Emacs or Xipe Totec (`4000`, `4001`, `4100`, `4200` on loopback), not even with `to` | Those programs can act outside the wall (run commands, edit files), so reaching them is going out. |
| The PROXY protocol v2 header that forbidden's door puts in front of each connection is **read and removed**: never sent on to the destination | The header is between forbidden and Citlalpol; the destination should see the same bytes as without Citlalpol. |
| **Every attempt is one JSON line** in the records (`~/.local/share/citlalpol/records/`): when, the run and its label, the process inside the wall (pid, command, executable, mode — from the PROXY header), `door` (`proxy_v2` or `none`), `via` (`redirect` / `dns` from the catch-all), the protocol (`socks5`, `http`, `connect`, `tcp`, `dns`), the destination as named (and the fake `address`), the request line of plain HTTP or the DNS question's type, the decision and the rule that made it, `sent_to` (the address actually connected to) or the DNS `answer`, bytes each way, time, and why when refused | "Removed the header and sent it to XX" must be readable from one line, without guessing. |
| Values of a query, `Authorization` / `Cookie` / API-key headers and the usual secret-bearing arguments of a command line are blanked before anything is written | The records are read in tezcatl and elsewhere; secrets must not end up in them. |
| `citl label <run> <label>` (or `--clear`) names what a run is doing now — e.g. the row of Xipe Totec being evaluated — and every attempt of that run from then on carries it (`label`); it works only from outside the wall (the labels are in the runtime directory the wall hides) | A program inside must not be able to put its attempts under another name. |
| `citl log` shows the records (`--run`, `--label`, `--since`, `--decision`, `--json`); tezcatl's Citlalpol panels read the same files, read only | Looking at the records never changes what the wall lets through. |
| `citl swallow` gathers the refused attempts (the last run, or `--run` / `--label` / `--since`) into a small table, one row a destination, printed and written to `$XDG_RUNTIME_DIR/citlalpol/swallow/last.tsv` (replaced by the next one; read with `cat`); `citl residual <name>` keeps it in `~/.local/share/citlalpol/swallow/` (replaced without asking) | Deciding the next step of the loop needs where the program wanted to go, not every line of the records. |
| `citl digest <id \| name:id \| host[:port]> pass \| to <host>:<port> \| refuse` writes one destination, first, into **the project's** `access.json`, never the copy in force (`citl read` applies it); what to do is always written; it refuses inside the wall, when the project's file differs from the copy by more than what digest wrote, and over a destination already declared ([design.md](design.md#from-the-records-to-accessjson-swallow-digest-residual)) | Loosening stays a person's act, and a change a program inside made to the project must not come in with it. |
| The small tables hold refused attempts only, blanked as the records are, and live where the wall hides them | A program inside must not learn what was refused; a name can still carry data, so a kept table is read before it is shown to anyone |
| `citl run <name> -- <command>` runs the command inside forbidden with the door to Citlalpol and `<name>`'s `access.json`; `citl use` sets what applies to `forbidden on` in a terminal | Running under the wall should be one command, not a set of steps to remember. |

## Outside the scope (what happens, and what a person does)

| What | What happens | What a person does |
|---|---|---|
| **Making what answers**: stand-ins, recorded replies, the expected answers of a contract ([design.md](design.md#what-moved-out), "What moved out") | Citlalpol starts no program and answers nothing itself; a `pass` with `to` reaches the zoozve gate the person runs at that address, or is refused (recorded) | Run the local server (a database of the same version, a stub), a zoozve gate in front of it, and name the gate in `to` |
| **`*.` with a plain `pass`** (`*.example.com`) | `*.` is safe with `refuse`, however wide, and with `pass` + `to` (the name is never resolved). With a plain `pass` it lets through every name under it: each name is resolved by the real resolver when a connection is made (a label can carry data: `c2VjcmV0.example.com` reaches example.com's name servers even if the connection then fails), and on a shared platform (`*.amazonaws.com`, `*.githubusercontent.com`) the hosts under it include other people's | Use it while trying things out if you must; for real runs, let the attempts be refused, then `citl swallow` → `citl digest` declares each host by its own name (`digest` writes `*.` only with `refuse`) |
| **`localhost` inside the wall** | It is the wall's own loopback: it never reaches the host, Citlalpol or the person's local servers, and leaves no record | Point the program at a name (`db.example.com`) and declare that name with `to`; this is on purpose — what the person runs locally is named, not reached by accident |
| **A door without the catch-all** (`citl setup --no-catch-all`, or no nftables) | Programs that ignore the proxy fail at once inside the wall (no route, no resolver) and leave **no record in Citlalpol** | Use the catch-all (`citl setup`), or configure the program to use the proxy |
| **A connection refused through the catch-all** | The program is not told why (it used no proxy that could answer): its connection is closed at once; the why is in the record | Read `citl log` |
| **What a record can be trusted for** | What Citlalpol decides or sees itself and what is set outside the wall holds (time, `run`, `label`, `mode`, `door`, `via`, the destination as named, the decision, `sent_to`, the bytes). What comes from inside is the program's word: `cmd` is the process's command line, which it can rewrite; `exe` (the file the kernel runs) is harder to fake but an interpreter's for a script; `pid` is the first holder of the socket; the request line is what the client sent. The same holds for `citl swallow`'s `command` / `exe` and tezcatl's citlalpol_log | Read `cmd` as a hint about who tried; tie an attempt to what was running by `run` and `label`, which only the outside sets |
| **Fake addresses after citld restarts** | The table of fake addresses lives in citld only: a program that kept an address from before is refused (an undeclared address); it resolves again next time | — |
| **TLS contents** | `CONNECT` is passed through without decrypting; Citlalpol sees the name and the bytes counted, never the request inside | If the request must be seen, have the program talk plain HTTP to a local server named with `to` |
| **A `to` server over TLS** | The client checks the certificate as it would the real one; a local server without a certificate the client trusts fails the handshake (a safe failure) | Make the client trust the local server's certificate, or use plain HTTP locally |
| **UDP (but DNS), ICMP, IPv6 (but the loopback), IP literals** | UDP, ICMP and IPv6 are refused at once inside the wall and leave no record in Citlalpol; a connection to an IP literal (IPv4) is refused and recorded unless `access.json` names that IP | Declare the IP when it is meant; *(planned: records of UDP / ICMP attempts)* |
| **Programs not run inside forbidden** | Citlalpol sees nothing of them | Run them with `citl run` or in a `forbidden on` terminal |
| **Hostile programs** | Only forbidden's promise holds ("ordinary means do not get out", with `--strict`); Citlalpol adds the records | Use a virtual machine for real malware |
| **Platforms** | Linux only (forbidden uses network namespaces) | — |

## Planned

| What | Where |
|---|---|
| UDP and ICMP attempts in the records (refused), IPv6 through the catch-all | M6 |
| Xipe Totec sets the label (the row's id) before evaluating a row | Xipe Totec; [design.md](design.md#the-loop-with-xipe-totec-loosening-the-wall-one-step-at-a-time) |
| How long the records are kept | [design.md](design.md#planned-and-open) |
