# GVRAM プレーン・インタリーブ化 計画書（別エージェント向け）

目的: GRCG RMW を「ラインバッファ＋書き戻し＋先読み」なしで実機並みの速さにし、
バッファ起因の不整合（カーソル化け・NEON ノイズ・スクロール横線）を原理的に消す。

この文書だけで着手〜検証〜報告まで完遂できるように書いてある。
まず `AGENTS.md` を読むこと（ローカル Quartus フルビルド禁止、np21w が基準、
lint/firmware/CI/JTAG の手順はそこにある）。

---

## 1. 背景（なぜやるか）

- 現行は SDRAM 上で 4 プレーンを別領域に置く
  （`fpga/core/pc98_sdram_map.svh` の `pc98_gvram_plane`: B=A8000, R=B0000, G=B8000,
  E=E0000、ページ1は `pc98_gvram_plane1` → RAM.sv が 0x600000+{plane,offset}）。
  `pc98_gvram_display.sv` のコメントによれば **1 ゲストバイト = 1 SDRAM ワード**
  （上位バイト未使用）で格納されている。要確認。
- GRCG RMW 1 ワードは「全プレーン読み → 各プレーン書き」で、プレーンごとに
  RAM.sv の往復（~29 chipset clk）が発生し、素朴実装は np21w MEMWAIT_GRCG の約 2.8 倍遅い。
- これを埋めるため `fpga/core/pc98_gvram_seq.sv` に RMWBUF（2 スロット×4 プレーン
  ×16B のラインバッファ）、WBACK（port G への dirty 書き戻し）、RB_PF（次ライン先読み）、
  PWPOST（posted write）を追加した。結果 RMW は 8/10/12MHz で 0.89/0.99/1.12（実機比）。
- 代償として SDRAM とバッファの不整合バグが 3 件出た（ブランチ `lode-dx7-fix`）:
  1. 8b57965 fill が他人の beat を数える（lodemnc カーソル化け）
  2. e2db078 pf_go がゲスト access と同クロックで発火（NEON3/4 ライン状ノイズ）
  3. b3a64e5 / ada1f80 dirty ラインが長く残り表示が古い SDRAM を読む
     （lodemnc マップスクロール時の一瞬の横線。ada1f80 = 表示中ページへの先読み禁止）
- 表示(port D)は SDRAM を直接読むので、書き戻し方式である限り (3) 系は残りうる。

## 2. 提案

**同じゲストオフセットの 4 プレーン分のバイトを SDRAM 上で隣接させる**。

候補レイアウト（どちらかを選び、理由を報告に書く）:

- **A: 2 ワード/オフセット（推奨）**: word0 = {R,B}, word1 = {E,G}（16bit SDRAM の
  上下バイトに 2 プレーンずつ）。1 オフセット = 4 バイト = 2 ワード。
  ゲスト 1 ワード（2 オフセット）の RMW = 4 ワード読み burst + 4 ワード書き burst（DQM でバイトマスク）。
  容量は 32KB×4 プレーン = 128KB/ページ（現行の 1 バイト/ワードより詰まる）。
- **B: 4 ワード/オフセット**（1 バイト/ワードのまま隣接）: 変更は小さいが burst が倍。

いずれも:
- GRCG RMW/TDW は「1 回の burst 読み（RMW のみ）＋1 回のバイトマスク付き burst 書き」。
  バッファ不要 → RMWBUF/WBACK/RB_PF/（たぶん PWPOST も）削除でき面積が減るはず。
- 単一プレーン（GRCG off）の読み書きは対象バイトだけ DQM で書く／ワードを読んで選択。
- 表示は 1 ラインの 4 プレーンを連続 burst で読める（現行はプレーンごとに 5 burst×4）。
- ページ1 も同じレイアウトで 0x600000 側に置く。

## 3. 変更が必要な箇所（洗い出し済み、着手時に grep で再確認）

