# PC-98 タイミング規約リファレンス — 一律ウェイトをやめて「契約」だけを再現するために

対象: z86(パイプライン化された 286 クラスコア)へ移行した PC-98 FPGA コア。
現状は CPU を次の 2 つの「一律ウェイト」で遅くしている。

| 現状の一律ウェイト | 場所 | 中身 |
|---|---|---|
| `IO_GAP = 64` clk | `fpga/core/z86/z86_wbif.sv` | すべての I/O サイクルの終わりから次の I/O まで最低 64 clk_chipset(42.954545 MHz で **約 1.49 µs**)。ITF の PIT チェックを通すために入れたもの(同ファイルのコメント) |
| 286 Ts/Tc バスペーシング | `fpga/core/cpu_bus_bridge.sv` | バイトエンジンが cpu_ce 列で T ステート・AEN ストレッチ・SDRAM ウェイトを数える。`pace_286`(全速度設定で 1)のとき Ts+Tc の 2 クロック相当に短縮、INTA は faithful のまま |

この文書では、実在の PC-98 ソフトウェアが**実際に頼っている**タイミング契約を洗い出し、
最後(§5)で「どのウェイトをデバイス単位・ポート単位の回復時間として実装すべきか」を µs 値つきでまとめる。

表記:
- `np21w <path>` は `~/repo/np21w/np21w-src-rev106/` 配下の np21w 0.86 rev106 ソース(このプロジェクトの挙動リファレンス)。
- clk 換算はすべて clk_chipset = **42.954545 MHz**(1 µs ≒ 43 clk。`fpga/core/chipset/HDL/Peripherals.sv` の `CHIPSET_HZ`)。
- **未確認** = 一次資料で裏付けが取れていないもの。数値を実装に使う前に確認すること。
- V30/286/386 の命令クロック数は概算(**未確認**)。V30 の正式値は NEC V20/V30 User's Manual
  (https://ia903205.us.archive.org/28/items/bitsavers_necV20V30U_11351331/V20_V30_Users_Manual_Oct86.pdf)を参照のこと。

---

## 0. 要約

1. ソフトが「時間」として明示的に使う仕組みは **PIT(8253)**、**ARTIC(5Ch–5Fh、307.2 kHz)**、**OUT 5Fh(約 0.6 µs の固定ウェイト)**、**VSYNC/HBLANK ステータス**の 4 つだけ。どれも CPU 速度に依存しない実時間の仕組みなので、CPU を一律に遅くする必要はない。
2. 「CPU が遅いから結果的に満たされていた」デバイス側の制約は、FPGA の同期回路で作り直したデバイス(PIC、8251、8237、RTC、8255、CG 窓)では**ほぼ消える**。残るのは、FPGA 側でも実時間で動いているもの、つまり **PIT のカウンタ**、**OPNA(jt12)のレジスタ反映**、**GDC の描画エンジン**、**FDC(floppy.v)**。
3. ITF ROM が実際に確かめているのは (a) PIT にカウント値を書いてから約 1 µs 後にカウンタが動いていること、(b) カウント 1Ah をロードしてから 32 回のポーリングループ内に IRQ0 が来ること、の 2 点。(b) は**ループ回数で時間を測っている**ので、デバイス単位のウェイトでは救えない(§4.3)。
4. 推奨(§5): `IO_GAP` は廃止し、代わりに次を入れる。PIT のイベント駆動ストール(≤1.25 µs)、OUT 5Fh = 0.6 µs、OPNA データ書込み後の busy ストール(≤24 µs)、GDC の EXECUTE をバックプレッシャー化。ITF の IRQ0 窓は「ITF がマップされている間だけの互換速度」で対処する。

---

## 1. ソフトウェアから見える遅延・計時の仕組み

### 1.1 I/O ポート 5Fh への書込み(「OUT 5Fh,AL」ウェイト)

| 項目 | 内容 | 出典 |
|---|---|---|
| 公式な位置づけ | 一定時間ウェイト用のポート。対象機種は **PC-H98 と PC-9821 シリーズ** | take52 "How to Wait at constant time" http://www2t.biglobe.ne.jp/~take52/tech/soft.htm |
| ウェイト時間 | リアルモードで **約 0.6 µs**。仮想 86 モードでは I/O トラップが入るので約 1.75–1.8 µs(9821Ap/Xa/Xt16 の実測) | 同上 |
| 9801(非 9821)での実測 | PC-9801NS/E(386-16 MHz)リアルモードで 0.92 µs、PC-9801VX(286-10 MHz)で 5.29 µs。「PC-9801シリーズでは機種ごとに実行時間が異なる」。単なる I/O バスサイクルのコストと読める | 同上 |
| ReactOS | `CPU_IO_o_ARTIC_DELAY 0x5F /* Constant delay (about 600 ns) */` | https://doxygen.reactos.org/d0/db5/sdk_2include_2reactos_2drivers_2pc98_2cpu_8h_source.html |
| Linux/98 | `__SLOW_DOWN_IO` を `outb %al,$0x5f` に置き換え、"Using ioport 0x5f to wait is recomended by vendor." | https://lkml.iu.edu/0304.0/1415.html |
| MAME | `artic_wait_w`: `spin_until_time(600 ns)`(コメント "0.6 μsec") | https://raw.githubusercontent.com/mamedev/mame/master/src/mame/nec/pc9801.cpp |
| np21w | `artic_o5f`: `CPU_REMCLOCK -= 20`。書いた値が 0x0B でも 0x20 でもなければさらに −20。**エミュレートしている CPU のクロック数**で引くので、実時間は倍率で変わる(既定倍率 20、49.152 MHz なら 0.41/0.81 µs)。0x0B/0x20 を特別扱いする理由は**未確認** | `np21w io/artic.c`、`np21w pccore.c`(`PCBASEMULTIPLE`) |

手元 ROM での使用状況(バイト列 `E6 5F` の出現数を数えたもの):
`bios.rom`(PC-9801UX 純正、286)は **0 回**で、`JMP $+2`(`EB 00`)は 293 回。
`bios_retrobios386.rom` は `E6 5F` が 55 回。ITF(RA 世代、1988)は `E6 5F` が 0 回、`EB 00` が 117 回。
つまり **5Fh 規約は 386/9821 世代のもの**で、それ以前の ROM は `JMP $+2` と LOOP に頼っている(ROM の機種判定は `docs/PC98_MACHINE_SPEC.md` の F4 節、`docs/PC98_ITF_TRACE.md` の冒頭)。

### 1.2 ARTIC(A Relative Time Indication Counter、5Ch–5Fh)

| 項目 | 内容 | 出典 |
|---|---|---|
| 構成 | 24 ビットのアップカウンタ。5Ch = bit15–0、5Eh = bit23–8(16 ビット IN)。8 ビット IN では 5Ch/5Dh/5Eh/5Fh | take52(上記)、ReactOS cpu.h、`np21w io/artic.c`(`artic_i5c/i5d/i5f`、`artic_r16`) |
| 周波数 | **307.2 kHz**(3255.2 ns/count)。CPU 速度に依存しない | take52「Time Stamper」、ReactOS `ARTIC_FREQUENCY 307200` |
| np21w の式 | `2 × CPUクロック / (multiple × 16)`。8 MHz 系は `×13`。1.9968 MHz 系も 2.4576 MHz 系も 307.2 kHz になる | `np21w io/artic.c`(`artic_getcnt`) |
| 搭載機種 | take52 は PC-H98/9821 としている。`docs/PC9801UX_DIFF.md` は UX クラスのデータブックにあると書いている。9801 系のどの機種から載っているかは**未確認** | — |
| MAME | `timestamp_r` が `total_cycles()` を返していて、307.2 kHz ではない(MAME 側が不正確) | MAME pc9801.cpp |
| FPGA の現状 | 307.2 kHz の位相アキュムレータで実装済み | `fpga/core/chipset/HDL/Peripherals.sv`(ARTIC 節) |

ARTIC を読むソフトは CPU 速度の影響を受けない。FreeDOS(98) のカーネルは HMA 確保中に [1] を頻繁に読む(MAME のコメント)。

### 1.3 PIT(8253 / µPD8253C-5 / µPD71054)

| 項目 | 内容 | 出典 |
|---|---|---|
| 入力クロック | **2.4576 MHz**(406.9 ns): システムクロック 5/10/12/20 MHz 系と 9821 系。**1.9968 MHz**(500.8 ns): 8/16 MHz 系 | take52「Timer Counter(8253C)」、`np21w pccore.h`(`PCBASECLOCK25 = 2457600`、`PCBASECLOCK20 = 1996800`)、`np21w pccore.c`(`pccore.baseclock`) |
| 用途 | #0 = タイマ割込み(IRQ0)、#1 = ビープ、#2 = RS-232C ボーレート | take52、`np21w io/pit.c` |
| ソフトの推奨 | 一定時間待ちには #1 か #2 を監視する(#0 は止まっていることがある) | take52 |
| どちらの系統かの判定 | ポート 42h bit5(ITF/BIOS が見る)、BDA 0:0501h bit7(1 = 8 MHz 系、つまり 1.9968 MHz) | `docs/PC98_ITF_TRACE.md`(F805B9、F808B6)、`np21w bios/bios.c`(`biosflag |= 0x80` if `CPUMODE_8MHZ`)、`np21w bios/bios19.c` |
| カウント値のロード | 8253: カウント値を書いた後、「CLK の立ち上がりと立ち下がり」が来るまでカウンタレジスタにロードされない。その立ち下がり前の読出しは無効値になりうる | Intel 8253/8253-5 データシート(OCR) https://mark-ogden.uk/files/intel/publications/231306-001%208253_8253-5%20Programmable%20Interval%20Timer-Nov86.pdf |
| 同(8254) | 初期値は次の CLK パルスでロードされ、そのパルスでは減算しない。mode 0 の OUT は N+1 パルス後に立つ | 82C54 データシート https://pdos.csail.mit.edu/6.828/2017/readings/hardware/82C54.pdf |
| np21w | カウント値は書込み時点から nevent の残り時間として即座に動き出す(ロード遅延はモデル化していない)。`cnt <= 8` は 65536 扱い | `np21w io/pit.c`(`setsystimerevent`、`getcount`、`pit_setcount`) |
| FPGA の現状 | 42.954545 MHz からの位相アキュムレートで 2.4576 MHz を作る。立ち下がりの平均周期は正確 | `Peripherals.sv`(8253 節) |

### 1.4 `JMP $+2`(`EB 00`)とダミー I/O

- `JMP $+2` は 8086/V30/286 ではプリフェッチキューを捨てて再フェッチするので、数 µs 程度の「I/O 間の間隔」になる。286 以前の NEC ROM は I/O 回復待ちをすべてこれで書いている。ITF の PIT/DMA/PIC テストは `OUT` と `IN` の間に `JMP $+2` を 1〜2 個挟んでいる(`docs/PC98_ITF_TRACE.md` §1.8、§1.14)。
- np21w の GDC ステータス読出しには VSYNC 待ちループの高速化(`SEARCH_SYNC`)があり、`IN AL,60h/A0h` と `TEST/JZ` の間の `EB 00`(`JMP $+2`)と `E6 5F`(`OUT 5Fh,AL`)を読み飛ばしてパターンを照合している。つまり実在ソフトの VSYNC 待ちループには、この 2 つのイディオムが実際に挟まっている(`np21w io/gdc.c` の `gdc_i60`、`gdc_ia0`)。
- z86 のようにフェッチバッファから分岐を数 clk で処理するコアでは、`JMP $+2` はほぼ時間を生まない(`z86_wbif.sv` のコメント)。**`JMP $+2` が作っていた間隔は「実在 CPU の副作用」で、契約ではない**。契約になるのは、その間隔を必要としていたデバイス側の要件だけ(§2)。

### 1.5 BIOS/ITF のソフトウェアループ遅延

手元 ROM に出てくる `LOOP $`(`E2 FE`)の例。CPU 速度に比例して短くなる遅延。

| ROM / アドレス | CX | 用途(前後の命令から推定) | FPGA での影響 |
|---|---|---|---|
| ITF F805DF–F805F6 | 0Ah ×3 | キーボード 8251 の初期化(`OUT 43h`: 02h, 40h, 5Eh)の各書込みの間 | 8251 は同期回路なので影響なし |
| ITF F805FA–F8060E | A0h、6Bh | 8251 コマンド 3Ah → 32h → 16h(キーボードへのリセット/ブレーク信号のパルス幅) | FPGA のキーボードが実時間のパルス幅を見ていなければ影響なし(**未確認**) |
| ITF F80614–F80625 | 3000h(ポーリング)、19h | キーボード応答待ちの RxRDY ポーリングと、データを読む前の待ち | 応答が窓に間に合わなければ「キーが押されていない」と判断されるだけ |
| ITF F8065B–F8065F | 0000h ×2 | 起動ビープ音の長さ(37h bit3 の ON/OFF の間) | 音が短くなるだけ |
| UX BIOS FD8C1 付近 | 0Ah | RS-232C 8251(ポート 32h)のリセットシーケンス | 影響なし |
| UX BIOS FE7C7–FE7D7 | 78h、60h | キーボード 8251 の 3Ah/32h/16h(ITF と同じ手順) | 同上 |
| UX BIOS FDD2E | 32h | µPD1990 カレンダーへのコマンド後、シリアル読出し前の待ち | FPGA の RTC は即応答するので影響なし |
| UX BIOS FF7D6/FF863 | 400h | FDC コマンド(46h/4Ah)送出後 | FDC 本体は RQM ハンドシェイク(§2.5) |
| UX BIOS FF162 / FF16A | 8 / `JMP $+2` ×4 | 汎用の短い遅延サブルーチン | — |

(上の UX BIOS は ROM オフセットに E8000h を足したアドレス。`scratch/dis8086.py` で逆アセンブル。)

### 1.6 CPU 速度・種別のソフトウェア判定

| 方法 | 内容 | 出典 |
|---|---|---|
| ポート 42h bit5 | システムクロック系統(DIP)。ITF は 20 MHz/16 MHz の表示と PIT の定数選択(03E6h/04CDh)に使う。**測定ではなくスイッチの読出し** | `docs/PC98_ITF_TRACE.md`(F805B9、F808B6) |
| 7FDDh bit2 | 80386 モードか V30 モードかのスイッチ。ITF の「Processor is …」表示 | `docs/PC98_ITF_TRACE.md`(F80897) |
| BDA 0:0501h | bit7 = 8 MHz 系(1.9968 MHz)、bit2–0 = メモリスイッチ由来。RS-232C BIOS などがボーレート定数の選択に使う | `np21w bios/bios.c`、`np21w bios/bios19.c` |
| ループ回数でのキャリブレーション | VSYNC 1 周期や PIT の一定時間に回るループ数を数えて遅延を較正するソフトがある、とされる。具体的なタイトルは**未確認** | 一般論として take52 が「固定値のループで wait を取るとマシンの高速化についていけない」と書いている |

### 1.7 I/O バスサイクルそのもののコスト(暗黙の契約)

- np21w は**すべての I/O アクセス**で `CPU_REMCLOCK -= iocore.busclock` を引き、`busclock = pccore.multiple` としている。つまり I/O 1 回 = **ベースクロック 1 周期 = 0.407 µs(2.4576 MHz 系)/ 0.501 µs(1.9968 MHz 系)**で、CPU 倍率に依存しない(`np21w io/iocore.c` の `iocore_bind`、`iocore_out8`、`iocore_inp8` ほか)。
- 実機でも I/O は C バス(8/10 MHz 系)で行われるので、CPU が速くなっても I/O 1 回のコストは下がらない。386-16 MHz 機の OUT 5Fh(未割当て相当)がリアルモードで 0.92 µs かかった実測がある(take52)。
- したがって「I/O 1 回あたり 0.4〜0.6 µs」は、高速な実機にも存在した**物理的な下限**と言える。現状の 1.49 µs(`IO_GAP`)はこれより 2.5〜3.5 倍長い。

---

## 2. デバイス側の回復時間と、ソフトがそれを満たしている方法

一覧(詳細は各小節):

| デバイス | ポート | データシート上の最小間隔 | ソフトの守り方 | np21w のモデル | FPGA での要否 |
|---|---|---|---|---|---|
| 8259A PIC | 00/02、08/0A | WR→WR 190 ns、RD→RD 160 ns、別種コマンド間 500 ns(8259A)/ 150 ns(8259A-2) | CPU が遅いこと + `JMP $+2` | モデル化なし | 不要(同期回路) |
| 8253 PIT | 71/73/75/77、3FD9–3FDF | RD/WR 間の回復 1 µs。カウントのロードは書込み後の CLK 立ち上がり→立ち下がり | `JMP $+2`。ITF はロード→減算を**読んで確かめる** | ロード遅延なし。I/O ごとに 0.41 µs | **必要**(§4.1、§5) |
| 8251 キーボード | 41/43 | 書込み間の回復 6 tCY(モード初期化)/ 8 tCY(非同期モード)。TxRDY=1 のときだけデータ書込み可 | `LOOP` 遅延、RxRDY のポーリング | 1920 B/s の転送イベント。ステータスは常に `|0x85` | 不要(同期回路)。PC-98 での 8251 の CLK は**未確認** |
| 8251 RS-232C | 30/32 | 同上 | 同上 | — | 不要 |
| µPD765 FDC | 90/92、C8/CA | RD/WR パルス幅 300 ns。RQM フラグの遅延 12 µs(8 MHz CLK)/ 24 µs(4 MHz CLK)。コマンドバイト後 RQM は 2〜50 µs 落ちる | **MSR の RQM/DIO をポーリング**(必須の手順) | RQM は即座に立つ | 書込みストローブで RQM が同期的に落ちることだけ確認(§2.5) |
| µPD7220 GDC | 60/62、A0/A2 | RD/WR 回復 **4 TCY**。FIFO 16 段、ステータスに FULL/EMPTY | 書く前に FIFO FULL(bit1)/EMPTY(bit2)をポーリングするのが基本。VSYNC/HBLANK は bit5/bit6 | FIFO 32 エントリ、時間モデルなし。VRAM の memwait | 回復時間は不要。**EXECUTE の取りこぼしは要対策**(§2.6) |
| YM2203/YM2608 | 188/18A(/18C/18E) | アドレス後 17 φM、データ後 83 φM(FM 21–9E)/ 47 φM(A0–B6)/ 576 φM(リズム $10)/ 83 φM(リズム 11–1D)、SSG/ADPCM は 0 | BUSY(bit7)のポーリング、または固定ループ | **BUSY は一度も立てない** | **必要**(jt12 は実時間で反映。§2.7) |
| 8237 DMA | 01–1F 奇数 | 8237A-5: 連続する R/W 間に最低 400 ns | `JMP $+2` | モデル化なし | 不要 |
| µPD1990/4990 RTC | 20(書)、33 bit0(読) | **未確認** | `LOOP 32h` 遅延 | 即応答 | 不要(即応答) |
| マウス 8255 | 7FD9–7FDF | **未確認** | ラッチ(HC)→ニブル読出し | タイミングなし(120 Hz の割込み) | 不要 |
| プリンタ 8255 | 40/42/44/46 | ストローブ幅などは**未確認** | BUSY(42h bit2)のポーリング | 1 バイトごとに BUSY 20 µs(0x11 のときだけ 100 µs) | 実プリンタがないので不要 |
| CG 窓 | A1/A3/A5/A9 | **未確認** | — | タイミングなし | 不要(バスの ready で吸収) |

### 2.1 8259A(PIC)

- Intel 8259A(Dec 1988)の AC 特性: `TRHRL`(RD→次の RD)160/100 ns、`TWHWL`(WR→次の WR)190/100 ns、`TCHCL`(別種コマンド間)500/150 ns(8259A/8259A-2)。注記には「実システムでは TCHCL は普通 500 ns より十分長い(8086 で 1 µs、8086-2 で 625 ns)」とある。つまり CPU が遅いことで満たされる前提の仕様。https://pdos.csail.mit.edu/6.828/2017/readings/hardware/8259A.pdf
- ITF の IMR リードバックテストは `OUT 02h` → `JMP $+2` → `IN 02h`(`docs/PC98_ITF_TRACE.md` F80D03)。
- FPGA の i8259 は 42.95 MHz の同期回路なので、回復時間は要らない。INTA の 2 サイクル列はブリッジ側で忠実に回している(`cpu_bus_bridge.sv` の「INTA pairs keep the faithful count」)。これは**維持すべき契約**。

### 2.2 8253(PIT)

- 8253/8253-5: 「Recovery Time between READ」「…between WRITE」ともに **1 µs**。8254(82C54)の command recovery `tRV` は 165 ns(出典は §1.3 と同じデータシート)。
- ソフトから見える本当の契約はロード遅延のほう(§1.3、§4.1)。FPGA の PIT は同期回路なので、1 µs の回復時間そのものは不要。

### 2.3 8251(キーボード、RS-232C)

- 8251A: `tRV`(Recovery Time Between WRITES)= 6 tCY。注 4 に「この回復時間はモード初期化だけに適用。データ書込みは TxRDY=1 のときだけ。非同期モードの書込み間回復は 8 tCY、同期モードは 16 tCY」。リセットパルス幅は最低 6 tCY。https://mark-ogden.uk/files/intel/publications/205222-002%208251A%20Programmable%20Communication%20Interface-Nov86.pdf
- PC-98 の BIOS と ITF は 8251 の各書込みの間に `LOOP` 遅延(CX=0Ah)を入れている(§1.5)。
- np21w: キーボードは `xferclock = realclock / 1920`(1920 バイト/秒。19200 bps 相当)で、ステータス読出しは `keybrd.status | 0x85` を返す(`np21w io/serial.c` の `keyboard_changeclock`、`keyboard_i43`)。
- FPGA の `pc98_kbd8251.sv` は np21w に合わせて同じ `0x85` を返す。回復時間は不要。

### 2.4 8237(DMA)

- 8237A-5: 「外部プロセッサが連続して行う読み書きは、アクティブな R/W パルスの間に最低 400 ns の回復時間を空けること。アクティブな R/W パルスの後に DMA 転送が続く場合も同じ」。https://mark-ogden.uk/files/intel/publications/231466-005%208237A%20High%20Performance%20Programmable%20DMA%20Controler%20(8237A-5)-Sep93.pdf
- ITF の DMA レジスタリードバックテストは `OUT` → `JMP $+2` → `OUT` → `JMP $+2` → `IN` → `IN`(`docs/PC98_ITF_TRACE.md` F80CD7)。FPGA 側は同期回路なので不要。

### 2.5 µPD765(FDC)

- µPD765 データシート(Dec 1978)の AC 特性: RD 幅 `TRR` 300 ns、WR 幅 `TWW` 300 ns、DRQ サイクル `TMCY` 13 µs。書込み後の一般的な回復時間の規定はない。https://bitsavers.org/components/nec/_dataSheets/uPD765_Data_Sheet_Dec78.pdf
- 8272A データシートの注記: 「8 MHz / 4 MHz クロックでは 12 µs / 24 µs の RQM フラグ遅延がある」。https://mark-ogden.uk/files/intel/publications/210606-002%208272A%20Single_Double%20density%20Floppy%20Disk%20Controller-Nov86.pdf(OCR)
- NEC AN-08: 「コマンドフェーズの各バイトを書く前に MSR を読み、RQM=1 かつ DIO=0 を確認すること。最初のバイトを書くと RQM は 0 になり、コマンドによって 50 µs から 2 µs のあいだ 0 のまま」。https://bitsavers.mirrorservice.org/components/nec/_appNotes/AN08_uPD765_preliminary_197902.pdf
- **ソフトは RQM をポーリングする**ので、CPU が速くなってもポーリング回数が増えるだけ。危険なのは、書込み直後に MSR を読んで**古い RQM=1** が見えるケース。FPGA の `floppy.v`(`pc98_fdc_glue.sv` 経由)が書込みストローブと同じサイクルで RQM を落とすかどうかは**未確認**。落とさない場合は「FDC データポートへの書込み後、RQM が確定するまで次の MSR 読出しを止める」というデバイス単位のストールを入れる。
- np21w は RQM を即座に再び立てる(`np21w io/fdc.c`)。PC-98 の FDC クロック(2HD/2DD で 8 MHz か 4 MHz か)は**未確認**。

### 2.6 µPD7220(GDC)

- 82720(µPD7220 のセカンドソース)の AC 特性: **`TRV` RD 回復時間 = 4 TCY、WR 回復時間 = 4 TCY**。TCY(クロック周期)は最小 250/200/180 ns(グレード別)。https://bitsavers.org/components/intel/_dataSheets/82720_Data_Sheet_Preliminary_Jun83.pdf
- PC-98 の GDC クロックは 2.5 MHz か 5 MHz で、モード F/F2(ポート 6Ah)の 82h/83h、84h/85h で切り替える(`np21w io/gdc.c`)。2.5 MHz が CLK ピンの周波数だとすると TCY = 400 ns で 4 TCY = **1.6 µs**、5 MHz なら 0.8 µs。この対応関係は**未確認**。
- ステータス(60h/A0h): bit0 = DATA READY、bit1 = FIFO FULL、bit2 = FIFO EMPTY、bit5 = VSYNC、bit6 = HBLANK(`np21w io/gdc.c` の `gdc_i60`、`gdc_ia0`)。FIFO が空・満杯の判定やコマンド完了待ちはポーリングで書くのが基本(82720 データシートの FIFO 節)。
- np21w: FIFO は 32 エントリ(`np21w io/gdc.h` `GDCCMD_MAX`)。CPU から VRAM へのアクセスに、表示期間と VSYNC 期間で違う memwait をかける(TRAM 1/1、VRAM 6/1、GRCG 8/1 CPU clk。`np21w pccore.c` の `np2cfg.wait` と `screenvsync`/`screendisp`)。
- **FPGA 特有の問題**: `pc98_gdc.sv` は、描画が保留中か実行中のあいだに来た EXECUTE 系コマンドを**捨てている**(「further EXECUTEs while pending are dropped (the FIFO-empty bit is already clear, so software that polls waits)」)。実機の GDC はコマンドを FIFO に溜めて順に処理するので、捨てることはない。CPU が遅ければ描画完了前に次のコマンドが届くことは少ないが、z86 では増える。時間ベースのウェイトではなく、**バックプレッシャー**(描画保留中は CPU のコマンドポート書込みを止める)で直すべき。

### 2.7 YM2203(OPN)/ YM2608(OPNA)

- YM2608 アプリケーションマニュアル(英訳)の「書込みモードの待ち時間」。数値の単位は**マスタークロック φM のサイクル数**:

| 区分 | レジスタ | アドレス書込み後 | データ書込み後 |
|---|---|---|---|
| FM | $21–$9E | 17 | **83** |
| FM | $A0–$B6 | 17 | **47** |
| SSG | $00–$0F | 0 | 0 |
| リズム | $10 | 17 | **576** |
| リズム | $11–$1D | 17 | 83 |
| ADPCM | $00–$10 | 0 | 0 |

  STATUS0 の D7 = BUSY:「レジスタにデータを取り込んでいる間 1。FM 音源部のレジスタにだけ有効。フラグを見ながらアドレスとデータを書くなら待ち時間は要らない」。
  https://csclub.uwaterloo.ca/~pbarfuss/YM2608J_Translated.PDF
- µs に換算すると、PC-98 の OPNA(φM = 7.9872 MHz。FPGA は 7.987005 MHz、`pc98_opna.sv`)では、アドレス後 2.13 µs、FM データ後 10.39 µs / 5.88 µs、リズム $10 で 72.1 µs。OPN(26K、φM = 3.9936 MHz)に同じサイクル数を当てはめると 4.26 / 20.8 / 11.8 µs になるが、YM2203 固有の表は**未確認**。
- 実装系の BUSY 幅: ymfm は書込みごとに `32 × prescale` φM(プリスケーラ 6 なら 192 φM。OPNA で 24 µs)(https://github.com/aaronsgiles/ymfm `src/ymfm_opn.cpp`)。jt12 は「32 synthesizer clock cycles」(`fpga/core/sound/jt12/hdl/jt12_mmr.v`)。YM2612/YM3438 の実測では 83/47 サイクルがよく合うという報告がある(https://gendev.spritesmind.net/forum/viewtopic.php?p=27104)。
- np21w: `opna_readStatus` はタイマフラグしか返さず、**BUSY を一度も立てない**(`np21w sound/opna.c`)。BUSY をポーリングするドライバはすぐ抜け、固定ウェイトのドライバも問題なく動く。例外として、WaveStar ドライバは I/O が速すぎるとエラーになるので、np21w は 188h の読出しごとに `realclock/800000`(**1.25 µs**)を引く回避策を入れている(`np21w cbus/boardws.c`)。
- **FPGA の現状**: jt12 はデータ書込みを `op_din/up_ch/up_op` に保持し、スロットが一巡してきた時点でレジスタに反映する。反映前に次のデータ書込みが来ると上書きされうる(`jt12_mmr.v`)。これは実チップの「待ち時間を守らないと書込みが化ける」と同じ性質。`pc98_opna.sv` はルータの処理中(数 clk)の書込みを捨て、その間 BUSY を立てて見せている。ポーリングしない固定ループのドライバを高速 CPU で動かすと書込みを失う可能性がある。→ §5 で対策。

### 2.8 RTC(µPD1990AC / µPD4990A)

- PC-98 は 20h への書込み(STB/CLK/DATA)と 33h bit0 の読出しで、シリアルに 48 ビットを読む(`fpga/core/pc98_upd4990.sv` のヘッダ、`np21w io/upd4990.c`)。
- UX BIOS はコマンド後に `LOOP 32h` で待ってから読む(§1.5)。データシート上の CLK/STB の最小幅は**未確認**。
- FPGA の実装は同期回路で即応答なので、ウェイトは不要。

### 2.9 マウス 8255、プリンタ 8255、CG 窓

- マウス: np21w は 120 Hz の割込みと移動量のスケーリングだけで、アクセスタイミングの制約はない(`np21w io/mouseif.c` の `mouseif_changeclock`)。
- プリンタ: np21w はデータを送るたびに BUSY を 20 µs(0x11 のときだけ 100 µs)立てる(`np21w io/printif.c`)。ソフトは BUSY をポーリングする。
- CG 窓(A1/A3/A5/A9): np21w にタイミングの制約はない(`np21w io/cgrom.c`)。実機のコードアクセス/ドットアクセスモードに伴うタイミング制約は**未確認**。
- 3 つとも FPGA ではウェイト不要。

---

## 3. CPU 速度に依存するソフトと、実機の対処

| 事実 | 出典 |
|---|---|
| 「ゲームなどごく少数のソフトが V30 固有の命令や**動作タイミング**に依存し、80286 以降の CPU では正常に動かない」。そこで VX 以降の機種は V30 と 80286 以降の両方を載せ、電源投入時にスイッチで CPU を選ぶようにした | ja.wikipedia「PC-9801シリーズ」 https://ja.wikipedia.org/wiki/PC-9801%E3%82%B7%E3%83%AA%E3%83%BC%E3%82%BA |
| VX01/21/41 は 80286 のクロックも 8 MHz / 10 MHz から選べる。DA/DS/DX 以降は V30 とディップスイッチがなくなり、代わりに VM/VF 相当の速度で動くモードがある(機種によって 10 MHz 相当か 8 MHz 相当) | 同上 |
| 機種ごとの CPU 構成: VX = 80286-10 + V30-8、UX = 80286-10 + V30-8、DX = 80286-12 + V30-8、RX = i286 + V30、RA = i386DX + V30 | MAME pc9801.cpp のコメント |
| ITF(RA 世代)は 7FDDh bit2 のスイッチで 386 と V30 を区別して表示する | `docs/PC98_ITF_TRACE.md` F80897 |
| サードパーティのアクセラレータには、I/O アクセス全体、またはグラフィック I/O・RS-232C/プリンタ I/O・ユーザー I/O に個別にウェイトを入れる設定がある。目的は「拡張ボードや周辺機器が正常に動作しない」「グラフィック画面が乱れる」「プロテクトキーが認識されない」場合の対処 | 98epjunk「486機以前のPC-98用CPUアクセラレータのスイッチ設定」 https://98epjunk.shakunage.net/sw/cpu/accel_sw.html |
| 固定ループでウェイトを取るとマシンが速くなったときに破綻する。推奨は 5Fh、8253、タイムスタンパ(ARTIC) | take52 |
| np21w は命令ごとのクロック数(286 の表 + V30 用パッチ)× 倍率で CPU 速度を再現し、ユーザーが倍率を選ぶ | `np21w i286c/i286c.c`、`np21w i286c/v30patch.c`、`np21w pccore.c`(`multiple`) |

整理:
- 実機での対処は (1) **V30 に切り替える / 低速モード**(機種ごとのスイッチ。ソフトからは選べない)、(2) **I/O バスが CPU より遅いこと**(§1.7)、(3) 386/9821 世代からの **5Fh/ARTIC 規約**、の 3 つ。
- 「V30 タイミング依存ソフト」は、実機でも高速 CPU では動かないことが前提になっていた。FPGA では、これを**ユーザーが選ぶ互換速度モード**として扱うのが筋。デバイス単位の回復時間とは別の軸。
- 具体的にどのタイトルが速度に依存するかは**未確認**。

---

## 4. ITF ROM の PIT チェック(何を測っているか)

対象は `~/.pc98roms/itf.rom`(RA 世代、"Initial Test Firmware (C) NEC 1988")。逆アセンブルは `docs/PC98_ITF_TRACE.md`。

### 4.1 8253 リードバックテスト(F80C87–F80CBD)— 「TIMER ERROR」

```
OUT 77h,AL        ; 10h/50h/90h: カウンタ n、LSB のみ、mode 0
JMP $+2 ; JMP $+2
MOV AX,BP
OUT DX,AL         ; カウンタ n の LSB := FFh(1 巡目)/ 00h(2 巡目)
JMP $+2 ; JMP $+2
MOV AL,BH
OUT 77h,AL        ; 00h/40h/80h: カウンタ n をラッチ
JMP $+2 ; JMP $+2
IN  AL,DX
CMP AH,AL
JNZ ok            ; 書いた値と「違えば」合格。同じなら TIMER ERROR → HLT
```

- 3 つのカウンタ(71h/73h/75h)それぞれで、FFh と 00h の 2 回行う。
- **測っているもの**: カウント値を書いてからラッチするまでに、8253 が (a) その値をロードし、(b) 少なくとも 1 回減算したこと。8253 は書込み後の CLK 立ち上がり→立ち下がりでロードし、ロード前の読出しは無効値になりうる(§1.3)。したがって必要な時間は、**書込みストローブからラッチストローブまでに CLK 立ち下がりが 2 回**。最悪で約 2.5 PIT クロック、つまり **1.02 µs(2.4576 MHz)/ 1.25 µs(1.9968 MHz)**。
- 実機の余裕(概算、**未確認**): V30-8 MHz では `JMP` 2 回 + `MOV` + `OUT imm` で約 40 clk ≈ 5 µs。386-20 MHz でも I/O サイクルを含めて 1.5 µs 以上。
- np21w はロード遅延をモデル化しておらず、書込みの瞬間からカウントが動く。加えて I/O 1 回ごとに 0.41 µs 進むので、間に `OUT` が 1 回あれば必ず値が変わる(`np21w io/pit.c`、`np21w io/iocore.c`)。
- z86 + `IO_GAP=64` は、このテストを「OUT の後に 1.49 µs 空ける」ことで通している。**必要なのは PIT へのアクセスの間だけ**。

### 4.2 PIT の初期化(F8059E–F805DE)

- 30h(カウンタ 0、LSB+MSB、mode 0)、カウント 0000h。42h bit5 を見てカウンタ 1(ビープ)に 03E6h か 04CDh を mode 3 で設定し、カウンタ 2 を B6h で設定する。各 `OUT` の間に `JMP $+2` を 2 個。時間の検査はない。

### 4.3 IRQ0 テスト(F80D38–F80D93)— 「TIMER INTERRUPT ERROR」

```
STI                ; IMR=FFh のまま 32 回ポーリング → 割込みが来たら NG
...
MOV AL,1Ah ; OUT 71h,AL ; XOR AX,AX ; JMP $+2 ; JMP $+2 ; OUT 71h,AL   ; カウンタ 0 := 001Ah(mode 0)
MOV CX,20h
MOV AL,0FEh ; OUT 02h,AL       ; IRQ0 のマスクを外す
L: TEST AH,0FFh ; JNZ ok ; LOOP L     ; 32 回のうちに IRQ0 ハンドラが AH=FFh にしなければ NG
```

- **測っているもの**: mode 0 でカウント 1Ah をロードすると、MSB 書込みから N+1 = **27 PIT クロック**後に OUT が立って IRQ0 になる。**11.0 µs(2.4576 MHz)/ 13.5 µs(1.9968 MHz)**。この時間が **32 回のポーリングループ**(+ `OUT 02h` など)の中に収まらなければならない。逆に言えば、**ループ 32 回が 11〜13.5 µs より短い CPU は落ちる**。
- 実機の余裕(概算、**未確認**): V30-8 MHz は TEST 4 + Jcc(不成立)4 + LOOP 13 ≈ 21 clk/回で、32 回 ≈ 84 µs。386-20 MHz は 2 + 3 + 11 ≈ 16〜18 clk/回で、32 回 ≈ 26〜29 µs。
- z86 at 42.95 MHz: 1 回が **15 clk 未満**だと I/O 分を足しても 11 µs に届かない可能性がある(`IO_GAP` は `OUT 71h` と `OUT 02h` の 2 回で +3 µs)。z86 の `TEST/JNZ/LOOP` のクロック数は**未計測**。**現行ビルドが余裕を持って通っているかは要確認**。
- これは**ループ回数で計時している**ので、デバイス単位のウェイトでは本質的に救えない。IRQ0 経路(PIT OUT → 8259 IRR → INTR → INTA)の遅延を足しても数百 ns にしかならない。

### 4.4 その他の ITF の計時

- キーボード 8251 の初期化と応答待ち、起動ビープ(§1.5)。いずれも合否には関わらない(応答が窓に間に合わなければ、押されたキーなしとして扱われるだけ)。
- CPU 種別とクロックの表示は、スイッチ(7FDDh、42h)を読むだけで測定はしない(§1.6)。

---

## 5. FPGA コアでの推奨

### 5.1 基本方針

1. **一律の `IO_GAP` と V30 T ステートペーシングは、デバイス契約を守る手段としては廃止する**。CPU コアは全速で動かす。
2. 待ちは「**どのデバイスの、どのアクセスの後の、どのアクセスを、何 µs / 何のイベントまで止めるか**」の表で表す。止めるのはそのデバイスへの次のアクセスだけにして、他の I/O やメモリアクセスは止めない(z86_wbif の `io_rec` を、ポートデコード付きのデバイス別カウンタに置き換えるイメージ)。
3. 時間ではなく**イベント**(カウンタのロード済み、busy の解除、描画完了)で止められるものは、イベントで止める。そのほうが短く、しかも正しい。
4. CPU 速度そのものに依存するソフト(§3、§4.3)は、デバイス契約とは別に「**互換速度モード**」(ユーザー選択、または ITF 実行中に限定)で扱う。

### 5.2 推奨する個別ウェイト

| # | 契約 | トリガ | 止める対象 | 解除条件 / 最大時間 | clk(42.95 MHz) | 根拠 |
|---|---|---|---|---|---|---|
| 1 | **PIT のロード** | カウンタ n のカウント値の書込み(71h/73h/75h、3FD9h/3FDBh/3FDDh の別名も) | PIT ポート(70h–77h の奇数、3FD9h–3FDFh)への次のアクセス | カウンタ n がロード済みで、1 回減算した(イベント)。時間で代用するなら **1.25 µs** | ≤ 54 | §1.3、§4.1。ITF の TIMER ERROR |
| 2 | **OUT 5Fh** | 5Fh への書込み | CPU(この I/O の完了を遅らせる) | **0.6 µs** 固定 | 26 | §1.1(MAME、ReactOS、take52) |
| 3 | **OPNA のデータ書込み** | 18Ah/18Eh への書込み(FM、リズムのレジスタ) | OPNA ポート 188h–18Eh への次の**書込み**。読出しは止めない(BUSY のポーリングが本物の値を見られるようにする) | jt12 の busy が 0、かつルータが空き(イベント)。上限の目安は FM 10.4 µs(データシート)〜24 µs(jt12 の 32 合成クロック)、リズム $10 は 72 µs | 447〜1031(リズムは 3097) | §2.7 |
| 4 | OPNA のアドレス書込み | 188h/18Ch への書込み | 次のデータ書込み | 17 φM = **2.13 µs**。jt12 はアドレスを即座にラッチするので**省略してよい** | 92 | §2.7 |
| 5 | **GDC の EXECUTE** | 描画保留中または実行中 | 62h/A2h(コマンド/パラメータ)への次の書込み | 描画エンジンが次を受け付けられるようになるまで(イベント。時間上限なし) | — | §2.6。捨てるのをやめる |
| 6 | FDC の RQM | 92h/CAh への書込みまたは読出し | 90h/C8h(MSR)の次の読出し | RQM が新しい状態になるまで(イベント)。floppy.v が同期的に落とすなら不要 | — | §2.5。**要確認** |
| 7 | (任意)I/O バスサイクルの下限 | すべての I/O | その I/O の完了 | **0.41 µs**(np21w と同じ。ベースクロック 1 周期) | 18 | §1.7。1〜6 で不足するソフトが見つかった場合の保険。現行の 64 clk の 1/3.5 |

`IO_GAP` の元の目的(ITF の PIT リードバック)は #1 で満たされる。#1 は PIT へのアクセス時しか発生せず、PIT を叩くのはタイマ設定のときくらいなので、性能への影響はほぼゼロ。

### 5.3 ウェイト不要と判断するもの

| デバイス | 理由 |
|---|---|
| 8259A(PIC) | 同期回路。INTA の 2 サイクル列はブリッジが維持する(これは別の契約として残す) |
| 8251(キーボード、RS-232C) | 同期回路。ステータスは np21w 互換の `|0x85`。リセットシーケンスの判定が時間に依存していないことだけ確認 |
| 8237 DMA | 同期回路(400 ns の回復時間は実チップの都合) |
| RTC、マウス 8255、プリンタ 8255、CG 窓 | 同期回路または即応答。必要な待ちはバスの ready で吸収されている |
| GDC の RD/WR 回復(4 TCY) | FPGA の GDC は同期回路。FIFO の FULL/EMPTY を正しく返すことのほうが重要 |
| VSYNC/HBLANK | 実時間で生成済み。CPU 速度に依存しない |
| ARTIC | 307.2 kHz で実装済み |

### 5.4 ITF の IRQ0 窓と、速度依存ソフト一般

- ITF の IRQ0 テスト(§4.3)は、**ループ 32 回 ≥ 約 11〜13.5 µs** という CPU 速度の下限を要求する。デバイスウェイトでは満たせない。選択肢は次のとおり。
  - (a) **ITF スコープの互換速度**: ポート 43Dh で ITF ROM がマップされている間(`docs/PC98_ITF_TRACE.md` §1.13 の `043Dh := 10h/12h`)だけ、z86 を V30/386 相当まで落とす。ITF は起動時に一度しか走らないので、全体の性能には影響しない。**推奨**。
  - (b) z86 の `TEST/JNZ/LOOP` の実クロック数を測り、32 回で十分な時間がかかることを確かめる(余裕が小さいので非推奨)。
  - (c) ITF に手を入れる(ROM を書き換えることになるので不可)。
- 一般ソフトの速度依存(§3)は、実機と同じく**ユーザーが選ぶ互換速度モード**(例: 286-8/10/12 MHz 相当)で対応する。clk_select / `pace_286` は 2026-10 の bus-faithful 改造でこの役割に作り直済み(CE 1× + Ts/Tc + キャッシュなし)。デバイス契約(§5.2)はどの速度モードでも常に有効にする。

### 5.5 移行時の確認項目

| 確認 | 期待される結果 |
|---|---|
| ITF の起動 | TIMER ERROR(F80CA3)、TIMER INTERRUPT ERROR(F80D4D/F80D73)、DMA ERROR が出ない |
| `IO_GAP=0` + #1 だけ | ITF の PIT リードバックが通る(#1 が十分であることの確認) |
| BIOS のキーボード、RTC、FDC の初期化 | 起動時にキー入力が効く、日付が読める、FD から起動できる |
| OPNA ドライバ(BUSY をポーリングするものと固定ループのもの) | 音色化けやノートの欠落がない。#3 を外すと化けるケースがあれば、#3 の必要性の裏付けになる |
| GDC 描画(N88-BASIC(86) の LINE/CIRCLE など、EGC/GRCG を使うもの) | 描画コマンドが落ちない(#5) |
| VSYNC 待ちループ(`JMP $+2`/`OUT 5Fh` を挟むもの) | フレームレートが実機と同じ |

### 5.6 未確認事項のまとめ

- ARTIC/5Fh が 9801 系のどの機種から存在するか(§1.1、§1.2)。np21w の 5Fh で 0x0B/0x20 を特別扱いする理由。
- PC-98 の GDC の「2.5 MHz/5 MHz」が CLK ピンの周波数かどうか(§2.6)。
- PC-98 の 8251 のクロック(tCY)と、キーボード側がリセットパルス幅を見ているか(§2.3、§1.5)。
- FDC のクロック(8/4 MHz)と、floppy.v が書込み直後に RQM を同期的に落とすか(§2.5)。
- YM2203 単体の待ちサイクル表(§2.7)。
- µPD1990/4990、8255、CG 窓のアクセスタイミング(§2.8、§2.9)。
- z86 の LOOP 系命令の実クロック数と、現行ビルドでの ITF IRQ0 テストの余裕(§4.3)。
- 速度依存ソフトの具体的なタイトル(§3)。

---

## 出典一覧

ローカル(np21w 0.86 rev106、`~/repo/np21w/np21w-src-rev106/`):
`np21w io/artic.c`、`np21w io/iocore.c`、`np21w io/pit.c`、`np21w io/gdc.c`、`np21w io/gdc.h`、`np21w io/fdc.c`、`np21w io/serial.c`、`np21w io/printif.c`、`np21w io/mouseif.c`、`np21w io/upd4990.c`、`np21w io/cgrom.c`、`np21w io/pic.c`、`np21w sound/opna.c`、`np21w cbus/boardws.c`、`np21w pccore.c`、`np21w pccore.h`、`np21w bios/bios.c`、`np21w bios/bios19.c`、`np21w i286c/v30patch.c`

ローカル(このリポジトリ): `docs/PC98_ITF_TRACE.md`、`docs/PC98_MACHINE_SPEC.md`、`docs/PC9801UX_DIFF.md`、`docs/PC98_IO_MAP.md`、`fpga/core/cpu_bus_bridge.sv`、`fpga/core/chipset/HDL/Peripherals.sv`、`fpga/core/pc98_opna.sv`、`fpga/core/sound/jt12/hdl/jt12_mmr.v`、`fpga/core/pc98_gdc.sv`、`fpga/core/pc98_kbd8251.sv`、`fpga/core/pc98_upd4990.sv`、`fpga/core/pc98_fdc_glue.sv`、手元 ROM(`~/.pc98roms/bios.rom`、`itf.rom`、`bios_retrobios386.rom`)のバイト列検索と逆アセンブル

Web:
- take52 "PC9821 Software Technical Data"(5Fh、8253、Time Stamper): http://www2t.biglobe.ne.jp/~take52/tech/soft.htm
- ReactOS PC-98 cpu.h: https://doxygen.reactos.org/d0/db5/sdk_2include_2reactos_2drivers_2pc98_2cpu_8h_source.html
- Linux/98 パッチ(io.h、5Fh): https://lkml.iu.edu/0304.0/1415.html
- MAME pc9801.cpp: https://raw.githubusercontent.com/mamedev/mame/master/src/mame/nec/pc9801.cpp
- ja.wikipedia「PC-9801シリーズ」: https://ja.wikipedia.org/wiki/PC-9801%E3%82%B7%E3%83%AA%E3%83%BC%E3%82%BA
- 98epjunk アクセラレータのスイッチ設定: https://98epjunk.shakunage.net/sw/cpu/accel_sw.html
- Intel 8253/8253-5: https://mark-ogden.uk/files/intel/publications/231306-001%208253_8253-5%20Programmable%20Interval%20Timer-Nov86.pdf
- Intel 82C54: https://pdos.csail.mit.edu/6.828/2017/readings/hardware/82C54.pdf
- Intel 8259A: https://pdos.csail.mit.edu/6.828/2017/readings/hardware/8259A.pdf
- Intel 8251A: https://mark-ogden.uk/files/intel/publications/205222-002%208251A%20Programmable%20Communication%20Interface-Nov86.pdf
- Intel 8237A: https://mark-ogden.uk/files/intel/publications/231466-005%208237A%20High%20Performance%20Programmable%20DMA%20Controler%20(8237A-5)-Sep93.pdf
- Intel 8272A: https://mark-ogden.uk/files/intel/publications/210606-002%208272A%20Single_Double%20density%20Floppy%20Disk%20Controller-Nov86.pdf
- NEC µPD765 データシート: https://bitsavers.org/components/nec/_dataSheets/uPD765_Data_Sheet_Dec78.pdf
- NEC µPD765 AN-08: https://bitsavers.mirrorservice.org/components/nec/_appNotes/AN08_uPD765_preliminary_197902.pdf
- Intel 82720(µPD7220): https://bitsavers.org/components/intel/_dataSheets/82720_Data_Sheet_Preliminary_Jun83.pdf
- YM2608 アプリケーションマニュアル(英訳): https://csclub.uwaterloo.ca/~pbarfuss/YM2608J_Translated.PDF
- ymfm: https://github.com/aaronsgiles/ymfm
- YM2612 の BUSY に関する議論: https://gendev.spritesmind.net/forum/viewtopic.php?p=27104
- NEC V20/V30 User's Manual: https://ia903205.us.archive.org/28/items/bitsavers_necV20V30U_11351331/V20_V30_Users_Manual_Oct86.pdf
