# PC-XT 実装の削除計画 (2026-09-22) — 実施済み

**状態: 完了 (2026-09-22)**。commit `bcf2e1c` がディレクトリ改名、`47623e5`
が Peripherals.sv の中身、`2b6ff7d` がファイル本体・qsf・config.tcl・
ファームウェア・scripts を削除した (合計 約 50,700 行減)。計画との差分:

- **8088 (`core/8088/`) も削除**: 計画表に無かったが `ifdef MACHINE_PC98` の
  else 側でしか実体化されておらず、XT 本体そのものなので同時に落とした。
- **KFPS2KB は残留**: Set-2 ストリームの pacing (`kb_ready`) を握っており、
  これが消えると pocket_keyboard のキューが進まない。XT キーコード出力側は
  `clear_keycode = 1` で捨てる。
- **ALM は空かない**: マクロ殺し済みのモジュールは既に合成から落ちていた。
  実測で回収できたのは 8255 の 53.4 + KFPS2KB 相当 + splash タイマ ≈ 80 ALM。
- **残件**: Peripherals/CHIPSET/core_top のポート signature に死んだポートが
  残っている (定数で tie-off 済み)。EMS は計画どおり対象外。


目的: このコアは PC-98 専用になった。XT 时代的な #ifdef 分岐・モジュール・
資産をすべて削り、`MACHINE_PC98` を唯一のビルドにする。

**前提条件**: もう一人のエージェントが Chipset/Peripherals/RAM/gvram_seq を
修正中 (01:33 現在も書き込み)。**その作業が commit されてから**、
`scripts/restructure.sh` (ディレクトリ改名) を先に実行し、その後この削除を
実行する (順序: 移動 → 削除。逆だと移動の sed が消した後のパスを探す)。

## 削除対象

### 1. モジュール群 (ディレクトリごと qsf からも外す)

| パス (fpga/ 移動後) | 備考 |
|---|---|
| `core/video/` の cga*, hgc*, vram.v, UM6845R.v | XT 映像。video.qip を書き換え (splash とscandoubler/converter は PC-98 も使うか要確認 — `swap_video_sel`/`R_HGC` 参照を先に切る) |
| `core/uart/` 全部 (16750 ベース) | PC-98 のシリアルは 8251。ENABLE_XT_UART=0 で死んでいる |
| `core/chipset/HDL/XT2IDE.sv` | PC-98 のディスクは SCSI (scsi_service.c) + FDC。IDE サービス (ide_service.c) も firmware から削除 |
| `core/chipset/HDL/rtc.v` (MC146818) | PC-98 は uPD4990 (pc98_upd4990.sv 実装済み) |
| `core/sound/jtopl/` (OPL2) | PC-98 の FM は jt12_opna。CMS (jt89?) と Tandy 関連も |
| `KF8255` (8255 PPI) | 使用箇所を確認 — PC-98 の sysport が 8255 を流用しているなら残す |

### 2. `#ifdef MACHINE_PC98` の else 側 (全部で約 50 箇所)

- `Peripherals.sv` 28 箇所、`core_top.sv` 15、`Chipset.sv` 2、`RAM.sv` 3 ほか
- else 側 (XT パス) を削除し、ifdef 自体を剥がす (常時 PC-98)
- `config.tcl`: SYSTEM_VARIANT_TANDY / ROM_VARIANT_TANDY / ENABLE_TANDY_* /
  ENABLE_CGA / ENABLE_HGC / ENABLE_OPL2 / ENABLE_CMS / ENABLE_XT_RTC /
  ENABLE_XT_UART の VERILOG_MACRO を削除
- ファームウェアの `HW_DEFINES` からも同名を削除 (Makefile は config.tcl から
  読むので自動追従、`#ifdef` 参照箇所を掃除)

### 3. ファームウェア

- `ide_service.c` (SCSI に一本化。udiv32 は gdc_service.c が独自コピー済み)
- `vkb_layout.c` の PC/XT 83 キー表 (`#else` 側)
- `vkb_ui.c` の `#ifndef MACHINE_PC98` 分岐 (vrows 2 表)
- `settings_ui.c` の PC/XT 用メニュー項目 (BIOS Writable 等、§9.5 参照)

### 4. sim / scripts / docs

- `scripts/deploy.sh` (PC/XT コア用) — 削除して `deploy_pc98.sh` を `deploy.sh` に改名
- `sim/` の XT 専用ベンチがあれば削除 (tb_ce_rates は PC-98 の CE 生成の検証
  なので残す。stub_vhdl.sv は uart/VHDL stub — uart 削除後は不要かも)
- `tb_bios_map` / `tb_bios_memtest` は PC-98 の BIOS 検証なので残す

### 5. 縮小効果 (目安)

- ソース ~40 ファイル、ROM 語で 1-2KB、ALM は既にマクロで 0 化済みなので
  主に可読性とコンパイル時間

## 実行順序

1. (他エージェントの commit 待ち)
2. `scripts/restructure.sh` — パス変更 + 全参照 sed
3. 上記 1-4 を機械的に削除 (`git rm` + ifdef 剥がし)
4. `make -C firmware` + `tb_pc98_gdc` `tb_pc98_text` `tb_pc98_kbd_ps2` を
   ローカルで流す
5. push — CI の sim/quartus が全面の門番

## 危険箇所 — 確認済み (2026-09-22 調査)

- **8255 → 削除可** (再調査で判定変更): 実配線に見えたが PC-98 の全経路が
  専用スタブで横取りしている — 読みは 0x31/0x33/0x35/0x42 が `sysport_data`
  (mux が 8255 より優先、Peripherals:3876)、beep は `pc98_sysport_c[3]`
  (§1025)、0x37 の bit set/reset 書き込みも専用ラッチが処理 (§2090)。
  8255 が唯一応答するのは 0x37 の読み出しだが BIOS/ITF は一度も読まない。
  残る参照の tie-off: `ps2_reset_n`→1 (port_b_out[6] は PC-98 では
  書かれない定数、BAT 注入は不発で無害)、XT キーコード経路
  (port_a_in/keycode_ff) は PC-98 で消費者なし。qsf から KF8255 一族を外す
- **splash 画像 → 削除、ブートホールドだけ残す**: スプラッシュの正体は
  CGA VRAM への 4000 バイトコピー (Peripherals:1642-) を CGA ジェネレータで
  表示する PC/XT 機構。ENABLE_CGA=0 の PC-98 では**何も映らない**のに
  設定はデフォルト On — 毎ブート、見えない 5 秒 + splash 後リセット待ちを
  支払っている。削る: `splash_rom.v/splash.hex`、コピー/クリア機構、
  5 秒タイマ、splash_reset_hold、設定の Boot Splash 項。
  **残す**: `splash_pending` — dataslot ロード + 設定ステージングまで
  ゲストを hold するブート同期 (名前が共有なだけ)。`guest_ready` 等へ改名
- **CGA/HGC → 削除可**: `swap_video_sel=0` 固定、`R_HGC/R_CGA` は 0 固定
  (Peripherals:1833,2633)、core_top に HGC/CGA 信号の参照なし (grep 0 件)
- **EMS (ENABLE_EMS=1)**: RAM.sv のバンクロジックと TVRAM 配線が共有。
  削除は深部改修なので**今回の対象外**、config のフラグは残す
