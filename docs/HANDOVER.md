# 引き継ぎドキュメント — PC-98 Pocket / ROM BASIC ブート(改訂第3版)

最終更新: 2026-09-13
前回からの変更: **N88-BASIC が起動プロンプトまで到達。タイマーは障害ではなかった**

---

## §1 現在位置

**N88-BASIC(86) が `Ok` プロンプトまで完全起動する。**

```
00 |How many files(0-15)? 3                                                  |
01 |NEC N-88 BASIC(86) version 2.0                                           |
02 |Copyright (C) 1983 by NEC Corporation / Microsoft Corp.                  |
03 |641372 Bytes free                                                        |
04 |Ok                                                                       |
24 |    load " auto   go to  list   run.      save " key    print  edit . cont. |
```

再現:

```bash
SIM_THREADS=1 SIM_NAME=run1 bash scripts/sim_pc98_v30.sh -d '+keys=3\r'
```

(約45分。`+keys` の詳細は §1.1、ビルドフラグの実測は §1.4。)

### §1.0 対話も通る

`+keys=3\r\w\w\wPRINT_2\r` で `Ok` にコマンドを打った結果:

```
04 |Ok                     |
05 |print 2                |
06 | 2                     |
07 |Ok                     |
```

スキャンコード → 8251 → IRQ1 → PIC → INT 09 → BIOSバッファ →
BASICの行エディタ → トークナイザ → インタプリタ → コンソール出力 →
テキストVRAM → 画面、が端から端まで閉じている。
(キーはシフトなしなので小文字で入るが N88-BASIC はそれを受ける。)

### §1.1 キー入力(commit caf056a)

`+keys=3\r` で guest は4バイト全部読み取る(make 03 / break 83 / make 1C /
break 9C)。**マスタPICの IRQ1 が `1'b0` に結線されていた**ので、それまでは
8251 が何を返してもキーは届かなかった。エスケープ: `\r` = RETURN、
`\w` = guest 1秒待ち、`_` = スペース(シェルの単語分割対策)。

### §1.2 今回直した2つの実バグ

**(a) テキストVRAMのワード読み出しが `{b, b}` だった(commit 032547f)**

`pc98_tvram` の CPU ポートはバイト幅かつレジスタ出力。ベンチの `din_of()` は
ワード読み出しのためにレーンごとに2回評価されるが、`tvram_q` は引数ではなく
`cpu_address` で駆動されていたため、両レーンが同じバイトを返していた。

BASIC は `F4AF2  MOV AX,ES:[DI]` でセルをワード読みし、**AH(上位バイト)**で
漢字左半分かを判定する(`F4AFA CMP AH,0FFh` → `F3D8C CMP AH,00h`)。AH に文字
コードが入るせいで全ANK文字が漢字と誤判定され、印字直後に消されていた。
**実機は無関係**(出荷設計は8088、ワードを2回のバイトサイクルで読む。
`v30_core` はベンチにしか存在しない)。

**(b) `memsw[3]`(A3FEE)が存在しないオプションROMを主張していた(commit bbc5e01)**

A3FEE は不活性な設定値ではなく、**BASIC が読む「設置済みオプションROMの
マスク」**で、ビットの立った窓を無条件に far call する:

| bit | 窓 | bit | 窓 | bit | 窓 | bit | 窓 |
|---|---|---|---|---|---|---|---|
| 0 | C000 | 1 | C400 | 2 | C800 | 6 | CA00 |
| 3 | **CC00** | 7 | CE00 | 4 | D000 | 5 | D400 |

```
E824D  MOV BX,0EEh      ; A3F0:00EE = A3FEE
E8250  CALL 0A1D1h      ; AL = そのバイト
E8253  MOV [1596h],AL   ; マスク
E8288  TEST [1596h],AH
E828E  CALL FAR [1598h] ; ゲートが開いていれば呼ぶ
```

既定値 0x08 は np2 のテーブル(`pccore.c`)をそのまま引き継いだもの。実測:
0x08 は5番目のゲート(CC00、空の窓=ゼロ)で脱線、0x00 は8つ全部歩いて `Ok`。
**np2 の値を戻すなら、それが主張する ROM も用意すること。**

なお np2 のこのバイトはバッテリバックアップの保存値で、実機なら前回ブートの
スキャン結果が入る。こちらは継承できない: POST の一括VRAMクリア(`FED0B`、
実測でスイッチ領域全域に 0xE1)からスイッチを守る書き込み禁止が、正当な
書き込みも塞いでいるため。**保護は外さないこと** — 外すとクリアで
`memsw[3]` が 0xE1 になり8ゲート全開で悪化する。

### §1.3 誤診2件とその原因(同じ罠)

**(a) nuV30 の disp16 EA バグ — 存在しない。**
BASIC の文字出力末尾は

```
F4912  26 89 05        MOV ES:[DI],AX          ; 文字   → cell N
F4915  26 88 BD 00 20  MOV ES:[DI+2000h],BH    ; 属性   → A200 プレーンへ
```

`+2000h` はコードプレーンからアトリビュートプレーンまでの距離そのもの、
BH は 0x20(通常色)。ディスプレースメントが落ちれば症状と完全に一致する —
が、`sim/tb_v30_ea_disp16.sv` が実コアに ROM と同じバイト列を食わせて
**8形式すべて PASS**(mod=10 の全 r/m、8/16ビット、disp8 と no-disp の対照)。
アトリビュートプレーンにもブート中 28000回以上書かれている。**コアは無実。**

**(b) 「1/3 だけ潰される」 — 数え方の欠陥。** 文字自身がスペースの対を
除外していた。実際は 100%。

どちらも原因は同じ: **`eu_pc` はリタイア済み PC で数十命令遅れる。**
F4912 の文字ストアと、その約100命令後の 0x20 ストアが**両方 F4915 と表示
されていた**(67us = 約2900チップセットクロック、隣接命令にはあり得ない)。
commit 3e1471a で**書き込みサイクル開始時点の EU ライブ PC**(`u_cpu.u_eu.pc`)
と書き込みワードをログに追加。次のランは実際にバスに乗っている命令を名指す。

### §1.4 Verilator ビルドフラグ(実測)

同一マイルストーン(PASS1 = guest 30.6s)までの実時間で比較:

| | PASS1 到達 |
|---|---|
| `-Os`(verilator 既定) | 32.2分 |
| `-O2` | 28.7分 |

**約11%のみ。** ボトルネックは生成コードの最適化ではなく `--timing` の
イベントスケジューラ。以下は**使ってはいけない**:

- `--threads 4`: **18倍遅い。** 400% CPU がバリア待ちに溶ける。
  `--timing` のコルーチン＋単一クロックドメインでは分割対象がない
- `--x-assign fast` / `--x-initial fast`: **ブートを壊す。**
  ITF が F8448/F8476 の2命令ループで停止 — 未初期化値が 0 ではなく X と
  読まれることに依存している箇所がまだ残っている

