# 引継ぎドキュメント(2026-09-07 夜セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. 現在位置(ここだけ読めば再開できる)

**P0(メモリアーキテクチャ)の山場: 自作SDRAMコントローラ `sdram_mp` の実機証明。**
**testB6 は ❌ 真っ黒。原因を特定した(下記)。testB7 を準備中。**

やっていること: desaster/openfpga-PCXT ベースのコアで SDRAM コントローラを
`KFSDRAM`(実績品)から自作 `sdram_mp`(マルチポート・バースト対応、PC-98 G-RAM 用)に
差し替える A/B。**全シミュレーションは緑なのに実機だけ BIOS まで届かない**バグを、
実機バイセクトで絞り込んでいる最中。

### 実機バイセクト台帳(全ビルド CI 成功・全シム合格のものだけ比較)

| テスト | run | 構成 | 実機結果 | 判定 |
|---|---|---|---|---|
| testB1 | #39 | 純KFSDRAM + 実firmware | ✅ BIOS POST | ベースライン(動作実績) |
| testB2 | #46 | shim + sdram_mp(2バグ修正済み) | ❌ スプラッシュ→真っ黒 | mp 経路が壊れている |
| testB3 | #49 | 現行ツリー + 純KFSDRAM | ✅ POST | **ツリー・KFSDRAM経路は健全** |
| testB4 | #51 | shimのグルー + 純KFSDRAM末端(`SDRAM_MP_KF_REF`) | ✅ POST | **shimグルーは無罪。犯人は sdram_mp 内部** |
| testB5 | #53 | mp + 幅キャスト定数 + 233µs INIT | ❌ 真っ黒 | 定数合成/INIT待ちの仮説は死んだ |
| testB6 | #54 | mp + negedge DQキャプチャ | ❌ 真っ黒 | **改悪だった**(§1.1)。posedge に revert 済み |
| testB7 | #57 | mp(posedge復帰)+ SDRAM I/O 制約 | (実機未投入) | **制約は効いた。読み出しパスの実違反が初めて可視化された** |
| **testB7b** | — | **上記 + dram_* を IO レジスタに固定** | **ビルド待ち** | **§1.4** |

症状(ユーザー観測): testB2/5 とも**スプラッシュ(ファームウェア描画)は出る→真っ黒**。
= picorv32 は正常・8088 は解放されているが、BIOS が SDRAM 依存コード
(スタック・メモリテスト)で死んでいる。メモリ破壊系と整合。

### 1.1 testB6 の negedge キャプチャは改悪だった(revert 済み)

逆相なので「negedge = 窓の中央」と考えたのが誤り。**逆相だからこそ posedge が中央**になる。

READ がバスに出るサイクルを P とすると:
- 部品は**自分の立ち上がり = 我々の negedge** でコマンドを取り込む → P+0.5 で READ 確定
- CL=2 のデータ launch は device edge P+0.5+2 = **negedge P+2.5**
- 有効窓は概ね `[P+2.5+tAC, P+3.5+tOH]` ≒ `[P+2.7, P+3.6]`(サイクル単位)
- → **窓の中央は posedge P+3**。negedge P+2.5 は *launch の瞬間そのもの*で tAC 前 = 前ワードを掴む

**KFSDRAM(実機実績)の実サンプル点を追うと厳密に P+3。**
IDLE→READ 遷移サイクル C0 で ACT、state=READ の cycle0 で READ コマンド発行
(バスは [C0+1, C0+2) なので P=C0+1)、`read_flag_comb = state_counter > cas_latency`
が cycle3 で立ち、`data_out <= sdram_dq_in` は posedge C0+4 = **P+3**。

**testB5(posedge 版)も P+3 で完全一致していた。** つまり読み出し点は元から正しく、
testB6 が半サイクル早めて壊した。testB5 の失敗原因は別のところにある(→ §1.2)。

