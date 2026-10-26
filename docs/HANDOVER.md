# PC-98 Pocket 引き継ぎ — 2026-10-26 夜

> ユーザーの最後の報告: 「またフリーズだよ、これ改善してないね。引き継ぎmd書いて」
> これを受けて作成。前回版 (9e74305) から全面改訂。

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
  フレーム境界ラッチして対策。**実機での効果確認はまだ**。
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
