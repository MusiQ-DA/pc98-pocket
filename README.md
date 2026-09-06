# PC-98 for Analogue Pocket (openFPGA)

NEC PC-9800シリーズ(PC-9801VX級: V30、640×400 16色、OPNA)を
Analogue Pocket の openFPGA で動かすプロジェクト。

**現状: Phase 1(ビルド基盤+テストパターン)** — 詳細は [docs/PORT_PLAN.md](docs/PORT_PLAN.md)

## 背景

MiSTerにはPC-9800系コアが存在しないため、PC-98固有のシステムRTL
(GDC、テキストVRAM、EGC、OPNA、FDC、PIT/PIC/8255系)を新規に設計する。
挙動のリファレンスには np2(Neko Project 2 kai)のソースを用いる。

## 構成

```
src/fpga/
  ap_core.qsf      Quartus プロジェクト(デバイス 5CEBA4F23C8)
  apf/             Analogue openFPGA テンプレートのラッパー
  core/
    core_top.sv    シャーシ(bridge/video/audio契約) — 現在はテストパターン
    core_bridge_cmd.v, i2s.v, core_constraints.sdc  インフラ
```

## ビルド(docker)

```bash
docker pull raetro/quartus:pocket   # 約6.4GB
bash scripts/build-docker.sh
# → src/fpga/output_files/ に bitstream.rbf
```

## 謝辞 / ライセンス

- インフラ部分は [danifunker/MacLC_pocket](https://github.com/danifunker/MacLC_pocket)
  (系譜: MacLC_MiSTer → Sorgelig/MacPlus → Plus Too、Analogue openFPGA テンプレート)を
  雛形として利用。MiSTerエコシステムの慣行に従い **GPL-3.0** で公開する予定です。
- PC-98の挙動リファレンスとして NP2kai の開発者の皆様の成果に大きく依存します。
