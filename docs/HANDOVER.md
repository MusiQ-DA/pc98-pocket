# PC-98 Pocket 引き継ぎ — 2026-10-26 夜

> ユーザーの最後の報告: 「またフリーズだよ、これ改善してないね。引き継ぎmd書いて」
> これを受けて作成。前回版 (9e74305) から全面改訂。

> **2026-10-26 追記（M2 結果）**: `db6f679`（a2f0d62 + 3745704 を revert、38da6ab は残置）の
> CI 1002 を SD デプロイ → **コールドブート 3/3 起動**。フリーズの原因は a2f0d62
> （posted-write queue 系）で確定、38da6ab は無罪。ウォーム実機ベンチ（pf ON, Turbo）:
> GVRAMTDW 13,884 / GVRAMRMW 119,942 / DEPTHDRAW 139,067 / FARCALL 63,136 / GVRAM16K 15,904。
> ステージ2解析は `sd-stage2-profile` ブランチ（docs/SUPERDEPTH_STAGE2_PROFILE.md）:
> BGM 遅れは z86 の REP が割り込み不可（16k ワード rep stosw で IRQ0 が 44〜58 ms 止まる）ため。
> 対策を `z86-rep-intr` ブランチで作業中。

> **2026-10-27 訂正（フリーズの真因）**: §2 の「RAM.sv が R2 で read p_done 待ち」署名は
> **プローブの誤読**だった。core_top のプローブ case で 0xA0-0xA7 が二重定義
> （先勝ちの OSD 設定アーム 6121b501 が wedge スナップショット dd18389 を覆い隠す）で、
> 健全な機械でも同じ値が読める。slot 0x17 retired=0 も z86 に retire タップが無いだけ。
> 実機再現（BASIC から `OUT &HF0,0` で再起動を繰り返す）＋ tlog/ライブ z86 レジスタで確定した真因は
> **SCSI オプション ROM のメールボックス非同期化**: scsi_go のタイムアウト（~60 ms @Turbo）が
> ブート直後で忙しいソフトコアに対して短く、放棄したコマンドの遅れ完了が次コマンドの完了に化け、
> IPL として READ CAPACITY 応答（00 00 6A 40 00 00 02 00…）が 1FC0:0000 に置かれて far call →
> ゴミ実行で停止（pc=1FC0:0494 等、X000:0094 系）。加えて NHD がマウント時にフラット扱いされ
> LBA0 にヘッダが出ていた。修正: 6e0a46a / 0ff6fba（ROM タイムアウト延長＋残留完了の破棄、
> マウントのヘッダ読みを検証して再試行）。SDRAM revert (db6f679) はタイミングを変えただけ。

---

## §1 現在位置（これだけ読めば再開できる）

**ゴール**: SuperDepth (PC-98) の ①ステージ2以降のスロー・BGM遅れ ②ステージ間遷移の黒帯
を解消すること。並行して pf (286 BIU-queue) を ON でも安定させる。

**現在の blockers（優先順）**:

1. **SD コールドブートフリーズ（未解決・最優先）**
   CI 1000 (a2f0d62 SDRAM最適化) で発生、**CI 1001 (3745704 緩和版) でも再発**。
   3回とも同一署名（§2）。SDRAM 最適化ラインのどこかに実物タイミングのみの完了レース。
   **次の一手 = M2: `git revert a2f0d62` → CI → SD デプロイ → コールドブート×3検証**。
   それでも出たら `38da6ab` (chained legs) も revert（この2コミットは未分離）。
2. **黒帯修正 (918bd95) の実機確認ができていない** — フリーズの陰で SuperDepth を
   まともにプレイできていない。M2 後に確認。
3. **速度体感の確認** — ベンチ上の RMW 2.46× が体感として残るか（a2f0d62 revert で
   キュー分は失われるが、GRCG word batch 0d9be87 分は残る）。

**HW/リポジトリ状態 (2026-10-26 21:00時点)**:

