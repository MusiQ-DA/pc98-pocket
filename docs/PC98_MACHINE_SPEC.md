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
| 0xA0000-0xA1FFF | 8KB | **TVRAM 文字コード**(`A0000 + idx*2` が下位、`+1` が上位=漢字/フラグ) | BRAM(デュアルポート) |
| 0xA2000-0xA3FFF | 8KB | **TVRAM アトリビュート**(`A2000 + idx*2`、奇数番地は未使用) | BRAM |
| 0xA4000-0xA4FFF | 4KB | テキストページ2等 | BRAM |
| 0xA8000-0xBFFFF | 96KB | G-RAM(グラフィック4プレーン) | SDRAM |
| 0xC0000-0xDFFFF | 128KB | VRAMウィンドウ/EGC窓 | バンク窓 |
| 0xE8000-0xFFFFF | 96KB | BIOS+ITF ROM(bios.rom) | BRAM/SDRAM |
| 0xF00000- | 拡張 | 9821 VRAM direct 等 | 後期フェーズ |

> **TVRAM は char と attr が交互ではなく別領域**。np2 `vram/maketext.c` で確認:
> `mem[0xa0000 + edi*2]`(文字下位)、`mem[0xa0001 + edi*2]`(上位、`gdc.bitac` と AND される)、
> `mem[0xa2000 + edi*2]`(アトリビュート)。
> 旧 `src/fpga/core/tvram.sv`(ピボット前の資産)は「char at even, attr at odd」を
> 仮定しており**誤り**。流用する際は書き直すこと。
> 80×25 = 2000 セルなので実使用は各 4000 バイトだが、窓は各 8KB。
> BRAM 16KB = 4 M10K ブロック。

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

実測と NP2kai ソースの読み取りで確定した、**計画の前提に関わる事実**。

> ⚠️ この節は一度書き間違えている(初版の F3)。
> **手元の `~/Documents/lodemnc/np2rom/` のダンプはパッチ済みで、
> それを根拠に「np2 は実 BIOS を走らせない」と結論したのが誤りだった。**
> ユーザーが提示した2つの外部ソースで訂正できた。

### 使う ROM(結論)

