# 引継ぎドキュメント(2026-09-08 セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. ★現在位置(2026-09-08 深夜)

### 1.0 ★★★ 解決: **`sdram_mp` は正しいが遅く、遅さが BIOS ロードを壊していた**

run#109 で **実機に POST 画面が出た**(それまで一度も splash から進んだことがない)。

**故障は SDRAM の正しさではなく、スループット。**
`RAM.sv` に対して BIOS ローダのカデンスで実測:

| コントローラ | ローダ1バイトあたり | 実機 |
|---|---|---|
| KFSDRAM | **8.08** クロック | 起動する |
| sdram_mp(修正前) | **19.11** クロック | 起動しない |
| **予算(APF の供給速度)** | **約 10.9** クロック | |
| **sdram_mp(修正後)** | **7.25** クロック | **POST 到達** |

**APF は止められない。** `data_loader` に ready 入力が無く、
`core_top` のロード FIFO は満杯で**黙って捨てる**:

```systemverilog
if (dl_wr && ~rlf_full) begin ... end
```

APF は 32bit ワードを約75 clk_74a サイクルごとに届ける
= 16bit ワード2個で約43 chipset クロック = **1バイトあたり約10.9**。
1.75倍負けていた結果が **`DROP 4682`(イメージの約14%)**。

run#106 がその2つを直接捕まえていた: `F000:D882-D883` と `D88E-D88F` が
**一度も書かれていない**(`LDN 12`、16 のはず)。CPU がそこで読んだ値は
壊れたデータではなく**未初期化メモリ**だった。

**SDRAM のテストベンチが全部通り続けていたのは当然で、SDRAM は一度も間違っていない。**

### 1.1 修正(すべて実測で効果確認)

1. **オープンロウ化**(`sdram_mp.sv`)
   毎トランザクションが ACTIVATE / アクセス / PRECHARGE で、
   ロウが既に開いていても前に4クロック(ACT + T_RCD)、後ろに4クロック(PRE + T_RP)払っていた。
   ロウを開いたままにする: ヒットなら両方スキップ、
   同バンクのミスなら元々払うはずの PRECHARGE 1回(`S_PRE_MISS`)。
   ローダは連番アドレスなので `{row,bank,col}` = `addr[23:11]`,`addr[10:9]`,`addr[8:0]`
   で **512回に511回ヒット**。→ **19.11 → 10.35**

   > リフレッシュ経路の PRECHARGE ALL は必須なので残してある
   > (バンクが開いたままの AUTO REFRESH は違法)。`S_REF_PRE` で全フラグをクリアする。

2. **tWR の後回し**(`sdram_mp.sv`)
   tWR は「最後の書き込み → そのバンクの PRECHARGE」の間にだけ必要で、
   ロウを開いたままにした今その PRECHARGE は出口で起きない。
   `S_RW` が最終ビートで完了を報告し、`pre_guard` が
   **PRECHARGE しうる2つ(ロウミスとリフレッシュ)だけ**を押さえる。→ **10.35 → 7.25**

3. **ローダの整定短縮**(`core_top.sv`)
   1バイトごとの整定を 5→2 クロック。`RAM.sv` は `write_command` が落ちた次サイクルに
   `COMPLETE_RAM_RW` を抜けるので、4クロックは無駄だった。

`tb_ram_ab` が clocks/byte を表示するようになったので、**この数字は今後ビルドゲート**。

### 1.2 残っている宿題

- **`data_loader` にバックプレッシャーが無いこと自体は直っていない。**
  今は 7.25 < 10.9 で間に合っているだけで、消費が遅くなる変更
  (バースト、追加ポート、GDC のフェッチ)を入れると再発する。
  **`DROP` は計測器として残してあるので、変更のたびに 0 を確認すること。**
- ext ポートのリードが壊れている(§1.4)
- 読み出しパスの STA -2.357ns(§1.5。ただし KFSDRAM も同値でそちらは起動する)

### 1.4 計測器についての教訓(この日だけで3回踏んだ)

1. **取り込みエッジ**: 読みデータはサイクルの**末尾**で有効。
   先頭でラッチすると1つ前の値が入る。POST ポートで直したのに ROM スヌープで再発させた。
2. **AEN の修飾**: `Bus_Arbiter` は `address_enable_n <= hold_acknowledge`、
   `hold_request = dma_hold_request | ext_access_request`。
   **ext アクセスは DMA と同じくゲストバスを AEN 高で駆動する**。
   run#105 で `guest_peek` の6回が ROM 窓に入り、`N` が 16→22 になって
   `RD0` の先頭6バイトが CPU の値でなくなった。窓は `~address_enable_n` で修飾すること。
