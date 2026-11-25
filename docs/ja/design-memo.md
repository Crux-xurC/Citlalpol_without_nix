# Citlalpol 設計メモ v0.11

2026-11-24 · @Crux（v0.2：Xipe Totec で回す繰り返し、三つの段階、ローカルのプログラムの起動と verify、抜け道、記録の秘密。
v0.3：段階 2・3 は設計者が access.json に書く、応答と照合は別リポジトリ swallow、プログラムへの渡し方。
v0.3.1：決まっていないところのデフォルトは swallow。
v0.4：Citlalpol の本体は「偽の外」、権限の位置、forbidden（端末で on / off）、ping の 4 段の受け入れ。
v0.5：壁は別リポジトリ forbidden、Citlalpol は扉の向こうの 4600、access.json にないものは全面禁止、確かめる順序。
v0.6：PROXY protocol v2 を扉の socket からだけ受ける、記録に pid とコマンド、他人のプログラムを調べる使い方。
v0.7：素朴な版を実装した（「実装」の節）。
v0.8（2026-11-25）：範囲を [../scope.md](../scope.md) にまとめた。代役の用意（起動・stdio / fd / addr・stand_ins.json・swallow を既定）は
Citlalpol の範囲外。`pass` に送り先 `to`（ローカルのアドレスだけ）、記録に `door` と `sent_to`。proxy を読まないプログラムは TUN・
tun2socks・fake-IP の DNS で（forbidden F5 と M6）。この文書の代役・段階 2・3・verify の節は経緯として残す。
v0.9（2026-11-25）：proxy を読まないもの（t-33）は TUN・tun2socks ではなく forbidden の `--catch-all`（nftables の REDIRECT と
SO_ORIGINAL_DST）で：tun2socks を挟むと記録の pid とコマンドが失われるため。citld が壁の DNS に答え、宣言した名前に 198.18.0.0/15 の
仮のアドレス。名札（t-27）は制御用 socket ではなく、壁から隠れる runtime の `labels/<run>` に `citl label` が書き、citld が接続ごとに
読む（citld が再起動しても残り、壁の中からは名前も書けない）。
v0.10（2026-11-25、レビューの指摘から）：効くのは citl read が写し取った写し（`~/.config/citlalpol/access/<name>.json`）で、プロジェクトの
access.json が壁の中から書き換えられても、壁の外で読み直すまで効かない。壁の中では Citlalpol の設定と記録を隠す（forbidden の
`hide`。forbidden の設定は読み取り専用）。`allow_local` は廃止し、ローカルへは `to` だけ。`to` の先は zoozve（別リポジトリの門番：
接続の頭で HMAC のチャレンジ・レスポンス、通れば後ろの任意のサーバーへ中継）に限る予定。詳しくは scope.md。
v0.11（2026-11-25）：zoozve（https://github.com/Crux-xurC/zoozve、python3 の単体）を作り、`to` はその門番にだけ繋ぐ。取り決め zoozve/1：
`ZOOZVE/1 <nonce>` に `ZOOZVE/1 OK <HMAC-SHA256(鍵, "zoozve/1 <nonce> <門番のポート>")>` で答える。鍵は `citl setup` が
`~/.config/citlalpol/zoozve.key` に作り、壁の中では隠れる。ポートを含めるのは、他のポートのサーバーが本物の門番へ問いを
取り次いでも答えが合わないようにするため。記録に `to_auth`）

**範囲（何が約束され、何が範囲外か）は [../scope.md](../scope.md) が正です。** 下の節と食い違うときは scope.md に従います。

## 概要

Citlalpol（コマンド名 `citl`）は、開発中に走らせるプログラムが勝手にネットワークへ出ないようにする道具の、**扉の向こう側**です。