| ファイル | 出所 | 用途 | 配置 |
|---|---|---|---|
| `itf.rom` (32,768) | [Abdess/retrobios](https://github.com/Abdess/retrobios/tree/main/bios/NEC/PC-98) | **ITF(電源投入時)** | `F8000-FFFFF` |
| `bios.rom` (98,304) | 同上 | システム BIOS | `E8000-FFFFF` |
| `font.rom` (288,768) | 同上 / 手元 | ANK + 漢字 | SDRAM 常駐(R2) |

**手元の `np2rom/BIOS.ROM` と `ITF.ROM` は使わない**(下記 F2/F5)。

### F1. BIOS.ROM は物理 `0x0E8000` に 96KB で載る

np2 `bios/bios.c`: `file_read(fh, mem + 0x0e8000, 0x18000)`。
`0x18000` = 98,304 = ファイルサイズと一致。

### F2. ⚠️ 手元の `ITF.ROM` は ITF ではない — BIOS.ROM 末尾32KB の複製

バイト比較で `BIOS.ROM[0x10000:0x18000]`(= `F8000-FFFFF`)と**完全一致**。
初期化ファームではない。

**retrobios の `itf.rom` は本物**(F4)。

### F3. リセットベクタの本来の姿(訂正済み)

実 PC-9821Ce2 の `BANK7`(system BIOS @F8000)と手元ダンプの比較:

```
BANK7            EA 00 00 80 FD      JMP FD80:0000
手元 BIOS.ROM    CD 19 00 80 FD      INT 19h（後続 00 80 FD が残存）
retrobios        EA 00 00 80 FD      JMP FD80:0000（無改変）
```

**後続3バイトが一致している** = 手元のものは先頭2バイトだけ潰されたパッチ品。
実 BIOS のエントリは `FD80:0000`(物理 `0xFD800`)に無傷で存在し、
手元ダンプでも `EB 02 EB 5D FA 33 C0 8E D8 E4 35`
(CLI / DS クリア / `IN AL,35h` = PC-98 システムポート)と読める。**8086 命令のみ。**

> **初版の誤り**: 「np2 はリセットベクタを上書きして自前 BIOS へ飛ばす =
> 実 BIOS を走らせない」と書いたが、np2 の
> `mem[0xffff0]=0xea; STOREINTELDWORD(mem+0xffff1, 0xfd800000)` は
> **本物のリセットベクタを復元しているだけ**だった。
> `FD80:0000` は実 BIOS 自身のエントリポイント。
> パッチ済みダンプだけを見て一般化したのが原因。

### F4. ★ retrobios の `itf.rom` は本物の ITF で、**8086 互換**

リセットベクタ `EA 00 00 00 F8` = `JMP F800:0000`(Ce2 BANK4 と同形式)。
`bios.rom` の末尾とは別物。エントリ(`F800:0000`)は **電源投入時の CPU セルフテスト**:

```
FA              CLI
B4 D5  9E       MOV AH,D5h / SAHF
79 FE 75 FE 7B FE 73 FE   JNS/JNZ/JNP/JNC $-2   ← 失敗したらその場で無限ループ
F8 3F 73 FE               CLC / AAS / JNC $-2
B0 01 B4 02 F6 E4 70 FE   MOV AL,1 / MOV AH,2 / MUL AH / JO $-2
33 C0 9E 78 FE 74 FE ...  XOR AX,AX / SAHF / フラグ再検査
B8 FF FF 8E D8 8C DB ...  セグメントレジスタ総当り
```

**Ce2 BANK4 との差は `FA` 直後の `8E E2`(`MOV FS,DX`、386以降)が無いことだけ。**
→ retrobios のものは 8086 互換の旧世代版で、**V30 ターゲットでそのまま走る。**
Ce2 版は 386 命令を含むので使えない(機種も 486SX 機で対象外)。

### F5. 手元ダンプと retrobios の差は 252 バイト

最初の差分は `0xB1F0`。np2 の `setbiosseed(mem + 0x0e8000, 0x10000, 0xb1f0)` が
**まさにその位置に BIOS チェックサムのシードを書く**。
= 手元のものはパッチ後にチェックサムを付け直したもの。

---

## ★ 起動方式の決定(2026-09-09)

**道 A(完全に忠実な起動)を採用。** F4 により ITF が手に入り、8086 互換と確認できた。

```
リセット FFFF:0000
  → ITF(F8000-FFFFF)  EA 00 00 00 F8 = JMP F800:0000
  → CPU セルフテスト → メモリサイジング → ハード初期化
  → ROM バンク切り替え
  → システム BIOS(E8000-FFFFF、FD80:0000 がエントリ)
  → INT 19h でブート
```

合成 BIOS も、ソフトコアによるワークエリア注入も**不要**。

### 実装に必要なもの

| # | 項目 | 状態 |
|---|---|---|
| 1 | BIOS を `E8000` に 96KB ロード | ✅ 実装済み(`MACHINE_PC98`) |
| 2 | ROM 書き込み保護 `E8000-FFFFF` | ✅ 実装済み |
| 3 | パッチ済みダンプのリセットベクタ復元 | ✅ 実装済み(無改変 ROM では no-op) |
| 4 | **ITF を `F8000` にロードし、リセット時はそちらを見せる** | ⬜ |
| 5 | **ROM バンク切り替え**(ITF → システム BIOS) | ⬜ ポート番号を np2 から特定する |
| 6 | フェッチの可視化(`post_monitor` を PC-98 へ) | ⬜ |

**次の一手は 5**。ITF がバンクを切り替えられないと BIOS に渡らないので、
これが P1 の実質的な山場。np2 の `memm_arch` / `sysport` 周辺から
ポート番号を特定する。
