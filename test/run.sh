#!/usr/bin/env bash
# test/run.sh -- Citlalpol with forbidden, on simple communication (docs/scope.md is what is checked):
# the order of checks of the design memo (1. forbidden alone is forbidden's own test; 2. a small
# Citlalpol through the door; 3. the ping in four steps), then pass / to / refuse / SOCKS5 / the records.
# Everything is its own: citld's runtime, state and config directories, forbidden's config, and a
# "pong" server on the host's loopback that stands for a local server the person runs, behind a zoozve
# gate. Nothing reaches the network. Needs forbidden and zoozve (CITLALPOL_FORBIDDEN / CITLALPOL_ZOOZVE,
# else on PATH), Elixir, python3 and curl (nix develop gives the last three).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$here/bin/citl"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
work="$(mktemp -d)"
export CITLALPOL_RUNTIME="$(mktemp -d "$runtime/citlalpol-test.XXXXXX")"
export CITLALPOL_STATE="$work/state" CITLALPOL_CONFIG="$work/config" FORBIDDEN_CONFIG_DIR="$work/forbidden"
export CITLALPOL_FORBIDDEN="${CITLALPOL_FORBIDDEN:-$(command -v forbidden || echo "$here/../forbidden/bin/forbidden")}"
Z="${CITLALPOL_ZOOZVE:-$(command -v zoozve || echo "$here/../zoozve/bin/zoozve")}"
fails=0
ok() { echo "  ok   $1"; }
ng() { echo "  FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ng "$1"; fi; }
last() { "$C" log --json | tail -1; }
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# the pong: an HTTP server on the host's loopback (the wall cannot reach it by itself)
pong_port="$(free_port)"
python3 - "$pong_port" >/dev/null 2>&1 <<'PY' &
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = b"pong\n" if self.path.startswith("/ping") else b"?\n"
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
pong_pid=$!
gate_pids=""
cleanup() { "$C" stop >/dev/null 2>&1; kill $pong_pid $gate_pids 2>/dev/null; rm -rf "$work" "$CITLALPOL_RUNTIME"; }
trap cleanup EXIT

"$C" start >/dev/null || { echo "citld did not start"; cat "$work/state/citld.log" 2>/dev/null; exit 1; }
"$C" setup >/dev/null
for _ in $(seq 1 30); do curl -s -m1 "http://127.0.0.1:$pong_port/ping" >/dev/null && break; sleep 0.1; done
# the pong behind a zoozve gate, with the key citl setup made (CITLALPOL_CONFIG/zoozve.key), and a gate with another key
gate_port="$(free_port)"
"$Z" --port "$gate_port" --to "127.0.0.1:$pong_port" 2>/dev/null &
gate_pids="$gate_pids $!"
python3 -c 'import secrets; print(secrets.token_hex(32))' > "$work/other.key"; chmod 600 "$work/other.key"
other_port="$(free_port)"
"$Z" --port "$other_port" --to "127.0.0.1:$pong_port" --key "$work/other.key" 2>/dev/null &
gate_pids="$gate_pids $!"
sleep 0.5

mk() { mkdir -p "$work/$1"; cat > "$work/$1/access.json"; "$C" read "$work/$1/access.json" "$1" >/dev/null 2>&1; }
nobody="$(free_port)"
mk empty <<'J'
{ "destinations": [] }
J
# a server at another loopback address, at the gate's own port, that passes everything on to the real gate
python3 - "$gate_port" >/dev/null 2>&1 <<'PY' &
import socket, sys, threading
p = int(sys.argv[1])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.2", p)); s.listen()
def pump(a, b):
    try:
        while (d := a.recv(65536)): b.sendall(d)
    except OSError: pass
    finally:
        try: b.shutdown(socket.SHUT_WR)
        except OSError: pass
def one(c):
    u = socket.create_connection(("127.0.0.1", p)); threading.Thread(target=pump, args=(u, c), daemon=True).start(); pump(c, u)
while True:
    c, _ = s.accept(); threading.Thread(target=one, args=(c,), daemon=True).start()
PY
gate_pids="$gate_pids $!"
sleep 0.3
mk decided <<J
{ "destinations": [
  { "host": "pong.citlalpol.test", "port": 80, "do": "pass", "to": "127.0.0.1:$gate_port" },
  { "host": "tls.citlalpol.test", "port": 443, "do": "pass", "to": "localhost:$gate_port" },
  { "host": "bare.citlalpol.test", "do": "pass", "to": "127.0.0.1:$pong_port" },
  { "host": "other.citlalpol.test", "do": "pass", "to": "127.0.0.1:$other_port" },
  { "host": "down.citlalpol.test", "do": "pass", "to": "127.0.0.1:$nobody" },
  { "host": "passon.citlalpol.test", "do": "pass", "to": "127.0.0.2:$gate_port" } ] }
J

echo "2. a small Citlalpol through the door"
out="$("$C" run decided -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
r="$(last)"
check "curl in the wall reaches the local server named by to (pong)" '[ "$out" = pong ]'
check "the record has the executable too, from the door's header (what the kernel runs)" '[[ "$r" == *"\"exe\": \"/"*curl\"* ]]'
check "the record has the run, the process (curl), the door's header and the decision" \
  '[[ "$r" == *"\"run\": \"c-"* && "$r" == *"\"cmd\": \"curl "* && "$r" == *"\"door\": \"proxy_v2\""* && "$r" == *"\"decision\": \"pass\""* ]]'
check "the record says where it was sent (sent_to) and that a zoozve gate answered" '[[ "$r" == *"\"host\": \"pong.citlalpol.test\""* && "$r" == *"\"sent_to\": \"127.0.0.1:$gate_port\""* && "$r" == *"\"to_auth\": \"zoozve\""* ]]'
out="$("$C" run decided -- curl -sS -m5 -w ' %{http_code}' http://bare.citlalpol.test/ping 2>/dev/null)"
check "a to at a local server that is not behind a gate: refused (the challenge is not answered)" '[[ "$out" == *"not a zoozve gate"*" 403" ]]'
out="$("$C" run decided -- curl -sS -m5 -w ' %{http_code}' http://other.citlalpol.test/ping 2>/dev/null)"
check "a gate with another key: refused" '[[ "$out" == *"another key"*" 403" ]]'
out="$("$C" run decided -- curl -sS -m5 -w ' %{http_code}' http://passon.citlalpol.test/ping 2>/dev/null)"
check "a server at another loopback address passing the challenge on to a real gate (same port): refused" '[[ "$out" == *"another key"*" 403" ]]'

echo "3. the ping in four steps"
check "a. outside the wall, the pong answers at its own address" '[ "$(curl -sS -m3 "http://127.0.0.1:$pong_port/ping")" = pong ]'
out="$("$C" run empty -- curl -sS -m5 -w ' %{http_code}' http://pong.citlalpol.test/ping 2>/dev/null)"
r="$(last)"
check "b. not in access.json: refused (403), recorded as such" '[[ "$out" == *"not in access.json"*" 403" && "$r" == *"\"decision\": \"refuse\""* ]]'
out="$("$C" run decided -- curl -sS -m5 -w ' %{http_code}' http://down.citlalpol.test/ping 2>/dev/null)"
r="$(last)"
check "c. declared, the local server not running: refused with why, recorded" \
  '[[ "$out" == *"does not answer"*" 403" && "$r" == *"\"decision\": \"refuse\""* && "$r" != *sent_to* ]]'
out="$("$C" run decided -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
check "d. declared and running: pong" '[ "$out" = pong ]'
line="$("$C" log | tail -1)"
check "citl log shows the request (GET /ping), the command and where it was sent" \
  '[[ "$line" == *"GET /ping"* && "$line" == *"[curl "* && "$line" == *"-> 127.0.0.1:$gate_port"* ]]'
"$C" run decided -- curl -sS -m5 "http://pong.citlalpol.test/ping?token=s3cret&x=1" >/dev/null 2>&1
check "a query's values are never recorded (names only)" '[[ "$(last)" == *"/ping?token=…&x=…"* && "$(last)" != *s3cret* ]]'
check "a long command is cut with …" '[[ "$("$C" log | tail -1)" == *"…]"* ]]'

echo "pass, to, refuse, SOCKS5, the rest"
mk local <<J
{ "destinations": [
  { "host": "127.0.0.1", "port": $pong_port, "do": "pass" },
  { "host": "localhost", "port": $pong_port, "do": "pass" },
  { "host": "upload.example.test", "do": "refuse", "why": "uploads never run while trying code" } ] }
J
out="$("$C" run local -- curl -sS -m5 --noproxy "" "http://127.0.0.1:$pong_port/ping" 2>/dev/null)"
check "pass to a local address is refused (an address)" '[[ "$out" == *"resolves to a local address"* ]]'
out="$("$C" run local -- curl -sS -m5 --noproxy "" "http://localhost:$pong_port/ping" 2>/dev/null)"
check "pass to a local address is refused (a name): only to reaches a local server" '[[ "$out" == *"only with to"* ]]'
mk never <<'J'
{ "destinations": [ { "host": "localhost", "port": 4100, "do": "pass" } ] }
J
out="$("$C" run never -- curl -sS -m5 --noproxy "" http://localhost:4100/ 2>/dev/null)"
check "tezcatl's relay port (4100) is never passed to" '[[ "$out" == *"never"* ]]'
out="$("$C" run local -- curl -sS -m5 http://upload.example.test/x 2>/dev/null)"
check "refuse in access.json: refused with its why" '[[ "$out" == *"uploads never run"* ]]'
out="$("$C" run decided -- curl -sS -m5 -x "socks5h://127.0.0.1:4600" http://pong.citlalpol.test/ping 2>/dev/null)"
check "SOCKS5 (socks5h: the name goes to Citlalpol) works the same" '[ "$out" = pong ] && [[ "$(last)" == *"\"proto\": \"socks5\""* ]]'
"$C" run decided -- curl -sS -m5 -x "socks5h://127.0.0.1:4600" http://not-declared.example/ >/dev/null 2>&1
check "SOCKS5: a name not in access.json is refused" '[[ "$(last)" == *"\"host\": \"not-declared.example\""*"\"decision\": \"refuse\""* ]]'
out="$("$C" run decided -- curl -sS -m5 https://tls.citlalpol.test/ 2>&1)"
check "https: CONNECT goes to the to, the TLS is not read (fails against a plain server, recorded)" \
  '[[ "$out" == *"curl: ("* ]] && [[ "$(last)" == *"\"proto\": \"connect\""*"\"decision\": \"pass\""* ]]'

echo "programs that ignore the proxy (the door catches all: nftables in the wall, citld's DNS)"
out="$("$C" run decided -- curl -sS -m5 --noproxy "*" -w ' %{remote_ip}' http://pong.citlalpol.test/ping 2>/dev/null)"
check "no proxy: the declared name gets a fake address and reaches the to (pong)" '[[ "$out" == "pong"*" 198.1"[89]"."* ]]'
r="$(last)"
check "...recorded as tcp via redirect, with the name, the fake address, the process and sent_to" \
  '[[ "$r" == *"\"via\": \"redirect\""* && "$r" == *"\"proto\": \"tcp\""* && "$r" == *"\"host\": \"pong.citlalpol.test\""* && "$r" == *"\"address\": \"198.1"* && "$r" == *"\"cmd\": \"curl "* && "$r" == *"\"sent_to\": \"127.0.0.1:$gate_port\""* ]]'
check "...and its DNS question as dns, answered with the fake address" \
  '"$C" log --json | grep "\"proto\": \"dns\"" | grep "\"method\": \"A\"" | grep -q "\"answer\": \"198.1"'
out="$("$C" run decided -- curl -sS -m5 --noproxy "*" http://not-declared.example/ 2>&1)"
r="$("$C" log --json | grep "\"proto\": \"dns\"" | tail -1)"
check "no proxy: a name not declared does not resolve, refused at the question" \
  '[[ "$out" == *"Could not resolve"* && "$r" == *"\"host\": \"not-declared.example\""*"\"decision\": \"refuse\""* ]]'