| ファイル | 内容 |
|---|---|
| `fpga/core/pc98_sdram_map.svh` | `pc98_gvram_plane` / `pc98_gvram_plane1` をインタリーブ写像に。新関数（オフセット→ワードアドレス、プレーン→バイトレーン）を追加 |
| `fpga/core/chipset/HDL/RAM.sv` | GVRAM ウィンドウ（A8000-BFFFF, E0000）のゲスト直アクセスのアドレス変換・バイトレーン選択・DQM。ページ1 (`gvram_page1_flag`, 0x600000) も同様 |
| `fpga/core/pc98_gvram_seq.sv` | GRCG RMW/TDW を 4 プレーン一括 burst に。RMWBUF/WBACK/RB_PF/PWPOST はパラメータで残しつつ新経路では 0 に。TCR（タイル比較読み）も一括読みに |
| `fpga/core/pc98_gvram_display.sv` | プレーン別 burst → インタリーブ burst。4 バンク（plane 別 M10K）への振り分け |
| `fpga/core/sdram_shim.sv`, `fpga/core/sdram_mp.sv` | burst 長・DQM（バイトマスク）サポートの確認。port G（WBACK 用）が不要になれば撤去可 |
| `fpga/core/chipset/HDL/Chipset.sv` | `pc98_gvram_seq` インスタンスのパラメータ、`vram_wait_now` の GRCG 価格（RMW 5 / TDW 4、VBlank 1）を新経路の実測で再調整 |
| `fpga/core/core_top.sv` | JTAG/ファーム経由の GVRAM 読み書き（スクリーンショット・svc op・data_loader）があれば写像を合わせる |
| `firmware/*.c` | GVRAM を直接触るコード（svc op、セーブ/ロード、OSD）を grep: `0xA8000`, `gvram`, `plane` |
| `sim/tb_pc98_gvram_seq.sv`, `sim/tb_mem_perf.sv`, `sim/tb_gvram_ram_leg*`, `sim/tb_seq_ram_stosb*`, `sim/tb_pc98_egc.sv` | 期待アドレスの更新。EGC は本コアでは無効（EGC=0）だがビルドが通ること |

注意: EGC は外してある（`EGC(1'b0)`）。EGC 経路は壊さずコンパイルが通れば良い。

## 4. 手順

1. ブランチ: `lode-dx7-fix` の先端（ada1f80 以降）から `gvram-interleave` を切る。
2. 現状把握: 上表の各ファイルで GVRAM アドレス生成箇所を列挙し、報告の冒頭に一覧を載せる。
   「1 バイト/ワード」の前提を RAM.sv と display で確認。
3. 写像関数を差し替え（パラメータ `GV_IL` で旧/新を切替可能にしておくと A/B が楽）。
4. RAM.sv（ゲスト直アクセス）→ display → seq（GRCG）→ firmware の順で移行。
5. seq の新 GRCG 経路: RMW = burst 読み → np21w 式演算 → バイトマスク burst 書き。
   TDW = 書きのみ。TCR = burst 読み → 比較。
6. Chipset の GRCG 価格を cycle table の実測で調整（np21w 比 1.00 狙い）。
7. 面積を `scripts/measure_core.sh` で見積もってから CI。

## 5. 検証（全部通すこと）

ローカル:
- `bash scripts/lint_core.sh` / `python3 scripts/check_unconnected.py`
- `--timing` ベンチは **pc98-sim docker**（Verilator 5.020）で:
  `docker build -t pc98-sim sim/` → `.github/workflows/build.yml` の sim job と同じ呼び出し。
  Homebrew の Verilator は誤スケジュールするので合否判定に使わない。
- `tb_pc98_gvram_seq`（PW=0/1）、`tb_mem_perf`（既定 phase と `+speed=3 +GRANT`）PASS。
- **ゴールデンストリーム**（実ゲームの GRCG 操作列、np2kai で記録済み）:
  `sim/golden/streams/lodemnc_cursor.ops`, `sim/golden/streams/neon3_lines.ops`
  （`tools/ops2prog.py` で z86 プログラム化、tb_mem_perf `+cursor=<hex>` で再生、不一致 0 件）。
  CI の sim job が perf3 の後に回している。
- **cycle table**: `scripts/sim_cycle_table.sh`（8/10/12MHz、基準 `sim/cycle_table_baseline.txt`）。
  目標: GRCG RMW rep stosw 0.95–1.05、TDW 0.95–1.05、plain VRAM rep stosw 1.00 前後、
  他行（mov/movsw/int/call 等）が悪化しないこと。`+seqdisp=1`（A6≠A4）でも測る。
- firmware: `cd firmware && PATH="/opt/homebrew/opt/llvm/bin:$PATH" make`、
  変更したら `firmware.vh`/`firmware.bin` をコミット（Quartus は commit 済み firmware.vh を使う）。

