# PC-98 for Analogue Pocket (openFPGA)

NEC PC-9800シリーズ(PC-9801VX級: V30、640×400 16色、OPNA)を
Analogue Pocket の openFPGA で動かすプロジェクト。

**ベース**: [desaster/openfpga-PCXT](https://github.com/desaster/openfpga-PCXT)
(実機でDOSブート実績のあるx86コア。MCL86 CPU、SDRAM、CGAビデオ、仮想キーボードを流用し、
機械層をPC-98に入れ替えていく)。元のMacLCテンプレート検討は git history 参照。

## 構成

```
pcxt-base/          PCXTコアの作業ツリー(ここをPC-98化していく)
  src/fpga/         Quartusプロジェクト
docs/               設計ドキュメント(PIVOT.md, PC98_MACHINE_SPEC.md, PORT_PLAN.md)
```

## ビルド

- **CI**: pushで自動ビルド → Actionsのartifactにrbf
- **ローカル**: `pcxt-base/scripts/build-docker.sh`(raetro/quartus:pocketイメージ、Rosetta)

## ロードマップ

docs/PC98_MACHINE_SPEC.md 参照(B0 ベースライン→P1 メモリマップ→P2 テキスト→P3 GDC→P4 FDD/DOS→P5 OPNA→P6 EGC)