"$C" run decided -- curl -sS -m5 --noproxy "*" http://203.0.113.9:8080/ >/dev/null 2>&1
check "no proxy: an address not declared is refused, recorded" '[[ "$(last)" == *"\"host\": \"203.0.113.9\""*"\"decision\": \"refuse\""* ]]'
out="$("$C" run decided -- python3 -c '
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try: s.sendto(b"x", ("203.0.113.9", 9)); print("sent")
except OSError: print("refused")' 2>/dev/null)"
check "other UDP is refused at once (not recorded: planned)" '[ "$out" = refused ]'

echo "labels (set from outside the wall)"
"$C" run decided -- sh -c 'sleep 3; curl -sS -m5 http://pong.citlalpol.test/ping' > "$work/label.out" 2> "$work/label.err" &
lp=$!
for _ in $(seq 1 50); do grep -q "citl: run " "$work/label.err" 2>/dev/null && break; sleep 0.1; done
lrun="$(sed -n 's/^citl: run \([^ ]*\).*/\1/p' "$work/label.err")"
"$C" label "$lrun" row-7 calc >/dev/null
wait $lp
check "a label set while the run goes on is in its records" '[ "$(cat "$work/label.out")" = pong ] && [[ "$(last)" == *"\"label\": \"row-7 calc\""* ]]'
check "citl log --label picks them" '[ "$("$C" log --json --label "row-7 calc" | wc -l)" -ge 1 ] && [[ "$("$C" log --label "row-7 calc" | tail -1)" == *"{row-7 calc}"* ]]'
check "a label cannot be set from inside the wall" '! "$C" run decided -- "$C" label "$lrun" forged 2>/dev/null'
"$C" label "$lrun" --clear >/dev/null
check "--clear removes it" '[ ! -e "$CITLALPOL_RUNTIME/labels/$lrun" ]'