> ⚠️ だった問題: `sim/sdram_board_model.sv` は **posedge 版と negedge 版の両方を PASS
> させていた**。原因は `sdram_model.sv` が1ワードを CL-1〜CL+1 の**3スロット**保持して
> いたこと(実部品は自分の1周期だけ)。窓が3倍広ければ何でも祝福する。
> **修正済み**: `PHYSICAL_DQ` パラメータを追加し、board model 側は 1(= スロット CL のみ、
> 実周期ぴったり)で駆動する。ゼロ遅延の `tb_ram_ab` 側は従来どおり 0。
> 検証: KFSDRAM 参照 PASS / posedge mp PASS / **negedge(testB6)版は全 read が 00 で FAIL**。
> これでこの TB は「DQ サンプル点」に対する判別能力を持つ。

### 1.2 真因: **dram_* ピンにタイミング制約が1つも無かった**

`build/artifact_54/ap_core.sta.rpt` が明言している:

```
Unconstrained Input Ports:   dram_dq[*]   "No input delay ... found"
Unconstrained Output Ports:  dram_a[*] dram_ba[*] dram_dqm[*] dram_clk
                             dram_ras_n dram_cas_n dram_we_n dram_dq[*]
```

= **SDRAM インターフェースで解析されたパスはゼロ**。帰結が3つ、そのまま今回のバグ:

1. Fitter に SDRAM ピンのタイミング目標が無く、ドライブ元レジスタを自由に配置した
2. STA の worst-case slack は SDRAM について**沈黙していただけ**。このバイセクト中の
   「全部緑」レポートは SDRAM について何も言っていない
3. よって配置がリコンパイルのたびに変わり、**ビルド毎に変動するマージナルな回路**になる。
   シミュレーションが構造的に再現できない唯一のクラス = 「全シム緑・実機だけ黒」の正体

**fit のくじ引き度合いは6ビルドで実機結果と完全に分離する**
(CGA ドメイン general[3] の TNS を代理指標として):

| ビルド | 構成 | 実機 | TNS | ALM |
|---|---|---|---|---|
| #49 testB3 | 純KF | ✅ | **-1.30** | 12,049 |
| #51 testB4 | KF末端 | ✅ | **-1.07** | **12,233** |
| #42 | mp | ❌ | -5.52 | — |
| #46 testB2 | mp | ❌ | -5.26 | — |
| #53 testB5 | mp | ❌ | -3.89 | 12,183 |
| #54 testB6 | mp | ❌ | -6.35 | 12,170 |

**論理量の効果ではない**: 最良スコアの testB4 が最大(12,233 ALM)。

KFSDRAM が生き残っていたのは、出力が素朴な `casez` レジスタ直結で経路が浅く、
くじ引きに勝ち続けていたから。sdram_mp は負けた。

### testB7 の中身

1. **DQ キャプチャを posedge に revert**(KFSDRAM 準拠の P+3。§1.1)
2. **SDRAM I/O 制約を追加**(`pcxt-base/src/fpga/core/core_constraints.sdc`)。
   数値は同じ基板・同じ部品で動いている姉妹コア(`src/fpga/core/core_constraints.sdc`、
   MacLC/Pocket-Amiga 系)由来: read `-max 5.9 / -min 0.9`、
   write/command `-max 2.0 / -min -1.0`、いずれも `-reference_pin dram_clk`。
   general[0]=clk_chipset(コントローラ)と general[2]=clk_sdram_ph(dram_clk ピン)は
   **既に同一クロックグループ**なので、launch→chip の関係が成立し制約が効く。
   - **姉妹コアの `set_multicycle_path -setup -end 2` は移植しない。** あちらのコントローラ用で
     こちらでは誤り。dram_clk は clk_chipset の反転なので、部品は我々の negedge で
     データを出し、sdram_mp も KFSDRAM も**次の posedge**で取る = 正真正銘の
     シングルサイクル(窓は半周期 11.64ns)。2周期与えると実在する違反を隠す。
3. **`scripts/check_sdram_paths.tcl` + CI ゲート**を追加。解析パスが0本なら赤くする。
   「パスの裏付けが無い良い slack 値」= このファイル群が存在する理由そのもの。

### 1.3 実測: mp のアクセスレイテンシは KFSDRAM の2倍(今は無害、turbo では致命)

board-timing TB に計測プローブを入れて実測(read command → data_bus_out 確定までの
chipset サイクル数):

| コントローラ | レイテンシ |
|---|---|
| KFSDRAM | **5 サイクル** |
| sdram_mp(shim 経由) | **10 サイクル** |

