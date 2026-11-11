# gvram-interleave ブランチ 結果まとめ

日付: 2026-11-11
ブランチ: `gvram-interleave`(main へ未マージ)

## 概要

GVRAM プレーン・インタリーブ(pc98_gvram_il)の段階2(line buffer 復活)
で見つかったバグ3件を修正し、速度調整の試みを行い、tb の EGC を本番
と同一化した。全ての検査が緑、CI 4 run 全 success、実機での動作確認済み。

## コミット一覧(5件、古い順)

| # | SHA | タイトル | 規模 |
|---|-----|---------|------|
| 1 | `4326937` | gvram seq: fix two RMW line-buffer bugs found by the neon3 golden stream | 10 files, +922/-319 |
| 2 | `e1dbfc2` | cycle table: regenerate baseline under Verilator 5.020 (host 5.052 skewed --timing) | 1 file, +73/-73 |
| 3 | `2ba840b` | gvram: document why vram_wait_now no longer calibrates the cycle table | 3 files, +45/-12 |
| 4 | `1f0696c` | gvram seq: consume the line-buffer dirty bitmap at flush latch | 2 files, +57/-4 |
| 5 | `d066022` | tb_mem_perf: build the seq with EGC=0 to match the board | 1 file, +8/-15 |

## 修正したバグ(3件)

### 第11+第12修正(コミット 4326937)— neon 169 mismatch

neon3_lines.ops ゴールデンストリーム(NEON3286 デモの np2ops キャプチャ)
が dx=00(line buffer ON)で 169 mismatches。TRC/FB/SLOTEV 同一 run 計装で
2つの独立バグを特定。

1. **fill ビート/完了スロット・デシンク(第11修正)** — fill の bank 格納
   アドレス(fb_wa)と完了時の rb_v/rb_tag が同じライブ wire ws を別サイクル
   に評価し、ws 反転で別スロットに散らばる。`fws`(fill slot ラッチ)を
   導入し、fb_wa と完了ブロックが同じスロットを参照するようにした。

2. **rb_ra pair ラグ(第12修正)** — `rbq` registered read のアドレス
   `rb_ra` が S_WR マージ発火サイクルも `gp[1]`(現プレーンのペア)のまま。
   pair 境界を跨ぐ chained RMW(gp=1→2)で chain 先の S_RBH が pair-0 語を
   読み、gp=2 の lane0 のみ常に誤読。RMW 式 `(old&~d)|(d&t)` で wd=0x1f の
   時は結果が old に依らず 0x1f になるため 161 パス中の特定パターンでのみ
   発覚(0x3D2 の 1f→18→10 逐次劣化)。

### 第13修正(コミット 1f0696c)— seqdx=2 の id=2076

seqdx=2(PF ON+即時 WB 実験モード)のみ 1 mismatch(id=2076=0xAA4D4
want 0x80 got 0x00)。WATCH+CY 計装で根因を特定。

**flush 完了時の `rb_d[fl_s] <= 4'h0` 全クリアが、flush と並走する次
walk の merge マークを破壊**。即時 WB では毎 walk 直後に flush が走る
ため、同一ライン連続 W8 の 2 本目 plane-0 マークが前 flush のクリア窓に
飲まれ、fl_d が B lane 欠落のまま writeback → mask で 0x80 が SDRAM に
落下せず。

修正: dirty bitmap の消費を flush 完了から **fl_start ラッチ時点**へ移動。

## 速度調整の結論

### 最終サイクルテーブル(baseline、np21w 参照比)

| 操作 | 8 MHz | 10 MHz | 12 MHz |
|------|-------|--------|--------|
| 34 TDW rep stosw 256 | 1.15 | 1.26 | 1.41 |
| 35 TDW x8 | 1.04 | 1.19 | 1.34 |
| 36 RMW rep stosw 256 | 1.14 | 1.25 | 1.41 |
| 37 plain VRAM rep | 1.21 | 1.33 | 1.43 |
| 33 rep movsw(参考) | 1.00 | 1.00 | 1.00 |

### wait 調整は打ち止め(実証済み)