| 場所 | 内容 |
|---|---|
| Pocket ファブリック | run 1001 (3745704) JTAG フラッシュ済み — **フリーズ状態で放置** |
| SD カード | run 1001 デプロイ済み（ユーザーが挿入→デプロイ→コールドブートでフリーズ確認） |
| ブランチ | `z86-bus-faithful` @ 3745704 (push 済み) |
| CI | run 1001 green (headSha 3745704, databaseId 40213590462) |
| ローカル | クリーン（緩和はコミット済み） |

**電源再投入すればフリーズからは脱するが、同じビルドならまた凍結する**（間欠だが高頻度:
run 1000 で2回、run 1001 で1回、全てコールドブート直後の BIOS POST 中）。

---

## §2 フリーズ問題 — 全証拠と診断手順

### 症状
- 電源オン → 画面真っ黒（テキスト VRAM 全ゼロ = BIOS が一文字も書いていない）
- BIOS POST 中に停止。ウォームブート（JTAG hdload / ファブリック再構成直後）では
  **発生しない**。SDRAM 全面初期化 + ファームウェア ROM コピー + POST メモリテストという
  コールドブート特有の負荷経路のみ。

### 3回の観測（全部 JTAG ポストモーテムで同一構造）
| 回 | ビルド | pc_cursor | 備考 |
|---|---|---|---|
| 1 | run 1000 (a2f0d62) | 0x33c1c | POST メモリテスト領域（0xE5 パターン） |
| 2 | run 1000 | 0x00050094 | より早い段階＝間欠性 |
| 3 | **run 1001 (緩和版)** | 0x317a8 | **同一署名で再発 → 緩和不成立** |

### 確定した構造（全回共通）
```
slot 0x17 retired=000000 (CPU は一度も命令を retire していない)
slot 0x18 pc_cursor=固定
RAM.sv : st=R2 (リード待ち) park=0000 rd_conf=0
shim   : p_req{F..A}=000000 ← mp への要求が無い
mp     : st=4 (リフレッシュ) have_req=0 grant=0 busy=0
```
⇒ **ラッチされた read の p_done がどこかで失われ、RAM.sv が永久に R2 で張り付く**。
CPU はバスサイクル途中で握ったまま（jtag_memwrite の HOLD/HLDA バス借用が全部
"rmem timeout" になる）。UNSTICK (`wr 0x88 0x02` = キュー破棄 + RAM.sv→IDLE) を
パルスしても CPU は復活しない（完了通知が永遠に来ないため）。**電源再投入以外の回復手段なし**。

### 诊断に使った道具（/tmp 消滅に注意 — 再作成が必要なら §9 のプローブ表参照）
- `scripts/jtag_wedgehunt.tcl`（**コミット済み・残っている**）: ウェッジ検出＆ライブデコード。
  `TIMEOUT_S=15 CLEAR=0 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wedgehunt.tcl`
  注意: ウェッジラッチ（0xA0-0xA7 スナップショット）は「retire が動いた後の静止」を要求する
  ため今回のブート（retired=0 まま）では **latch=0 で不発**。ライブデコード部分だけが効く。
- `/tmp/opencode/wedge_decode.tcl`（消える）: スナップショットをクリアせずに1回だけデコード。
- `/tmp/opencode/jtag_rds.tcl`（消える）: 汎用スロットリーダー `ADDR=0x9d N=3 openocd ...`。
  **教訓: OpenOCD の env は `$::env(ADDR)` で読む。`info exists ADDR` は届かない**。
- `/tmp/opencode/pm2.tcl`（消える）: 2回目ポストモーテム用。スロット 0x9d-0xa4 の読み取りが
  「expected integer but got " "」で失敗する問題あり（drscan 返りの空白除去が必要。未解決）。

### ソースレビューで確認している構造（fpga/core/sdram_shim.sv / sdram_mp.sv / RAM.sv）
- shim read latch: `:494 if (~rd_busy & read_request)` で rd_busy/rd_addr/rd_len をラッチ。
  read_flag = rd_busy。RAM.sv は R2 で flag の落下（= read の p_done）を待つ。
