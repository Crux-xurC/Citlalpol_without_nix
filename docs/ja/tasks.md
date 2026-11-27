# citlalpol のタスク

tezcatl の agenda で管理する表です。下の表を tezcatl で開き、`:w replace #eigenvalue tasks` で印をIDに置き換えてから、
`task_table take` で取り込み（markdown パネルなら表の上で `t`）、task_table で `L` を押すと agenda（`C-c a`）に載ります。
agenda での変更は task_table の book に戻り、この文書へは task_table の `W` で戻します。

tezcatl のファイルの起点（`~/my_app`）から見たこの文書のパス：`citlalpol/docs/ja/tasks.md`

Table: citlalpol_#eigenvalue

| id   | state | pri | task                                                                              | inner_id    |
|------|-------|-----|-----------------------------------------------------------------------------------|-------------|
| t-01 | DONE  | A   | 設計の叩き台を書く（design-memo.md v0.1）                                         | #eigenvalue |
| t-02 | DONE  | A   | 書く言語：素朴な版は python3（citld・citl は一つのファイル）                      | #eigenvalue |
| t-03 | DONE  | A   | （forbidden へ）壁の試作：unshare -rn の中で ping・curl が失敗すること            | #eigenvalue |
| t-04 | TODO  | A   | access.json の形と stand_ins.json の分け方を決める                                | #eigenvalue |
| t-05 | TODO  | A   | 記録の 1 件の形（stage、stopped_at、label）と、citld ↔ citl の socket の取り決め  | #eigenvalue |
| t-06 | DONE  | A   | M1：扉の向こうの SOCKS5 / HTTP proxy、pass と全面禁止、記録、doors.json を用意    | #eigenvalue |
| t-07 | TODO  | A   | M1 の確認：xipe_totec のテストを全部遮断で回して外への試みが 0 件                 | #eigenvalue |
| t-08 | DONE  | B   | （不要に：代役は範囲外、v0.8）渡し方 stdio / fd / addr の取り決めと環境変数（CITLALPOL_ACCESS ほか）            | #eigenvalue |
| t-09 | DONE  | B   | （不要に：代役は範囲外、v0.8）M2：起動・stand_ins.json・trust、stand_in（TLS なし）、段階 2 と秘密を伏せること  | #eigenvalue |
| t-10 | TODO  | B   | M3：Xipe Totec で回す一周目（名札の単位、draft --since、承認）                    | #eigenvalue |
| t-11 | TODO  | B   | citld の起動のしかた（systemd のユーザー service か、必要なときに起動か）         | #eigenvalue |
| t-12 | DONE  | C   | （範囲外に：TLS の代役は人の側、v0.8）M4：ローカルの CA と、言語ごとの信頼のさせ方                                      | #eigenvalue |
| t-13 | DONE  | C   | （swallow へ：代役は範囲外、v0.8）M5：stages の形と swallow（serve / verify、HTTP から）、Pact 形式への書き出し     | #eigenvalue |
| t-14 | TODO  | C   | M6：IP 直書きと UDP の記録（TUN）                                                 | #eigenvalue |
| t-15 | TODO  | C   | ライセンスを決める                                                                | #eigenvalue |
| t-16 | DONE  | A   | 設計 v0.2：Xipe で回す繰り返し、三つの段階、ローカルのプログラム、verify          | #eigenvalue |
| t-17 | DONE  | A   | 設計 v0.3：段階 2・3 は設計者が access.json に書く、swallow を分ける、渡し方      | #eigenvalue |
| t-18 | DONE  | A   | 設計 v0.4：偽の外が本体、権限の位置、forbidden、ping の 4 段                      | #eigenvalue |
| t-19 | DONE  | A   | citl-ping と偽の外の pong（a・b は M1、c・d は M2 と swallow S1・S2）             | #eigenvalue |
| t-20 | DONE  | A   | （forbidden へ）forbidden on / off / status                                      | #eigenvalue |
| t-21 | DONE  | A   | （不要に）権限の位置：forbidden の性質と、名札を壁の外から付けることで足りる      | #eigenvalue |
| t-22 | DONE  | A   | 設計 v0.5：壁は forbidden、扉の向こうの 4600、access.json にないものは全面禁止    | #eigenvalue |
| t-23 | DONE  | A   | 設計 v0.6：PROXY v2、記録に pid とコマンド、他人のプログラムを調べる              | #eigenvalue |
| t-24 | TODO  | B   | M2.5：PROXY v2 を扉の socket から受ける、扉からの入力の上限                       | #eigenvalue |
| t-25 | DONE  | A   | M1 に：宣言のない名前は引く前に禁止                                               | #eigenvalue |
| t-26 | DONE  | A   | 素朴な版：SOCKS5 / HTTP proxy、pass・stand_in・refuse、swallow が既定、記録       | #eigenvalue |
| t-27 | DONE  | B   | citl label（Citlalpol の側。Xipe が行の id を伝える側と一周目は t-10）                         | #eigenvalue |
| t-28 | DONE  | A   | Elixir へ書き換える（確定 2026-11-24）：citld から。docs/scope.md の範囲で、それに合わせて直した test/run.sh が合格条件 | #eigenvalue |
| t-29 | DONE  | B   | （不要に：代役は範囲外、v0.8）代役の起動に中継プログラムを挟む（Port は追加の fd・stdin だけ閉じるが難しい。t-08 と） | #eigenvalue |
| t-30 | DONE  | B   | （省略：BEAM は通信の制御に使うだけ、2026-11-25 crux）BEAM の起動の遅さ：遅いのは動き始めだけか、常駐した citld が機械を圧迫するか。問題なければ初動の遅さは容認 | #eigenvalue |
| t-31 | DONE  | A   | docs/scope.md：範囲と範囲外を明示（代役は範囲外、to、door・sent_to、localhost と proxy を読まないもの） | #eigenvalue |
| t-32 | DONE  | A   | Nix 版へ：~/my_app/citlalpol へ移す、flake.nix（tezcatl と同じ nixpkgs） | #eigenvalue |
| t-33 | DONE  | B   | proxy を読まないもの（forbidden の --catch-all・nftables に変更）：citld の DNS と fake-IP の対応（forbidden F5 の TUN・tun2socks と組む） | #eigenvalue |
| t-34 | DONE  | B   | Citlalpol_without_nix を作る（~/my_app_no_nix/citlalpol_without_nix、release、sync）（tezcatl_without_nix と同じ形：Mix プロジェクト、sync） | #eigenvalue |
| t-35 | DONE  | C   | --strict でもすべてを受ける扉（bubblewrap を普段の壁の中で、ネットワークだけ共有）（forbidden、bubblewrap の network namespace） | #eigenvalue |
| t-36 | DONE  | B   | tezcatl の citlalpol_image（Zoozve の軌道、to_auth は Zoozve へ、DNS は戻る）：to でローカルへ送ったものを外へ出たと描かない（sent_to がローカルなら別の行き先） | #eigenvalue |
| t-37 | DONE  | A   | 指摘への対処：access.json の写しで判断・壁の中で設定と記録を隠す・allow_local を廃止 | #eigenvalue |
| t-38 | DONE  | A   | zoozve：to の門番（HMAC のチャレンジ・レスポンス、後ろの任意のサーバーへ中継）と citld の側の認証 | #eigenvalue |
| t-39 | DONE  | B   | citl swallow / digest / residual：拒否された試みの一時的な小さい表（cat で読む）、プロジェクトの access.json への書き込み（効かせるのは citl read）、表を残す（2026-11-27 設計、design.md） | #eigenvalue |