echo "citl read refuses what is not Citlalpol's"
bad() { mkdir -p "$work/bad"; echo "$1" > "$work/bad/access.json"; ! "$C" read "$work/bad/access.json" bad 2>/dev/null; }
check "a program to start" 'bad '"'"'{ "destinations": [ { "host": "x.test", "do": "pass", "exec": ["sh"] } ] }'"'"
check "a stand-in (do: stand_in)" 'bad '"'"'{ "destinations": [ { "host": "x.test", "do": "stand_in" } ] }'"'"
check "a to outside this machine" 'bad '"'"'{ "destinations": [ { "host": "x.test", "do": "pass", "to": "example.com:80" } ] }'"'"
check "a to at a port that can act outside the wall (4100)" 'bad '"'"'{ "destinations": [ { "host": "x.test", "do": "pass", "to": "127.0.0.1:4100" } ] }'"'"
check "allow_local (gone)" 'bad '"'"'{ "destinations": [ { "host": "localhost", "do": "pass", "allow_local": true } ] }'"'"
check "a to with do: refuse" 'bad '"'"'{ "destinations": [ { "host": "x.test", "do": "refuse", "to": "127.0.0.1:9" } ] }'"'"

echo "what is in force is the copy citl read took (the wall cannot change it)"
mk copy <<J
{ "destinations": [ { "host": "pong.citlalpol.test", "port": 80, "do": "pass", "to": "127.0.0.1:$gate_port" } ] }
J
"$C" run copy -- sh -c "echo '{ \"destinations\": [] }' > '$work/copy/access.json'" 2>/dev/null
out="$("$C" run copy -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
check "the project's access.json changed (here from inside the wall): the copy still applies" '[ "$out" = pong ]'
check "citl status says it changed and is not in force" '"$C" status | grep -q "copy .*changed since it was read"'
"$C" read "$work/copy/access.json" copy >/dev/null
out="$("$C" run copy -- curl -sS -m5 -w ' %{http_code}' http://pong.citlalpol.test/ping 2>/dev/null)"
check "read again from outside: the change is in force" '[[ "$out" == *" 403" ]]'
check "inside the wall, citl's config (the copies) is hidden" '! "$C" run copy -- ls "$CITLALPOL_CONFIG/access" 2>/dev/null'
check "inside the wall, the records are hidden" '! "$C" run copy -- ls "$CITLALPOL_STATE/records" 2>/dev/null'
check "citl read is refused inside the wall" '! "$C" run copy -- "$C" read "$work/copy/access.json" copy 2>/dev/null'