- **rd_busy が落ちる唯一の経路**は read 完了分岐 (`:509 if (eng_busy) ... if (p_done) ... else we_r==0` の `:527`)。
  read の p_done が eng_busy=0 の間にパルスすると永久に失われる — ウェッジ構造と一致。
  静的解析では exact な失点窓を確定できず。sim (sdram_model) では再現しない。
- engine: `:332 pop_now = eng_busy & we_r & p_done`、`:341 push_now`（write_request 1回/窓、~rd_busy ゲート）、
  `:378 eng_rd_next`、`:537` アイドルから read 開始、`:510 if (p_ack) req <= 0`。
- mp grant: `:397`、fused row-hit: `:407`。`:589 idle = stat_idle & ~busy & ~(...)`、
  `:604 refresh_mode = stat_refresh | busy`。busy = eng_busy|aq*_v|rd_busy (`:553`)。

### 緩和の内訳（何を試して効かなかったか）
- `3745704`: `READ_REORDER=0`（read はキュー排出後のみ＝厳密到着順）+ `FUSED_ISSUE=0`
  （row-hit も S_RW ウォーク）— **再発したのでこの2つは原因ではない**。
- **残る容疑（未分離）**: ① posted-write queue + serial engine 本体（shim）② RAM.sv の
  WRITE_2 COMPLETE スキップ ③ `38da6ab` chained plane legs（gvram_seq — 同じビルドに含まれる）。
- sim での性能内訳 (ph11): queue −3.9% / fused −1.0% / reorder+COMPLETE −0.5%。
  ⇒ **a2f0d62 全 revert でも HW RMW 2.46× が ~2.3× に落ちるだけ**（queue 分喪失）。
  GRCG word batch (0d9be87) 分は無関係なので残る。

### M2 手順（次の実行者向け）
1. `git revert a2f0d62`（conflict なし想定 — 緩和 3745704 は localparam 2本なのでそのまま残る。
   残したければ `git revert a2f0d62 3745704` で両方）
2. lint + Docker sim で主要ベンチ（tb_gvram_ram_leg / tb_ram_mix_stress / tb_sdram_shim）
3. push → CI → `bash scripts/deploy.sh --run <n>`（バックグラウンド）
4. ユーザーにコールドブート×3 を依頼。直っていれば 38da6ab を再適用して再度検証（分離確定）
5. それでも凍結する場合: `git revert 38da6ab` も

---

## §3 コミット履歴（新しい順）と意味

| コミット | 意味 | 状態 |
|---|---|---|
| `3745704` | read-reorder / fused-issue 無効化（フリーズ緩和） | **効かず再発** |
| `ac15f26` | CI sim ジョブを ubuntu-24.04 にピン（Verilator 5.020 固定） | 必須（§8） |
| `a2f0d62` | SDRAM 最適化: posted-write queue + fused-issue + read-reorder + COMPLETE skip | **フリーズの容疑本体** |
| `38da6ab` | gvram_seq: chained plane legs（retire エッジで次脚発行） | 容疑②（未分離） |
| `7f4cdba` | 自発リブートは async set への生 PLL-unlock ブリップと判明 | 済 |
| `18fce8d` | reset-source witness + FFF0 trail freeze | 済 |
| `b685d61` | bus ring 復帰（除去が fitter poison だった） | 済 |
| `c68fe68` | qsf SEED 21→22 | 済 |
| `4f12555` `751edfd` `20cdac6` `4f0ed91` `28fd476` | stub window / wild-fetch trap / LAB 節約系 | 済 |
| `afe65e6` | upd71071 dbg_mask repack revert | 済 |
| （CI 996/997/998 = b685d61/18fce8d/7f4cdba は green） | | |
| `23f51eb` | merge pf-boot-safe | 済 |
| `918bd95` | **SAD/pitch フレームラッチ（黒帯対策）** | **実機未確認** |
| `d9a506b` | pf: ITF バンクマップ中は pf 保持（TIMER INTERRUPT ERROR 修正） | **pf ON 実機ブート確認済み** |
| `e97d1a6` | 0xA4 表示ページのフレームラッチ | 黒帯消えず（SAD 側が本体と判明し 918bd95 へ） |
| `8addaa0` | pf 既定 OFF | 済（既定 ON 化は未実施） |
| `0d9be87` | GRCG word バッチ（RMW 1.70×） | 済 |

