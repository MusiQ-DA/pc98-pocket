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
`scripts/deploy_pc98.sh` のROMパスを更新。

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

1. **実機デプロイ**: `bash scripts/deploy_pc98.sh`。
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