CPU 側 wait(vram_wait_now)は write posting/backpressure に完全吸収:
RMW 5→0・plain 6→0 でも cpu カウント bit-identical(10/12MHz)。VRAM 行
ratio はエンジン規定。np21w 名目値(RMW=5/TDW=4/plain=6)を維持。
詳細は docs/GVRAM_PLANE_INTERLEAVE.md「段階2の速度」節と Chipset.sv
コメントに記録。

### 速度改善の試み(両方 FAIL → revert)

1. **候補①(wbatch 復活=bridge word passthrough)**: buffered 3 +
   直接 path 82 mismatches — seq 側 grcg_wbatch 経路が長期 dead code
   で第11-13修正系が未適用。
2. **候補②(walk lane 並列化=pair 両 lane 同時 merge)**: 全 4 モード
   1468 mismatches — last_gp/gp_nx の変更が全 walk モード(TDW/plain/
   EGC)に波及。

両方の根本原因: walk state machine の構造変更は S_RBH/S_WR/S_WRW の
chain・fill・flush・prefetch・dirty bit・live 判定が複雑に絡み合い、
部分的な変更が全体に波及する。

ユーザー決定: **現状で accept**(docs 記録済み)。

## tb EGC 削除(コミット d066022)

本番 Chipset.sv は `.EGC(1'b0)` で EGC 不搭載だが、tb_mem_perf のみ
`.EGC(1'b1)` だったのを本番と同一化(EGC=0 + phase 6 削除)。EGC 専用
bench(tb_pc98_egc / tb_pc98_egc_golden)は EGC=1 のまま維持。

## 検証結果(全て緑)

- **neon ゴールデン 4 モード**(dx=00 / seqdx=1 / seqdx=2 / dx=0x80):
  全て 0 mismatches + PASS
- **回帰スイート**: tb_gvram_ram_leg PASS / z86 free+paced 0 FAIL /
  tb_z86_loop 3 モード $finish / perf0+perf3 PASS / cycle table PASS /
  lint PASS
- **CI**: 4 run 全 success(firmware/sim/quartus)
- **実機**: CI bitstream を JTAG フラッシュ(USERCODE 一致・SD 不触)し、
  NEON デモ+カーソル表示をユーザー確認

## 計装遺産(sim-only plusarg ゲート、全て残置)

pc98_gvram_seq.sv 内:
- TRC(`+trace_line=1`): RMW walk merge の全トレース
- SLOTEV(`+trace_line=2`): スロット状態遷移
- FB(`+trace_line=3` または `1`): fill beat ダンプ
- CY(`+cyct=1`): タグゲート cycle ダンプ(id=2076 調査用)

tb_mem_perf.sv 内:
- `+gw=N` / `+gwt=N` / `+vw=N`: wait sweep
- `+seqdx=N` / `+dx=N`: 実験モード切替
- `+fintrace`: GVRAM 窓読み ack ダンプ
- `+watch=<word>`: SDRAM 語書き込み監視(sdram_model)

## gvram-il-speed: VRAM 書き込み速度の回復(2026-11-12)

ブランチ `gvram-il-speed`(`gvram-interleave` 6b3de20 から)。

### 遅かった原因(tb_mem_perf の per-phase 計数 + bridge/8288/RAM の clock トレースで確認)

1. **GVRAM 書き込みが bridge で post されない**(`srv_memw_plain` が GVRAM を除外)。
   CPU は毎ワード、bridge のバスペアが終わるまで Wishbone ack を待つ。
2. **GVRAM ワードが 2 バイトペアに分割**(`word_1cyc` が GVRAM を除外 — GV_IL では
   オフセット n / n+1 が SDRAM ワード W / W+2 で非連続のため)。1 ペアは 8288 の
   ALE→MWTC→witness→GAP→再 arm で ~5 CE(12MHz で ~18 chipset clk)かかり、
   1 ワード = 2 ペアが plain VRAM の律速(12MHz で 1.43)。
3. **TDW がプレーンごとの port-A 書き込み**(1 バイト 3〜4 回の SDRAM トランザクション、
   12MHz で ~24 clk/byte)— seq 律速。
