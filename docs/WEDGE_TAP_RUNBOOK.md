# ウェッジ計測タップ運用手順 (WEDGE TAP RUNBOOK)

最優先バグ「ウェッジ」(6〜36秒後に fetch が永久停止、retired_cnt=0、
greset でも復帰しない) のための計測インフラと判読表。

## 1. なぜ greset で直らないか (静的監査の結論)

greset (write slot 0x87 bit2) が押す reset_wire が届くのは
`reset_cpu` / `reset_chipset` 系 (**Bus_Arbiter・uPD71071・READY・i8288・
cpu_bus_bridge・z86・Peripherals**)。

**届かないのは `reset_sdram` domain (PLL ロックのみ)**:

| モジュール | リセット | greset で初期化されるか |
|---|---|---|
| cpu_bus_bridge / z86 | reset_cpu | される |
| Bus_Arbiter / uPD71071 / READY / Peripherals | reset (=reset_chipset) | される |
| **RAM.sv (parked-write FIFO 含む)** | **sdram_reset** | **されない** |
| **pc98_gvram_seq (全メモリアクセスが通るシーケンサ)** | **sdram_reset** | **されない** |
| **sdram_shim / sdram_mp** | **sdram_reset** | **されない** |

「greset 後も PC=FFF0 の最初の fetch すら完了しない」= この生存ドメイン
(RAM.sv / sequencer / shim / mp) のどれかが停止状態を保持している、
と整合する。さらにウェッジ後のリセットループは greset 可能な証人
(arbiter/DMA/READY) を消してメモリも汚すため、**発症瞬間の凍結スナップ
ショット** が必要。

## 2. 追加したインフラ

- **ウェッジ検出器** (core_top): liveness 信号 (retired_cnt **または zet_pc** —
  z86 には retire タップが無く retired_cnt は常に 0 なので、実効的には
  fetch cursor の静止) が ~390ms (2^24 clk) 変化なし (CPU 動作中・非 pause・
  非 reset・非 probe停止 のときのみカウント) で `wedge_latch=1` を立て、
  下記スナップショット全レジスタを**凍結**。
  以後リセットループが起きても値は動かない。
- **遷移捕獲トリガ 2種** (run#976 凍結署名対策 — poll ループ滞留では
  retired/pc が「動いたまま止まらない」ため旧検出器が発火しない):
  - **poll-trap** (書き込みスロット 0x07, wr 0x87 形式 `{en[31], pc[19:0]}`):
    fetch cursor が arm したアドレスの 32 バイト窓 (pc[19:5] 一致) に
    ~390ms 留まり続けたら発火。0x317A8 の BGM sequencer poll 用。
  - **FDC DRQ-stall** (常時武装・書き込み不要): floppy の dma_req レベル
    (= Peripherals の fdd_dma_req_wire) が ~390ms 立ち続けたら発火。
    正常転送は DACK 毎に数クロックで折れるので遠く届かない。
  - どちらも発火で wedge snapshot + pc_hist + tlog を凍結
    (書き込みスロット 0x08 bit0 で全解除=再アーム)。
