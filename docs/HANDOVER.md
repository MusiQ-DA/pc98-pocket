# 引継ぎドキュメント(2026-09-10 セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. ★現在位置(2026-09-10 早朝)

### 1.0 P0 は完了。SDRAM は解決済み

`sdram_mp` は実機で PC/AT BIOS を POST 完走させ、`No ROM BASIC` まで到達した(run#109)。

**故障は SDRAM の正しさではなくスループットだった。**

| コントローラ | ローダ1バイト | 実機 |
|---|---|---|
| KFSDRAM | 8.08 クロック | 起動する |
| sdram_mp(修正前) | **19.11** | 起動しない |
| 予算(APF の供給速度) | 約 10.9 | |
| **sdram_mp(修正後)** | **7.25** | **POST 完走** |

`data_loader` に ready 入力が無く、ロード FIFO は満杯で**黙って捨てる**。
1.75倍負けていた結果が `DROP 4682`(BIOS イメージの約14%)。
修正は **オープンロウ化**(19.11→10.35)と **tWR の後回し**(→7.25)。

> ⚠️ **バックプレッシャー欠如は未修正。** 速度差で勝っているだけなので、
> **消費が遅くなる変更(バースト、ポート追加、GDC/漢字フェッチ)のたびに
> OSD の `DROP` が 0 のままか確認すること。**

### 1.1 ★ 現在の作業: PC-98 BIOS 起動シーケンス。FDD の先まで来た

実機コアは `hiroya.PC9801`(ROM・ファーム込み完全パッケージ、
`scripts/deploy_pc98.sh` で投入)。**run#170 がビルド済み・SD投入待ち。**
BIOS は PC-9801VM の実機ダンプ(V30 機=全 8086 コード)で直入り。

起動シーケンスの通過状況(それぞれ実機観測と tb で裏取り済み):

| # | 関門 | 箇所 | 状態 |
|---|---|---|---|
| 1 | 8253 カウンタ試験 | FD873(ゲート固定に修正) | ✅ run#164 |
| 2 | DMA レジスタ試験 | FD8E6(0x01-0x0F 奇数) | ✅ |
| 3 | 8259 IMR 試験(両方) | FDA4F(slave PIC を実装) | ✅ run#166 |
| 4 | タイマー割り込み INT 08 | FDA83(KF8259 の IRR をラッチ式に修正) | ✅ |
| 5 | CRT 割り込み(VSYNC→IRQ2) | FED44(crt_vsync_irq を実装) | ✅ run#167 |
| 6 | GDC vsync 待ち(0x60/0xA0 bit5) | FDBB3/FDC3E(gdc_status は既存) | ✅ |
| 7 | FDD モーター系列(0xCC) | FF67D(100ms XTMASK タイマー→slave IRQ2) | 🔧 run#170 |
| 8 | FDC コマンド(SPECIFY/RECAL/SENSE) | FF6F5+(最小 μPD765 モデル、RECAL→slave IRQ3) | 🔧 run#170 |
| 9 | ブートビープ | FE0DB(8255 PC3 がゲート、spkdata を修正) | 🔧 run#170 |
| 10 | 画面クリア | TVRAM 全セル 0020/E1(tb で証明) | ✅ tb |
| 11 | メモリテスト+カウント表示 | — | tb 35秒で 280KB、90秒シミュ実行中 |
| 12 | IPL 読み出し(READ ID/DATA) | — | 未(FDC は「ドライブなし」で即失敗を返す) |

**run#170 の実機観測手順**(カードを挿し `hiroya.PC9801` を起動):
1. **画面**: メモリカウントの数字、エラーメッセージ、カーソル
2. **音**: 「ピポ」(FD8B4 のカウンタ2+PC3 ゲート)
3. **OSD**: `N`(17244 を超えれば 0xCC ループ解消)、`IO` の並び、`LIVE`
4. 期待: N は 17244 からさらに増え、IO に 0x90/0x92(FDC)が混ざる

#### 実機観測と tb の対応(ここまでの一致)

- 実機停止値 N=17244(IO `00CC 00CC 00CC 000A`)に対し、tb(FDC モデル込み)は
  I/O 17223 まで同一経路を歩く。差は事前 I/O 数の ±1
- LIVE の読み方: HLT の4バイト先読み位置として読むこと
  (FD89F=FD89B の HLT、FDA69=FDA65 の HLT、FED49=FED44 のスピン、等)
- `HIGH FFFFF` はリセットベクタでしかない(進捗指標ではない)

### 1.2 並行タスク

- **USB キーボード(ドック)**: `pocket_keyboard.sv` が既にドックの生キーを
  Set-2 ストリームに合成している(PC/XT 用)。PC-98 で使うには
  **Set-2 → PC-98 キーコード変換 + 8251(0x41/0x43)への注入**が必要。
  BIOS のキーボードありパス(`in 0x41` が 0x60)への切り替えもセット
- **tb**: `scripts/sim_pc98_boot.sh`(+gate2=N で PIT ゲート試験、
  +ccms=N で 0xCC タイマーを実時間に)。
  8253/8259×2/DMA スタブ/キーボードなし/FDC+0xCC モデル/GDC ステータス/
  周期 VSYNC/TVRAM スヌープを搭載
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
