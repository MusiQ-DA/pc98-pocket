# PC-98 for Analogue Pocket — ポート計画(凍結版 2026-09-06)

NEC PC-9800シリーズ(PC-9801VX級)を Analogue Pocket openFPGA で動かすプロジェクト。

## 参照実装

| リポジトリ | 用途 |
|---|---|
| [danifunker/MacLC_pocket](https://github.com/danifunker/MacLC_pocket) | Pocket openFPGA の「シャーシ」構造のテンプレート(bridge/data slots/video/audio/input/SDRAM)。AI協働開発の先例(CLAUDE.md) |
| [MiSTer-devel/X68000_MiSTer](https://github.com/MiSTer-devel/X68000_MiSTer) | 日本語PCのシステム統合パターン。FDC/FDC_xdf・sasiif・OPM(YM2151)実装・メモリ制御 |
| [MiSTer-devel/PC88_MiSTer](https://github.com/MiSTer-devel/PC88_MiSTer) | uPD765系FDCの別実装、日本語PC周辺IC |
| [AZO234/NP2kai](https://github.com/AZO234/NP2kai)(np2) | PC-98ハードウェア挙動の**リファレンス**(GDC/EGC/DMA/PIT/OPNAのレジスタ動作)。コード移植はしない |
| alfikpl/ao486 | 486コア(容量検証後に再評価。初手は不採用) |
| mtrberzi/ym2608 / nukeykt/YM2608-LLE | OPNA RTL試作 / サイクル精度リファレンス |

## ハードウェア制約(Pocket実力)

- デバイス: **Cyclone V 5CEBA4F23C8 — 18,480 ALM / 308 M10K**(DE10-Nanoの約44%/55%)
- MacLCの実測: MiSTer版 emu モジュールだけで 20,900 ALM = Pocketの113% → 大削減が必要だった
- **制約はFmaxではなくロジック容量**

## 主要決定(凍結)

1. **CPU: V30/8086互換16bit** — 候補 MCL86(MiSTer IBM 5150で実績)/Zet。
   - 80286はスキップ(公開コア不在+286必須のPC-98ソフトがほぼ無い)
   - 486(ao486)は初手リスク大: 容量検証が取れた後の拡張課題
   - 実機換算クロック切替(5/8/10MHz)を最終的に用意
2. **対象機種: PC-9801VX級**(V30@8/10MHz、640×400 16色、86サウンド相当)
3. **RAM**: 640KB + 拡張(外部SDRAM 64MBに配置、まず640KB+1〜3MB)
4. **ビデオ**: GDC(μPD7220互換)+テキストVRAM+4プレーングラフィック16色(4096色中)。
   実機24.83kHz/56Hz → Pocket出力は60Hz化。**VRAMバス設計にはEGCを最初から織り込む**
5. **EGC**: scope-in(実装は#8、バス設計は#4で)
6. **サウンド**: BEEP(PIT ch1+sysportゲート)→ OPNA(YM2608)。OPN(2203/26相当)は内蔵扱い
7. **ディスク**: FDD優先(**1024バイト/セクタの1.2MB対応が必須**)、HDDイメージ(HDI等)
8. **ROM類**: BIOS/font/sound ROM は **np2互換のユーザー供給ダンプ**(bios.rom=96KB, font.rom, sound.rom=128KB)
9. **入力**: ゲームパッド→キーマップ + Dock実キーボード/マウス + 仮想キーボード
10. TH04/05など486必須級タイトルは対象外(V30 スコープ)

## ロードマップ

| # | マイルストーン | 完了条件 |
|---|---|---|
| 1 | openFPGAスケルトン + docker Quartusビルド | **output_files/ に bitstream.rbf が生成される** |
| 2 | CPU最小システム(MCL86統合) | BIOS ROMフェッチが波形で確認できる |
| 3 | テキストVRAM表示 | 画面に文字が出る |
| 4 | GDC グラフィック16色(EGCバス設計含む) | グラフィック画面が出る |
| 5 | FDD読み → DOSブート | DOSプロンプトが起動する |
| 6 | BEEP(PIT ch1 + sysportゲート + オーディオ経路) | 音が鳴る |
| 7 | OPNA(YM2608) | FM音源でゲーム音が鳴る |
| 8 | EGC | EGC使用タイトルが正速で動く |
| 9 | マウス/拡張RAM/細部詰め | — |

## Phase 1 の現状

- [x] リポジトリ雛形(ap_core.qsf / core_top.sv テストパターン / apf ラッパー / JSON定義)
- [x] docker ビルドスクリプト(Quartus: raetro/quartus:pocket イメージ)
- [ ] Quartusコンパイル通過(RBF生成)← Phase 1の出口基準
- [ ] Pocket実機でテストパターン表示確認
