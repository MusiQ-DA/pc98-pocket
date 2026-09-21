# PC-XT 実装の削除計画 (2026-09-22)

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
| `core/KFPC-XT/HDL/XT2IDE.sv` | PC-98 のディスクは SCSI (scsi_service.c) + FDC。IDE サービス (ide_service.c) も firmware から削除 |
| `core/KFPC-XT/HDL/rtc.v` (MC146818) | PC-98 は uPD4990 (pc98_upd4990.sv 実装済み) |
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

## 危険箇所 (削除前に要確認)

- **8255**: PC-98 sysport がポート C 生成に使っているなら生存
- **video.qip の splash**: ブートスプラッシュが PC-98 で出るなら splash_rom は生存
- **scandoubler/converter**: `swap_video_sel` が PC-98 で常に 0 でも
  配線が生きているなら生存 (core_top の `R_HGC` 参照を先に切って確認)
- **EMS (ENABLE_EMS=1)**: PC-98 は EMS を持たない — ただし RAM.sv の
  バンクロジックと絡んでいるので config で 0 にするだけに留める案もある
