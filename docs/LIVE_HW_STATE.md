# LIVE HARDWARE STATE — read before touching the Pocket (2026-09-28 ~09:00 JST)

> **ハードを共有している可能性への注意書き。** このセッション(Devin)は実機に
> 介入を残したまま止まっています。あなたが別エージェントなら、以下を読んで
> から作業してください。

## ★ RAM write-strobe 修正: 実機検証済み (2026-09-28 08:5x JST, commit 75187b8)

CI run 36358008905 のビットストリーム (USERCODE=0x0680F7B3) で
ブート経路をフル検証 — **周期性 DMA 書き込みドロップは解消**:

- BIOS の IPL 読み出しに JTAG で `fdc_ipl.hdm` セクタ 0 を供給
  → **0x1FE00 (DMAC→SDRAM 経路): 511/512 byte-exact**。唯一の差分は
  IPL 自身の `markpos` 変数 (実行の証拠)。修正前は 76/512 が
  pre-dirty 0xFF のまま残る周期性ドロップだった。
- IPL が自前で C0H0R1 を PIO 再読み → **0x40000: 512/512 byte-exact**。
- 画面に **"ISRDPE"** — IPL 全フロー走破 (result phase まで到達)。

再現手順: flash → `MGMOUNT=1` → req 待ち →
`MGSECT=/tmp/fdc_ipl.hex MGNOWAIT=1` (hex = `od -An -v -t x1 hdm` 出力)
→ 0x1FE00 dump → IPL の req で再 push → 0x40000 dump。

テスト stub 側の修正 2 点 (commit af41bbb): `putmark` の push/pop 不整合
(3 push vs 4 pop で ret がゴミへ) と `EOT=8→1` (NDMA は sector==eot まで
result phase に入らず .rs が永久ブロック)。

## 前回セッションからの状態: Pocket は復帰済み (要 再スリープ注意)

- ~03:58 JST に JTAG スキャンチェーンが全ゼロを返すようになり、
  SLD hub (`hub=00000000`) も応答しない = **FPGA 無設定**。
  直前までコアは正常動作していた → Pocket の auto-sleep か電源断が濃厚。
- `ap_core.svf` (USERCODE=067F6330, mgmt直叩き入り) の replay は
  **「コア実行中でないと nCONFIG が開かない」**ため失敗する。
  再開にはまず Pocket の電源ON + コア起動が必要。

## このセッションで実証済みのこと (commit 58104b3)

CI run 36333730260 のビットストリーム (PC98_PROBE_EXTRA 入り) で:

- **JTAG→CHIPSET mgmt 直叩きが完結** (write slot `0x86`, witness `0x27`):
  `MGMOUNT=1 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_mgmt.tcl` で
  firmware 無しに `present=01` が立つ (wr_seen=12, last=F200)。
- **FIFO 直 push → ゲストメモリ往復がバイト一致**: `MGSECT` で
  `fdc_ipl.hdm` の 1024B を `0xF20F` に push → `req` がちょうど 1024B で
  降り、stub が drain した sector_buf = 投入データ完全一致
  (E5フィルのセクタで実測)。
- **mgmt write の CDC 取りこぼし説は棄却**: 120ns パルスを clk_chipset が
  そのまま受けるので、JTAG ドライブの write は全部届く。
- **ゲスト stub 運用の罠**: stub は IF=0 で走る + iret 時 EOI を送るが、
  `.rs` 結果フェーズの長いタイムアウト中は ISR が in-service のまま
  残り IRQ1 再発火がブロックされる → 次発火まで数分待ち。

## 未解決/次の検証 (再開手順)

1. Pocket 電源ON → コア起動 → `scripts/jtag_flash.sh build/artifact_new/output_files/ap_core.sof`
   (SVF キャッシュ `build/svf_jtag/ap_core.svf` でも可)。
2. `MGMOUNT=1` で 2HD メディアを仮想マウント (firmware 不要)。
3. BASIC プロンプトで Enter キー注入 → BIOS ディスクブート →
   FDC req 発火 → `MGSECT=testdisk/fdc_ipl.hex SECTOFF=0 MGLEN=1024` で
   IPL sector を push → BIOS が DMAC 経由で 0x1FE00 にロード。
   IPL (`testdisk/fdc_ipl.asm`) は自身が PIO で C0H0R1 を再読みして
   `0x40000` に格納する → もう一度 req が立つ → 再 push。
4. **0x1FE00 (DMA 経路) と 0x40000 (PIO 経路) を `MODE=dump` で読み、
   イメージと比較** — DMAC/SDRAM 書き込み経路と FDC/FIFO 経路を分離。

## 破損の有力容疑 (floppy.v)

`floppy.v:1119,1132`: DMA モードで `dma_has_terminated` が立つと
**fifo が `8'h00` で埋められる** (TC 後の残りをゼロ埋め)。
DMAC が sector 途中で TC を出すと、以降の位置が位置保存型で 0x00 になる
= 観測されたブート時 IPL 破損 (~18% 散発ゼロ) と一致する注入経路。
upstream (dataslot→BRAM) のゼロ混入も未排除 — 上記 0x1FE00/0x40000
比較で切り分けられる。

## JTAG slot 早見表 (PC98_PROBE_EXTRA ビルド)

- write `0x81`: キーマトリクス byte (press `0x34`, release `0xB4`)
- write `0x84` / read `0x25`: guest メモリ master (jtag_memwrite.tcl)
- write `0x85` / read `0x26`: firmware FDD チャネル (要新版 firmware)
- write `0x86` / read `0x27`: **CHIPSET mgmt 直叩き** (jtag_mgmt.tcl)
  - write data = `{addr[15:0], data[15:0]}`; addr `0xF2nn`:
    reg0 present / 1 wrprot / 2 cyls / 3 spt / 4 total / 5 heads /
    6 secsize(0=512,1=1024) / **F = FIFO push**; bit7 = drive B
  - read `0x27` = `{wr_seen[7:0], last_addr[15:0], req[1:0], present[1:0]}`
    の packing = 実際は `{wr_seen,last,2'b00,req[7:6],2'b00,present[1:0]}`