4. その結果 CPU 側 wait(z86_cache pdebt)が完全に隠れ、wait 調整が効かなかった。

### 変更

- **cpu_bus_bridge**: GVRAM 書き込みも posted queue に入れる。GVRAM 読み出しは queue が
  空になるまで待ち、queue からの forward もしない(GRCG TCR 読みは別窓への書き込みに
  依存しうるため)。I/O は従来どおり queue 空待ち(GRCG/ページ切替の順序保証)。
  queue の GVRAM ワードは、seq がワードを丸ごと受けられる時(`gv_word_ok`)は **1 ペア**、
  それ以外は偶数バイト→奇数バイトの 2 ペア(エントリをその場で奇数バイトに書き換え)で drain。
- **pc98_gvram_seq**: `gv_word_ok` = plain ページ0、または GRCG TDW(RMWBUF かつ
  バッファ ON)。**TDW を port-G の 1 バースト**(バイト 2 beat、ワード 4 beat、
  `{R,B}/{G,E}` の tile、マスクプレーンは DQM 閉)で書く新状態 S_TG/S_TGW。
  gv_a_quiet 待ち・port G 空き待ち・gvwb_done まで FSM を保持(順序は line fill と同じ)。
  `gvwb_len` 出力を追加(fill/WB は 15、TDW は 1/3)。rmwbuf_off 時は旧 plane walk。
  RMW は従来のバイトペアのまま(word batch 経路は未検証のため使わない)。
- **RAM.sv / sdram_shim**: GV_IL の plain ワード書き込みを **3 beat バースト**
  (W: lane、W+1: DQM 全閉、W+2: lane)で 1 トランザクション化。hi データの lane 配置、
  posted queue の read-conflict span を 3 に。port G の長さを `gvwb_len` に。
- **Chipset**: TDW の CPU 側 wait を 4→7(np21w MEMWAIT_GRCG 8/1 のフレーム平均 =
  cycle table の参照値と同じ)。plain 6 / RMW 5 は据え置き。

### cycle table(docker Verilator 5.020、np21w 参照比)

| row | 8 MHz 前→後 | 10 MHz 前→後 | 12 MHz 前→後 |
|-----|------------|-------------|-------------|
| 32 rep stosw (RAM) | 1.00→1.00 | 1.00→1.00 | 1.00→1.00 |
| 33 rep movsw (RAM) | 1.00→1.00 | 1.00→1.00 | 1.00→1.00 |
| 34 TDW rep stosw | 1.15→1.00 | 1.26→1.00 | 1.41→0.43 (*) |
| 35 TDW mov x8 | 1.04→0.96 | 1.18→0.97 | 1.33→0.83 (*) |
| 36 RMW rep stosw | 1.14→0.98 | 1.25→1.05 | 1.41→1.17 |
| 37 plain VRAM rep stosw | 1.21→1.00 | 1.33→1.00 | 1.43→1.00 |

(*) 12MHz の phase 34 はこの bench では丸ごと垂直帰線期間に入る(portD own=0)。
np21w はそこで 1 wait しか取らず、本実装も CPU 律速になったので同じく速くなる。
垂直帰線の参照(3+1 clk/word)比では 1120/1045 = 1.07。phase 35 は一部が帰線期間。
以前はエンジン律速で帰線の有無が見えなかった。RMW 12MHz の 1.17 はバイトペア 2 個/ワードの
bridge 律速(wait 8 にしても 12MHz は不変、8/10MHz だけ 1.10 へ悪化するので 5 据え置き)。

### 検証

- lint_core / check_unconnected: OK
- docker(5.020): cycle table PASS(baseline 更新済み)、tb_mem_perf 既定 / `+speed=3 +GRANT` PASS、
  tb_pc98_gvram_seq(PW=0/1)PASS、tb_gvram_ram_leg PASS
- golden: lodemnc_cursor.ops / neon3_lines.ops を dx=00 / seqdx=1 / seqdx=2 / dx=80 の
  4 モードで各 0 mismatches
