# LIVE HARDWARE STATE — read before touching the Pocket (2026-09-27 ~22:45 JST)

> **ハードを共有している可能性への注意書き。** このセッション(Devin)は実機に
> 2つの介入を残したまま止まっています。あなたが別エージェントなら、以下を読んで
> から作業してください。

## 何が刺さっているか

### 1. 新しいビットストリームをフラッシュ済み → マシンは cold boot した

- `gh run 36320551695` (branch `probe-extra-debug`, HEAD `62b1ddf`) の
  `quartus-win-bitstream` 成果物から `ap_core.sof` を取り、
  `scripts/jtag_flash.sh` で JTAG 書き込み。**MCU が再構成を検出して
  コアを再起動** — 前のセッション状態は全て揮発。
- 画面は現在 **N88-BASIC の cold-boot プロンプト `How many files(0-15)?`**。
- もしあなたが旧ビットストリーム上でテスト中だったなら、この再構成が
  それをリセットしています。謝ります。

### 2. ⚠ ARMED — IVT[8](タイマー割り込み) をハイジャックしたまま

- ゲスト RAM **`0x80000` に `testdisk/draw_test.bin` (428B, 位置独立) がロード済み**。
- **`IVT[8]` (phys `0x20`-`0x23`) = `0x8000:0x0000`** に書き換え済み(実測値
  `00 00 00 80` = CS:IP 0x8000:0000)。
- **現在は dormant**: PIC `IMR=0x3D` で **IRQ0 (timer) がマスク中**(probe 0x1f)。
  BASIC がこのプロンプトの時点ではタイマー割り込みをまだアンマスクしていない
  (§3.7: タイマーBIOSはBASICが `INT 1Ch AH=02` で自分で起動する)ため発火しない。
- **リスク**: あなた/ゲストが IRQ0 をアンマスク(`IN AL,02; AND 0FEh; OUT 02`)
  した瞬間、次のタイマーtick で `draw_test` が走り**画面を奪います**
  (`cli` → 16色バンド+GRCG箱+テキスト+カーソル描画 → 永久 `.hang`)。

#### 無害化するには(どれか1つ)

- **リセットが一番クリーン** — コア/ゲストをリセットすれば BIOS が IVT を
  再構築し、`0x80000` の注入コードも揮発。
- または IVT[8] を IRET スタブに向け直す(下記 mem-write で `0x20` 番地を書く)。

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