## §2 根本原因(全て解決済み)

### 2.1 bios.romは「Franken-ROM」だった(最重要発見)

旧bios.romはE800部分(file 0-0x7FFF)とFD80部分(file 0x8000-0x17FFF)が
**別世代のROMから混在**していた:

| | 旧bios.rom(壊) | UX BIOS(正) |
|---|---|---|
| E800:0000(IVT[1E]飛び先) | `06 66 18 77 D5…`(cmp命令の続き) | **`EB 22` → jmp E800:0024 → BASIC INIT直行** |
| file 0x7EBD | 別ルーチンのコードバイト | 実トークンテーブル |

**UX BIOS ROM**: `/tmp/uxroms/bios.rom` (md5: 3af0ae01)
ソース: `/Volumes/Backup 4TB/Downloads/NEC PC-9801UX [ROM].zip`

### 2.2 0x66「バグ」はバグではなかった

サブエージェントDが証明:
- E800:0000の`06 66 18`は**命令境界ではなく**`3B 06 66 18`(cmp ax,[1866])
  の opcode がE800:FFFFにあり、ModR/M+disp16が0000-0002にまたがっている
- `77 D5`(JA)は正しくtaken(CF=0, ZF=0)→ FFDAへ
- **nuV30コアは正常、修正不要**
- 0x66はV30の予約NOP(ModR/Mを消費する2バイトNOP)

### 2.3 SS=0xF202も全て説明済み

壊れたE800部分の偽ディスパッチ → int 1Eフレームを誤消費 →
`88 17`の2バイト目(0x17=POP SS)を命令として実行 → SS=フラグ値

## §3 残る課題: KF8253タイマー — **解決済み(2026-09-13)**

### 3.1 診断の訂正: mode-3は壊れていなかった

「mode 3出力が~5エッジで停止」の正体は **mode 0 の正常動作**:
- ITF(F854E)はカウンタ0に ctrl 0x30(**mode 0**)を書き込み、
  カウンタテスト(FD873相当)とINT 08テスト(F8A3C)に使う
- ROMセット全体で ctr0 を mode 3 にする書き込みは **FD80 POSTのFDE20の一箇所のみ**
  (ctrl 0x36 + LSB 0x00 + MSB 0x60 → 0x6000 = 2.4576MHzで100Hz、続けてIRQ0アンマスク)
- ゴールデンステートのストラップはPOSTをスキップするためFDE20が走らず、
  タイマーはITFが残したmode 0(1回のTCで1割込み、以後沈黙)のまま → BASICの
  初期化待ちループが永遠に回る
- なおログの時刻表示 `%t` は **ps単位**(timescale 1ns/1ps)。旧ログの
  「~2秒間隔」は実は 2.1s、「#9→#10の0.05s」は50ms(mode 0のTCそのもの)

検証: `sim/tb_kf8253_mode3.sv` — KF8253単体で0x8000/0x6000/奇数/再プログラム
の全ケースが正確にN/2カウント毎に永遠にトグルすることを直接測定。
**KF8253_Counter.svのmode-3ロジックは無修正。**

### 3.2 本当にあった3つのバグ(全て修正済み)

1. **KF8259エッジ検出がレベル追従だった**(`KF8259_Interrupt_Request.sv`)
   - `low_input_latch`がピンLOWでセットされた後、**HIGHの間ずっと武装解除されず**、
     IRRが毎クロック再アサート(mode 3の矩形波High半周期中は実質レベルトリガ)
   - 8259A本来の「立上がりエッジ1回でラッチ、次のエッジまで再武装しない」に修正
   - これがないと割込み確認直後に同一割込みが再燃し続ける
2. **PIT入力クロックが1.193MHz(PC/XT)だった**(`Peripherals.sv` / ベンチ)
   - PC-98は **2.4576MHz**(VM=5MHz機、np2のclk_baseと同じ)
   - 42.954545MHzは非整数倍(17.48)なので位相アキュームレータで正確に2.4576MHzを生成
3. **np2のIRR0クリア特性が未実装**(`KF8259.sv`に`external_irr_clear`ポート追加)
   - np2 io/pit.c: ch0への書き込み(カウント値、またはRL≠ラッチのコントロール
     ワード)でマスタPICのIRR bit0をクリア
   - 再プログラム前にラッチされた古い割込みが、新しいハンドラに届くのを防ぐ
     実機由来の挙動。Peripherals.svとベンチ両方に配線

### 3.3 ベンチ(tb_pc98_v30.sv)の変更

- IRQ0を **ハードウェアPIT出力(timer_out0)から直接** 駆動。
  固定レートのソフトウェアトグラー(pit_timer_irq, 16384ce毎)は削除
  — mode 3矩形波+エッジトリガPICで「周期ごとに1回の割込み」= np2の
  NEVENT_ITIMERと同一のケイデンス
- **PITシード**: ブート判断(FE1FD)の瞬間 — +goldenのRAM事前投入と同じ境界 —
  にFDE20の書き込み列(ctrl 0x36, LSB 0x00, MSB 0x60)を実際のバス経路で注入。
  ツーパスブートの2回目の判断でも再注入(ITFパスがmode 0に書き戻すため)。
  `+nopitseed`で無効化
- タイマークロックを2.4576MHzに(位相アキュームレータ、RTLと同一方式)

検証: `sim/tb_pit_boot_seq.sv` — クロック較正(2,457,432Hz実測)、
ITF列(mode 0ワンショット=エッジ2本)、FDE20列(mode 3連続、半周期5.000ms)、
IRR0クリア両経路。**全フェーズPASS。** `tb_pic_cascade`も変わらずPASS。

### 3.4 RTL(FPGA実機)への影響

実機のフルブートはITF→FD80 POST全体を実行するのでFDE20が走り、
シードは不要。実機に必要なのは上記3修正(クロック・エッジ検出・IRR0クリア)
のみ。`Peripherals.sv`のPITクロックとIRR0クリア配線はMACHINE_PC98側で対応済み。

### 3.5 訂正: FE1FD は UX BIOS では命令アドレスではない(2026-09-13 計測)

`+golden` のRAM事前投入と §3.3 のPITシードは **どちらも発火していない**。
両方のフックが `eu_pc == 20'hFE1FD` を待つが、UX BIOS のその番地はパディング:

```
FDE35  E9 E3 FE     JMP 0DD1Bh
...
FE1F3  E9 56 FF     JMP 0E14Ch      ← ルーチンの最後
FE1F6  00 00 ...    (FE1FF までゼロ)
FE200  FA           CLI             ← 次のルーチン(INT ハンドラ)
```

FE1FD は **FE1F6-FE1FF のゼロ埋めの中**。命令境界として retire することは
なく、`wait (eu_pc == 20'hFE1FD)` は永久に成立しない。計測: 素のブート
(`pitfix4`/`pitfix5`)のログに `PIT seeded` が **0 件**。