3. **バスを奪う計測は測定対象を壊す**: `guest_peek` は `ext_access_request` を上げる。
   testB21〜23 の POST 54 はこれ。現在は `idle_ticks >= 4000 && post_max >= 0x08` でゲート。

**ext ポートのリードは壊れている**: 最初の1アクセスだけ正しく、以降は定数
(`MEM F8 51 51 51 51 51`、セルフテストマスタは `ROM 11 11 ...`)。
`st_rdata` 経由とバススヌープの両方が同じ値を示したので、片方の取りこぼしではなく
本当にそういうデータが返っている。**直すまで ext リードの答えを信用しないこと。**

### 1.5 ✗ 外れた対策(繰り返さないこと)

- ✗ **PLL 位相 11640 → 8730 ps**(run#104): **両方悪化**。11640 に戻した。

  | | 11640 ps | 8730 ps |
  |---|---|---|
  | setup write/command | +4.395 | +2.018 |
  | setup read | **-2.357** | **-4.585** |
  | hold write/command | — | +11.429 |
  | hold read | — | +16.021 |

  「早めれば書き込み側の余りが読み出し側に 1:1 で移る」というモデルが間違っている。
  逆方向の3点目を取るまで動かさないこと。
  位相は量子化されている(VCO 687.2727 MHz、周期 1455.03 ps、**1455 ps の整数倍のみ**。
  `8264 ps` は Fitter に拒否される)。

- ✗ **CAS レイテンシ 3**(testB22): STA が動かず(-2.408 → -2.357)、実機も不変。
  この制約が測るのは「部品が出してから FPGA が掴むまで」のピン間関係で、CL は無関係。

- ✗ **`-max 3.5` への較正**: STA 悪化(-2.408 → -5.222)。5.9 に戻した。

- △ **`sdram_a`/`sdram_ba` の毎サイクルクリアを止めた**(SSO 低減、testB23):
  効果は未証明だが害も無いので残してある。
  **PCXTDEV でも起動音は鳴っていた**ので「これで直った」とは言えない。

> **読み出しパスの STA -2.357ns について**: run#101 と run#105 で**完全に同値**
> (write 側は配置差で 4.395→3.548 と動いているのに)。配置が変わっても動かない値は
> 配線遅延ではなく制約の算術から出ている疑いが濃く、しかも **KFSDRAM も同値で
> そちらは実機で起動する**。この数字は「動く/動かない」を分けていない。
> hold 側には 11〜16ns 余っている。

### 1.6 アドレスマッピング(実測で確定)

`RAM.sv` は 1 PC バイトを **SDRAM の 16bit ワード1個**に割り当てる
(`access_address = {7'h00, latch_address}`、`access_num = 1`、データは下位8bit)。
`sdram_kf_shim` の `ADDR_BITS` は 9+13+2 = 24 で、**バイトアドレスがそのままワードアドレス**。

`sdram_mp` の写像は `{row, bank, col}` = `addr[23:11]`, `addr[10:9]`, `addr[8:0]`。

| 番地 | row | bank | col |
|---|---|---|---|
| `FD880` | 507 | 0 | 128 |
| `FD883` | 507 | 0 | 131 |

### 1.7 シミュレーションのカバレッジ穴(塞いだ)

`tb_ram_ab` / `tb_ram_ab_ph` の既存テストは、上の写像だと
`0x01000` の512バイトも `0x02000` の256バイトも**バンク0の1ロウに丸ごと収まる**。
バンク切り替えもロウ跨ぎも一度も踏んでいなかった。

追加した2フェーズ(両ベンチ):

1. `0xFD800` から 2KB — バンク境界4回とロウ境界1回を跨ぎ、`0xFD880-83` を含む
2. **BIOS ローダのカデンス** — `bios_load_state` 02〜04 をそのまま写した

**結果: `sdram_mp` は全部 PASS**(理想タイミングでも基板タイミングでも違反0・誤り0)。
今となっては当然で、故障は SDRAM に無い。

> ローダのカデンスのフェーズは `SDRAM_USE_MP` 側でだけ走らせている。
> 実カデンスで **KFSDRAM はモデルに対し tRP 違反を 41 回出す**(データは正しい)。
> 既知良品のリファレンスを落とす刺激は悪い刺激なので、記録するがゲートにはしない。

## 2. セルフテストが表示されない件(**保留**。現在の作業対象ではない)

> ⚠️ §1.0 で故障箇所が SDRAM の**手前**(BIOS ローダ)に確定したので、
> この節の追跡は保留。ただし **ext ポートのリードが壊れている**という事実
> (§1.4)はここから来ており、いずれ直す必要がある。

### 2.1 経緯

実機で「どのアドレスで何が壊れたか」を見るためのコア内蔵セルフテストを実装した
(設計: `docs/P0_SELFTEST_SPEC.md`)。**3ビルド出して実機表示は一度もゼロ。**

| ビルド | 出力手段 | 実機 |
|---|---|---|
| testB9 (#61) | OSD オーバーレイ(結果表示のみ) | スプラッシュのまま |
| testB10 (#63) | OSD + **アクセス前にバナー** + 進捗 + パイロット | スプラッシュのまま |
| testB11 (#64) | **CGA テキストVRAM 直書き**(0xB8000) | スプラッシュのまま |

testB11 の1行目 `SELFTEST START` は **SDRAM を一切使わない CGA VRAM への書き込み**。
それすら出ない。

### 2.2 潰した箇所(すべてシミュレーションで検証済み)

| 検証項目 | 手段 | 結果 |
|---|---|---|
| ファームにコードが入っているか | `llvm-nm` / `llvm-objdump` | ✅ `sdram_selftest_run` @0x31f8、main から呼出 |
| スピンループがハングしないか | 逆アセンブル | ✅ 上限2000(`li a0,0x7cf`) |
| RAM.sv レベルの ext シーケンス | **`sim/tb_ext_access.sv`(新規)** | ✅ 書き/読み/バンク1 正常(ref/mp両方) |
| CGA VRAM がガードで抜けるか | 同上 | ✅ complete=0 / 200サイクル(想定通り) |
| リセット中の 8088 status | `biu_max.v:280` | ✅ `S2_S0_OUT = 3'b111`(passive) |
| **Bus_Arbiter のホールド調停** | **`sim/tb_ext_arbiter.sv`(新規)** | ✅ granted、3アクセス完了(KF 4〜7 / mp 15サイクル) |

**= ext ポート → 調停 → RAM.sv → SDRAM の全経路は正常。**

### 2.3 残っている未検証区間(ここに原因がある)

1. **`core_top.sv` のセルフテスト・シーケンサ**(`st_state` FSM、l.1490付近)
2. **`softcpu_subsystem.sv` の MMIO**(region `0x5`、l.243付近)
3. その間の clk_pico ↔ clk_chipset ハンドシェイク

目視精査では**両方とも正しく見える**(FSM の状態遷移、`cpu_mem_addr[3:2]` デコード、
`cpu_mem_ready` によるコミット、st_req/st_done のハンドシェイク)。見つけられていない。

### 2.4 次の一手

**softcpu_subsystem + core_top のシーケンサをシミュレーションする。**
picorv32 / altsyncram / synch_3 のスタブが要る。これで最後の区間が埋まる。

> ⚠️ **CHIPSET 丸ごとは Verilator で elaborate できない。**
> `Peripherals.sv:1385` が `ide0_data_bus_out` にブロッキング/ノンブロッキング混在代入
> (`%Error-BLKANDNBLK`)。arbiter 単体なら通る(`sim/stub_saa1099.sv`、`sim/stub_vhdl.sv`
> = uart_16750 と dpram の VHDL スタブが必要。`-Wno-PROCASSWIRE` も要る)。

### 2.5 この失敗から得た教訓(繰り返さないこと)

**自分が新しく書いた RTL をシミュレーションせずに実機へ出した。**
このプロジェクトは「動作既知の参照を同じ TB に通す」という鉄則で何度も救われてきたのに、
その鉄則を他人のコード(sdram_mp)にだけ適用し、自分の追加コードには適用しなかった。
実機3往復を無駄にした。**新規 RTL は必ず TB を通してから SD に載せること。**

## 3. 技術知見(これまでのセッションで確定したもの)

1. **rbf_r パッケージ変換は「バイト内ビット順のリバース」(0x6a→0x56)。XOR 0xFF ではない。**
   CI の生 rbf は `FF×128 + 6a 6a 6a 6a 36 f4` で始まり、ビット順反転すると正規形式
   `FF×128 + 56 56 56 56 6c 2f`(SD 内278コアすべてがこの形式)。
   実証: `bitrev(build/b1/ap_core.rbf) == dist/testB1/.../bitstream.rbf_r` が
   **全 1,741,492 バイト一致**(実機 BIOS 動作実績ペア)。XOR 0xFF に読み替えると
   `00×128` 始まりになり Load error。変換コードは `scripts/package.sh`。
   パッケージ手順: `dist/testB1` をコピーして bitstream.rbf_r だけ差し替え(過去実績あり)。
2. **dram_clk は clk_chipset と半周期(180°)逆相。** リードデータの *launch* が negedge 同相
   ということは、**有効窓の中央は posedge** という意味。「逆相だから negedge で取る」は
   逆向きの誤り(testB6 で1ビルド失った)。KFSDRAM の実サンプル点 P+CL+1 posedge に
   合わせるのが唯一の正。導出は §1.1。
3. **KFSDRAM(実績品)の設計値**: CL=2・BL=1・毎サイクルパイプラインREAD・
   リフレッシュは enable_refresh 駆動(バスアイドル時)+ 1024サイクル(23.8µs)強制。
   23.8µs は規格違反だが実機で動く = リフレッシュ間隔は致命要因になりにくい。
4. **自作モデルの教訓(2度やらかした)**:
   - モデルの DQ 駆動は実部品の「次データで置換されるまで保持」を再現すること
     (`sdram_model.sv` はスロット CL-1〜CL+1 の3スロット保持に修正済み)
   - **TB は必ず動作既知の参照(KFSDRAM)も同じ条件で通すこと**。
     参照が落ちるなら疑うべきはモデル/ TB 側
   - 同相クロックのモデルはこの基板では位相が違う。逆相+フライト遅延込みが
     `sim/sdram_board_model.sv`(T_CO=7ns / T_RET=8ns。実測値ではないので過信しない)
5. **SDC は `pcxt-base/src/fpga/core/core_constraints.sdc` が唯一の正**(47行→現在)。
   `apf/apf_constraints.sdc` が `read_sdc` で読む。リポジトリ直下の
   `src/fpga/core/core_constraints.sdc`(185行)は**姉妹プロジェクト由来でビルドされない**
   — PLL インスタンス名が `ic|mp1|mf_pllbase_inst|...` でこの設計には存在しない。
   数値の参照元としては有用(同一基板・同一 SDRAM 部品)だが、そのままコピーしないこと。
6. **STA の "worst-case slack" は制約したパスについてしか語らない。**
   `Unconstrained Input/Output Ports` セクションを必ず見ること。今回 SDRAM 全ピンが
   そこに並んでいた = 解析パス0本。`scripts/check_sdram_paths.tcl` が CI でこれを見張る。
7. **シミュレーション環境**: Docker `pc98-sim` イメージ(Verilator 5.020)。
   `bash sim/run_ph.sh` で tb_ram_ab を ref / mp / mp_kfref の3モード実行。
   CI(`.github/workflows/build.yml`)に全TB+ボードタイミング版を回帰登録済み。
   落とし穴: Verilator 5.020 の `fork/join` は SIGSEGV。コメント内に "verilator"
   という単語を書くとディレクティブ誤解析でエラー。
8. **ビルドは CI 一択**(13〜15分)。ローカル Docker は45分以上かかる(検証済み、使わない)。
   DNS 故障中は `scripts/tools/ghpush2.py` で push(履歴維持)、`getartifact.py <run> <dest>`
   で成果物取得、`ghpoll2.py` で状況(たまにタイムアウトするので `ghlib` 直叩きも可)。
   `diskutil eject /dev/disk4` は今回のセッションでは成功した(以前は権限エラーだった。
   失敗したら Finder をユーザーに依頼)。
9. **`SDRAM_USE_MP`(config.tcl)** = shim 経由で mp を有効化。
   `SDRAM_MP_KF_REF` も追加すると shim の末端が純KFSDRAM に変わる(バイセクト用。
   testB4 の構成。enable_refresh を KFSDRAM に直結しないとリフレッシュ間隔違反になる)。
   コメントアウトで完全にKFSDRAMに戻る(testB3 の構成)。

## 4. 環境の注意事項

- **システムDNSが壊れている**(scutil --dns → No DNS configuration available)。
  すべてのネットワークは dig ピン留め(scripts/tools/ghlib.py が内蔵)。
  修復: `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8`(ユーザー作業)
- Docker Desktop はコンテナ内 DNS が生きている(sim イメージの構築/実行は可)
- firmware ビルドは Homebrew LLVM 23(`export PATH=/opt/homebrew/opt/llvm/bin:$PATH`)
- ROM 資産: `~/Documents/lodemnc/np2rom/`(bios.rom 96KB / font.rom 288KB / sound.rom 16KB)
- 参照ソース: `~/repo/_refs/`(X68000_MiSTer, NP2kai — np2 は挙動リファレンス専用)

## 5. 次セッションの作業リスト(優先順)

### A. まず `DROP` の数字を見る(run#107、実機テスト待ち)

| `DROP` | 次 |
|---|---|
| 0 でない | **FIFO 溢れ確定**。§B へ |
| 0 | 溢れではない。§1.3 の `ioctl_wait` ack 誤用を疑う |

### B. `DROP` が 0 でなかった場合の対策設計

`data_loader` に **ready/backpressure が無い**のが根本。選択肢:

1. **`data_loader` に ready 入力を足す**(本命だが `data_loader.v` 側の変更)。
   `write_en` を出す前に `~rlf_full` を待たせる。
   `clk_74a` → `clk_chipset` の CDC を跨ぐので、full の同期化が必要
2. **FIFO を深くする** — `HW`(高水位)が 256 に張り付いているなら、
   平均で消費が追いつかない可能性があり、深くしても解決しない。
   `HW` の数字を見てから判断すること
3. **ロード中だけ RAM.sv の待ちを短くする** — 消費を速くする方向。
   ただし SDRAM の実タイミングを削ることになるので最後の手段

> `HW`(FIFO 最大到達段数)が対策の選択を決める。256 張り付き = 平均で負けている。
> 256 未満なら瞬間的なバーストなので、深くするだけで足りる。

### C. ローダが直ってから戻る所

1. **ext ポートのリードを直す**(§1.4。最初の1アクセスだけ正しく以降は定数)
2. SDRAM 読み出しパスの STA -2.357ns — ただし **KFSDRAM も同値でそちらは起動する**
   ので、これ単独では「動かない理由」ではない(§1.5 の注記)
3. P0 手順4: `gram_cache.sv` の実装(設計済み: `docs/P0_CACHE_DESIGN.md`)
4. その後 85.9MHz 化 → P1(PC-98メモリマップ)

### D. 運用

- **実機テストはユーザー担当。ビルド・解析・SD 投入はこちら**
- `scripts/deploy.sh --core PCXTA` で CI 監視 → 取得 → 変換 → カード待ち →
  書き込み → verify → eject まで自動。**push はしないので先に
  `scripts/tools/ghpush2.py`** を実行すること
- カード待ちは90分でタイムアウトする。切れたら `--run <番号>` で再開できる
- CI 待ちの間は待たずに次のタスクへ(ビルドは15分)
- `/goal` 継続用プロンプト:

```
docs/GOAL.md のゴール(実機で PC-98 ソフトが GDC グラフィックと FM音源つきで
実用速度で動く)に向けて進める。現在地と次の一手は docs/HANDOVER.md §1/§5 を唯一の正とし、
メモリ設計の判断は docs/P0_MEMORY.md に従う。

1イテレーションで (1) 未完タスクを1つ進める (2) 結果を HANDOVER.md に反映
(3) commit する (4) 必要なら scripts/tools/ghpush2.py で push する。

停止条件:
- 実機テストが必要になったら、SD への投入まで済ませてユーザーに依頼し停止する
- 実機バイセクトの結果が想定外だったら、深追いせず次の仮説を1つだけ用意して報告する

CI ビルド待ちの間は待たずに次のタスクへ進む。
np2 のコードは移植しない(挙動リファレンスのみ)。
```

## 6. 現在のSD / 成果物の状態

- **SD(`/Volumes/ANALOGUE`)= `Cores/hiroya.PCXTA` に run#106 投入済み**
  - Pocket 側で USB アクセスモードに入ると Mac にマウントされる。
    書き込み後の `diskutil eject` は**残すこと**(macOS の書き込みキャッシュを流すため)
  - run#107(`DROP`/`HW` 表示つき)がビルド済み。投入待ち
- リモート main = `96bc02ee43`

## 7. 大事な約束事(以前から継続)

- np2 のコードは移植しない(挙動リファレンスとしてのみ使用)
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は dig ピン留め curl / ghlib 系ツールで回避する
- **自作 RTL を自作モデルで検証するときは、動作既知の参照実装を同じ TB に通すこと**