CI:
- `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin gvram-interleave`
- `gh workflow run build.yml -R MusiQ-DA/pc98-pocket --ref gvram-interleave`
- 確認: sim / firmware / quartus success、ALM（現行 lode-dx7-fix ≒ 91%、増やさない）、
  タイミング違反なし（`sta_cpu_honest.txt`, `sta_sdram_read.txt`）。
- GitHub のポーリングは 3 分以上間隔を空ける（レート制限）。

実機（コーディネータ＝メインセッションに依頼。サブエージェント自身は flash/reset しない）:
- `scripts/jtag_flash.sh <CI の output_files/ap_core.sof>` → `HDIMG=<img> openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl`
- 確認項目:
  1. SuperDepth START（`testdisk/superdepth.hdm`、`scripts/jtag_superdepth.tcl`、10MHz/Turbo/12MHz で 40/40）
  2. NEON3/NEON4 の 286 版でライン状ノイズなし（`testdisk/neon125.hdm`）
  3. lodemnc のカーソル跡・マップスクロールの横線なし（lodemnc は JTAG で `$TMPDIR/lode.hdm`）
  4. FreeDOS 起動・DOS=High（`testdisk/neon125.hdm` 等）
  5. 画面取得 `scripts/jtag_screen.tcl` が正常
- A/B 用に slot 0x09 の既存ビット（[27] バッファ off, [29] 先読み off, [30] 即時書き戻し）は
  旧経路用に残すか、新経路では無意味になる旨を報告に書く。

## 6. 完了条件と報告