echo "from the records to access.json: swallow, digest, residual"
mk sw <<'J'
{ "destinations": [
    { "host": "upload.sw.test", "do": "refuse", "why": "never" } ] }
J
"$C" run sw -- sh -c 'curl -sS -m5 http://pong.citlalpol.test/ping; curl -sS -m5 http://pong.citlalpol.test/ping; curl -sS -m5 --noproxy "*" http://dns-only.sw.test/' >/dev/null 2>&1
t="$("$C" swallow 2>/dev/null)"
row() { printf '%s\n' "$t" | awk -F'\t' -v h="$1" -v p="$2" '$2 == h && $3 == p'; }
check "swallow: the last run's refused attempts, one row a destination (twice -> count 2)" \
  '[[ "$(row pong.citlalpol.test 80 | cut -f6)" == 2 && "$(row pong.citlalpol.test 80 | cut -f7)" == sw ]]'
check "...stopped at the DNS question: no port, stopped dns" '[[ "$(row dns-only.sw.test - | cut -f5)" == dns ]]'
check "...written to the runtime as a table cat reads (header, tabs)" \
  '[ "$(cat "$CITLALPOL_RUNTIME/swallow/last.tsv")" = "$t" ] && sed -n 2p "$CITLALPOL_RUNTIME/swallow/last.tsv" | grep -q "^id	host	port"'