---

## §4 実機ベンチ実測（ticks、低いほど速い、pf ON + Turbo）

比較基准: `bench_hdm_wbatch_speed3.log`（0d9be87, Oct 20、16テスト版イメージ）。
現行 bench.hdm は Oct 20 12:06 生成の17テスト版（15/16 のテスト本体は不変＝比較可）。

| テスト | 0d9be87 | run 1000 (a2f0d62) | 変化 |
|---|---|---|---|
| 15 GVRAMTDW | 64,310 | 52,187 | **1.23× 速い** |
| 16 GVRAMRMW | 185,996 | 75,517 | **2.46× 速い** |
| 17 DEPTHDRAW | （なし） | 179,041 | 初回データ |
| 08 GVRAM16K | 15,590 | 15,177 | −2.6% |
| 11 FARCALL | 57,773 | 62,478 | **+8.1% 遅い**（stack 書き込みが read と直列化? watch） |
| 09/10/12/13/14 | — | — | ±3% |

run 1001 (緩和版) は未計測。M2 (a2f0d62 revert) 後は queue 分（約 −3.9%/ph11 sim）を失うが
word batch 分は残る。bench の marker は `jtag_bench.sh` 既定の "Execute time" ではなく
**`'GVRAMRMW'` を渡すこと**（実在する行文字列。既定 marker は 420s timeout する）。

ベンチ実行: `HDPFON=1 bash scripts/jtag_bench.sh testdisk/bench.hdm 3`
（env は子プロセスへ伝播 = pf ON。slot89=0xF spd_ovr=1 sel=3 で確認。

---

## §5 SuperDepth 解析知見（再利用可能）

- **起動オプション**: `DEPTH -P810` でデバッグ解錠（di=1）。`-S<n>` = 開始ステージ `[0x2150]`、
  `-H<n>` = 開始ライフ `[0x212E]`。`-R` は存在しない。
- **遷移判定** (disasm 0x258B4): `[0x1DAE]=[0x1818]`(完了ステージ)、`ax=[0x1842]`(残ライフ)、
  `if ([0x1510] <= ax) [0x1818]++`。`[0x1510]` = ステージ開始時ライフ。
- **ポークレシピ**: `NP2POKE="1400:0x368E0:1"`（phys。DS=0x353D なので DS:off → off+0x353D0）
  で死亡→クリア遷移を強制（本物の `0x275FD → 0x2E69C` Clear 演出経路）。
- **クリア演出の実体**: `0x30AA0` が GDC 表示開始アドレスへ `row*40` ワードを書き、
  **4ライン/フレーム × 68回** スクロール（0x2E78C で port 0x60 bit5 ウェイト）。
  同時に 0xA4/0xA6 でページ切替。
- **np2kai では黒帯ゼロ**（733フレーム全文面検査）→ Pocket 固有 → 918bd95 で SAD/pitch を
  フレーム境界ラッチして対策（69f745c で revert 済み）。
- **gdc-frame-snapshot ブランチ**: pc98_gvram_display が PRAM 全体（SAD/LEN/pitch単位×4、PITCH、
  LR、0xA4 ページ）を 1 フレーム 1 回（line 435）スナップショットし、フレーム全体をそれで walk
  （np21w screendisp→makegrph と同じ「1フレーム=1 PRAM 状態」）。旧 RTL は LEN だけ live で
  継ぎ目に VRAM 400 行目以降（黒）が 4〜8 行出ていた。`sim/tb_gvram_depth_wipe.sv` が 68 ステップを
  np21w モデルと行単位で照合。実機確認は `scripts/jtag_blackband.tcl`（スロット 0x84-0x86）で
  ワイプ前後の band_cnt / pram_cnt を差分。