- 上記ローカル検証・CI すべて green、ゴールデンストリーム 2 本 0 不一致、cycle table の表（前後比較）。
- 面積（ALM/LAB）とタイミングの数値、run id。
- 実機確認用 .sof の場所と、メインセッションに依頼する確認項目リスト。
- 旧経路（RMWBUF 等）を削除したか残したか、その理由。
- マージはしない（実機合格後にメインセッションが z86-bus-faithful へ）。
- コミット末尾:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01H6QCgDqMQjbvbUQVhDQcEP
  ```

## 7. 段階状況（実装メモ）

段階的に実装している。段階1は「正しさ」のみ（速度は旧来の plane walk 並み）。

### 段階1（このブランチの最初のコミット）— 実装済み

- レイアウトAを採用: `pc98_gvram_il(pg, off, p)` = `{7'h30, pg, off, p[1]}`。
  偶数ワード={R[off]上位, B[off]下位}、奇数ワード={E[off]上位, G[off]下位}、
  バイトレーン=p[0]。ページ0=0x600000、ページ1=0x610000。
- RAM.sv: latch_address 生成を GV_IL 化（ページ0は `pc98_gvram_own_plane`、
  ページ1は address[16:0] 直接解釈）。posted-write queue の各スロットにレーン
  ビットを追加、shim に port A per-beat wmask（a_wmask0/1）を新設し
  sdram_mp の `~p_wmask` DQM を実ピンまで接続（従来 dqm_unused で廃棄、
  RAM.sv が常時全レーン開放だった）。読み出しはレーン選択で data_bus_out へ。
- cpu_bus_bridge: GVRAM ワードを word_1cyc から除外（バイト2回に分割）。
  インタリーブ後ワードは 2 ワード間隔で非連続のため。
- display: 1ライン=160連続ワード=10バーストで全プレーン同時取得
  （旧: プレーン別 5 バースト×4、デジタル時 E スキップの節約も廃止 —
  インタリーブは全ワード必須）。
- seq: RMWBUF/WBACK/RB_PF/PWPOST-arm は Chipset が `.rmwbuf_off(dx_rmwbuf_off
  | 1'b1)` で強制OFF。GRCG は従来の plane walk（S_RD/S_WR per plane、
  RAM.sv port A 経由で自動 GV_IL 変換）にフォールバック。
  port G の gvwb_wmask ポートを追加（段階1では常時 2'b11）。
- firmware/JTAG dump はゲストアドレス渡しで SDRAM マップ非依存 → 変更不要。
- 既知の変化: tb_mem_perf 既定 dx_r を 8'h80 に（rmwbuf_off=1 相当、
  slot 0x09 bit 27 は段階1では常時1）。cycle table の VRAM 行は
  walk に戻る分 baseline から遅くなる（段階2で戻す）。
  実測（np21w 比）: TDW rep 1.63-1.70 / TDW x8 1.41-1.62 /
  RMW rep 3.42-4.82 / plain VRAM 1.30-1.43。
  plain VRAM は word を bridge がバイト分割する分の低下
  （CPU/RAM 行 20-33 は不変、phase38 RMW CHECK は GV_IL 直接
  検証に修正して 3 速度とも 0 bad）。baseline は段階1値で更新。

### 段階2（2つ目のコミット群）— 実装済み: line buffer を GV_IL で復活

- seq のラインバッファを GV_IL ジオメトリに再構成:
  - 16バイトライン = 32連続 SDRAM ワード [2L, 2L+31]。半分（オフセット
    L+0..7 / L+8..15 の全4プレーン）ごとに port G 16ワードバーストで
    fill（gf_h で切替、`g_il(pg, line, h)` = `{7'h30,pg,line[10:0],5'h0}
    + (h?16:0)`）。カラム境界は跨がない（2L は32ワードアライン）。
  - バンクは rbE/rbO（64×8、プレーン別）→ **rbW0/rbW1（各32×16bit、
    オフセット偶奇=SDRAM ワードの直接イメージ）**。アドレス
    ={slot, off[3:1], pair}、pair=off[0] に相当（B:R ワードか G:E か）。
    1 fill ビート=1エントリ、RMW 更新は対象バンクへのマージ書き込み
    （レーン=gp[0]）。B→R/G→E チェインの同一エントリ読み書きに備えて
    読み口 rbq0/rbq1 は write-forward バイパス付き。
  - WBACK（fl）: プレーン反復を廃止し、dirty はスロット単位 fl_d[3:0]
    （pair=off[0]、レーン=p と解釈）で DQM マスク
    `wcnt[0] ? {fl_d[3],fl_d[2]} : {fl_d[1],fl_d[0]}`、
    データは stg[16]×16bit をそのまま2バーストで書き戻し。
  - RB_PF（pf）: プレーン反復を廃止、`pf_ready = (rb_tag[~mru]==pf_nxt)
    & (rb_v[~mru]==4'hF)`（次ラインの4プレーン一括先読み）。
  - fill は常時 port G（RAM.sv prefetch 経路は GV_IL と非互換のため
    廃止、rb_g を削除し rb_leg に一本化、mem_pf_len はパススルー）。
  - WBACK パラメータは obsolete（wb_on = RMWBUF。GV_IL では書き戻し必須）。
- RAM.sv / Chipset: gvwb_rdata/wdata を 16bit 化（port G はワード幅で
  受け渡し、shim の g_wmask でレーン制御）。
- Chipset: `.rmwbuf_off(dx_rmwbuf_off)` の強制 tie を解除、
  tb_mem_perf 既定 dx_r を 8'h00 に戻す（slot 0x09 bit 27 が再び
  RMW バッファ無効化ビットとして機能）。
- 修正途中で見つかった不具合: fill 2バースト目完了時に gf_sent を
  クリアし忘れると tb のドレイン待ちが永遠に終わらない（DUT 動作には
  無害だが in-flight の意味が壊れる）→ S_RDW のバースト2完了分岐で
  gf_sent<=0 を追加。
- tb_gvram_ram_leg を RMWBUF=1/WBACK=1/RB_PF=1/PWPOST=1 + port G 実結線
  に変更、GV_IL 上のバッファ RMW 64レーン検証（np21w モデル比較）を
  追加。walk erase / cross-lane park はバッファ経路で回帰。

### 段階2の速度（cycle table 実測で調整）— 判定済み: wait 調整では目標未達・名目値維持

段階2のコードで vram_wait_now（RMW=VBlank?1:5 / TDW=VBlank?1:4 /
plain VRAM=VBlank?1:6）を sweep して cycle table（Verilator 5.020・
script path）で測り直した。結論:

- **wait はほぼ完全に吸収される**。posted write キューと bridge の
  backpressure ストールが CPU 側の wait と重畳し、10/12MHz では
  RMW 5→0・plain 6→0 でも rep ループの cpu カウントが
  bit-identical。つまり VRAM 行の ratio はエンジン規定で、
  CPU 側 wait の調整では 0.95-1.05 に入らない。
- 最終 ratio（np21w 参照比・cycle table baseline）:

  | phase | 8MHz | 10MHz | 12MHz |
  |-------|------|-------|-------|
  | 34 TDW rep stosw 256 | 1.15 | 1.26 | 1.41 |
  | 35 TDW x8            | 1.04 | 1.19 | 1.34 |
  | 36 RMW rep stosw 256 | 1.14 | 1.25 | 1.41 |
  | 37 plain VRAM rep    | 1.21 | 1.33 | 1.43 |

  （33 rep movsw は全速度 1.00。RMW は段階1の 3.42-4.82 から
  line buffer ヒットで大幅改善。12MHz は port-G 帯域が律速。）
- **wait 値は np21w 由来の名目値（RMW=5 / TDW=4 / plain=6）のまま
  維持**する。実測上どの値でも速度は変わらず、名目値が実機の
  安全サイドに立つ。EGC（非 posted）は 0 のまま。
- 計測の注意: tb の pace-wait 測定は実行 cwd や plusarg の有無で
  8MHz TDW が二峰性（1.15 / 1.02）に出る。権威は CI が再現する
  `scripts/sim_cycle_table.sh`（repo root 実行）の値。
  手動 run（別 cwd / plusarg 付き）で 8MHz が改善したように見えた
  sweep 結果はこの artifact だった（判別実験で plusarg 値は無関係
  と確認済み）。

### 段階2で見つかり直した RMW line buffer の 2 バグ（第11+第12修正）

neon3_lines.ops（NEON3286 デモの np2ops キャプチャ、4プレーン RMW
ライン描画、page flip）が dx=00（バッファON）で 169 mismatches、
dx=80（rmwbuf_off）でのみ PASS。TRC/FB/SLOTEV の同一 run 計装
（pc98_gvram_seq.sv 内 `+trace_line=1/2/3`）で 2 つの独立バグを特定した。

1. **fill ビート/完了スロット・デシンク（fws ラッチ修正）** — fill の
   bank 格納アドレス（`fb_wa={ws,...}`）と完了時の `rb_v[ws]/rb_tag[ws]`
   が同じライブ wire `ws` を別サイクルに評価する。fill 中/直後に ws が
   反転するとビートとタグが別スロットに散らばり、片側が v=f+旧データ
   でヒットする。`fws`（fill slot ラッチ）を S_RD/S_WRW fill 開始時に
   固定し、fb_wa と完了ブロックが同じスロットを参照するようにした。
2. **rb_ra pair ラグ（第12修正が本体）** — `rbq` registered read の
   アドレス `rb_ra` が S_WR マージ発火サイクルも `gp[1]`（現 plane の
   ペア）のまま。pair 境界を跨ぐ chained RMW（gp=1→2）で chain 先の
   S_RBH が pair-0 語（word4）を読み、gp=2（pair-1 語 word5 の
   lane0）だけが常に誤読。RMW 式 `(old&~d)|(d&t)` で wd=0x1f の時は
   結果が old に依らず 0x1f になるため 161 パス中の特定パターン
   （wd=0x18/0x10/0x80/0x02）でのみ発覚した（0x3D2 の 0x1f→0x18→0x10
   逐次劣化）。`rb_ra` の条件を `!rb_upd_w` → `(!rb_upd_w || !pf_bw)`
   に変更（マージ発火中も gp_nx[1] 先読み。ストール再試行
   `rb_upd_w&&pf_bw` は従来どおり gp[1] = lodemnc 保護維持）。

dx=80（RMWBUF+PWPOST 両方無効）が PASS だったのは buffer を使わ
ないため。z86 読み完了交叉説は 1-based インデックスの誤読による
レッドヘリングだった（id=4440 は 0xB83D2 want 31 で、A 窓エイリアス
0xA83D2 経由の RMW 書きが B 窓の同じオフセットに展開される正常動作）。

既知の残件: `+seqdx=2`（PF ON+即時 WB の実験モード）に
id=2076（0xAA413 want 255）が 1 件残る。修正前から存在した独立の
稀レースで、生産構成（dx=00 デフォルト）には影響しない。後日調査。

## 8. リスク

- 改修範囲が広い（RAM.sv / display / seq / firmware）。`GV_IL` パラメータで旧経路に戻せる形を推奨。
- SDRAM の burst 長・バンク衝突で RMW が想定より遅い可能性 → cycle table で早めに実測。
- 単一プレーン書き（plain VRAM）が DQM 前提になる。sdram_mp が DQM を出せるか最初に確認。
- 面積は減る見込みだが、display の 4 バンク振り分けロジックが増える。