pid_="$(row pong.citlalpol.test 80 | cut -f1)"
dns_="$(row dns-only.sw.test - | cut -f1)"
check "swallow, digest and residual are refused inside the wall" \
  '! "$C" run sw -- "$C" swallow 2>/dev/null && ! "$C" run sw -- "$C" digest "$pid_" pass 2>/dev/null && ! "$C" run sw -- "$C" residual x 2>/dev/null'
check "digest says what to do (no word: refused)" '! "$C" digest "$pid_" 2>/dev/null'
"$C" digest "$pid_" to "127.0.0.1:$gate_port" --why "the pong" >/dev/null
check "digest writes the project's access.json, the new destination first" \
  'python3 -c "import json,sys; d=json.load(open(sys.argv[1]))[\"destinations\"]; sys.exit(not (d[0]==dict(host=\"pong.citlalpol.test\",port=80,do=\"pass\",to=\"127.0.0.1:$gate_port\",why=\"the pong\") and d[1][\"host\"]==\"upload.sw.test\"))" "$work/sw/access.json"'
out="$("$C" run sw -- curl -sS -m5 -w ' %{http_code}' http://pong.citlalpol.test/ping 2>/dev/null)"
check "...but not the copy: still refused until citl read" '[[ "$out" == *" 403" ]]'
"$C" residual swtest >/dev/null
check "residual keeps the table in the state directory" '[ "$(cat "$CITLALPOL_STATE/swallow/swtest.tsv")" = "$t" ]'
"$C" digest "swtest:$dns_" pass >/dev/null
check "a second digest before citl read, from a kept table (<name>:<id>): a destination with no port" \
  'python3 -c "import json,sys; d=json.load(open(sys.argv[1]))[\"destinations\"]; sys.exit(not (d[0]==dict(host=\"dns-only.sw.test\",do=\"pass\") and len(d)==3))" "$work/sw/access.json"'
check "digest writes *. only with refuse" '! "$C" digest "*.wide.sw.test" pass --name sw 2>/dev/null && ! "$C" digest "*.wide.sw.test" to "127.0.0.1:$gate_port" --name sw 2>/dev/null'
check "digest over a refusal written on purpose: refused" '! "$C" digest upload.sw.test pass --name sw 2>/dev/null'
check "digest over a destination declared already: refused" '! "$C" digest "$pid_" pass 2>/dev/null'
"$C" read "$work/sw/access.json" sw >/dev/null
out="$("$C" run sw -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
check "citl read: the digested destination is in force (pong)" '[ "$out" = pong ]'
"$C" run sw -- sh -c "echo '{ \"destinations\": [] }' > '$work/sw/access.json'" 2>/dev/null
check "the project's file changed by something else: digest refuses" '! "$C" digest other.sw.test pass --name sw 2>/dev/null'
"$C" read "$work/sw/access.json" sw >/dev/null

echo "runs, walls without a run, the door"
check "citl log --run picks one run" '[ "$("$C" log --json | head -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[\"run\"])" | xargs -I{} "$C" log --json --run {} | wc -l)" -ge 1 ]'
"$C" use decided >/dev/null
out="$("$CITLALPOL_FORBIDDEN" run --door citlalpol -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
check "forbidden alone (citl use): the access.json in use applies" '[ "$out" = pong ]'
out="$(python3 - "$CITLALPOL_RUNTIME/door.sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
s.sendall(b"GET http://pong.citlalpol.test/ping HTTP/1.1\r\nHost: pong.citlalpol.test\r\n\r\n")
b = b""
while True:
    d = s.recv(4096)
    if not d: break
    b += d
print(b.decode().split("\r\n\r\n", 1)[-1].strip())
PY
)"
check "straight to the socket, without the PROXY header: answered, recorded as door none" '[ "$out" = pong ] && [[ "$(last)" == *"\"door\": \"none\""* ]]'
out="$("$C" run decided --strict -- curl -sS -m5 http://pong.citlalpol.test/ping 2>/dev/null)"
check "--strict through citl run: still pong" '[ "$out" = pong ]'
"$C" stop >/dev/null
out="$("$CITLALPOL_FORBIDDEN" run --door citlalpol -- curl -sS -m3 http://pong.citlalpol.test/ping 2>&1)"
check "citld stopped: nothing goes through" '[[ "$out" == *"nothing listens"* || "$out" == *"curl: ("* ]]'

echo
if [ "$fails" -eq 0 ]; then echo "all ok"; else echo "$fails failed"; exit 1; fi
