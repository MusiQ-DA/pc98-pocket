# PC-98 機械層仕様(設計ドキュメント v0.1)

ベース: desaster/openfpga-PCXT(chassis — 実機でDOSブート実績あり)
リファレンス: np2(Neko Project 2 kai)の挙動。コード移植はしない。

## 方針

- PC/AT機械層(KFPC-XTチップセット)をPC-98機械層に置換する
- CPU(MCL86)・SDRAM・ビデオパイプライン・入力・bridgeはPCXTの実績を流用
- I/Oマップは np2 の `iocore_attach*` 呼び出しから機械的に抽出して確定する

## PC-98 メモリマップ(PC-9801VX級)

| 範囲 | サイズ | 内容 | 実装 |
|---|---|---|---|
| 0x00000-0x9FFFF | 640KB | コンベンショナルRAM | SDRAM |
| 0xA0000-0xA3FFF | 16KB×? | TVRAM(char/attr交互) | BRAM(デュアルポート) |
| 0xA4000-0xA4FFF | 4KB | テキストページ2等 | BRAM |
| 0xA8000-0xBFFFF | 96KB | G-RAM(グラフィック4プレーン) | SDRAM |
| 0xC0000-0xDFFFF | 128KB | VRAMウィンドウ/EGC窓 | バンク窓 |
| 0xE8000-0xFFFFF | 96KB | BIOS+ITF ROM(bios.rom) | BRAM/SDRAM |
| 0xF00000- | 拡張 | 9821 VRAM direct 等 | 後期フェーズ |

## I/Oマップ(主要デバイスと np2 対応)

| デバイス | np2リファレンス | 備考 |
|---|---|---|
| システムポート | io/sysport.c | リセット/電源/NVRAM制御 |
| 割り込み(8259互換) | io/pic.c | 6体制割り込み |
| PIT(8253/8254) | io/pit.c | BEEP音源(ch1)/タイマ |
| CRTC/テキスト属性 | io/crtc.c | 80x25, 属性ビット |
| GDC(uPD7220互換) | io/gdc_sub.c + gdc/ | グラフィック/テキスト同期 |
| EGC | io/egc.c | グラフィックチャージャ(後期) |
| CG ROM窓 | io/cgrom.c? + font | font.rom(ユーザーダンプ) |
| FDC(uPD765系) | io/fdc.c | 1.2MB/1.44MB。1024B/sect必須 |
| DMA(uPD71071) | io/dmac.c | FDC/ サウンド転送 |
| RS-232C(8251系) | io/serial.c | マウス接続想定 |
| サウンド(OPNA/26K/86) | sound/ + cbus/pcm86io.c | FM 6ch + SSG + ADPCM + リズム |
| SASI/SCSI | (PCXTのSASI構造を参考) | HDDイメージ |

※正確なポート番号は実装時に np2 の `iocore_attach*` 呼び出しから抽出する
(抽出スクリプトを作成済み。低域 0x00-0xF0 は確認済み: sysport 0x31, pic 0x00,
pit 0x71, crtc 0x70, fdc 0xBE, dmac 0x01/0x21, serial 0x30/0x41)

## マイルストーン(新ベース)

| # | マイルストーン | 完了条件 |
|---|---|---|
| B0 | PCXTベースがローカル/CIでビルド成功 | rbf生成 |
| B1 | 実機でPCXTのDOSブート確認 | ベースライン確立 |
| P1 | PC-98メモリマップ(ROM/RAM)+BIOSフェッチ | 波形/ログで確認 |
| P2 | TVRAM+テキスト表示(Phase 3資産移植) | BIOSの文字が出る |
| P3 | GDCグラフィック16色 | 画面描画 |
| P4 | FDD → PC-98 DOS起動 | DOSプロンプト |
| P5 | BEEP → OPNA | 音が出る |
| P6 | EGC/拡張RAM/マウス | ゲームが動く |

## 開発モデル

- ローカルDockerビルド(raetro/quartus:pocket, Rosetta)で反復
- GitHub Actionsで回帰ビルド
- ハードウェアテストはユーザーがPocket実機で実施
