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

---

## ★ ROM 資産についての確定事実(2026-09-09 調査)

`~/Documents/lodemnc/np2rom/` の実測と NP2kai ソースの読み取りで確定した、
**計画の前提に関わる事実**。

### F1. BIOS.ROM は物理 `0x0E8000` に 96KB で載る

np2 `bios/bios.c`:

```c
biosrom = (file_read(fh, mem + 0x0e8000, 0x18000) == 0x18000);
```

`0x18000` = 98,304 = ファイルサイズと一致。→ **`E8000-FFFFF`**。

### F2. ⚠️ `ITF.ROM` は ITF ではない — BIOS.ROM 末尾32KB の完全な複製

バイト比較の結果、`ITF.ROM`(32,768B)は
`BIOS.ROM[0x10000:0x18000]`(= `F8000-FFFFF`)と**1バイトの差もなく一致**。

→ **「ITF が実機どおり初期化してから BIOS に渡す」という起動経路は、
この吸い出しでは再現できない。** 初期化ファームのダンプは手元に存在しない。

> `docs/GOAL.md` §5 の「`ITF.ROM` 32,768 = 初期化ファーム」は誤り。
> 同 §5 R3 の「`sound.rom` = 128KB」の誤記と同種の間違いが2件目。

### F3. ★ np2 は実 BIOS の起動シーケンスを実行していない

`bios_initialize()` の末尾(`BIOS_SIMULATE` 有効時):

```c
CopyMemory(mem + BIOS_BASE, biosfd80, sizeof(biosfd80));   // BIOS_BASE = 0xFD800
...
mem[0xffff0] = 0xea;                       // JMP far
STOREINTELDWORD(mem + 0xffff1, 0xfd800000);  // -> FD80:0000
```

**リセットベクタを上書きして、自前の合成 BIOS(`biosfd80.res`)へ飛ばす。**
実 BIOS.ROM はデータと一部ハンドラとして参照されるだけで、
**ブートシーケンスは np2 自身の 8086 コード**。

さらに `bios_vectorset()` は IVT を
`mem + BIOS_BASE + BIOS_TABLE`(= 合成 BIOS 内のテーブル)から作る。
実 ROM 側のテーブルではない。

**含意**: 「np2 を挙動リファレンスにする」という方針は、
**BIOS レベルでは成立しない**。np2 は忠実な機械エミュレータではなく
BIOS シミュレータで、実 ROM をそのまま走らせる実機ポートとは道が分かれる。

### この分岐で取りうる道

| 道 | 内容 | 障害 |
|---|---|---|
| **A. 忠実起動** | BIOS.ROM を `E8000` に置き `FFFF:0000` から実行 | `FFFF0` は `CD 19`。IVT を用意する実 ITF が**手元に無い**(F2) |
| **B. np2 方式** | 自前のブートコードを用意し、そこへ飛ばす。実 ROM はデータ/ハンドラとして使う | **8086 のブート firmware を自作する必要がある**(np2 のコードは移植しない方針) |
| **C. ハード支援** | picorv32(既存)が起動前にゲストメモリへ IVT/ワークエリアを書き、ゲストは小さなスタブだけ実行 | B の変種。書く 8086 コードは最小で済む |

**現時点の推奨は C。** ext ポート経由でゲストメモリを書く仕組みは
BIOS ローダとして既に動いており(`core_top` の `bios_load_state`)、
`guest_poke` も firmware にある。B の「自作 BIOS」を丸ごと書くより、
初期化をソフトコア側に置くほうが小さく、デバッグも OSD に出せる。

**ただしこれは互換性の上限を決める判断なので、実装前にユーザー確認が要る。**

### P1 のうち、どの道でも必要な作業

1. **PC-98 メモリマップのデコード**(RAM `0-9FFFF` / TVRAM 窓 / G-RAM / ROM `E8000-FFFFF` 書き込み保護)
2. **BIOS.ROM を `0xE8000` に 96KB ロード**
   (現ローダは `{4'b1111, ioctl_addr[15:0]}` = `F0000` に 64KB のみ。要拡張)
3. **フェッチの可視化** — `post_monitor` を PC-98 向けに向け直す

→ この3つを先に進める。道の選択(A/B/C)はそのあとでよい。
