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

- **ウェッジ検出器** (core_top): retired_cnt が ~390ms (2^24 clk) 変化なし
  (CPU 動作中・非 pause・非 reset・非 probe停止 のときのみカウント) で
  `wedge_latch=1` を立て、下記スナップショット全レジスタを**凍結**。
  以後リセットループが起きても値は動かない。
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
- **書き込みスロット 0x08** (wr 0x88 形式):
  - bit0: ラッチ解除+再アーム
  - bit1: **RAM.sv unstick パルス** (parked-write FIFO 全廃棄・FSM を
    IDLE 強制)。shim/mp の進行中トランザクションには触らない
    (単一トランザクションは必ず自力完結するため)。
- **各 dbg ポートの新設**: sdram_mp→shim→RAM.sv, pc98_gvram_seq,
  READY, upd71071(Timing_And_Control)→Bus_Arbiter, cpu_bus_bridge,
  Chipset 経由で core_top へ (すべて core_top 境界で 1 段レジスタ)。

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

### 4.7 unstick 実験の判読

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
