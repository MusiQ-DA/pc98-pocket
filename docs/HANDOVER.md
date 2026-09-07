# 引継ぎドキュメント(2026-09-07 夜セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. 現在位置(ここだけ読めば再開できる)

**P0(メモリアーキテクチャ)の山場: 自作SDRAMコントローラ `sdram_mp` の実機証明。**
**現在地: コア内蔵セルフテスト(testB9/10/11)を実装したが、実機で何も表示されない。**
**原因はセルフテストの実装側にあり、SDRAM の話にはまだ戻れていない。** → §2

**SDRAM 本体について分かっていること**: testB7b(#58)で実機の症状が変わった。
スプラッシュ → **ビープ3回** → 停止。testB6 までは完全に無音。
**XT系BIOS のビープ3回 = base 64KB RAM failure** = SDRAM 先頭64KBがメモリテストで落ちる。
「SDRAM は全く動かない」から「データが壊れる」段階へ前進しており、
これまでの「メモリ破壊系」という推定が初めて BIOS 自身の言葉で裏付けられた。

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
| **testB7b** | **#58** | **上記 + dram_* を IO レジスタに固定** | **SD投入済・実機テスト待ち** | **§1.5 / §1.6** |
| testB7ref | #59 | 純KFSDRAM + 新SDC(測定専用) | (実機不要) | **§1.8 判別完了 = (a)。読み出しパスは無罪** |
| **testB8** | — | **mp + 較正済み入力遅延(3.5ns)** | **ビルド中** | §1.10 |

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

### 1.6 run#58: IO レジスタ化は効かなかった。-2.4ns は配線ではない

| クロック | testB7(#57) | testB7b(#58) |
|---|---|---|
| general[0] clk_chipset | -2.417 / TNS -18.068 | **-2.408 / TNS -17.914** |
| general[3] CGA | -0.386 / TNS -2.002 | -0.905 / TNS -8.196 |

パッキング自体は成功している(fit.rpt: `sdram_a[*]`/`cmd[*]`/`sdram_dq_out[*]` が
"Fast Output Register assignment" で `dram_*~output` に、`p_rdata[*]` が
`dram_dq[*]~input` に Packed Register)。**それでも slack が 0.009ns しか動かない。**

→ **-2.4ns はピン→FF の配線遅延ではない。** 予算の内訳を見直すと、`-reference_pin dram_clk`
は「SDRAM が見るクロック」基準なので、STA は **FPGA から dram_clk が出て行くまでの
clock-to-out 遅延**を launch 側に加算する。半周期 11.64ns はその分だけ食われており、
5.9ns の tAC+フライトを引くと確かに足りない。

### 1.7 ⚠️ 未解決の分岐: この -2.4ns は sdram_mp 固有か、インターフェース共通か

**ここが今いちばん重要な未確定点。** 2つの可能性があり、実機テストでは区別できない:

- (a) `-max 5.9` が この部品/基板には悲観的 → -2.4ns は両コントローラ共通の見かけ上の値で、
  真犯人ではない(KFSDRAM も同じ値を示すはず)
- (b) sdram_mp の読み出しパスが実際に KFSDRAM より悪い → これが真犯人

**判別実験 testB7ref**: `config.tcl` の `SDRAM_USE_MP` を外し、**純KFSDRAM + 新SDC** で
1本ビルドして SDRAM パスの slack を読むだけ(実機投入は不要)。

- KFSDRAM も ≒-2.4ns → **(a)**。制約値を実測ベースに見直す。読み出し点は犯人ではない
- KFSDRAM が正の slack → **(b)**。sdram_mp の読み出しパスを KFSDRAM と同じ深さまで削る

> 注意: 読み出しサンプル点は P+2.5(testB6)・P+3(testB5)・P+4(testB2、
> 「a cycle late で 0 を読んだ」と当時記録)の**3点とも実機で失敗している**。
> サンプル点そのものが犯人である可能性は低い。だからこそ (a)/(b) の判別を先にやる。

### ★ 1.7b セルフテスト実装の現状(2026-09-07 夜。ここが今の作業対象)

実機ビルドを **3本(testB9/10/11)使って情報ゼロ**。詳細は §2 に分離した。
**次のセッションは §2 から読むこと。**

### 1.8 ★判別完了: -2.4ns は sdram_mp のせいではない(読み出しパスは無罪)

run#59 = **純KFSDRAM + 同じ新SDC**(測定専用ビルド、実機投入せず):

| ビルド | 構成 | 実機 | 読み出しパス slack |
|---|---|---|---|
| #59 testB7ref | **純KFSDRAM** | **✅ 動作実績あり** | **-2.357 / TNS -17.784** |
| #58 testB7b | sdram_mp | ❌ | -2.408 / TNS -17.914 |

**実機で確実に動く KFSDRAM が、ほぼ同じ違反値を出す。** → §1.7 の分岐は **(a)** で確定。
`-max 5.9` がこの部品/基板に悲観的なだけで、**読み出しパスは犯人ではない**。もう追わないこと。

副産物として実 tAC+フライトの上界が得られた: `5.9 - 2.357 = 3.54ns`。
= 「動作実績構成が満たすと分かっている最大値」。SDC を **`-max 3.5`** に較正した
(1ビルドからの推論であって実測ではない、と SDC 内に明記済み)。
到達不能な制約は Fitter が他を諦める副作用もある(#57→#58 で CGA が -0.386→-0.905 に悪化)。

### 1.9 現在地のまとめ(ここから再開する)

**潰し終わったもの(もう戻らないこと):**

| 仮説 | 結果 |
|---|---|
| shim のグルー | 無罪(testB4 が POST) |
| DQ サンプル点 | **P+2.5 / P+3 / P+4 の3点とも実機失敗** → 犯人ではない |
| 定数の合成事故 / INIT 待ち | testB5 で死亡 |
| SDRAM I/O 無制約 | **真であり修正済み**。ただし単独では完治せず(症状は前進) |
| 読み出しパスの -2.4ns | **無罪**(動作実績の KFSDRAM が同値。§1.8) |

**新しい最重要事実:** testB7b で **音が出た**。testB6 までは無音。
POST が進んで診断を鳴らす段階に来た = **SDRAM は応答しているがデータが壊れている**方向。
「メモリ破壊系」というこれまでの推定と整合する。

**次に調べるべき残りの差分(sdram_mp vs KFSDRAM、優先順):**

1. ~~**書き込みデータのサンプル時刻**~~ — **このセッションで否定済み。追わないこと。**
   仮説は「RAM.sv の `latch_data <= internal_data_bus` は毎サイクル無条件なので、
   WRITE を req+5 サイクルで出す mp は遅く掴んで壊す(KFSDRAM は req+1)」。
   検証: TB で書き込みデータを3サイクル後に引っ込めるチェックを追加 →
   **参照の KFSDRAM も落ちた**(3アドレスごと = リフレッシュで WRITE が後ろへずれた分)。
   KFSDRAM は実機で動くのだから、`internal_data_bus` は実機で**十分長く保持されている**。
   よって遅いサンプルは犯人ではない。TB 変更は撤回済み(鉄則: 参照が落ちたら疑うのは TB)。
   ついでに shim 側ラッチも試したが **1サイクル早く掴んで mp を壊した**(766 data errors)ので撤回。
2. **リフレッシュ方式**。KFSDRAM は PRECHARGE ALL → AUTO REFRESH。
   sdram_mp は「毎トランザクション末尾で当該バンクのみ precharge 済み」を前提に
   AUTO REFRESH を直接発行する。前提が崩れる経路が1つでもあれば破壊される。
   ※ 机上では不変条件は成立して見える(INIT で PRECHARGE ALL、以降 ACT→RW→TAIL→PRE(cur_bank))。
3. **アドレス写像の違い**。KFSDRAM `{bank[23:22], row[21:9], col[8:0]}`(実質バンク0のみ・8192行)
   vs mp `{row[23:11], bank[10:9], col[8:0]}`(4バンク・2048行)。
   ※ 全単射なのでこれ単独ではデータを壊せない。優先度は低い。

**それでも切り分かない場合** → §4-B のコア内蔵セルフテスト。
ただし今は「音」という観測チャンネルが1本増えたので、
**OSD 表示より先に「ビープ回数で結果を鳴らす」セルフテスト**の方が安く実装できる可能性が高い。

### 1.10 testB8 の根拠(次の実機ビルド)

**「音が出た」のは制約が効いた結果である**、という読みが最も整合する:

- testB5 = posedge 読み出し + **無制約** → 無音
- testB7b = posedge 読み出し + **制約あり** → **発音**
- 読み出しサンプル点は testB5 と testB7b で同一

つまり差分は制約(= 配置とIOレジスタ = **物理マージン**)だけ。故障はマージン性であり、
今は「近づいたがまだ届いていない」状態と読める。

そして §1.8 で **`-max 5.9` は到達不能と判明し、3.5ns に較正した**。到達可能な目標を
与えれば Fitter は初めて本気で最適化できる(到達不能な目標は他所を諦める副作用があり、
実際 #57→#58 で CGA が -0.386→-0.905 に悪化していた)。

→ **testB8 = ロジック無変更 + 較正済み制約のみ。** 変数1個の正しい A/B。

### testB7b の判定と次の一手

- ✅ **POST が出る** → sdram_mp 実機動作確定、P0 残作業へ(§4-A)
- ❌ **真っ黒** → まず `ap_core.sta.rpt` の **SDRAM パスの実 slack** を読む
  (CI ステップ "SDRAM interface is actually timed" が各コーナーの write/read setup を出す)。
  ここで初めて SDRAM に対する意味のある数字が手に入る。
  - 制約が閉じているのに黒 → §5-B のコア内蔵セルフテストへ
  - 制約が閉じていない → `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` を dram_* に付けて
    レジスタを IO セルに固定する(配置くじ引きを構造的に消す。今回は温存した2手目)

## 2. ★セルフテストが表示されない件(現在の作業対象)

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

## 6. 現在のSD / 成果物の状態

- **SD(`/Volumes/ANALOGUE`)= testB11(セルフテスト版)投入済み**(2026-09-07 夜)
  - Pocket は USB 挿しっぱなしで運用中。物理抜き差しは不要で、
    Pocket 側で USB アクセスモードに入ると Mac にマウントされる。
    書き込み後の `diskutil eject` は**残すこと**(macOS の書き込みキャッシュを流すため)
  - `Cores/hiroya.PCXTDEV/`(JSON/boot.bin は testB1 流用・検証済み)
- ローカル: `dist/testB1` 〜 `dist/testB11`、`build/artifact_{42,46,49,51,53,54,57,58,59,60,61,63,64}/`
  (git 管理外。run#54 の fit/sta レポート入り)
- リモート main = `271f84f774`(ローカル `f8f93d5` まで反映。履歴維持 push)

## 7. 大事な約束事(以前から継続)

- np2 のコードは移植しない(挙動リファレンスとしてのみ使用)
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は dig ピン留め curl / ghlib 系ツールで回避する
- **自作 RTL を自作モデルで検証するときは、動作既知の参照実装を同じ TB に通すこと**