**FE1FD は旧 Franken-ROM 由来の番地**だった(§2.1)。UX BIOS を使う限り、
`+golden` もPITシードも無効 — フックし直すまで「シードした結果」を語っては
いけない。素のブートでは後述のとおりROM自身がタイマーを設定するので、
シード自体が不要な可能性が高い。

### 3.6 タイマーのレートはROMが [0x0501] bit 7 で選ぶ

ROMセット中でカウンタ0に mode 3 を書く唯一の場所は **FDE00**(`OUT 77h` は
ROM全体で FDE02 と FEF76 の2箇所のみ):

```
FDDF4  MOV [058Ah],CX        ; タイマーカウンタのソフト分周
FDDF8  MOV [001Ch],BX        ; IVT[7] = INT 08 ハンドラ
FDDFC  MOV [001Eh],ES
FDE00  MOV AL,36h            ; ctrl: counter 0, LSB+MSB, mode 3
FDE02  OUT 77h,AL
FDE04  TEST BYTE PTR [0501h],80h
FDE09  JNZ  FDE19
FDE0B  MOV AL,00h            ; ─ bit7=0: 5/10MHz クラス
FDE0D  OUT 71h,AL
FDE0F  MOV AL,60h
FDE15  OUT 71h,AL            ;   count 0x6000 = 24576 → 2.4576MHz で 100Hz
FDE17  JMP SHORT FDE25
FDE19  MOV AL,00h            ; ─ bit7=1: 8MHz クラス
FDE1B  OUT 71h,AL
FDE1D  MOV AL,4Eh
FDE23  OUT 71h,AL            ;   count 0x4E00 = 19968 → 1.9968MHz で 100Hz
FDE25  CLI / IN AL,02 / AND 0FEh / OUT 02 / STI   ; IRQ0 アンマスク
```

つまり **PIT入力クロックと `[0x0501]` bit 7 は必ず一致させなければならない**。
一致しなければ 100Hz のはずの割込みが 123Hz(または 81Hz)になる。

現状は整合している: ベンチのRAMは t=0 で全ゼロ、POST は 0x501 bit 7 を
立てないので ROM は 0x6000 を書き、RTL/ベンチの 2.4576MHz と合う。
**将来 0x501 を 8MHz クラスで事前投入するなら、PITクロックを 1.9968MHz に
変えること**(`Peripherals.sv` の `PIT_CLK_HZ_TOGGLE`)。

§3.3 の「FDE20 の ctrl 0x36 + 0x6000」という記述は番地が FDE00-FDE15、
分岐付き、が正確な姿。

### 3.6b 000KB の正体 — ITF は引き渡している(2026-09-14, フラットベンチで再現)

実機の POST パネルが `BANK 1` を返すので「ゲストは `OUT 043D, 12` を
一度も実行していない」と読んでいたが、**誤り**。`tb_pc98_boot --v30 +itf=1`
(フラットメモリ、SDRAM なし)が同じ症状を再現し、引き渡しは起きていた:

```
2.328s  EU f957c  wr 00000-1ffff n 131072   メモリテストは 128KB しか舐めない
2.332s  CS f800 -> 0000  (pc 008d6)         低位 RAM のスタブへジャンプ
2.332s  OUT 043D, 12  -> itf_bank 0         バンクを BIOS へ
        → フェッチ履歴が 00000 op 00 ×48    0x00000 に 48 回戻る = ゼロを実行して
                                            64KB を周回している
2.614s  OUT 043D, 10  -> itf_bank 1         ITF に戻る
2.614s  CS 0000 -> f800  (pc f8043)         最初から
```

ROM から実行中にその ROM のバンクは切れないので、ITF は低位 RAM にスタブを
置いて飛ぶ。**そのスタブが 0x008D6 に無い**(ゼロ)ため、CPU はゼロを実行して
彷徨い、やがて ITF に戻って全部やり直す。実機の「000KB で再起動」はこれ。

**`bios.rom` のチェックサムは正常**。ITF は F88D6 で `OUT 043D,12` のあと
F800:0000 から 0x4000 ワードを `add dl,al / add dh,ah` で合計し `or dx,dx` で
検証し、失敗すれば F890E で `OUT 043D,10` して戻る——という経路を持つが、
実イメージは E8000/F0000/F8000 の 3 ブロックとも DL=DH=00 で通る。ROM の
問題ではない。

**容疑者から外れたもの**: SDRAM、`v30_cpu_bridge`、実メモリ経路。
フラットメモリで再現するので、これらは無関係。

### 3.6c 撤回 — ITF と BIOS は対になっている(2026-09-14)

一度「ITF と BIOS が別世代で対になっていない」と結論し、検出器
(`scripts/check_rom_pair.py`)まで書いて `deploy.sh` の門に入れた。
**すべて誤りだったので撤回する。** 門は同じ日のうちに外した
(あのままなら正しい UX セットを拒否していた)。

**誤りの中身**: F88D6 のルーチンは ROM 上で実行されるものではなく、
**低位 RAM にコピーして走らせるもの**。F8000 から実行中のルーチンが
自分の足元のイメージを差し替えることはできないので、それが唯一の方法で
あり、だからこのルーチンは RAM 上で同じに動くオフセットに書かれている。
バンク切替後は RAM から実行しつつ `DS:SI` で新しく選ばれた BIOS を読む。
**BIOS イメージの F88DC が違うバイトなのは正常。**

`~/.pc98roms` の 3 本は所有者が渡した保存用 zip とバイト単位で同一の、
**1 台の PC-9801UX から採られた一組**。md5 のピン留めは正しく、
私の検出器が間違っていた。

**実際に分かっていること(未解明)**:

| | |
|---|---|
| バンク切替の瞬間の低位 RAM `008D0` | **32 バイトとも 00** — コピーされたはずのスタブが無い |
| その直前 48 件のジャンプ履歴 | **すべて `00000`** — 切替より前から CPU は 0x00000 を周回している |

つまり**脱線は引き渡しより上流**で、`OUT 043D,12` も `pc 008d6` も結果に
すぎない。次に見るべきは「いつ 0x00000 の周回が始まったか」で、
`OUT 043D` の瞬間ではなくもっと前。

`docs/FRANKEN_ROM_LESSON.md` は「ROM についての誤った説がいかに自信を
もって語られうるか」という主題の文書で、これはその 2 件目にあたる。
今回の語り手は私だった。

### 3.7 タイマーBIOSは POST ではなく BASIC が呼ぶ(計測済み)

ブート全体の **PIT 書き込みを全数記録した**(`PIT WR` ログ、commit ed61a8e)。
結果:

| 発行元 | 書き込み |
|---|---|
| ITF (F8091/F8552/F866B/F868F/F896E/F8A40…) | 全部 |
| FD80 BIOS POST | **ゼロ** |
| `ctrl <= 36`(カウンタ0を mode 3)| **0 回** |

POST は PIT に一切触らない。カウンタ0に mode 3 を書く FDE00 は
**POST のコードではなく INT 1Ch サービスの一機能**だった:

```
IVT[0x1C] = FD80:0500 = FDD00          ← POST が正しく設定している(計測)
FDD00  PUSH…; XOR SI,SI; MOV DS,SI
FDD0B  OR AH,AH    / JZ DD23   → AH=0: カレンダ読み出し(IN 33h / OUT 20h)
FDD0F  DEC AH      / JZ DD63   → AH=1: カレンダ書き込み
FDD13  DEC AH      / JZ DD5D   → AH=2: **タイマ設定** → JMP DDF4
FDD17  DEC AH      / JZ DD60   → AH=3: カウント再設定のみ → JMP DDF2 → DE04
FDD1B  POP…; IRET                それ以外: 何もせず IRET

FDDF4  MOV [058A],CX     ; ソフト分周カウント
       MOV [001C],BX     ; ユーザハンドラ ES:BX を IVT[7] へ
       MOV [001E],ES
FDE00  MOV AL,36h / OUT 77h    ; counter 0, mode 3   ← §3.6 の分岐へ続く
```

そして **BASIC 自身がこれを呼ぶ**。E800 ROM 内の INT 1Ch 呼び出し 4 箇所のうち
タイマ起動は2つ:

```
F44CB  B4 02        MOV AH,02h
F44CD  33 C9        XOR CX,CX
F44CF  8C CB        MOV BX,CS
F44D1  8E C3        MOV ES,BX
F44D3  BB B0 12     MOV BX,12B0h      ; ユーザタイマハンドラ CS:12B0
F44D6  CD 1C        INT 1Ch
(F45D1 以降も同じ形、CX は呼び出し側指定)
```

**つまりプロンプト待ちの時点で「カウンタ0が mode 0、IRQ0 がマスクされたまま」は
正常な状態**。BASIC がプロンプトに答えてもらってから自分でタイマを起動する。
§3.2 の3つの修正(エッジ検出・PITクロック・IRR0クリア)は実機で必要な正しい
修正だが、**BASIC 起動の障害ではなかった**。

## §4 セットアップ

### 4.1 ROMファイル

```bash
# UX BIOS(正しいROM)
/tmp/uxroms/bios.rom  (md5: 3af0ae01)

# シミュ用hexファイル
HEX=/var/folders/df/39xrvpn57gj_g103mfbqvy5c0000gp/T/v30sim
python3 -c "
rom = open('/tmp/uxroms/bios.rom','rb').read()
with open('$HEX/bios.hex','w') as f:
    for b in rom: f.write(f'{b:02x}\n')
"
```

### 4.2 ブート実行

```bash
docker run -d --name <name> \
  -v "$PWD":/work -v "$HEX":/hex -w /hex pc98-sim \
  bash -lc '<verilator build + /tmp/obj_v30b/v30boot>'
```
(~30分でBASIC初期化まで到達)

### 4.3 ハードウェアROM

デプロイ時に `/tmp/uxroms/bios.rom` を使用する。
`scripts/deploy.sh` のROMパスを更新。

## §5 コミット一覧(最終)

```
afc1e6d BREAKTHROUGH: UX BIOS boots into BASIC initialization
7f6487c sim: +golden=<file> work-area pre-seeder
c085cb3 sim: 0x66-prefix workaround (superseded — was a Franken-ROM artifact)
67d3e28 docs: final handover
a9cde63 sim: keyboard ACK delayed 80ms
d4dda77 sim: memory switch protected from POST clear
... (全履歴は git log 参照)
```

## §6 注意事項

- **FD80部分は互換**: UX BIOSのFD80部分は旧ROMとバイト同一(サブエージェントB
  が確認)。ポートモデルとの互換性は維持される
- **ITF**: UXのitf.romも使用(md5同一)。ITFのメモリカウントは000KBのまま
  進まないが、BIOSブートには影響しない
- **66→90パッチは不要**: UX BIOSには0x66が存在しない。ベンチの
  `if (bios[1] == 8'h66)` 条件付きパッチは自動的に無効化される
- **RTL移植済み**(サブエージェントC): キーボードACK遅延、メモリスイッチ
  プリシード+保護、DIP 0x31=0xE3
- **nuV30コアは未変更のまま**: 0x66問題はコアのバグではなかった

## §7 次のアクション

1. **実機デプロイ**: `bash scripts/deploy.sh`。
   **`memsw[3]` の修正(§1.2b)が入っていることを確認すること** —
   入っていないと実機でもバナー直後に CC00 へ飛んで落ちる。
   シミュレーション側でやるべきことは一通り終わっている。
2. **インターバルタイマは1ブート中で一度もアームされない**
   (`PIT WR ctrl <= 36` が0件)。ROM 内の INT 1Ch AH=02 は `F44CB`/`F45CB`
   の2箇所だけで、**どちらも IRET で終わるハンドラの中**(BASIC が
   `CS:12B0` に置いたタイマハンドラの自己再アーム)。ハンドラのオフセット
   `12B0`/`44B0` は ROM 内にポインタとして格納されていない(検索ヒットは
   全て `MOV AL,12h` のようなバイト一致)。
   BASIC は**タイマなしで `Ok` まで来て `print 2` も実行する**ので、
   インターバルタイマを使うのはそれを要求するプログラム(`ON TIMER`)
   だけの可能性が高い。§3.2 の3修正は単体テストでは PASS 済み
   (`tb_pit_boot_seq` 全フェーズ、`tb_kf8253_mode3`、`tb_pic_cascade`)
   だが、**ブート経路はそれを踏まない**。
   実機で踏ませるなら `ON TIMER` を打つ必要があり、そのためには
   `+keys` に SHIFT(スキャン 0x70)対応を足して `(` `)` `"` を打てる
   ようにすること。
3. `+golden` と PIT シードのフックは FE1FD で死んでいる(§3.5) — 撤去してよい。

---

## §8 実機ラウンド(2026-09-14 深夜)

§7-1 を実行した。結果: **真っ暗回帰 → キーボード8251が犯人 → ITF は
MEMORY SWITCH ERROR まで到達**(ポート0x31を誤って0x12にしたのが原因、
0xE3に戻す)。未解決3件を並行調査中。

### §8.1 デプロイの足元(失敗2件)

- `scripts/deploy.sh` は `hiroya.PCXTDEV` に書く。**PC-98 は
  `scripts/deploy.sh`** — ROM 3本(bios/itf/font)と firmware を
  `Assets/pc98/hiroya.PC9801/` に一式置く。
  **「間違えた方は1発で分かる」は誤り**(2026-09-14 に実証)。`deploy.sh` は
  "written and verified" と成功を報告して exit 0 し、起動される
  `hiroya.PC9801` は前回のビットストリームと **firmware.bin** のまま動く
  (firmware はカードから読むデータスロットなので、ビットストリームだけ
  新しくしても置き換わらない)。OSD フォント修正が「効いていない」と
  読めたが、実機に一度も届いていなかった。
  `deploy.sh` は `--core` 明示なしでは実行を拒否するようにした。
  効かないように見えたら、まず
  `/Volumes/ANALOGUE/Assets/pc98/hiroya.PC9801/firmware.bin` を
  そのコミットの `firmware/firmware.bin` とバイト比較すること。