- 道具: `/tmp/opencode/np2run3`（np2run.c 拡張: NP2KEYS/NP2POKE/NP2SHOTDIR/NP2WATCH/
  NP2WATCHPOST/NP2DUMPAT）、`/tmp/opencode/sd_work/`（depth_tr.exe, dump.py, flocate.py,
  ffind.py, rwalk.py）、`/tmp/opencode/depth_disasm.txt`（live アドレス逆アセンブル）。
  **全部 /tmp — 消えていれば tools/np2run/np2run.c（コミット済み）から再ビルド可能**。

---

## §6 pf (286 BIU-queue) の現状

- 既定 OFF (`jtag_pf_dis=1`)。ON は JTAG 経由のみ: `HDPFON=1`（slot 0x89 **bit3=1 の表示が
  pf ON**（jtag_pf_dis=0）の慣例 — 読み間違え注意）。
- `d9a506b` により **pf ON のまま ITF POST を通過**することを CI1000 ビルドの実機ベンチで確認
  （TIMER INTERRUPT ERROR 解消）。ただしコールドブートでの pf ON 検証は未実施
  （slot 0x89 は電源投入で 1 に戻るため、コールド試験には既定 ON のテストビットストリームが必要）。
- pf ON 既知の別問題（未解決・低優先）: Turbo の SuperDepth で RET が stale pre-push を拾う
  （engine on 3/50, nofill 2/57, nohit 1/85, off 0/85 — core_top.sv コメント）。

---

## §7 運用手順

- **CI**: push → `build.yml`。quartus ジョブ = docker `raetro/quartus:pocket`。
  **sim ジョブは ubuntu-24.04 ピン（ac15f26）** — ubuntu-latest は Verilator 5.032 に
  ドリフトして tb_sdram_mp を偽 FAIL させる（5.020✓/5.032✗/5.052✓ を3環境で確認済み）。
- **JTAG フラッシュ**: `bash scripts/jtag_flash.sh <ap_core.sof>`（コア起動中のみ有効。
  フリーズ中でもファブリックは生きているので書込可＝再起動扱い）。
- **SD デプロイ**: `bash scripts/deploy.sh --run <n>`（必ずバックグラウンド。カード挿入を
  90分まで待つ。検証＋イジェクトまで自動）。
- **ローカル Quartus フルビルド禁止**（AGENTS.md）。資源見積りは `scripts/measure_core.sh`。
- **Docker sim**（権威あるローカル実行）: `docker build -t pc98-sim sim/` 後、CI と同一コマンド。
  ハマり点: docker run の引数に host 側シェル変数を書いても展開されない — コンテナ内
  bash -c '...' 内で定義する。--rm で消えるので grep も同一コンテナ内で。
- **Homebrew Verilator (5.052)**: `--timing` ベンチを誤スケジュール（tb_pc98_font_stress の
  偽 wedged）。tb_sdram_mp は通る。権威は Docker pc98-sim。

## §8 JTAG プローブスロット早見（読み: `ADDR=0xXX N=n openocd -f scripts/jtag_probe.cfg -f jtag_rds.tcl`、jtag_rds.tcl は /tmp 製・要再作成）

| スロット | 意味 |
|---|---|
| 0x17 | retired カウント（0 のまま＝1命令も retire せず） |
| 0x18 | pc_cursor（バスアドレス） |
| 0x35 | BIOS POST マイルストーン (FD80x) + PIT in42 回数 + w43d_10/12 回数 |
| 0x89 | pf/speed 制御（bit3=pf, sel=speed）— 電源投入でリセット |
| 0x84 | 黒帯 witness `{band_cnt, pram_cnt}`（≥8 行の全黒ラン有フレーム数 / 表示中に PRAM 書換えのあったフレーム数）— `scripts/jtag_blackband.tcl` |
| 0x85/0x86 | 直近フレーム / 起動以来最悪の最長全黒ラン `{start, len}`（各 9bit） |
| 0x90 | エントリ経路 witness (cold/warm/F0) |
| 0x9D | rst_raw/rst_real（PLL-unlock ブリップ検出） |
| 0x9E/0x9F | ドロップ数 / parked-write カウント（0xFFFF 飽和=FWコピー走った） |
| 0xA0-0xA7 | ウェッジスナップショット（latch 条件に注意 — §2） |
| wr 0x88 0x02 | UNSTICK（キュー破棄 + RAM.sv→IDLE。CPU は復活しない点に注意） |