- read `0x1F/0x20/0x21`: PIC {IRR,IMR,ISR,timer} / slave+kbd_irq / irq_level

### 旧セッション履歴 (IVT[8] draw_test の話)

以前のセッションで IVT[8] を draw_test に向けた記録は**揮発済み**
(FPGA 再構成で RAM ごと消えた)。以下は当時の記録として残す。

## 新しい JTAG ゲストメモリ経路(この bitstream で有効)

`POST_MONITOR` オフ・`PC98_PROBE_EXTRA` オンのデバッグビルド。
`sdram_selftest_master` (u_selftest) を JTAG から駆動 — HOLD/HLDA で
**実行中のゲストのバスを借りて** RAM を read/write する(実証済み: 0xA5 往復 OK)。

```
write slot 0x84 : 40-bit scan, waddr byte = 0x84
                  data = {2'b0, go(29), we(28), wdata(27:20), addr(19:0)}
                  go=1 で 1アクセス発行、st_done で自己解放
read  slot 0x25 : {16'h0, done(15), busy/req(14), 6'h0, rdata(7:0)}
```

スクリプト: `scripts/jtag_memwrite.tcl`

```bash
MODE=selftest   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_memwrite.tcl  # 往復検証
MODE=peek ADDR=0x80000  ...   # 1バイト読み
MODE=inject HEX=testdisk/draw_test.hex SEG=0x8000 VEC=0x08   # 注入+IVTハイジャック
```

注意: `MODE=inject` は `VEC` (default 0x08=timer auto-fire) の IVT を
ハイジャックする。**もう一度走らせると今走っているコードを上書きする**ので、
draw_test が既に動いているなら先にリセットすること。

TVRAM/GVRAM(0xA0000+, 0xB0000+ 等)はこの経路では `ram_rw_complete` が上がらず
読めない → テキスト確認は probe `0x1b` (dbg cell、read で auto-step) を使う。

## draw_test が描くもの(画面の見え方の期待値)

実行されれば: 16本の水平カラーバンド(パレット 0-15, GVRAM B/R/G/E 4プレーン)
+ GRCG TDW のシアン箱 + テキストラベル + 点滅ブロックカーソル。
**まだ実行していない** — 画面は BASIC プロンプトのまま。

## このセッションのまとめ

- ゴール: SDカード無しで `draw_test.hdm` のテストカードを出す(B案: JTAG→
  guest-mem 注入 + 割り込みベクタ起動)。
- 到達: ビットストリーム構築(GHA, native Windows)・フラッシュ・mem-write
  経路の実証・draw_test の注入とベクタ armed まで完了。**発火と画面確認は未実施**
  (ハード共有の可能性を受けて停止)。
- ボタン不動の原因は別件で判明済み: `postmon_shown=1` が `VKB_CTRL=1` を保持して
  `osd_active` が全ボタンをゲート → `postmon_shown=0` を firmware.vh に焼き込み済み。

再開するなら: IRQ0 をアンマスクして draw_test を発火させ、画面と probe 0x1b の
TVRAM ラベルで確認するだけ。

## 2026-09-28: no-media wedge = per-boot timing flake (not RAM regression)

検証シーケンス:
- `dc9a7e1` (RAM held-twin 修正版) 初回ブート wedge → RAM 修正を疑ったが
- `8848e35` (RAM 変更前) でも同一 wedge 再現 → **同じ bitstream で起動/停止が揺れる**
- `4a4aef0` / `8848e35` とも retry で "How many files" 到達 → 決定的バグではない

定量化: `scripts/boot_flake_test.sh` (JTAG reflash = 新規ブート試行) で
8848 を 5 連続 → **5/5 BOOT OK**。wedge 率は条件付きで低い。
注意: 成功時も `PIC1=0x053D0005` (ticks=5 停止) は BIOS 入力待ちの正常状態 —
wedge の判定は TVRAM テキスト有無で行うこと。

タイミング側の犯人特定 (run 525 sta_74a_intra.txt):
- 違反 -2.485ns、top100 全て同一 endpoint: `lpm_divide:Mod0` = `rtc_acc % 7`
- 起点 `pmp_wr_data_latch` (ブリッジ生データ) → Sakamoto/bcd2bin/加算 → 剰余器
- **ただしこのパスの出力は rtc_time (rtc_valid ロード 1 回のみ) — 実質休眠パス**
  → wedge の直接原因ではない可能性が高い。違反解消しても wedge が残るなら別経路
  (同期チェーンの metastability / SDRAM init 位相 / etc.) を疑う。

同時に発見した実バグ (`b662321` で修正済み):
- `{rtc_mo, rtc_acc % 7}` の `%7` が 32bit → concat 76bit → 48bit 代入で
  sec/min/hour が捨てられていた。`rtc_valid` ロードは常に壊れていた
  (weekday 機能追加以来)。`{1'b0, rtc_mo, rtc_wday_q}` に修正。
- `tb_rtc_roll.sv` 等価ベンチ: 新旧 ~1000 tick + 全月/年末境界で一致。

実機確認済み (8848):
- N-88 BASIC `Ok` 到達、`PRINT TIME$` が tick で進行 (00:00:00→00:00:01)
  ※ JTAG ブートでは host が RTC を送らないため 00:00:00 開始は正常
- `WIDTH 40` の TVRAM 偶数セル配置は正常 (描画側の stride 修正は ef77488+)