**Citlalpol の本体は「偽の外」です。** 対象のプロセスから見える外の世界——繋げば出てくる相手（代役）、本物へ通す窓、すべての試みを
書き留める記録のデーモン（citld）——を Citlalpol が用意します。壁（外への道をなくすこと）は別のリポジトリ
[forbidden](https://github.com/Crux-xurC/forbidden) が受け持ち、その壁に開けた一つの扉（壁の中の `127.0.0.1:4600`）の向こうに
Citlalpol がいます。

- **すること**：4600 で受けた接続を、宛先ごとに**通す**か**ローカルの代役へ回す**。`access.json` に書かれていない宛先は**全面禁止**
  （既定を変える設定は持たない）。すべての試みを記録する。
- **宛先の宣言**：アプリケーションがアクセスする先は、作る段階で分かっているはずです。それを `access.json` に書いてもらい、
  `citl read` で読み込みます。
- **記録**：記録はデーモン（`citld`）が持ちます。`citl` で「この 10 分」「この実行」「全部」などの単位で引けます。
- **使われ方の中心**：Xipe Totec で対象のリポジトリの関数を、forbidden の壁の中で評価し、止まったところを記録し、記録から
  `access.json` を一段ずつゆるめては評価し直す繰り返し（「Xipe Totec で回す」の節）。
- **もう一つの使い方：他人のプログラムを調べる**：安全性の分からないプログラムを `forbidden run --strict --door citlalpol` の中で
  動かし、Citlalpol という偽の外だけを相手にさせて、どこへ出ようとするかを記録する（「他人のプログラムを調べる」の節）。
- **使い方の約束**：Citlalpol を使って契約テストをするときは、forbidden を入れた上で実行し、契約テストが不用意に外へ出ないことを
  確かめてください（`forbidden on --door citlalpol`、または `citl run`）。
- **しないこと**：壁（forbidden）、ファイルや外部の状態の隔離（sandbox）、悪意のあるコードを閉じ込める保証、プロトコルの解釈と
  応答の中身を作ること（それは Citlalpol が起動するローカルのプログラム＝代役と照合のプログラム、標準は swallow）。
- **対象**：Linux（forbidden が network namespace を使うため）。
- **状態**：素朴な版が動く（2026-11-24、`test/run.sh` の 20 項目。forbidden・swallow と一緒に、ネットワークに出ずに）。始まりの話は
  [idea.md](idea.md)。

## 壁は forbidden、Citlalpol は扉の向こうの 4600

```
 forbidden の壁の中                                  壁の外
┌──────────────────────────────────┐            ┌──────────────────────────────────┐
│ 対象（テスト、REPL、端末）       │            │ citld（Citlalpol のデーモン）    │
│   proxy の環境変数に従い、       │            │   ├ access.json：書かれた宛先だけ │
│   宛先を名乗って 4600 へ         │  unix      │   │   通す / 代役へ。他は全面禁止 │
│        │                         │  socket    │   ├ 記録する                     │
│ 127.0.0.1:4600（扉）  ───────────┼───────────▶│   └ 代役・swallow を起動する     │
│ ほかの経路なし                   │            │                                  │
└──────────────────────────────────┘            └──────────────────────────────────┘
```

- **壁は forbidden**：forbidden が user namespace と network namespace を作り、その中で対象を起動します。中には自分だけの loopback と
  扉しかありません。壁の作り方、扉の中継、unix socket を通した肩代わりという抜け道、user namespace が使えない環境の扱いは
  forbidden の設計メモにあります
- **Citlalpol は扉の向こうだけ**：citld は扉から届いたものを受けます。4600 は**壁の中にだけ**開くので、その機械の他のプロセスが
  citld に「外へ通して」と頼むことはできません
- **扉で話すもの**：SOCKS5（`socks5h`：名前も Citlalpol が引く）と HTTP proxy（`CONNECT` と、平文の HTTP の絶対 URL）。どちらも
  **宛先を接続の最初に名乗る**ので、Citlalpol は名前とポートを確実に知り、DNS の細工や宛先ごとのアドレスが要りません
- **権限の位置**：要るのは「壁を作る側が親で、対象から見える外は扉だけ」の一つで、これは forbidden の性質です。対象が扉の中継を
  止めても外へ出る道がなくなるだけで、安全側に倒れます。記録の正しさ（名札を偽られない）は、名札を壁の外から付ける形にして守ります
  （「label」の節）。悪意のあるコードを閉じ込める保証は範囲外です
- **proxy の設定を読まないアプリ**は壁で止まります（外へは出ない）。ただしその試みは扉に届かないので記録に残りません。記録に
  載せるのは forbidden の後の段階（壁の中の名前解決と透過的な受け口）です

### 扉の socket と PROXY protocol v2

forbidden の扉の中継は、接続の最初に HAProxy の PROXY protocol v2 のヘッダーを付けて届けます（forbidden の設計メモ）。

- **信じるのは扉の socket から来た接続だけ**：citld は PROXY のヘッダーを、forbidden の扉の unix socket（`$XDG_RUNTIME_DIR/citlalpol/`、
  0700、壁の中には見せない）で受けた接続でだけ読みます。TCP のポートで受けた接続のヘッダーは読みません（PROXY protocol 一般の注意）
- **v2 の TLV に載るもの**：実行の id、壁の中で接続を開いたプロセスの pid とコマンド（中継が `/proc` から引いたもの）。番号と形は
  forbidden と一緒に決めます（未決）
- これで記録は「どの実行の、どのプロセスが、どこへ」まで持てます。壁の中の接続元はどれも `127.0.0.1` ですが、その先が分かります
- 代役が PROXY protocol を受けられる既製のサーバー（nginx など）なら、citld はヘッダーをそのまま渡せます（`stand_ins.json` に
  `"proxy_protocol": "v2"`）。代役の側でも「どのプロセスからか」が分かります

### citl run

`citl run [<name>] -- <command>` は `forbidden run --door citlalpol -- <command>` の短縮形で、実行（run）の id を citld に登録してから
起動します。端末では `forbidden on --door citlalpol` を使います。

## HTTPS

曲げても、クライアントは「`api.example.com` の正しい証明書か」を確かめます。なので宛先ごとの動作はこうなります。

| 動作 | HTTPS での結果 |
| --- | --- |
| 遮断（何も用意しない） | 接続を切る。クライアントは接続エラーになる |
| 通す | `CONNECT host:443` を受け、復号せずに本物へ転送する（宛先は CONNECT が名乗る） |
| 代役へ曲げる | 代役が `api.example.com` の証明書を出せない限り、クライアントの検証で失敗する。応答を返すには (a) ローカルの CA を対象のプロセスに信頼させる（言語ごとの対応：`SSL_CERT_FILE`、`NODE_EXTRA_CA_CERTS`、Erlang の cacerts、Python の certifi …）か、(b) アプリの設定で `http://` の代役を向いてもらう。証明書を固定（ピン留め）しているアプリは (a) でも不可 |

M1 は「禁止」と「通す」だけ、M2 で「代役へ曲げる」を TLS なし（HTTP、DB、その他の TCP）にかぎって足し、CA の方式は M4 です（マイルストーンの節）。

## 三つの段階：接続・送る中身・返ってきてほしいもの

一つの試みを三つの段階に分けて記録し、宣言します。段階ごとに、必要なものと分かることが違います。

| 段階 | 分かること | 何が要るか | 外に出るか |
| --- | --- | --- | --- |
| 1. 接続（安全な通信か） | 名前、ポート（扉で名乗られる）、プロトコル。TLS なら ClientHello の SNI・ALPN・版 | TCP を受け、最初のバイトを読んで閉じるだけ | 出ない。全部遮断のままでも取れる |
| 2. 何を送るか | HTTP ならメソッド・パス・ヘッダー・本文。他のプロトコルなら最初の要求 | 平文は読める。TLS の中身は復号が要る（ローカルのプログラムに借りる。対象にローカルの CA を信頼させる仕事は Citlalpol に残る） | 出ない |
| 3. 何を送ったら何が返ってきてほしいか | 要求と応答の組 | 人が書くか、代役が計算する。本物との照合は verify | verify のときだけ出る |

- **不要な遮断が減る**：段階 1 だけなら宛先単位の許可・遮断しかできません。段階 2 があれば「`GET /status` は通すが
  `POST /charge` は遮断する」と、要求の単位で決められます
- **代役の要件定義になる**：段階 2 で集めた要求の一覧が「代役が答えるべきもの」の一覧になり、段階 3 で応答を書けば代役の仕様になります
- 記録の 1 件は、どの段階まで進み、どこで止まったか（`stage`、`stopped_at`）を持ちます

### 段階 2・3 は推測しない：設計者が書く

段階 1 は機械で決まります（名前、ポート、ClientHello）。段階 2・3 は違います。「何を受け取ったら何を返し、何が発火するか」は、
アプリのコードを読める者でなければ決められません。これは LSP や Xipe Totec の走査、コードを読む AI エージェントの領域で、
ネットワークの層にいる Citlalpol が推測してよいものではありません（tezcatl の「人が読む文字列を解釈せず、構造は人が選んだ仕組み
から来る」と同じ考え方）。

- `access.json` に段階 2・3 の項目を用意し、**設計者が書き込みます**（次の節の `stages`）
- コードを読める道具（LSP、Xipe の走査、AI エージェント）は下書きを**提案**してよいが、入れるのは設計者です
- Citlalpol 自身が扱うのは段階 1 と経路だけです。段階 2・3 の照合（要求がどの項目に当たるか）と応答は、Citlalpol が起動する
  プログラム（swallow）が `access.json` の項目を読んで行います
- 記録には「何を受け取ったときに何が発火したか」（`matched`、`fired`）を残します。設計者が書いた項目と実際の動きを突き合わせる材料です

### 記録の秘密

段階 2 では `Authorization`・`Cookie` や本文中の鍵が記録に入ります。

- 既定で伏せて記録します（伏せるヘッダーの名前の一覧を持ち、本文は大きさと種類だけ。`--keep-bodies` で人が明示したときだけ残す）
- commit する `access.json` には要求の「型」（メソッド、パス、ヘッダーの名前）だけを書き、値は書きません
- 記録は `~/.local/share/citlalpol/` だけに置き、リポジトリには入れません

## access.json（宛先の宣言）

アプリケーションのリポジトリに置き、一緒に commit するファイルです。「このアプリはどこへアクセスするか」を書きます。

```json
{
  "citlalpol": 1,
  "name": "calc_app",
  "destinations": [
    { "host": "api.example.com", "port": 443, "do": "pass", "why": "the payment API; read-only calls in development" },
    { "host": "db.prod.internal", "port": 5432, "do": "stand_in", "as": "postgres" },
    { "host": "*.amazonaws.com", "port": 443, "do": "refuse", "why": "uploads must never run while trying code" },
    { "host": "hooks.slack.com", "do": "stand_in", "as": "slack_stub" }
  ]
}
```

- `do`：`refuse` / `pass` / `stand_in`。**書かれていない宛先は全面禁止**です（既定を変える設定は持ちません。書かれていないものに
  何かをさせたいなら、書く）。`refuse` は「書いたうえで禁止する」（理由を `why` に残す）ためにあります
- `host` は名前で書きます（`*.` の前置きを許します）。IP や CIDR も書けますが、M1 では IP 直書きの接続そのものが通らないので、意味を持つのは M2 からです
- **代役の居場所は書きません**。`as` は代役の名前だけです。代役がどのポートで待っているかは機械ごとに違うので、この機械の
  `~/.config/citlalpol/stand_ins.json` に分けます（`{"postgres": "127.0.0.1:55432", "slack_stub": "127.0.0.1:8099"}`）。
  `access.json` は「どこへ行くアプリか」、`stand_ins.json` は「この機械では代わりに何があるか」です
- `why` は人が読むための理由です。記録にも載ります
- 段階 2・3 の宣言は、宛先の下の `stages` に設計者が書きます（前の節）。形の叩き台：

```json
{ "host": "api.example.com", "port": 443, "do": "stand_in", "as": "payment_api",
  "stages": {
    "connect": { "proto": "tls", "sni": "api.example.com" },
    "send": [
      { "id": "status", "match": { "method": "GET",  "path": "/status" },     "do": "pass" },
      { "id": "charge", "match": { "method": "POST", "path": "/v1/charges" }, "do": "stand_in" }
    ],
    "expect": [
      { "on": "charge", "reply": "citlalpol/replies/charge.json", "fire": "after_charge", "verify": "never",
        "why": "a charge is never replayed; the reply is the shape the client reads" }
    ]
  } }
```

  `send` は「何を送るか」で、要求の単位の `do`（`pass` / `stand_in` / `refuse`）を持ちます。`expect` は「何を送ったら何が返って
  きてほしいか」で、`reply`（応答の表。リポジトリの中のデータ）、`fire`（受け取ったときに発火させるプログラムの**名前**）、
  `verify`（本物に当ててよいか：`safe` / `never` / `elsewhere`）を持ちます。`match` が何を比べられるかはプロトコルごとで、swallow が決めます
- **起動するプログラムは書けません**。代役も照合のプログラムも名前で指すだけで、何を起動するかはこの機械の
  `stand_ins.json` にだけ書きます（次の節）

### citl read

```
citl read [access.json]          （既定：カレントディレクトリの access.json）
```

1. 形を検査する（知らない `do`、`stand_ins.json` にない `as`、重なる規則はエラー）
2. 「何を通し、何をどこへ曲げ、それ以外は遮断する」を一覧で見せる
3. citld に `name` で登録する。以後 `citl run <name> -- <command>`（または `forbidden on --door citlalpol` の中で
   `citl use <name>`）で使える

`citl run -- <command>` だけで、カレントディレクトリの `access.json` を読んで実行する短縮形も用意します。

### access.json の下書きを記録から作る

宛先の宣言を人が一から書く手間を減らすために、逆向きの道も用意します。

```
citl run --learn -- mix test          宣言なし（全面禁止）で走らせ、どこへ出ようとしたかを記録する
citl draft --run <id> > access.json   その記録から下書きを作る（全部 refuse で、人が pass / stand_in に直す）
```

## ローカルのプログラムを起動する（代役と照合）

Citlalpol はプロトコルを解釈しません。中身が要るところでは、ローカルのプログラムを起動して接続を渡します。TLS の復号はサーバーや
proxy の機能を借り（caddy、mitmproxy …）、応答の計算や照合はそのためのプログラムに任せます。Pact のように言語ごとのライブラリを
アプリに組み込む必要がなく、結合が薄く済みます。

### 取り決め（inetd・CGI と同じ形）

渡し方はアプリ（対象のプロセス）とは関係しません。アプリは普通に TCP で繋ぐだけで、Citlalpol がその接続をどうプログラムへ渡すかは
見えません。渡し方は**起動されるプログラムの側**が受け取れる形で選び、代役ごとに `stand_ins.json` に書きます。

| 渡し方 | 受け取るプログラム | 向くもの |
| --- | --- | --- |
| `stdio`（既定） | 接続のバイト列が stdin/stdout に来る（inetd） | どんなプログラムでも。シェルスクリプト、`socat`、端末越しに人が手で答える代役（tezcatl の xterm）まで |
| `fd` | socket の fd を受け取る。systemd の socket activation と同じ取り決め（`LISTEN_FDS`、`LISTEN_PID`） | それに対応した既製のサーバー。接続の性質（半閉じ、TLS の終端）をそのまま扱える |
| `addr` | 既に listen しているアドレスへ citld が中継する | 人が自分で立てておいたもの（ローカルの DB、WireMock …） |

- **付随情報**：環境変数で渡す。`CITLALPOL_PROTOCOL`（取り決めの版）、`CITLALPOL_HOST`、`CITLALPOL_PORT`、`CITLALPOL_SNI`、
  `CITLALPOL_RUN`、`CITLALPOL_LABEL`、`CITLALPOL_ACCESS`（その宛先の `stages` を書いた JSON のパス）
- **監督**：起動・時間切れ・実行の終わりでの停止は citld が行い、stderr は記録に添えます
- **言語を問わない**：既製のサーバーをそのまま使えるし、自作の小さなスクリプトでもよい

`stand_ins.json`（この機械の）は、代役ごとに「アドレス」か「起動するコマンド」を持ちます。

```json
{
  "postgres":   { "addr": "127.0.0.1:55432" },
  "payment_api": { "exec": ["swallow", "serve"], "via": "stdio", "tls": "local-ca" },
  "after_charge": { "exec": ["/home/me/stubs/after_charge.sh"], "via": "stdio" },
  "payment_verify": { "exec": ["swallow", "verify"], "role": "verify" }
}
```

### 起動の設定を置く場所

`access.json` はアプリと一緒に commit されるので、そこに起動するコマンドが書けると「clone したリポジトリを開いたら任意の
プログラムが動く」ことになります（git hooks と同じ危険）。起動するコマンドとパスは `stand_ins.json` にだけ書きます。
リポジトリの中のプログラムを使いたいときは、`citl trust <path>` で人が一度承認してから `stand_ins.json` に載せます。

### TLS と CA

復号をローカルのプログラムに借りても、対象のプロセスがその証明書を受け入れるかどうかはクライアント側の判断です。Citlalpol は
対象を自分で起動するので、言語ごとにローカルの CA を信頼させる環境変数（`SSL_CERT_FILE`、`NODE_EXTRA_CA_CERTS`、Erlang の
cacerts の指定、Python の `REQUESTS_CA_BUNDLE` …）を渡す役を持ちます（M4）。証明書を固定しているアプリは対象外です。

## swallow（段階 2・3 を受け持つ、別リポジトリ）

リポジトリ：<https://github.com/Crux-xurC/swallow>（`~/my_app_no_nix/swallow`、設計は `docs/ja/design-memo.md`）

段階 2・3 の照合・応答・本物との照合は、Citlalpol から分けて **swallow** という別のリポジトリにします。Xipe Totec と embody の関係
（Xipe は REPL に渡す部分を embody に任せ、embody がなくても Xipe は動く）と同じです。Citlalpol は swallow がなくても段階 1 の
道具として完結し、swallow は Citlalpol の取り決め（起動・渡し方・環境変数）に従う一つのプログラムです。名前は vent、embody と同じく
意図して選んだやや珍しい英単語の系譜で、「受け取ったものを呑み込んで、返すべきものを返す」から。

- `swallow serve`：代役として接続を受け、`access.json` の `stages` で要求を照合し（`match`）、`expect` の `reply` を返し、`fire` を
  発火させる（Pact の mock server に当たる）
- `swallow verify`：`expect` の表を本物に当てて照合する（Pact の provider verification に当たる。次の節）
- プロトコルを解釈するのは swallow です（HTTP から始める）。Citlalpol はプロトコルを知らないまま
- 設計者が書いた `stages` を読むだけで、推測はしません

### 決まっていないところのデフォルトは swallow

設計者が「何を返すか」「何を発火させるか」をまだ決めていないところは、swallow を受け手にします。

- 宛先が `stand_in` で `as` がない → `swallow serve` を起動する（`stand_ins.json` に `swallow` の行がなければ、標準の
  `{"exec": ["swallow", "serve"], "via": "stdio"}` とみなす）
- `send` に当たらない要求、`expect` に `reply` がない要求 → swallow が受けて記録し（`captured`）、本物と取り違えようのない失敗を返す
  （HTTP なら `501` と `X-Swallow: undecided`）。それらしい答えを返さないのは、アプリが成功したと思い込み、評価の結果が誤るから
- `fire` がない → 発火しない（「発火しない」と決めたのと同じに扱う）
- swallow が入っていない機械では、これらは段階 1 の遮断と同じになる（Citlalpol は swallow なしで完結する）
- 書かれていない宛先そのものは、これまで通り全面禁止です。デフォルトが swallow なのは、設計者が
  宛先を宣言したうえで中身を決めていないところだけです。`citl run --learn --capture` のように人が明示したときだけ、宣言のない宛先も
  swallow に回して段階 2 まで記録する（TLS の中身は M4 の前は読めない）

## verify（段階 3 の表を本物に当てて照合する）

Pact の provider verification に当たります。行うのは `swallow verify` です。

- `citl verify <name>` という明示したコマンドでだけ動きます（citld が `role: "verify"` のプログラムを壁の外で起動する）。
  本物へ出る唯一の場面なので、その通信も citld を通して記録します
- どこを比べるかは swallow が決め、設計者が `expect` に書けるようにします（時刻や ID のように毎回変わるものがあるため）
- **表の行ごとに当ててよいかを書きます**：`safe`（副作用のないもの）／`never`（当てない）／`elsewhere`（検証用の環境の宛先に当てる）。
  `POST /charge` を本番に再生する事故を防ぐためです
- 結果は行ごとに 1 行の JSON：`{"row": …, "result": "match" | "differ" | "skipped", "why": "…"}`。記録・run_table・MCP で使えます
- 段階 3 の表は、後で Pact の形式に書き出せるようにしておきます（両方の良いところを取る）

## 端末から：forbidden

端末で使う入口は forbidden です（別リポジトリ）。`forbidden on --door citlalpol` で、その端末の次のコマンドから外へ向かうものは
扉（4600）の Citlalpol だけを通り、`forbidden off` で戻ります。forbidden は扉の向こうを知らず、Citlalpol は壁を知りません。
扉の設定（`~/.config/forbidden/doors.json` の `citlalpol`：4600 と citld の unix socket）は `citl` が用意します。

## 記録と citl の参照

記録は citld が `~/.local/share/citlalpol/records/<日付>.jsonl` に追記します（追記だけで、書き換えはしません）。1 件の形：

```json
{"at":"2026-11-24T08:41:03.112Z","run":"r-0007","project":"calc_app","command":"iex -S mix",
 "query":"api.example.com","port":443,"proto":"tls","sni":"api.example.com",
 "pid":48211,"cmd":"git fetch origin",
 "decision":"pass","rule":"api.example.com:443","stage":1,"stopped_at":null,"bytes_up":512,"bytes_down":20480,"ms":184,
 "label":"01M3D3ZDR9MW08P2VZ6Q73E2RE"}
```

| コマンド | 何を見せるか |
| --- | --- |
| `citl log [--since 10m] [--run <id>] [--project <name>] [--decision refuse]` | 記録を新しい順に |
| `citl summary [--since 1h] [--by host\|run\|decision\|hour]` | 宛先ごと・時間ごとなどの集計 |
| `citl runs` | 実行の一覧（いつ、何のコマンドを、どの access.json で） |
| `citl tail` | 今起きているものを流す |
| `citl status` | citld が動いているか、登録されている名前 |

どのコマンドも `--json` で 1 件 1 行の JSON を出します（tezcatl の run_table や、MCP から使うため）。

### label：誰がアクセスしたか

壁の中から見えるのは「どの実行か」までで、「どの関数か」は分かりません。そこで、**壁の外にいる起動した側**（Xipe Totec など）が
citld に直接「実行 `<run>` の今の名札は `<label>`」と伝えます（`citl label <run> <label>`、citld の制御用 socket）。壁の中から名札を
付ける口は持たないので、対象が名札を偽ることはできません。Xipe Totec が評価の前後で calc 行の id を名札にすれば、「この行の評価が
`api.example.com` へ出ようとした」が記録に残ります。

## Xipe Totec で回す（壁を一段ずつゆるめる）

Citlalpol の使われ方の中心です。Xipe Totec は対象のリポジトリの関数を「この引数で呼ぶとこうなる」と評価し、記録します。その評価を
Citlalpol の下で行い、ネットワークの振る舞いを重ねます。

```
 1. Xipe が対象の関数を評価する（Citlalpol の下、外部は全部遮断）
 2. citld が記録する：どの関数の評価が、どこへ、どの方式で出ようとし、どの段階で止まったか
       （接続で止まった / 送る中身まで行った / 応答を待った）
 3. 記録から access.json の差分を下書きする → 人が承認する（壁を一段ゆるめる）
       「通す」「代役へ回す（代役が計算して返す＝Pact 相当）」「遮断のまま」
 4. もう一度 Xipe で評価する → 1 へ
       （本物に当てて確かめる段階では verify のプログラムが照合する）
```

### 1. 試みを「どの行の評価か」に結び付ける

記録が「この実行で」までしか分からないと繰り返しの役に立ちません。「`Calc.fetch/1` のこの行が `api.x:443` に TLS で出ようとし、
接続の段階で止まった」まで要ります。Xipe が行を評価する直前に、名札（行の id）を citld に渡します（壁の外から。「label」の節）。

ただし Xipe は「一緒に送った行は同時に走る」作りなので、同時に評価すると接続と行を結べません。Citlalpol の下では行を一つずつ評価するか、
名札を評価の pass 単位にとどめるかを選びます（未決）。

### 2. ゆるめるのは人の承認だけ

Xipe の副作用の分類と同じ形にします（エージェントは提案するだけで、人が承認したものだけが評価される：Xipe の D-effect-approval）。
`citl draft --since <run>` が前回からの新しい試みだけを差分として下書きし（AI エージェントが MCP 越しに提案してもよい）、人が承認した
ものだけが `access.json` に入ります。段階的にゆるくなることを自動にしないのが、防御壁としての意味を保つ条件です。

### 3. Xipe Totec の側に要るもの（決まるまで Xipe の文書には書かない）

Xipe の「sandbox はない」という約束は変わりません。Citlalpol はネットワークだけを扱う別の道具で、なければ今まで通りに動きます。

- プロジェクトごとの設定で、REPL を `citl run <name> -- <REPL のコマンド>`（forbidden の壁の中、扉は Citlalpol）で起動する（`project_env.json` に近い置き場所）
- 行を評価する直前に名札を渡す
- 失敗した行で、Citlalpol の記録から「なぜ止まったか」を引けるようにする（対象のコードが投げる `:nxdomain` や TLS alert だけでは、
  遮断されたのか本当に落ちたのか区別できない）
- tezcatl の matrix で、行ごとの通信の試みを列として出す（`citl log --json --label <行 id>`）

### 4. 副作用の分類との関係

Citlalpol の下ならネットワークへ書き込む関数も評価できそうに見えますが、**ファイルへの書き込みは止まりません**。Xipe の `writes` を
緩めるのではなく、分類にネットワークの軸（外へ出ない／宣言した宛先にだけ出る）を足すのが筋です。記録はその提案
（`effect/propose` 相当、理由に記録を添える）に使えます。

### 実際に回すときの注意

- **`nix develop` の外側で包まない**：devShell を作るときの取得で記録が埋まります。`nix develop -c citl run --learn -- …` と内側で包みます
- 自分で listen して自分に繋ぐもの（xipe_totec のテストの serve_socket・lsp_relay など）は namespace 自身の loopback で完結させ、
  外への試みとは分けます（壁の中の loopback は forbidden が上げる。扉の 4600 とぶつからないポートで）
- xipe_totec 自身は評価中に何も取りに行かない作りです（cabal `--offline`、`COURSIER_MODE=offline`、NuGet は空の取得元）。xipe_totec の
  テストを全部遮断で回して試みが 0 件になることが、Citlalpol と Xipe の両方の確認になります（出れば Xipe の約束の穴か、道具が
  勝手に出ている：dotnet のテレメトリ、sbt の更新確認 …）

### tezcatl

- 端末（xterm）を `forbidden on --door citlalpol` で始める選択肢
- `citl log --json` を表で見る（matrix の `kind` の一つにする）

## 確かめる順序と最初の受け入れ

小さく三段で確かめます。

1. **forbidden だけ**（forbidden の F1）：`forbidden on` の中で `ping` と `curl` が失敗し、`forbidden off` の後で成功する
2. **小さな Citlalpol を扉の向こうに置く**（forbidden の F2、Citlalpol の M1）：`forbidden on --door citlalpol` の中で、`curl` の
   `GET /ping` が 4600 を経由して偽の外の pong に届く。`access.json` にない宛先は届かない
3. **ping の 4 段**（下の表）

### ping の 4 段

`citl-ping`（実体は `curl http://pong.citlalpol.test/ping` で足りる：proxy の環境変数を読み、`pong` を待つ）で、Citlalpol と swallow の
境目を順に確かめます。ICMP ではなく HTTP の上の ping にするのは、扉を通れるのが宛先を名乗る TCP だからです（壁が ICMP も止めることは
1 で確かめる）。

| | 条件 | 期待 | 要るもの |
| --- | --- | --- | --- |
| a | 壁の外 | 偽の外の pong にローカルのアドレスで直接繋いで届く（プログラムとサーバーが動くことの確認） | なし |
| b | 壁の中、`access.json` に宣言なし | 届かない。記録に「宣言なしで禁止」と残る | forbidden F2、M1 |
| c | `access.json` に宛先を宣言したが、返すものを決めていない | 届かない。swallow が `501`・`X-Swallow: undecided` を返し、記録に `captured` が残る | M2、swallow S1 |
| d | `expect` に `reply`（`pong`）を書いた | 届く（swallow が答える）。記録に `matched` が残る | M2、swallow S2 |

- 相手（pong）は偽の外の中に置き、ネットワークがなくても繰り返し回せるようにします
- b で確かめるのは timeout ではなく「すぐ失敗し、記録に理由が残る」こと。扉は禁止された宛先をすぐ断ります（SOCKS5 なら
  「許可されない」、HTTP proxy なら `403`）

## 他人のプログラムを調べる

安全性の分からないプログラム（他人が作ったもの、手に入れたばかりのツール）を、偽の外だけを相手に動かして、どこへ出ようとするかを
調べます。

```
forbidden run --strict --door citlalpol --dir ./the-tool -- ./the-tool/install.sh
citl log --run <id>          どこへ、どのプロセスが、どの段階まで出ようとしたか
```

壁の強さ（ファイル・socket・プロセス・端末を見せないこと）は forbidden の `--strict` が持ちます。Citlalpol の側で合わせること：

- **宣言のない名前は、名前を引く前に禁止する**：SOCKS5 の `socks5h` で名前が届いたら、`access.json` と照らしてから引く。引いてから
  断ると、名前そのもの（`<盗んだデータ>.attacker.example`）が DNS の問い合わせとして外へ漏れる。これは普段のモードでも同じにする
- **`pass` を置かないことを勧める**：調べるときに `pass` の宛先があれば、そこが持ち出しの道になる。調べるための `access.json` は
  空（全部禁止）か、`stand_in` だけで始める
- **扉から届く入力は信頼できないものとして読む**：SOCKS5・HTTP proxy の読み取り、swallow の HTTP の読み取りは、短く頑丈に。
  大きさの上限、時間切れ、一つの実行あたりの記録の量の上限（記録を溢れさせられないように）
- 記録が調べた結果になる：`citl summary --run <id> --by host` で「このツールはどこへ出ようとしたか」の一覧

## 実装（v0.7、素朴な版）

`bin/citl`（python3、一つのファイル）。citld は `citl serve`（`citl start` で裏に）。

- **扉で受けるもの**：PROXY v2（forbidden の中継から。TLV の `run`・`pid`・`cmd`・`mode` を記録へ）→ SOCKS5（CONNECT、名前・IPv4・
  IPv6）か HTTP proxy（`CONNECT host:port` と、平文 HTTP の絶対 URL。後者は origin 形式に直し、`Proxy-*` を外し、`Connection: close`
  にして一つの要求で閉じる）
- **決め方**：その実行に当たる access.json（`citl run <name>` が `$XDG_RUNTIME_DIR/citlalpol/runs/<run>` に名前を書く。なければ
  `citl use` の名前。どちらもなければ全部禁止）。宛先は `host`（完全一致か `*.` の前置き）と、あれば `port` で引く。**引けなければ、名前を
  引く前に禁止**。access.json は接続のたびに読み直す（直したらすぐ効く：Xipe で回す繰り返しのため）
- **pass**：名前を引き、ローカルのアドレス（loopback・private・link-local）に当たれば、エントリに `allow_local: true` がない限り禁止
  （この機械の relay や Emacs へ `pass` で抜けることを防ぐ。実装で足した決まり）
- **決して通さないローカルのポート**：tezcatl のページ（4001）と relay（4100：シェルを起動できる）、Emacs（4000）、Xipe Totec（4200）は、
  `allow_local` があっても `pass` しない。stand_ins.json の `addr` がそこを指していても繋がない。足すときは `~/.config/citlalpol/never.json`
  （`{"ports": [...]}`）。tezcatl から記録を見るようになったときに決めた（crux、2026-11-24）：壁の中から relay に届けばシェルを起動できるので、
  そこへの窓は人が書いても開かない
- **記録の読み口は扉にしない**：記録を外へ見せるのはファイルだけ（tezcatl の relay はファイルを読む）。citld に記録を問い合わせる口を扉の上に
  作らない。tezcatl・Poca・Emacs・Xipe を Citlalpol の下で動かさない。見ることが記録を生み、それをまた見る、という輪を作らないため
- **stand_in**：`as` があれば `~/.config/citlalpol/stand_ins.json` の `addr`（中継）か `exec`（起動）。`as` がなければ swallow
  （`SWALLOW`、PATH、このリポジトリの隣の順に探す。ないときは禁止）。起動するプログラムには、接続を stdin / stdout、
  `CITLALPOL_ACCESS`（`{"destination": <エントリ>, "base": <access.json のディレクトリ>}` の一時ファイル）、`CITLALPOL_HOST`・`PORT`・`RUN`、
  結果の口 `CITLALPOL_RESULT_FD`（JSON 1 行ずつ。記録に `request`・`matched`・`replied`・`default`・`captured` を足す）を渡す
- **禁止の見せ方**：HTTP は `403` と `X-Citlalpol: refused` と理由の一行、SOCKS5 は「許可されない」（0x02）
- **citl read**：形を確かめて名前で登録する（`~/.config/citlalpol/registered.json`）。**起動するプログラムを書いたエントリ
  （`exec`・`command`）は断る**
- **記録**：`~/.local/share/citlalpol/records/<日付>.jsonl`。`citl log` は `--run`・`--since`・`--decision`・`--json`。一行に、時刻・判断・
  プロトコル・宛先・**要求（`GET /ping`。平文の HTTP は citld が、SOCKS5・CONNECT の中は swallow が読んだもの）**・`[コマンド]`（48 文字で
  切り、切ったら `…`。全部は `--json`）・理由（crux の指摘、2026-11-24）
- **記録に秘密を残さない**：パスの問い合わせは名前だけ（`/ping?token=…`）。プロセスのコマンド行も、よくある秘密の場所を伏せてから記録する
  （URL の問い合わせの値、`user:password@`、`Authorization`・`Cookie` などのヘッダーの値、`--password` / `--token` などの値、`curl -u` の
  パスワード）。伏せるのはよくある形だけで、別の書き方の秘密は残りうる（記録はこの機械のもので git の外）
- 制御用の socket は作らなかった（実行と名前の対応は `runs/` のファイル、`use` も設定のファイル）。`runs/` は扉と同じディレクトリで、
  forbidden が壁の中から隠す
- まだ：TLS の中の応答（ローカルの CA）、proxy を読まないアプリの試みの記録、`citl label`、`verify`、`draft`、`trust`、記録の量の上限

## 構成

| 部品 | 役割 | 動く場所 |
| --- | --- | --- |
| `citld` | 扉（4600）の向こう：規則の表、記録、外への唯一の経路（禁止・転送・代役へ）、問い合わせへの応答 | 壁の外。ユーザーの systemd の service か、`citl` が初回に起動 |
| 壁と扉 | 外への道をなくし、4600 だけを citld へつなぐ | forbidden（別リポジトリ） |
| `citl` | `read` / `run` / `use` / `label` / `log` / `summary` / `runs` / `tail` / `status` / `draft` / `verify` / `trust` | どこでも（citld に unix socket で話す） |
| 代役・照合のプログラム | 段階 2・3 の中身（復号、応答の計算、本物との照合）。標準は swallow（別リポジトリ） | citld が起動する。この機械の `stand_ins.json` に書かれたものだけ |

citld と citl の間の socket：`$XDG_RUNTIME_DIR/citlalpol/citld.sock`（JSON を 1 行ずつ）。

## マイルストーン

| | 内容 | 終わったと言える条件 |
| --- | --- | --- |
| M0 | この設計 | 未決のうち M1 に要るものが決まる |
| M1 | citld が扉の向こうで SOCKS5 と HTTP proxy を受ける、`access.json` の `pass`（書かれていないものは全面禁止）、記録、`citl read` / `run` / `log` / `status`、扉の設定を用意する（forbidden の `doors.json`）、宣言のない名前は引く前に禁止 | 確かめる順序の 2 と、ping の a・b が通る。`curl https://example.com` が既定で失敗し、記録に残る。`pass` と書けば通る。citld を止めると何も通らない。**xipe_totec のテストを壁の中で回して、扉に届いた試みが 0 件** |
| M2 | ローカルのプログラムの起動（取り決め、`stand_ins.json`、`trust`）、`stand_in`（TLS なし）、段階 2（平文）と秘密を伏せること、`summary` / `runs` / `tail`、`--learn` と `draft --since` | ping の c・d が通る（swallow S1・S2 と一緒に）。Postgres へ向けたアプリが代役の DB に繋がる。HTTP の要求が型として記録され、`Authorization` の値は残らない |
| M2.5 | PROXY v2 を扉の socket から受ける（forbidden の F2 と）、記録に pid とコマンド、扉からの入力の上限 | 記録に出ようとしたプロセスのコマンドが載る。TCP で受けた PROXY のヘッダーは読まれない |
| M3 | Xipe Totec で回す一周目、`citl label` | Xipe の REPL が `citl run` の下で動き、評価した行の id が記録に載る。止まった行の理由が引ける。差分を承認して評価し直すと、その行が先へ進む |
| M4 | ローカルの CA（HTTPS の代役、段階 2 の TLS） | 言語ごとの信頼のさせ方の表と、そのテスト |
| M5 | `stages` の形を固める。swallow（別リポジトリ）の `serve` と `verify`（HTTP から） | `stages` の `send` と `expect` を swallow が読んで応答し、`fire` が発火したと記録に残る。`citl verify` が `safe` の行だけを本物に当てて照合する |
| M6 | proxy を読まないアプリの試みの記録（forbidden の F4 と一緒に） | 直接 socket を開くプログラムの試みも記録に残る |

## 未決

- 書く言語：**Elixir に書き換えると決めた**（2026-11-24、crux。他のプロジェクトと揃う。citld は OTP の service に向く）。
  開発は Nix 版（`~/my_app/citlalpol`、nixpkgs は tezcatl・Xipe Totec と同じ版に固定）、Nix なしは Citlalpol_without_nix（2026-11-25）。
  代役の起動が範囲外になったので（v0.8）、Port で fd を渡す・stdin だけ閉じる問題と中継プログラムは要らなくなった。残る問い：
  BEAM の起動の遅さが動き始めだけで済むか、常駐した citld が機械を圧迫しないかを確かめ、問題なければ初動の遅さは容認する
- citld の起動のしかた：ユーザーの systemd の service か、`citl` が必要なときに起動するか
- `access.json` の名前と置き場所（`.citlalpol/access.json` などに寄せるか）
- 記録をいつまで残すか（日ごとのファイルを何日で消すか）
- `stages` の形の細部（`match` に何を書けるか、`reply` の表の形）。swallow の最初のプロトコル（HTTP）で決める
- `fire` の発火は応答の前か後か、応答を変えられるか
- swallow を始める時期とリポジトリ（Citlalpol の M5 まではこのメモの中で扱う）
- Xipe で回すときの名札の単位：行を一つずつ評価するか、pass 単位にとどめるか
- 禁止の見せ方を選べるようにするか（すぐ断る／黙って待たせる）
- PROXY v2 の TLV の番号と中身（forbidden と一緒に）
- 他人のプログラムを調べるときの記録の量の上限
- 偽の外の pong の代役を Citlalpol に同梱するか、テストの中だけに置くか
- ライセンス