`scripts/jtag_memwrite`（HOLD/HLDA バス借用）はゲストがバスを握っていると "rmem timeout"。
`scripts/jtag_wedgehunt.tcl` にライブデコードとスナップショット decode() (55-120行) がある。

---

## §9 未解決・様子見リスト

1. **コールドブートフリーズ**（§2 — M2 revert が次の一手）
2. 黒帯修正 918bd95 の実機確認（M2 後）
3. SuperDepth 速度体感（同上）
4. FARCALL +8% 悪化（a2f0d62 revert で消えるはず — 要再確認）
5. ph06 EGC stosb +12.4%（sim・port D 帯域正常化の代償。revert で消える）
6. pf 既定 ON 化（実機コールド検証の後、`core_top.sv:298` を 1'b0 にする別コミット）
7. pm2.tcl のスロット 0x9d-0xa4 読み取り失敗（drscan 返りの空白処理）
8. ウェッジ検出器の latch が retired=0 ブートで不発（要改善: retire 一動後の静止を要求しない条件）

## §10 再開時の最初のコマンド例

```sh
cd /Users/hiroya/repo/pc98-pocket
git status && git log --oneline -5
# M2:
git revert a2f0d62
bash scripts/lint_core.sh && python3 scripts/check_unconnected.py
# docker sim 主要ベンチ → push → CI → deploy --run <n> → ユーザーにコールドブート×3依頼
```

## §11 次フェーズ計画: Stage 2 高速化（フリーズ・黒帯・REP 割り込みの完了後に着手）

前提: 下の 3 本が片付いてから始める（同時に回すとトークンが足りない）。
- フリーズ根本原因（読み p_done 消失）の修正と実機確認
- 黒帯: GDC PRAM のフレーム単位スナップショット（`gdc-frame-snapshot`）
- BGM 遅れ: z86 REP の割り込み対応（`z86-rep-intr`）

根拠: `sd-stage2-profile` ブランチ docs/SUPERDEPTH_STAGE2_PROFILE.md。
- ゲーム 1 フレーム = 5 VSYNC（88.6 ms）。S2 で増えるのは GRCG TDW ワード書き込みだけ（15.2k → 29.5k、毎フレーム 16,000 ワードの全画面クリア）。
- 286 10MHz 並みの目標: TDW ≤ 1.0 µs/word（GVRAMTDW ≤ 約 15k ticks）、GVRAMRMW ≤ 約 45k ticks。
- CI 1002 の実測（ウォーム、pf ON、Turbo）: GVRAMTDW 13,884 ticks（目標達成）、GVRAMRMW 119,942（目標の約 2.7 倍）、DEPTHDRAW 139,067。