- **読み出しスロット 0xA0-0xA7** (すべて凍結値、core_top 境界でレジスタ化
  済み — S2T クラッシュ対策の既存パターンと同じ):
  - `0xA0` = {Bus_Arbiter dbg_w[15:0], READY dbg[7:0], arbiter hold byte}
  - `0xA1` = RAM.sv dbg_w_ram[23:0]
  - `0xA2` = sdram_shim/mp dbg_w[31:0]
  - `0xA3` = {24'h0, dbg_w[39:32]} (port-A req_age)
  - `0xA4` = cpu_bus_bridge dbg_w[23:0]
  - `0xA5` = {pc98_gvram_seq dbg2[15:0], chipset_dbg2[7:0], 8'h0}
  - `0xA6` = {wedge_latch, 7'h0, snap_retired[23:0]}
  - `0xA7` = {12'h0, snap_pc[19:0]} (latch 時点の fetch cursor)
- **読み出しスロット 0xA8-0xAA** (run#976 第4切り分け用、同様に凍結値):
  - `0xA8` = uPD71071 リクエスト側レジスタ (upd71071 dbg_mask):
    `[31]` controller_disable, `[30]` dreq_sense_active_low,
    `[29]` rotating_priority, `[28:27]` transfer_mode[3],
    `[26:25]` transfer_mode[2], `[24]` autoinit[3], `[23]` autoinit[2],
    `[22:19]` mask_register, `[18:15]` request_register (SW),
    `[14:11]` dma_request_ff (DREQ 生ピン、sense 反転後),
    `[10:7]` dma_request_lock, `[6:0]` 0
  - `0xA9` = floppy 実行相ビュー (Peripherals dbg_fdc2 = {0, floppy dbg2, TC}):
    `[31]` 0, `[30:27]` main state, `[26:16]` fifo_count,
    `[15]` execute_ndma, `[14]` ndma_irq, `[13]` ndma タイムアウト検出,
    `[12]` dma_irq_enable (0x94 DMAE), `[11]` dma_has_terminated (TC 受領),
    `[10]` cmd_read 進行中, `[9]` cmd_write 進行中, `[8]` cmd_format 進行中,
    `[7]` dma_req, `[6]` irq (INT 線), `[5]` busy, `[4]` in_seek_mode,
    `[3]` datareg_ready, `[2]` transfer_to_cpu, `[1]` dma_ack パルス,
    `[0]` TC ラッチ
  - `0xAA` = {wedge_latch, poll_latch, fdq_latch, 5'h0, poll_static[23:0]}
    (どのトリガが発火したか。poll_static は窓滞留カウンタの途中値も読める)
- **書き込みスロット 0x08** (wr 0x88 形式):
  - bit0: ラッチ解除+再アーム (poll/fdq トリガのカウンタも全解除)
  - bit1: **RAM.sv unstick パルス** (parked-write FIFO 全廃棄・FSM を
    IDLE 強制)。shim/mp の進行中トランザクションには触らない
    (単一トランザクションは必ず自力完結するため)。
- **各 dbg ポートの新設**: sdram_mp→shim→RAM.sv, pc98_gvram_seq,
  READY, upd71071(Timing_And_Control + Priority_Encoder)→Bus_Arbiter,
  cpu_bus_bridge, floppy.v→Peripherals, Chipset 経由で core_top へ
  (すべて core_top 境界で 1 段レジスタ)。
- **撤去** (LAB 相殺): Bus_Arbiter の書き込みウォッチポイントリング
  (0xE1-0xE4 は死亡スロット化、書き込み 0x0A も無効)、RAM.sv の
  dbg_watch_addr 入力、core_top の ws_hit 凍結条件。
  0x3E の {break, grant, ack_wr} カウンタは現役残置。

## 3. 実機手順

```sh
# (1) イメージをロードして再起動 (いつもどおり)
openocd -f scripts/jtag_probe.cfg \
        -c "set HDIMG /tmp/opencode/superdepth_tr.hdm" \
        -f scripts/jtag_hdload.tcl

# (2) ウェッジ待ち + 自動凍結 + デコード表示 (タイムアウト 240s)
openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wedgehunt.tcl

# unstick 実験も同時にやる場合:
UNSTICK=1 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wedgehunt.tcl
```

`jtag_wedgehunt.tcl` は 0x17/0x18 を 400ms 毎に poll し、静止を検出したら
凍結スナップショットを判読可能な形で表示する。手動で読む場合:

```tcl
set x [rd 0xa6]   ;# bit31 = wedge_latch。以降 0xa0..0xa7 が凍結値
```

### 3.1 run#976 型 (poll ループ滞留 + DRQ pending) の狩り方

0x317A8 型の凍結は CPU が poll ループを回り続ける/留まり続ける形なので、
旧検出器 (完全静止) ではなく遷移トリガで捕まえる:

```tcl
# openocd のプロンプトまたは自作スクリプト内で:
wr 0x87 [expr {(1<<31) | 0x317A8}]   ;# poll-trap: 0x317A8 の32バイト窓, en
# 0x317A4 窓にするなら pc[19:5]=0x18BD — 0x317A8 をそのまま渡せばよい
# (窓は pc[19:5] 一致なので 0x317A0-0x317BF 全体が対象)
# FDC DRQ-stall は常時武装 — 何もしなくてよい

# 狩り: 0xAA を見ながら待つ (どちらかの latch が立ったら発火)
#   poll_latch = bit30, fdq_latch = bit29, wedge_latch = bit31
# 発火後: 0xA0-0xA9 を読んで切り分け (下の 4.6 節)
wr 0x88 0x01                          ;# 全ラッチ解除=再アーム
```

## 4. 判読表

### 4.1 まず見る 3 点

| フィールド | 値 | 意味 |
|---|---|---|
| `0xA6 bit31` | 1 | タップが発火 = 機械は本当に命令を retire していない |
| `shim req_age` (0xA3) | 0xFF | port-A の要求が **グラントされない** (仲裁/制御器が止まっている) |
| `shim busy_age` (0xA2[31:24]) | 0xFF | グラント済みトランザクションが **完了しない** (mp/SDDRAM 級) |

### 4.2 RAM.sv (0xA1)

| 状態 | 解釈 |
|---|---|
| `st=IDLE, age=0..数` + bridge `cmd_age=0xFF` | RAM は空いているのに bridge がコマンドを出せない → **上流 (arbiter/DMA hold, INTA, wb 停止)**。0xA0 の HLDA/AEN/dma HRQ と bridge cur_* で切る |
| `st=IDLE, rd_conf=1` が続く | 読み込みが parked write と衝突し続けている (FIFO が drain されていない = FSM が IDLE を回れていない矛盾 → age 参照) |
| `park={1,1,1,1}` + `age=0xFF` | **parked-write FIFO 満杯で FSM 停止** — RAM.sv の記帳が詰まっている。unstick (wr 0x88 0x02) で回復するはず |
| `st=COMPLETE` + `alr=1` + age 大 | 読み出し完了したが strobe が落ちない → bridge の rd_own/accept 経路 (0xA4 rd_own, saw_low) |
| `st=R1/R2/WAIT` + age 大 | SDRAM 待ち — shim の busy_age と突き合わせ |
| `rwc/wwc != 0` が続く | wait カウンタが減っていない = `wait_count_clk_en` (CE 列車) 停止の疑い |

### 4.3 sequencer (0xA5 上位)

| 状態 | 解釈 |
|---|---|
| `expand=1, age=0xFF` | GRCG/svc ウォークが完了しない。`mem_rd=1` なら読み leg 待ち (RAM 側を見る)、`mem_wr=1` なら書き leg の coverage 待ち |
| `svc_gap=1` 以外で `age` 小 + RAM も idle | sequencer は無罪、上流 (bridge/arbiter) を見る |
| slot 0x31 (既存, 生値) と併読 | `{svc_req, svc_done, svc_hold, st/gp}` — svc_hold=1 のままならソフトコアの描画チャネル滞留 |

### 4.4 bridge (0xA4)

| 状態 | 解釈 |
|---|---|
| `cmd_age=0xFF`, `rd_own=0` | byte engine が B_CMD で自分の読み完了証人を待っている (RAM/seq 側の対応する年齢と突き合わせ) |
| `cmd_age=0xFF`, `inta=1` | INTA ペアで止まっている → PIC/ベクタ系 (0x2F dbg_inta と併読) |
| `wrq=2..3` + `dq=1` が続く | posted-write drain が捌けない (RAM park 満杯と相互依存の疑い) |
| `cmd_age` 小さい or `pf/fillm` 以外で idle | bridge は無罪、arbiter/DMA 側 |

### 4.5 arbiter/DMA/READY (0xA0)

| 状態 | 解釈 |
|---|---|
| `HLDA=1, AEN=1` + dma `state=SW(5)` + `TC=0` | **DMA がバスを保持したまま ready を待っている**。mem_rdy (0xA5) が 0 なら RAM/seq 側が止めている。dma state=SI なのに HLDA=1 なら**解放側の不整合** |
| `HRQ=1` (dma_dbg bit2) + `HLDA=0` | DMA が hold を要求してもグラントされない (`hrq_ff1/ff2` でチェーンのどこで止まっているか) |
| `dce_pin` が 2 回の読みで不変 | **DMA の CE 分周器が停止** = バスが永久に DMA 保持 |
| `proc_rdy=0, mem_rdy=1` | READY チェーンの synthesis で ready が消えている (wait/Qn ビットで段を特定) |
| `ext_req=1` | BIOS ローダが ext_access_request を離さない (ioctl download 絡みの変則) |

### 4.6 mp (0xA2 下位)

| 状態 | 解釈 |
|---|---|
| `st=4 (S_IDLE)`, `have_req=1`, `idle=0`, `rfdue=1` が続く | リフレッシュと要求の両方を無視して S_IDLE 停止 (タイマー/状態矛盾 — 本監査では到達不能と判断した経路。再現したら mp 深掘り) |
| `st != S_IDLE` + `busy_age=0xFF` | コマンド系列 (ACT/RW/TAIL/REF) から抜けない |
| `p_req` のビット模様 | どのポートが要求を出し続けているか {F,E,D,C,B,A}。A=1 のまま=RAM.sv からの要求、D=1=表示フェッチ |

### 4.7 uPD71071 リクエスト側 (0xA8) — run#976 第4切り分け

凍結署名 `dma state=SI + drq=0011` (ch2/ch3 DRQ pending のまま grant なし)
を 3 仮説で割る:

| 0xA8 の読み | 結論 |
|---|---|
| `[22:19] mask` の ch2/ch3 ビットが **1** | 仮説 (a): **書き込みがまだどこかで消えている** — unmask (0x15) が 71071 に届いていない。第3修正 (CS窓内連続サンプリング) の窓をすり抜けた別経路を探す (i8288/ブリッジの再発、FDC 側ポートの干渉) |
| mask=0 でも `[10:7] dma_request_lock` の ch ビットが 1 | エッジセンス lock が外れていない (single モードの ack 辺検出が死んでいる) |
| mask=0, lock=0, `[14:11] dma_request_ff` に DRQ が反映されているのに state=SI | 仮説 (b): 優先エンコーダ以降 (encoded_dma→HRQ) か dce/CE 側。`[31] controller_disable` と 0xA0 の dce_pin も見る |
| `[30] dreq_sense_active_low=0` | コマンドレジスタ bit6 が書き換わっている (stray write) — DRQ 極性反転で req が見えない |
| `[28:25] transfer_mode` が single(01) でない | モードレジスタ破壊 — edge_request が立たず lock が組めない |
| 0xA8 すべて正常 + 0xA9 `[7] dma_req=1` のまま | 仮説 (b'): **FDC が DRQ を出したまま IRQ まで到達しない** — 0xA9 の state/fifo/ndma ビットで FDC 側停止位置を特定 |
| 0xA9 `[30:27] state` が S_WAIT_FOR_EMPTY_READ_FIFO 以外 / `[11] TC 受領=1` / `[14] ndma_irq=1` | 仮説 (c): FDC 側の状態遷移バグ (execute_ndma の `[15]` と組み合わせて NDMA/DMA モード混乱の判別) |

### 4.8 unstick 実験の判読

`UNSTICK=1` で wr 0x88 0x02 を打ったあと retired_cnt が再び動けば、
**詰まりは RAM.sv の parked-write/FSM 記帳** に確定 (修正対象は RAM.sv 側)。
動かなければ seq/shim/mp か上流。凍結スナップショットとの組み合わせで:

- `park 満杯 + unstick 回復` → RAM.sv 記帳デッドロック
- `seq expand=1, age=FF + unstick 非回復` → sequencer の leg 完了待ち
  (RAM は動いているのに leg_done/mem_ready が来ない経路)
- `shim busy_age=FF` → SDRAM 側 (要さらなる深掘り)

## 5. sim での再現結果

`sim/tb_wedge_hunt.sv` (実チェイン: pc98_gvram_seq + RAM.sv + sdram_shim +
sdram_mp + sdram_model) に 3 マスタ (fetch=ホールド読み / FDC DMA=
早期解放パルス込みの書き込み / GRCG RMW svc ウォーク) + port-D 表示
バースト + オートリフレッシュを同時負荷:

- SEED 1-8, 最大 6ms (=25万クロック強), 計 ~1万 fetch / ~11万 DMA バイト /
  ~1300 svc op — **ウェッジ未再現** (すべて PASS)。
- 初回の「再現」はベンチ側バグ (svc ストリームが SDRAM パワーアップ
  init (INIT_NOP=10000clk) 完了前に走り出し、watchdog 4000clk を誤爆)。
  修正後は全負荷で健全。
- ベンチは Bus_Arbiter/READY/71071/bridge を含まない (単一ゲストバスを
  モデル)。よって **上流 (arbiter/DMA/READY/bridge) 由来の経路はこの sim
  では検証外** — それが実機タップの 0xA0/0xA4 の役目。

## 6. 静的監査: 到達可能なデッドロック経路リスト (確度付き)

1. **RAM.sv parked-write FIFO 満杯 + FSM 非 IDLE 停留** (RAM.sv:643-670,
   704-818): 3 スロット + cap がすべて埋まり、かつ FSM が IDLE に戻れぬ
   場合、held strobe の coverage (memory_access_ready) が永久に出ない。
   監査上 FSM は自力で IDLE に戻る経路しか持たないため**条件付き**
   (確度: 中)。→ 0xA1 park+age と unstick 実験で判定。
2. **pc98_gvram_seq S_WRW/S_RDW の leg 完了待ち** (pc98_gvram_seq.sv:770,
   832): `leg_done | mem_ready` が永久に来ない場合 walk が止まり、ゲスト
   の strobe を握ったままになる (以降全アクセス停止)。RAM 側が健全なら
   到達不能のはずだが mem_ready の「idle-high」契約と svc_gap の綾で
   **条件付き** (確度: 中)。→ 0xA5 expand/age + 0x31。
3. **uPD71071 SW 停留 + hold 解放なし** (upd71071_Timing_And_Control.sv:217,
   339-353): dma_ready が来なければ SW から出ずバス保持。dma_ready は
   READY.sv のレベル合成で通常必ず立つが、リフレッシュ連続や
   memory_access_ready 停止と重なると**理論上残る** (確度: 低-中)。
   ただし greset でクリアされるため単独では「greset 不毛」を説明できず、
   真因が RAM/seq 側で二次的に DMA を止める形状が有力。→ 0xA0。
4. **shim busy 待ち / mp グラント喪失** (sdram_shim.sv:270-290,
   sdram_mp.sv:359-416): 監査では mp FSM は常に S_IDLE へ戻り
   round-robin も飢餓しない (pre_guard/timer は必ず減る)。
   **到達不能と判断** (確度: 高=無罪) — ただし 0xA2/0xA3 で実測確認する。
5. **Bus_Arbiter hold チェーン** (Bus_Arbiter.sv:76-102, 229): ext_request
   が立ったまま (BIOS ローダ停止) は CPU 永久バス喪失だが、ゲーム中は
   ioctl_download=0 で**到達不能** (確度: 高=無罪)。0xA0 ext_req で実測。

## 7. 今後の流れ

1. 実機で `jtag_wedgehunt.tcl` を回し、凍結スナップショットを取得 →
   判読表で犯人モジュールを確定。
2. `UNSTICK=1` で RAM.sv 記帳説の A/B。
3. 犯人確定後、対応するモジュールの修正 + 本ベンチへの再現ケース追加。

## 8. 修正 (RAM.sv ウェッジ watchdog) — 2026-10-22

実機判読 (0xA0-0xA7) と unstick 復活実験で犯人は RAM.sv の FSM 停留に確定
したため、RAM.sv に自己回復 2 層を実装した:

- **レイヤ 1 (served-park の上限)**: COMPLETE_RAM_RW は SDRAM トランザク
  ション完了後にのみ到達し、滞留の唯一の理由は「マスタの strobe が
  ready を待って上がったまま」。上流の ready 消費者 (READY.sv の CE-同期
  エッジ、bridge の rd_own witness、uPD71071 の dma_ready パルス) は
  すべてエッジ機械で、立上りがサンプル窓に落ちないと誰も消費しない
  = level が high のまま張り付き、マスタは永遠に accept しない。
  2^13 clk (≈190µs) 駐留したら ready を 2^6 clk マスクして再assert する
  (unstick パルスが実機で回復させたのと同じ dip-and-re-assert を in-place
  に再現。アクセスを再実行しないので fill の beat 二重 append や書き
  オペランドの再ラッチは起えない)。
  **DMA 保持窓では発動しない (dma_hold = AEN)**: run#973 の SD コールド
  ブート回帰で判明 — FDC が SD カードからセクタを待つ間の uPD71071 の
  書き strobe 保持は 10-100ms 超の**正規の長期駐留**で、190µs の dip が
  1パルス消費の dma_ready に偽パルスを注入して DMA を脱線させた
  (「MEMORY 640KB OK」停止、DRQ 未回収、unstick 無効)。正規 DMA 駐留は
  ストレージレイテンシ次第で無制限に長くなるため時間では区別できず、
  **バス所有権 (AEN) で区別する**: AEN 高の間カウンタは 0 に保持され、
  dip には 2^13 clk の**連続 CPU 所有**駐留が必要。CPU 側マスタの ready
  消費はレベル/パイプライン (偽 dip は高々 2^6 clk の遅延) なので
  CPU 所有窓の dip は安全。断念するもの: DMA 側 ready 取りこぼし駐留
  (未観測 — 元ウェッジは HLDA=0/AEN=0 で凍結) は修正前同様無回復の
  まま。タップはそれを park+age+AEN高 で特定できる。
- **レイヤ 2 (no-work watchdog)**: 非 IDLE かつ保留仕事ゼロ (park 空・
  write strobe 無し・read 要求無し) が 2^20 clk (≈24ms) 続いたら
  unstick と同じクリア (park 廃棄 + IDLE 強制) を自動発動。read_flag/
  write_flag 停留や WAIT の idle 停滞など、静的監査で到達不能とした
  ハンドシェイク停留の保険。
  **SD 起動の長い DMA 待ちでは発火しない**: ストローブ保持中の駐留は
  write/read 要求あり (=保留仕事あり) で条件不成立、バイト間は FSM が
  IDLE を通るたびにカウンタがリセットされるため、実トラフィック下で
  2^20 clk **連続**の no-work 非 IDLE は到達不能 (directed case (c) で
  2^16+ 駐留中の不発火を検証済み — 出荷値 2^20 ではさらに 500 倍の
  余裕)。

どちらも健全時の最大滞留 (16語 fill + リフレッシュ待ち ≈100 clk、
最遅ペースの wait カウント消化 ≈数百 clk) より桁違いに長いので、
生きているマシンでは一度も発火しない (tb_mem_perf 全フェーズ・
tb_wedge_hunt 8 シードで dip 発火ゼロを確認済み)。

### 実機での期待挙動

- 従来 6〜36 秒で死んだウェッジは、発症しても **~190µs 以内に自動復帰**
  する (レイヤ 1)。BGM/描画は継続し、`retired_cnt` (0x17) が止まっても
  数 ms 以内に動き出すはず。
- したがって **wedge_latch (0xA6 bit31) は基本発火しなくなる**
  (静止検出の ~390ms より速く回復するため)。もしまだ発火する場合は
  レイヤ 1/2 の前提外 (bridge/arbiter 上流や shim/mp 本体の停留) なので
  タップ判読を続行すること。
- `wr 0x88 0x02` (手動 unstick) はそのまま残る (保守用の手動オーバーラ
  イド)。probe スロットマップ (0xA0-0xA7) と probe mux の fanout は
  不変。

### sim

`sim/tb_wedge_hunt.sv` に 4つの directed case を収録:

- (a) served-park: held read が完了してもマスタが ready 立上りを見逃す
  形。FSM は COMPLETE に駐留 (タップの凍結形状) → レイヤ 1 が
  dip+再assert → マスタが 2 番目の立上りで accept → 経路復帰。
- (b) no-work watchdog: R2 のバースト中に shim の busy を jam してから
  全 strobe を落とす (保留仕事ゼロの非 IDLE 停留) → レイヤ 2 が
  2^16 clk (ベンチは縮小値) で auto-unstick → IDLE 復帰。
- (c) DMA 保持駐留 (run#973 回帰): dma_hold=1 (AEN 高) の書き strobe を
  ホライズン超で保持 → **dip 不発火・watchdog 不発火**・経路健全。
- (d) CPU 所有の書き駐留: 同形状を dma_hold=0 で → 従来どおり dip+
  再assert で回復 (ゲートが DMA 窓のみを無効化したことの証明)。


## 9. 第3のデッドロック (uPD71071 SI 停留 + DRQ pending) — 2026-10-22

### 実機症状 (0xA0-0xA7 凍結スナップショット)

RAM ウェッジ修正後もゲーム中 (SuperDepth タイトル BGM, 6-36秒) に同一署名で
フリーズ: 71071 state=**SI**・hrq=0、FDC の DRQ は **pending のまま**
(drq タップの 0011 = ch2/ch3 ピン low = fdd_dma_req=1、ch0/1 の見えはタイオ
フピンの定常 — ビット順の誤読に注意)、RAM/seq/shim/mp は全て idle、
retired_cnt は動き続ける (CPU はゲームのポールループで生存、wedge_latch
不発火)。RAM unstick 無効。

### 犯人: 71071 のレジスタ書き込みがストローブテールで消失

`upd71071_Bus_Control_Logic` の書き込みパルス検出は
`prev_write_enable_n` を **CS が上がった瞬間に再武装** していた。
このコアのバスでは cpu_bus_bridge が現ペアの解放クロックに次のアクセスを
アームし、i8288 のコマンドストローブは ~1 CE 遅れて退役する — つまり
**IOW がまだ low のうちにアドレス/データが次サイクルのものに差し替わり、
CS とともにウィンドウから外れる** (Peripherals.sv の io_wr_addr_q コメント
に記録されたのと同一病理; FDC 側は連続サンプリング+立上り消費で既に修正済
み)。テールで CS が外れると `prev_write_enable_n` が再武装され、IOW 立上り
で `write_flag` が**立たない = レジスタ書き込みが黙って捨てられる**。

数千回に一度 (位相依存) の割合で BIOS の `out 0x15, 0x02` (ch2 アンマスク)
が消失 → 次の FDC コマンドの DRQ が**マスクされたチャネルに**立ち、71071 は
SI から永遠に出ない → FDC は実行フェーズのまま FIFO を抱え、IRQ が出ず、
ゲームはポール待ちで永久停止。タップの全フィールドを説明する。

### 修正 (upd71071_Bus_Control_Logic.sv)

FDC ポート経路と同じ形に揃えた:

- アドレス+データは **CS low ∧ IOW low の間**毎クロック取り込み、CS が
  外れたら保持 — IOW 立上りのデコードは「最後に自分のものだったアドレス」
  を使う (`stable_address` の全遅延 1clk 版 → `write_address`)。
- 一度始まった書き込みパルスは **IOW の立上り (または DMA 転送の bus lock)
  でのみ**退役。CS のテール脱落では再武装しない。

### sim (`sim/tb_fdc_si_stall.sv`, `scripts/sim_fdc_si_stall.sh`)

実 BUS_ARBITER (実 71071 を 92/201 の dce クロックで、実 grant チェーンご
と) + 実 READY.sv + Peripherals の DRQ シェーパ (fdd_dma_req の DACK 保持
クリア/0x94 ゲート/TC 配線) とタイオフ付き dma_request、ITF と同じ
command 0x40、BIOS と同じアーム/ディスアーム列、fill 待ち中の MSR ポール
と INTA ストーム。`+TAIL=1` でブリッジ型テール (ストローブ終端で次サイク
ルのアドレス/データを差し込む) を再現:

- 修正前: TAIL=1 で 4速度×2モード全てが **SI 停留・mask=1111・fifo 満杯**
  (実機タップと同一署名) を即座に再現。
- 修正後: TAIL=0/1 × SPEED=0-3 × MODE=46/06 の **16 構成全て PASS**
  (4 セクタ×1024B、スコアボード全一致)。CI でも全構成を実行。

### 実機での再発待ち目安

BGM ストリーミングは数 ms に 1 回 FDC コマンドを発行し、そのたびに 0x15
アンマスクを書く。修正が効いていれば 6-36 秒だったフリーズは出なくなり、
タイトル BGM を **10 分以上** 放置しても retired_cnt (0x17) が動き続け
wedge_latch (0xA6 bit31) が立たない、で確認できる。