**RAM.sv の CPU ハンドシェイクは完了待ちではない。** `access_ready <= idle` は IDLE 状態で
拾うので、コマンド提示の約1サイクル後に `memory_access_ready` が上がる。CPU を実際に
守っているのは 8088 のバスサイクル長そのもの(オープンループ)。

- 起動時 `clk_select = 2'b00`(リセット既定)= 4.77MHz = **バスサイクル 36 chipset cycle**。
  10 < 36 なので**今回の真っ黒の原因ではない**。
- 最速 turbo `2'b11` は `cpu_edge_num/den = 1/1` = **42.95MHz 等速**。バスサイクルは 4 cycle 級で、
  KFSDRAM ですら `ram_read_wait_cycle=1` + `shift_read_timing` で補正している
  (`XT_CE_Generator.sv`)。**mp の 10 サイクルはここに収まらない。**

→ P0 完了後、または testB7 が黒だった場合の候補: shim の `T_RCD`/`T_RP`(現在 2)を詰める。
sdram_mp は `timer` が 0 になるまで次状態に進まないので ACT→READ に実質4サイクルかかる
(KFSDRAM は1)。ここだけでレイテンシは大きく縮む。

### 1.4 run#57 の結果: 制約は効き、隠れていた違反が数字になった

`build/artifact_57/ap_core.sta.rpt`:

- **`Unconstrained Input/Output Ports` から dram_* が全消滅**(0件)。
  プロジェクト史上はじめて SDRAM が解析対象になった。
- setup summary の変化:

| クロック | testB6(#54) | testB7(#57) | 意味 |
|---|---|---|---|
| general[0] clk_chipset | +2.463 / TNS 0 | **-2.417 / TNS -18.068** | **今まで見えていなかった読み出しパスの違反** |
| general[2] clk_sdram_ph | (表に無し) | +3.297 / TNS 0 | 新規に解析対象化 |
| general[3] clk_28_636 CGA | -0.977 / TNS -6.35 | **-0.386 / TNS -2.002** | 実目標を与えたら fit 全体が改善(動作実績ビルドより良い) |

TNS -18.068 が約16エンドポイントに分散 = **DQ 16ビットの捕獲FF**。予算計算とも一致:
半周期 11.64ns − 入力遅延 5.9ns(tAC+フライト)= **5.74ns** しか pin→FF 配線+setup に無く、
ファブリック上の FF では届かない。

### 1.5 testB7b(温存していた2手目を投入)

`ap_core.qsf` に `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` を dram_* に追加し、
**捕獲FF・駆動FFを IO セルに固定**する。読み出しパスからファブリック配線が消え、
同時に配置がビルド間で動かなくなる(= 病気の本体だった「くじ引き」を構造的に消す)。

KFSDRAM 側でも成立することを確認済み(パッキング条件は「FF がピンだけに繋がること」で、
`p_rdata <= sdram_dq_in`(mp)も `data_out <= sdram_dq_in`(KFSDRAM)も満たす)。
A/B の参照が壊れない。

### testB7b の判定と次の一手

- ✅ **POST が出る** → sdram_mp 実機動作確定、P0 残作業へ(§4-A)
- ❌ **真っ黒** → まず `ap_core.sta.rpt` の **SDRAM パスの実 slack** を読む
  (CI ステップ "SDRAM interface is actually timed" が各コーナーの write/read setup を出す)。
  ここで初めて SDRAM に対する意味のある数字が手に入る。
  - 制約が閉じているのに黒 → §5-B のコア内蔵セルフテストへ
  - 制約が閉じていない → `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` を dram_* に付けて
    レジスタを IO セルに固定する(配置くじ引きを構造的に消す。今回は温存した2手目)

## 2. 技術知見(今回のセッションで確定したもの)

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

## 3. 環境の注意事項

- **システムDNSが壊れている**(scutil --dns → No DNS configuration available)。
  すべてのネットワークは dig ピン留め(scripts/tools/ghlib.py が内蔵)。
  修復: `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8`(ユーザー作業)
- Docker Desktop はコンテナ内 DNS が生きている(sim イメージの構築/実行は可)
- firmware ビルドは Homebrew LLVM 23(`export PATH=/opt/homebrew/opt/llvm/bin:$PATH`)
- ROM 資産: `~/Documents/lodemnc/np2rom/`(bios.rom 96KB / font.rom 288KB / sound.rom 16KB)
- 参照ソース: `~/repo/_refs/`(X68000_MiSTer, NP2kai — np2 は挙動リファレンス専用)

## 4. 次セッションの作業リスト(優先順)

### A. testB7 が ✅ の場合(P0 完了へ)

1. HANDOVER に結果を記録・commit → **P0 手順4: `gram_cache.sv` の実装**
   (設計済み: `docs/P0_CACHE_DESIGN.md`。プレーンインターリーブ配置、
   表示ラインバッファ1 + ライトバックキャッシュ8 ≒ M10K 10ブロック)
2. その後 85.9MHz 化(クロック配線が CHIPSET〜core_top に波及する別変更)、
   PCXT が引き続き DOS ブートするか確認 → P1(PC-98メモリマップ)へ

### B. testB7 が ❌ の場合(SDRAM の実 slack を読んでから、セルフテストへ)

0. **先に `ap_core.sta.rpt` の SDRAM パス slack を読む**(§1.2 で初めて数字が出るようになった)。
   閉じていないなら `FAST_INPUT_REGISTER`/`FAST_OUTPUT_REGISTER` を dram_* に付けるのが先。
1. **コア内蔵 SDRAM セルフテスト**: 起動時にパターン書き→読み戻しを mp 経路で実行し、
   **OSD(スプラッシュ描画と同じ経路)に「最初の不一致アドレス/got/want」を表示**。
   実装先の候補: softcpu firmware(`pcxt-base/src/firmware/`、MMIO 経路は
   softcpu_subsystem.sv の FDD/IDE サービスがゲストRAMへ書く経路を流用)
   か、shim 内の独立テストFSM+bridge 窓。これで実機テストが「黒かどうか」から
   「どこでどう壊れるか」に変わり、残りの切り分けが一気に速くなる
2. 並行候補: mp のリフレッシュ設計を KFSDRAM 型(enable_refresh 駆動)に寄せる、
   T_RCD/T_RP を KFSDRAM と同一サイクルに寄せる、CL=3 化 — セルフテストの観察結果が出てから

### C. 共通

- 実機テストはユーザー担当。SD 投入・イジェクト・ビルド・解析はこちら
- CI 待ちの間は次のタスクへ(ビルドは15分)
- `/goal` 継続用プロンプト(更新版):

```
docs/GOAL.md のゴール(実機で PC-98 ソフトが GDC グラフィックと FM音源つきで
実用速度で動く)に向けて進める。現在地と次の一手は docs/HANDOVER.md §1/§4 を唯一の正とし、
メモリ設計の判断は docs/P0_MEMORY.md に従う。

1イテレーションで (1) 未完タスクを1つ進める (2) 結果を HANDOVER.md に反映
(3) commit する (4) 必要なら scripts/tools/ghpush2.py で push する。

停止条件:
- 実機テストが必要になったら、SD への投入まで済ませてユーザーに依頼し停止する
- 実機バイセクトの結果が想定外だったら、深追いせず次の仮説を1つだけ用意して報告する

CI ビルド待ちの間は待たずに次のタスクへ進む。
np2 のコードは移植しない(挙動リファレンスのみ)。
```

## 5. 現在のSD / 成果物の状態

- **SD(`/Volumes/ANALOGUE`)= testB6 投入済み・イジェクト済み**(2026-09-07 夕)
  - `Cores/hiroya.PCXTDEV/`(JSON/boot.bin は testB1 流用・検証済み)
- ローカル: `dist/testB1` 〜 `dist/testB6`、`build/artifact_{42,46,49,51,53,54}/`
  (git 管理外。run#54 の fit/sta レポート入り)
- リモート main = `271f84f774`(ローカル `f8f93d5` まで反映。履歴維持 push)

## 6. 大事な約束事(以前から継続)

- np2 のコードは移植しない(挙動リファレンスとしてのみ使用)
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は dig ピン留め curl / ghlib 系ツールで回避する
- **自作 RTL を自作モデルで検証するときは、動作既知の参照実装を同じ TB に通すこと**