手順（1 本ずつ、各段で実機ベンチ・SuperDepth 40 回テスト・コールドブート 3 回）:
1. **計測し直す**: REP 割り込みと黒帯の修正を入れたビルドで、bench.hdm（marker 'GVRAMRMW'）を測る。SuperDepth S2 の実時間フレームも測る（`[0xDD0]` のティック増分を JTAG で読む）。これで「まだ遅いか」をはっきりさせる。BGM 遅れは REP 側で直る見込みなので、残りはゲーム速度だけになる。
   - **結果（2026-10-27、CI #1024 = run 40443711725、`scripts/sd_stage2_check.sh`）**:
     Turbo は S1/S2 とも 5.00 VSYNC/フレーム（np2kai と同じ 100%）、BGM 99% → PASS。
     286 10MHz は S1 8.40 VSYNC/フレーム（60%）、S2 10.03（50%）、BGM は正常。実機 286-10 なら
     S2 は約 55 ms/フレーム（5 VSYNC 未満）のはず。残る問題は paced 速度（8/10/12 MHz）のゲーム速度だけ。
   - **10MHz の原因切り分け（2026-10-27、`z86-paced-speed`）**: JTAG の PC サンプリング（slot 0x18、
     3000 点）で S1 @10MHz の時間配分は IRQ0 ISR（DEPTH 0x32EAA 周辺 + 0x34772 長除算）≈ 32%、
     GRCG TDW 矩形塗り 29%、スプライト展開 25%。np2（≒286-10）では ISR は 2%。ISR 1 回 ≈ 210 µs
     （実機 ≈ 14 µs）で、原因は GRCG ではなく **paced 時のコードフェッチ**: キャッシュ OFF・pf OFF
     （retail 既定）では z86 の行ロードが毎回「行頭から 8 語」をフルバスペアで取り、分岐で捨てられても
     最後まで走り、さらに EU のデータ読みがその行ロードの後ろに並んでいた。pf ON（slot9 bit3）は
     この Pocket では逆に遅い（S1 51%、bench の GVRAM16K/DEPTHDRAW も 2〜3 倍悪化。§6 の
     「ウォーム劣化」と同じ状態で、原因未特定）ので既定 OFF のまま。
     対策: (1) uncached 行ロードを分岐先の語から始め、fetch が捨てたら途中で止める（fetch に
     半分ごとの buf_lo を追加し、それより下への分岐は再ロード）、(2) z86_cache の S_IDLE で
     データ読みを行ロードより先に出す。tb_mem_perf @10MHz pf OFF: CALL/RET 640k→267k clk、
     IRQ storm 6.84M→3.65M、frame-iret 455k→335k、ストリーム/GRCG 相は ±0.5%。
     (2) の初版は z86_cache の look_idx（タグ RAM の先読みアドレス）を旧順序のまま残し、Turbo の
     キャッシュ読みが別ラインを返して起動直後に X000:0094 へ暴走した（#1027）。#1028 で修正。
   - **実機結果（CI #1028 = run 40512626101、JTAG フラッシュ、ALM 17,833/18,480、LAB 1847/1848、
     最悪 setup slack +0.50 ns 級）**: ITF POST + SCSI HDD IPL PASS、SuperDepth Turbo 40/40、
     `sd_stage2_check.sh turbo` PASS（S1/S2 5.00）。`sd_stage2_check.sh 10`: S1 8.07→**7.15**
     VSYNC/フレーム（62→70%）、S2 10.70→**8.15**（47→61%）、BGM 99%（前値は同日 #1024 の実測）。
   - **まだ残るもの（次の一手）**: #1028 の S2 @10MHz PC サンプルは ISR ≈ 22%、GRCG TDW（全画面クリア
     + 矩形）≈ 27%。ISR は依然 1 回 ~190 µs で、行ロード中（S_WLD）は EU の読みが 1 行分待つ。
     S_WLD を EU アクセスで打ち切る案は試作して不採用（REP 書き込みが投機ロードを毎語打ち切って
     1 語ずつ再開し、STOSB 3 倍・frame-iret 悪化）。やるなら「打ち切った位置から再開」できる半分ごとの
     hi 境界（buf_hi）が必要。もう一つの軸はバスペア自体のコスト（sim で読み 1 回 ≈ 33 clk = 7.7 CE、
     実機 286 は 2 CE）。pf ON はこの Pocket では逆効果のまま（上記）。
2. **RMW の高速化**（S2 でも 1 フレームあたり約 3k ワード）: GRCG RMW の各プレーンの読み書きをまとめる。フリーズの教訓から、ポステッド書き込みは使わず、完了を待つ同期方式でまとめる。
3. **TDW の書き込み結合**（必要なら）: 連続アドレスをプレーンごとにバースト化する。slot ビットで既定 OFF にして導入し、コールドブートで確かめてから ON にする。
4. **プレーンのバンク分散 / 表示フェッチのバースト長 32**: 効果は 1〜2 割、リスクは中。上の 3 つで足りなければやる。
5. **書き込みキュー（a2f0d62）の再導入**は、読み p_done 消失の根本原因が確定し、ランダムタイミングの sim で再現・修正済みになるまでやらない。

サブエージェントは 1 段につき 1 体まで（計測は本体、実装は 1 体）。
