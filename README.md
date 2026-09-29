# PC-98 for Analogue Pocket (openFPGA)

NEC PC-9800シリーズ(PC-9801VX級: V30、640×400 16色、OPNA)を
Analogue Pocket の openFPGA で動かすプロジェクト。

**ベース**: [desaster/openfpga-PCXT](https://github.com/desaster/openfpga-PCXT)
(実機でDOSブート実績のあるx86コア。SDRAM、softcoreディスクサービス、CGAビデオ系、
仮想キーボードを流用し、機械層をPC-98に入れ替えた)。CPUは [wickerwaka/nuV30](https://github.com/wickerwaka/nuV30)
(実機V30のダイから抽出したマイクロコードで動く cycle-accurate コア)。
元のMacLCテンプレート検討は git history 参照。

## 構成

```
fpga/               Quartusプロジェクト・コアRTL
docs/               設計ドキュメント(PIVOT.md, PC98_MACHINE_SPEC.md, PORT_PLAN.md)
```

## ビルド

- **CI**: pushで`build`ワークフロー — sim/firmwareゲート + Quartus Standard 18.1(Windows runner)コンパイル → Actionsのartifactにsof/rbf
- **ローカル**: 廃止 — QuartusのローカルDockerビルド(wine/Rosetta)は不安定なため撤去。bitstreamはCI artifactの`.sof`/`.rbf`を使う(JTAGフラッシュは`scripts/jtag_flash.sh`にCIのsofを渡す)

## ロードマップ

docs/PC98_MACHINE_SPEC.md 参照(B0 ベースライン→P1 メモリマップ→P2 テキスト→P3 GDC→P4 FDD/DOS→P5 OPNA→P6 EGC)

## ライセンス

GPL-3.0 (`LICENSE`)。このプロジェクトは GPL-3.0 の openfpga-PCXT をベースにしており、
JT12(GPL-3.0)・nuV30(GPL-2.0)・kitune-san chipset cores(MIT)・floppy.v(BSD-2)・
PicoRV32(ISC)・OpenGateware audio(MIT/GPL-3.0-or-later)・Analogue APF を含みます。
コンポーネント毎の帰属とライセンスの一覧は `NOTICE.md` を参照。

NEC の BIOS/ITF/フォント ROM はこのリポジトリにもリリース zip にも含まれません。
Pocket 側では `Assets/pc98/hiroya.PC9801/` にユーザーが `bios.rom`/`itf.rom`/`font.rom`
を配置するデータスロット方式です。