- Pocket のカードは `/Volumes/ANALOGUE`。`/Volumes/Untitled`(exFAT)は
  別カード(h2testw の検査ファイル入り)。
- `--run N` は per_page=20 の縛りで古い run を引くと永久スピンしていた
  → per_page=100 に修正済み。

### §8.2 真っ暗回帰の切り分け(消去法の記録)

#193(最後に Quartus が通ったビルド)→#213 の間に20コミット、うち RTL は4本。

| 容疑者 | 判定 | 根拠 |
|---|---|---|
| port 0x31 (0x10→0xE3) | 無罪 | 0xE3 も 0x12 も真っ暗(キーボード有効時) |
| 8259 エッジ検出 disarm | 無罪 | `KF8259_EDGE_DISARM` で切っても変わらず |
| タイミング | 無罪 | #193 が -79.077ns で動作、#217 は -78.727ns。この-79ns は PC-98 ピクセル PLL の SDC 由来の長年の赤で今回無関係 |
| pc98_tvram (memsw) | 無罪 | ITF と同じ手順(0x3FE0バイトを0xFFで埋め→読み戻し→ゼロで再実行)のテストを追加して PASS |
| **キーボード 8251 モデル** | **犯人** | ポート 0x41/0x43 を新たに横取り(#193 では未応答)。`PC98_KBD_8251` マクロで切ると ITF が復活 |

実機での計測(OSD パネル): TVW 増加 + BANK 1 + FR 00000 + LIVE F84xx–F86xx
= ITF 内ループ。F84xx は GDC ステータス待ち(`IN AL,60h`)、**F8619 は
キーボード 0x43 ポーリング**(`KBD RD 0043 => 60` が末尾まで継続)。
MAX/RST は `#ifndef MACHINE_PC98` 内で PC-98 では描かれていなかった
→ RST を PC-98 でも表示(commit 54a11f9)。

### §8.3 MEMORY SWITCH ERROR(原因判明・修正済み)

真っ暗の犯人がキーボードと分かる前、私が port 0x31 を 0xE3→0x12 に
動かした。**bit 4 セットは「ROM よ、メモリスイッチを初期化せよ」**の意味で、
pc98_tvram のスイッチ8バイトは書き込み保護されているため ITF の初期化書き込みが
全部落ち、読み戻し不一致 → このエラー。bit 4 クリア(0xE3)が本来の意図
(スイッチはハードがリセット時に持つもの)。run#219 で戻した。

### §8.4 画面のゴミ2件(原因判明・修正済み)

- **左上の2バイト豆腐** = `PC98_OSD_MARK`(16×16 白四角、OSD 原点確認用
  デバッグマーカー)。コメントアウトで対処。オーバーレイ全空白/全黒時の
  最初の計測器なので残してある。
- **行頭1文字欠け(EMORY/ANJI)** = `pc98_text_render` の fetch pointer
  wrap が col 79(80文字)だったが、走査線は 848/8 = **106文字**。
  26文字分早く wrap して cell 0 がブランキングに流出していた。
  「次の走査線のセル0」を指すよう修正 + `tb_pc98_firstcell` 追加
  (エージェントB、commit 7af55cf)。

### §8.5 フォント経路2件(原因判明・修正済み — エージェントC)

`KANJI CG ROM ERROR`(正確には **CG RAM** ERROR)と CI の赤い
`glyphs come back out of SDRAM intact` は別物だった:

1. **FONT_BASE が 0x200000(EMS ウィンドウの底)** — ローダは font.rom を
   0x400000 に置く。今までのグリフ取得は全て空ページから読んでいた。
2. **OUT A5 のたびに再フェッチが走り CG ウィンドウのデータを上書き** —
   ITF の「書く→OUT A5→読み戻す」試験が 128/128 失敗していた直接原因。
   修正後 0/128。
3. CI の赤はベンチ側: `pc98_glyph_rowbuf` の ANK ポート未接続を Verilator が
   0 に縛っていた(commit 871e95f)。

### §8.6 OSD の実用性修正

- **OSD トグル**: 設定メニュー(SELECT ボタン)→ ボタン割り当て →
  `POST Overlay`。パネルがメニューに被さる問題(トグルを割り当てるための
  メニューがパネルで見えない循環)は、オーバーレイ表示中はパネルを描かない
  ことで解消(commit 4bcfd82)。
- **TVF/FRB が RD0 と重なっていた**(row 92 に3欄同居は幅不足)。
  パネル 162→182px に拡張して独立行に(commit 3d14a9c)。
- **BAD 0EC は誤報の可能性が高い**: 参照列は UX BIOS に更新済みだが、
  GOT 欄(覗き見た8バイト)が**全ゼロ** = 壊れたデータではなく何も読めていない。
  調停負け(ゲスト実行中)でもロード待ちでもない(どちらも確認済み)。
  `FFFF0 は byte-perfect、F800E0 は判読不能`という過去観測と併せ、
  **sdram_peek / self-test master のアドレス空間不一致**を疑って
  エージェントE が調査中。

### §8.7 並行サブエージェントの戦果(2026-09-14 02:00-04:00、6本)

| エージェント | 課題 | 結果 |
|---|---|---|
| A | ANK 2バイト化 | **ポート 0x68 は ROM が本当に書く**(BIOS FE272/FEB96/FEC6A で 0x0B/0x0A、ITF は CG 窓試験の前後)。`pc98_gdc_mode1.sv` 新規、rowbuf の bitac を実レジスタ化。**ただし実機「全文字2バイト幅」の直接原因は別件の疑い**: 実機 row0 の奇数バイトが VRAM テストの 0x55 のまま残っている(= ワード書きの奇数バイトが tvram に届かない?)。sim の V30 は再現しない。**次の実機ランで TVH を見る: 00 なら健全、55 なら 8088 ワード書き経路のバグ** |
| B | 行頭1文字欠け | fetch pointer wrap が col 79 だったが走査線は106文字。次走査線のセル0を指すよう修正 + tb_pc98_firstcell(§8.4) |
| C | フォント | FONT_BASE 0x200000(EMS の底)→0x400000、OUT A5 の再フェッチが CG 窓のデータを潰す(§8.5) |
| D | キーボード 8251 | **実8251モデル**(`pc98_kbd8251.sv`): SEND-BREAK 立ち下がりエッジ(0x43 への 3A→32)でだけ ARM。旧モデルは 0x73(beep)書き込みでも ACK を ARMしており、それが真っ暗の正体。ACK 遅延 350ms = ITF のポーリング窓(~82ms)の外 → ITF は no-keyboard パスを歩き、BIOS の INT 18h AH=3 リセット応答とキーストリームには生き残る。**IRQ1 を XT PS/2 → 8251 RxRDY に付け替え** |
| E | ROM 覗き見 | peek が itf_bank mux を通って itf.rom のゼロ領域(物理 0x1FD800)を読んでいた。`st_run` 中はメインバンクを読むよう修正 + self-test master の HLDA レース修正(8088 バスプロトコル違反、"11 11 11 11" の正体) |
| F | beep | 経路は存在したが両端が誤り: ゲートが XT 8255 のピン方向(ゲストは BSR ワードしか書かないため入力モード固定=永久消音)、トーンが ctr2(RS-232C 用)。**ctr1 × sysport ラッチ**に修正。実機仕様は bit3=1 がミュート(リセット値 0xF9) |
| G | Dock USB → PC-98 | `pc98_kbd_ps2.sv`: Set-2 → PC-98 変換(np2kai kbtrans 準拠、GRPH=右Ctrl 等)。core_top で tap(ストールなし) |
| H | VKB PC-98 配列 | PC-9801 配列93キー(F1-F10 左縦2列、STOP/KANA/GRPH/XFER/NFER/HELP/ROLL)。PC-98 固有キーは未使用 Set-2 コードに仮割り当て |
| (親) | 結線 | 8251 にキー注入ポート(stb+byte、1深 hold、break エッジでクリア、ACK より優先)、CHIPSET/PERIPHERALS/core_top を通して G/H の出力を接続。VKB 固有キーを G のテーブルに登録 |

**カットオーバーの全体像**: Dock USB / VKB / コントローラ → pocket_keyboard(Set-2 統合) → pc98_kbd_ps2(→PC-98 変換) → pc98_kbd8251(注入) → 0x41/0x43 → ゲスト。

run#219 の実機観測(§8.2 の後): MEMORY SWITCH ERROR 解消、MEMORY 000KB OK 表示。ただし **RST 0000 / TVW FFFF / FR 9Fxxx / BANK 1** — ゲストは生きてメモリテストを完走するが、キーボード ACK が無いため ITF の警告ビープ→全テスト再走ループ(IO 履歴 0037 = OUT 37h ビープ連発)に留まる。D のモデルがこれを解く。

---

## §9 2026-09-14 昼: run#221 の答え合わせと CPU の正体

### §9.1 run#221(全部入り第1弾)の実機結果

| 項目 | 結果 |
|---|---|
| ビープ | ✅ 鳴る |
| 行頭文字 | ✅ M 欠けず(MEMORY) |
| BAD | ✅ 000 |
| TVH | ✅ 00(ワード書き経路健全。ANK 2バイト化の「0x55 残り」説消滅) |
| KANJI CG RAM ERROR | ✅ 消失 |
| ITF | ❌ 000KB OK で再起動ループ |

### §9.2 ループの正体: **8088 が V30 命令を誤実行していた**

ITF の CPU リセット保存シーケンス F9476 は `68 97 14` = **PUSH imm16(186+/V30 命令)**。
8088(mcl86)は 0x68 を未定義 JS エイリアスとして実行し命令ストリームが脱線。
sim が通って実機だけ止まった理由は sim がずっと V30 ベンチだったこと。
`v30/README.md` にはこのために nuV30 を vendored した経緯が最初から書いてあった
(初測定は ITF の push imm16、と)。

### §9.3 CPU 差し替え: nuV30 + v30_cpu_bridge

- **`v30_cpu_bridge.sv`(新規)**: 16ビット max-mode V30 ↔ 8ビット 8288 世界。
  読み出しは CPU を CE 駐車(コアは ADDR/UBE/BS を固定したままフリーズ、
  ウェイトは純粋にカレンダー時間)、書き込みは 2段FIFO キュー(プログラム順序を
  保証、OUT 043D バンク切替も次フェッチ前に着地)。バイトエンジンは 8288 から
  見て 8088 そのもの(バイト毎の S2-S0、偶→奇の順、AEN 競合は自己修復)
- **tb_v30_bridge**: 実V30+実KF8288+実8259、INTA から IRET まで — PASS
- **tb_pc98_boot --v30 +itf=1(実機経路の完全リハーサル)**: F9476 実行 →
  640KB 掃引 → OUT F0 1回 → リジューム → FD80 POST → **N88-BASIC
  「How many files(0-15)?」到達**
- 8088 は XT ビルドで無傷。`v30/` ディレクトリは一切未変更。
  qsf に v30 ファイル + SEARCH_PATH、`rtl/ucore/` からシンボリックリンクで
  テーブル単一管理
- 実効速度はフラットバス想定の約 1/2.5(ワードが 2 バイトサイクルに分割される
  ため)。最適化候補: RAM の 16ビットワードポート / バイト間ギャップ短縮 / ターボ

### §9.4 OSD フォントのデータスロット化(著作権対応)

font.rom の ANK グリフを抽出してコミットしていた件の整理:

- `softcpu_subsystem.sv` の font_rom を $readmemh 焼き込みから **MMIO 書き込み
  可能**(リージョン 0x7)に。firmware の `osd_font.c` が起動時に font.rom 先頭
  2KB(8x8 ANK)をコピーし、独自グリフ(罫線・矢印・G_*、全て自作)を上書き。
  ¥ キーも CP437 0x9D → ANK 0x5C に修正
- リポジトリから `font_8x8.png/.vh`、`gen_8x8.py`、`gen_pc98.py` を削除。
  `sim/font_slice.hex` も合成グリフに置換(tb は往復比較のみで中身任意)
- **`git filter-repo` で png/vh を全履歴から除去し force push**。
  ビットストリーム・CI Artifact・リポジトリ履歴のすべてから NEC/IBM 由来
  グリフが消えた。ユーザー手順の増加ゼロ(font.rom は元から必須ファイル)
- ROM 予算の都合で sdramtest/postmon は `#ifdef`(出荷 23184/24576)

### §9.5 設定メニューの PC-98 化

PC-98 ビルドで BIOS Writable / OPL2 / C/MS / Composite を非表示
(enum は save blob のインデックス互換のため無変更)。CPU 速度の第4項目は
「Turbo (max)」。EMS 3項目(Lo-tech 2MB / Frame / A000 UMB)は将来のため温存。

## RTC (uPD4990) — 将来実装

Pocket の APF ブリッジは実時刻を持つ (core_bridge_cmd の rtc_date_bcd /
rtc_time_bcd / rtc_valid — core_top.sv では現在未接続)。必要になったら
これを uPD4990 モデルに食わせ、0x20/0x22 のコマンドと 0x33 の cdat を
本物のシリアルプロトコルで返す。現状は 0x33 = 0x08 (クロック線静止、
日付ゼロ) のスタブでブートを通している (2026-09-18, 9ac8deb)。

## §10 2026-09-21: N88-BASIC Ok 到達と VKB コード(同時押し)実装

### §10.1 実機 ROM ブート完成

run#342 の実機結果: `How many files (0-15)?` は **空 ENTER でdefault通り抜け**、
N88-BASIC `Ok` 到達。`PRINT 2` 等の入力・実行も正常(数値+ENTERで聞き直される
件は入力行がクリーンなのに残る謎、空 ENTER で回避可。カーソル表示も未達)。

### §10.2 BIOS キーボードハンドラの解析(実機 ROM 逆アセンブル)

`IN AL,0x41` は BIOS 0xFE65D–0xFE6C6 にのみ存在。判明した契約:

- 1バイト読む毎に `OUT 0x43, 0x16`(正常経路)/`0x14`(エラー回復: status 0x38)
- **全バイト(make/break問わず)を `XLAT(0xE3C)` マスクで 0x52A のキーマトリクスに
  XOR** — breakだけ送るとビットが立ってしまう(押下扱い)ので make/break 対が必須
- ≥0x70(SHIFT/CTRL/GRPH/KANA)はマトリクス更新のみで文字バッファに入らない。
  SHIFT は 0x70/0x7D、CTRL 0x74、GRPH 0x73
- 0x60(STOP)もバッファに入らずマトリクス参照専用

→ 修飾キーは「make を先に送り key make → key break → mod break」の順なら
確実に効く。これが VKB コード実装の根拠。

### §10.3 VKB トグル(X)の整理

VKB は同時押しできないが、BIOS の 0x52A マトリクスは make を覚えているので、
**X = 単純トグル**(押下で make 送出、再押下で break 送出、通常キーと完全に同一の
モデル)で十分。一時期入れた「アーム+コード(compose)」機構(chord_active /
is_modifier / compose_*、c011d8a)はユーザー指摘で撤去 — make はラッチ時に必ず
送出されているため「make なし break」は構造的に起きず、保護も不要。
残した修正: R1 反転・再オープンで latch 枠が落ちる既存バグの repaint_latched()。

実機検証: SHIFT 上で X → 枠が強調 → 文字キーで A → 大文字/記号になるか。
失敗する場合は「保持型 make が金属で届かない」ことを意味し、c011d8a の
chord 版(キー入力ごとに [mod make][key make]…[mod break] を組み直す)が
フォールバックとして git 履歴にある。

### §10.4 カーソルが出ない原因(確定・修正済み)

実機で「反転ブロックが一瞬も出ない」件。BIOS 逆アセンブルと np2kai の
maketext.c 突き合わせで pc98_gdc.sv の 2 バグを特定:

1. **CSRW のアドレスデコード**: RTL は uPD7220 マニュアル形式
   `{P3[1:0], P2, P1[4:0]}`(P1 のビット 7-5 を捨てる)だったが、
   BIOS (F49C9) は `mov ax,di / out 60h,al / mov al,ah / out 60h,al` と
   **EAD をプレーンなリトルエンディアン 16 ビット**で書く。np2kai も
   `LOADINTELWORD(para+GDC_CSRW)` で `curpos<0x1000` をセル番号として使用。
   旧デコードだと EAD がスクランブルされ、カーソルは見えない場所に飛ぶ
2. **点滅制御ビット**: RTL は P1 bit6 を見ていたが、np2 は **P2 bit5
   (0x20) = 点滅なし**。BIOS のフル CSRFORM テーブル書き込みの P2 は
   [0x53D](0x00=点滅 / 0x20=固定) — まさにこのビット

補足: BIOS は CSRFORM を「フル 3 バイト(テーブル駆動、FEA44)」と「1 バイト
ON/OFF([0x53B]|0x80、FEAA4)」で使い分け、CSRW は 2 バイトで EAD 下位のみ。
top=P1[4:0] / bottom=P3[7:3] / enable=P1[7] は np2 と一致(変更なし)。
tb_pc98_gdc の期待値を修正 + tb_pc98_text にカーソル描画の回帰試験を追加。

### §10.5 カーソル計器(run#346 でも出なかったため)

CSRW/blink 修正後も実機でカーソルが出ず、原因が GDC 受け側か描画側か
切り分け不能のため計器を追加:

- pc98_gdc: `csr_wr_count`(CSRW/CSRFORM コマンド到着数、飽和)
- Peripherals→core_top→softcpu MMIO **0x5000012C**:
  `{count, en, blink, top, bot, addr[11:0]}`
- パネル row 102 右端に `CS c=.. E=. A=... T=.. B=..` 表示

読み方(Ok プロンプトで):
- c=00 → BIOS が CSR 系を 1 回も送っていない(ポートデコードか初期化経路)
- E=0 → ON 書き込み([0x53B]|0x80)が届いていない
- E=1 T=0 B=0 → 3 バイトテーブル CSRFORM が未実行(ヘアライン化)
- 全部正常 → 描画/サンプラ側(peripherals の vsync ラッチか drawn_cell)

### §10.6 カーソル最終原因(T=F の計器読みで確定)

実機計器 `CS 40 1 090 F 1`: コマンド 40 回・E=1・アドレスは移動に追随 —
配信は全部生きている。だが **top=0F > bottom** でスライスが空。

原因: **cursor_top を P1[4:0] から取っていたが、np2kai (maketext.c:334) は
`para[GDC_CSRFORM+1] & 0x1f` = P2[4:0] が top**。P1[4:0] は TEXT_LR
(テキスト行の高さ、0x0F=16ライン) である (maketext.c:163)。BIOS 側も整合:
[0x53B]=0x0F(行高さ、ON 時 0x80 を OR)・[0x53D]=0x00/0x20(blink ビットのみ、
top=0)。実機の最終形は top=0(P2) / bottom≥15 → **フルブロック**になる。

つまりカーソル 3 バグの全容:
1. CSRW をマニュアル形式でデコード(プレーン LE が正)→ アドレススクランブル
2. blink を P1 bit6 と誤読(P2 bit5 の反転が正)
3. top を P1[4:0] と誤読(P2[4:0] が正)→ スライスが空になり絶対に描けない

### §10.7 カーソル「ちょっと違うところでちょこっと見える」(2026-09-21, c1a2b1a)

修正後も実機で点滅が「わずかに違う場所に少しだけ」見える、との報告。逆アセンブルで確定:

**BIOS はブート時 CSRFORM を 1 バイトしか送らない** ([0x53B]|0x80 = 0x8F:
enable + TEXT_LR=15)。3 バイトテーブル形式 (FEA44, CS=FD80 基準でテーブルは
FD800+0x1062 = linear FE862: {0F,7B},{13,9B},{07,3B},{09,4B}) は int18 AH=12/13
経由のみ。ゆえに **top/bottom/blink はチップのパワーオン値のまま**。

- np2kai gdc_reset のマスター既定値 = {P1=0F, P2=C0, P3=7B} → top=0, bottom=15,
  **点滅 (P2 bit5=0)** = 全画面ブロック。BIOS のフォームテーブル先頭 {0F,7B} と一致
- 当 RTL は para[] を全ゼロリセット → P3=0 → bottom=0 → **正しいセルの最上段
  1 ラインのスリバー**。これが「ちょこっと/違うところ」の正体
- run#348 の計器 B=1 は当時のビルドが bottom を P1[7:3] から読んでいた非表示
  (P1=0x8F→1)。1 バイト書き込みしか来ていないことの裏付け

修正: pc98_gdc に MASTER パラメータを追加し、リセット時に CSRFORM を
{0F,C0,7B}(マスター)/P1=1(スレーブ) にシード (c1a2b1a)。
tb_pc98_gdc にリセット形の回帰試験を追加。

EAD の検算も完了 (心配不要の確認):
- BIOS F49A3: EAD = (k·col + 160·row)/2、k は [0x474] bit1 で切り替わり
- bit1 は CRT 初期化 (F4BF2) が [0x42E]≥0x48 (80桁, [0:5C0] bit2=0 → 0x50) で
  **セット** → 80 桁ブートは常に k=2 → **EAD = 80·row + col (セル番号そのもの)**
- np2kai maketext の step-1 と一致。RTL の drawn_cell 比較は正しい

### §10.7 FDM が ROM BASIC に落ちる原因(確定・修正済み)

実機 `n94=FF / MA=00 / nD=FF / r2=00 / V13=FD80:22F7` の読み:
- BIOS は 0x94 を大量に書き、6 バイトのコマンド (SPECIFY+RECAL+SENSE_INT) まで出た
- しかし**モータタイマが一度も arm せず** (MA=00)、RECAL 完了割込みも出ず、
  MSR ポールが飽和 (nD=FF) → タイムアウト → ROM BASIC

原因: glue のモータ回路は **bit0 の立上り + XTMASK ゲート**で arm する設計だったが、
np2kai fdc_o94 (io/fdc.c:1104-1116) の実際は **bit3 (0x08) の立上りで ready
attention 割込み** (FDCRLT_AI、FDC_INT_DELAY=6×100ms 後、条件なし)。BIOS 自身の
0x94 値 (bios.rom 逆アセンブル) がまさに証拠: FF56C=0x08、FF638=0x18 (**bit0 は
一度も立たない**)、2DD 側 FF6BF の 09/0C、ハンドラ末尾の 0D/0C — 全部 bit3 搭載。
実機の LB=0x18 (最終 0x94 値) も一致。

修正: bit3 立上りで arm、~600ms 後に自スレーブ線をパルス (0x94→bit3/INT13h、
0xCC→bit2/INT12h)、XTMASK 条件は廃止。tb_pc98_fdc_glue のモータテストを新仕様に
書き換え PASS (タイムアウトも 250ms→3.2s に拡大)。

### §10.8 EGC 実装 (WIP → plane E バグ修正済み, 2026-09-22)

18b1b0d で EGC 一式 (レジスタ 0x4A0-0x4AF、raster op エンジン、fg/bg 色展開、
パターンレジスタ、ソースラッチ、アクセスページ 0xA6 のページ1バンキング) と
pc98_gvram_display (グラフィック表示フェッチの分離) が WIP で入り、
**tb_pc98_egc の blit plane E だけが赤** (11 が出る、88 が正) の状態だった。

**plane E の原因 (seq のストローブ残留)**: `egc_src_ld`/`egc_pat_ld` の
1 サイクルパルスのクリアが expand 分岐の中にしか無く、アクセス最終プランの
次サイクル (ゲストがストローブを下げて pass-through 分岐に入るサイクル) では
クリアが走らない。パルスが立ちっぱなしになり、**古いプラン番号のまま
mem_rdata を延々と再ラッチ**して src_q[3] を次のアクセスのデータで上書き。
修正: クリアを非リセット側の共通位置 (分岐の外) に移し、両分岐で毎サイクル
クリア。tb_pc98_egc 全ケース PASS。

CI に tb_pc98_egc を追加し、tb_pc98_gvram_seq のビルド行に pc98_egc.sv を明示。

残り (docs/SOFTCORE_RTL_SPLIT.md):
- sft/leng のシフトパイプライン (非アライン blit)。今はアライン済み
  = ソースラッチが最後のリードのバイトを保持する形のみ
- pc98_gvram_display 側: slave GDC の SAD/PITCH 未消費、パレットは固定 16 色、
  E プレーンは常に E0000 (アナログ前提)

### §10.8 リセット項の OSD 化 (帯ストリップ廃止)

ハードウェア帯 (pocket_video が画面下部に描く 16 ビットの縞) は読みにくい
ため廃止し、**POST パネル row 82 の `HLD` フィールド**に移した:
`SH GH BL IR RS LK` の 6 桁 (soft_guest_hold / guest_hold_sync2 /
bios_ever_loaded / interact_reset / reset / ~RESET)。点いている桁が
ゲストを止めている項。MMIO 0x50000134 (core_top の dbg_bits[7:0] を
softcpu で 2FF 同期)。帯の色バーも消え、背景は黒。

### §10.9 フロッピーの eject / 挿入状態 (2026-09-22, a21c43f の次)

実機からの問い「eject と挿入状態の確認はどうやる？」に対し、手段が無かったので実装。

- **挿入 (image を入れる)**: Pocket メニュー → Core Settings → データスロット
  「Floppy A/B」のロード（user-reloadable, parameters bit0）。APF の
  dataslot update → rebind トグル → main.c が fdd_mount。これは従来どおり
- **eject / 再挿入 / 状態確認**: **コア OSD** → Hardware → 「Floppy A / Floppy B」。
  - 表示は live 値: `Inserted 1232K`（sectors/2 KB）または `Ejected`
  - A（または左右）で eject ⇔ insert。eject は FMGMT_PRESENT=0 で
    ゲストに NOT READY を見せ、サイズは fdd_service が記憶するので
    **同じイメージを Pocket メニューに行かずに戻せる**
  - 保存 blob には乗らない（実行時状態）

実装: fdd_service.c に fdd_eject/fdd_insert/fdd_is_inserted/fdd_mounted_sectors、
settings_ui.c に IT_FDD 行（Hardware 先頭）。ROM +712B (28088 text / 28300 bin)。

### §10.10 Pocket メニューの整理 (2026-09-22, 4140b4e/このcommit)

- **固定アセットはメニューに出さない**: data.json のパラメータ bit0
  (user-reloadable = Core UI 表示) を BIOS/ITF/Font/Firmware/Settings から
  クリア。Core Settings に残るのは **Floppy A/B + Hard Disk**（選ぶための
  スロット）と interact の **Write Protect / Reset PC** のみ
- **OSD を開くのは SELECT 一択**: Pocket メニューの "Settings (OSD)" アクション
  (0x54) は削除した。APF に framework メニューを閉じる host/target コマンドは
  無く（0x00B0 は「メニューが開いている」をコアに教えるだけ）、選んでも
  「B を1回押す」対「SELECT ならメニューを一切開かない」の比較になっていた。
  RTL の 0x54 デコードと firmware の osd_open 経路は休眠のまま残置
- input.json の Select ラベル = "Select: Settings" がその唯一の入口
