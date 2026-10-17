# z86 設計リファレンス(上流と PC-98 ポート)

調査日: 2026-10-18 / 対象ブランチ: `z86-port`(HEAD `95d931c`)

| 項目 | 値 |
|---|---|
| 上流 | <https://github.com/nand2mario/z86>(作者 nand2mario、Apache-2.0) |
| ポートが基にしたコミット | `fdc7c3906f197d91346a5acaa0b99eef5cc92478`(2025-07-07 "add license")。`fpga/core/z86/UPSTREAM` に記録 |
| 上流の履歴 | コミットは 2 つだけ(`50bcd61` first commit → `fdc7c39` add license、どちらも 2025-07-06 UTC)。最終 push も 2025-07-06。**ポートの基点が上流 HEAD そのもの**で、以後上流に更新はない |
| 上流の規模 | `src/` で約 5.0K 行(execute 2430 / decode 848 / ucode.asm 628 / z86.sv 519 / fetch 364 / cache 283 …)。README は「~6K」と書いている |
| ポートの場所 | `fpga/core/z86/`。`cache.sv` を外し `z86_wbif.sv` に置き換えた |

本文中の `up:` は上流 `src/` のファイル(コミット `fdc7c39`)、`port:` は
`fpga/core/z86/` 以下のファイルを指す。行番号はどちらもこの調査時点のもの。

> **最重要の結論(第 2 節・第 5 節)**: 上流の `cache.sv` は**キャッシュではない**。
> 冒頭コメントが `// TODO: actually implement L1 cache`(up:cache.sv:2)で、
> README も "Cache implementation (framework exists)" を WIP に挙げている。中身は
> 「フェッチ/デコード/実行の 3 要求を 32 ビット Avalon とI/O ポートに振り分ける
> 非キャッシュの調停器」で、タグもデータアレイもない。したがって「キャッシュを
> 戻す」は「上流のキャッシュを復活させる」ことにはならない。**新しく設計する**
> 作業になる。そのときに守るべきメモリ側の前提は第 5 節にまとめた。

---

## 1. パイプライン全体

### 1.1 段構成

上流 README と up:z86.sv:1-15, 273-276 による。

```
 FETCH ──► DECODE1 ──► DECODE2 ──► EXECUTE ──► WRITE-BACK
 └──── fetch.sv ────┘   decode.sv   execute.sv   write_back.sv
  32B バッファ         EA 計算       ハードワイヤ   GPR/フラグ/
  命令長/プリフィクス    ハザード検出   + マイクロコード  セグメント/分岐
                       デコード時ロード  ストア発行
```

| 段 | モジュール | 役割 | 根拠 |
|---|---|---|---|
| FETCH | `fetch.sv` | 32 バイトの命令バッファ。16 バイト単位でキャッシュ(実体は調停器)から読み込む | up:fetch.sv:7-9, 60-74 |
| DECODE1 | `fetch.sv`(同じモジュール) | `FETCH_LUT`(`tools/fetch_lut.py` が生成)で命令レイアウトを決め、プリフィクス/opcode/modrm/disp/imm に分解する。通常 1 クロック、プリフィクス 1 個ごとに +1 クロック | up:fetch.sv:11-13, 94-148, 224-234 |
| DECODE2 | `decode.sv` | 実効アドレス計算、マイクロコード入口の選択、ハードワイヤ命令クラス(one-hot `I_*`)、レジスタ読み出し、**デコード時のメモリロード発行**、2 段スコアボードによるハザード検出、割り込み注入 | up:decode.sv:1-4, 100-119, 544 |
| EXECUTE | `execute.sv` | ハードワイヤ命令は 1 クロックで実行。複雑な命令はマイクロコードで複数クロック。ストアはここから出す | up:execute.sv:1-11, 147-166 |
| WRITE-BACK | `write_back.sv` | GPR 2 ポート、フラグ、セグメントレジスタ、分岐(CS:IP の更新) | up:write_back.sv:1-4 |

設計の手本は i486 の 5 段パイプライン(README の謝辞に Crawford の論文
"The i486 CPU: Executing Instructions in One Clock Cycle", 1990 を挙げている)。
README の比較表は ao486 を "4 stages / Real+Protected / Cache Implemented" とし、
z86 を "5 stages / Real-mode only / Cache Framework" としている。

### 1.2 実装している命令セット

- 8086 の全命令と、リアルモードの 80186/80286 拡張命令(PUSHA/POPA、BOUND、
  IMUL imm、INS/OUTS、ENTER/LEAVE、即値シフト C0/C1、PUSH imm)(README、
  up:decode.sv:234-246)。
- **プロテクトモードはない**。`0F 00`/`0F 01`(SLDT/LGDT/LMSW など)、LAR/LSL/CLTS
  のマイクロコード入口はコメントアウトされている(up:decode.sv:248-273)。
  `ARPL`(63h)だけは入口がある。up:z86.sv:3-4 にも "real-mode 80286
  instructions (but no protected mode)" とある。
- FPU はない(README の表)。
- アドレスは 20 ビット(`[19:0]`)。`a20_enable` 入力はあるが、どこにもつながっていない(up:z86.sv:26)。
- TF(シングルステップ)のトラップは実装が見当たらない。`TF` は INT 処理の中でクリアされるだけ(up:execute.sv:857)。
- **HLT は割り込みで再開しない**。`MC_HALT` は `mc_wait` で止まり続け
  (up:execute.sv:1183-1186)、テストベンチは `halted` を見て終了判定に使っている
  (up:tests/main.cpp:162)。ポートでも変わっていない(port:execute.sv:1210-1212)。
  → ゲストが `STI; HLT` で待つと戻ってこない。PC-98 側で問題になるかは**未確認**。
- `LOCK`(F0)は `is_prefix()` に入っていない(up:fetch.sv:347-349)ため、プリフィクスとしては消費されない。どう扱われるかは**未確認**。

### 1.3 マイクロコード

- ソースは `up:ucode.asm`(628 行、入口 74 個)。`tools/ucode.py` が
  `ucode_rom.svh` と `ucode_entry.svh` を生成する(上流はこの 2 つの生成物を
  コミットしておらず Makefile が作る。ポートは生成済みのものをコミットしている)。
- マイクロ命令は `{op[5:0], arg[3:0], stop}`(up:execute.sv:133-140)。PC は 9 ビット
  (`mc_pc`、up:execute.sv:198)。
- マイクロコード化されているのは、遠距離/間接の CALL/JMP/RET、INT/INTO/IRET、
  文字列命令とその REP 形、PUSHF/POPF、LES/LDS、MUL/IMUL/DIV/IDIV、BCD 補正、
  HLT、286 拡張命令(up:decode.sv:156-246, 278-295)。そのほかはハードワイヤ
  (`ex_iclass`、up:decode.sv:607-658)。
- ハンドシェイク: マイクロコード命令の `ex_ready` は最後の µop の `stop` ビットで
  立つ。それまで DECODE2 の出力は保持されたままになる(up:execute.sv:147-166)。
  µop が進めるのは `mc_active = ex_valid & rd_ready & (~wr_valid | wr_ready) & ~div_busy`
  のときだけ(up:execute.sv:169)。
- 除算器は別モジュール `divider.sv`。16÷8 が 16 クロック、32÷16 が 32 クロック
  (up:divider.sv:1-9)。

### 1.4 フェッチバッファ(プリフェッチ)

up:fetch.sv:58-74, 150-322。

| 項目 | 値 |
|---|---|
| バッファ | `buffer[0:31]`。16 バイトの半分 2 つ(`buf_valid[1:0]`)。リング状に使い、`buf_start` で先頭側の半分を示す |
| 読み込み単位 | 16 バイト、16 バイト境界に整列(`ld_addr` は `buf_addr` か `buf_addr+16`)。キャッシュ側へは 128 ビットを一括で渡す(`ld_data[127:0]`) |
| 補充方針 | 読み込み中でなければ、無効な半分を先頭側から順に要求する(up:fetch.sv:207-221)。同時に出ている要求は 1 つだけ(`loading`) |
| 消費 | 命令全体(`ptr_end`)がある半分も有効なら 1 クロックで 1 命令を DECODE2 に渡す(up:fetch.sv:235)。16 バイト境界を越えたら、使い終わった半分を無効化して `buf_addr += 16`(up:fetch.sv:312-317) |
| 分岐(上流) | `br_taken` のとき、ターゲットが `buf_addr` か `buf_addr+16` の 16 バイトブロックに入っていればポインタを動かすだけ。後半に飛んだら前半を捨てる(up:fetch.sv:194-205)。外れたらバッファを全部無効にして `buf_addr` を張り直す |
| `loading_drop` | ライン読み込みの途中でバッファを張り直したときに立てる。キャッシュ側の読み込みは**最後まで走り**、`ld_ack` が返ってきた時点でそのデータを捨てる(up:fetch.sv:171-180, 192-193)。バーストは中断できない前提 |
| ストアとの整合 | **上流には一切ない**。CPU のストアがバッファ内のバイトを書き換えても、古いバイトを実行する(ポートで修正、第 4 節 `31c40c3`) |

帯域についての上流の想定(up:z86.sv:8-10, 34-35): 1 命令平均 3 バイトなら、
32 ビットバスで CPI=1 を維持できる。コメント上の想定は CPI=2(1.5 バイト/クロック)。

### 1.5 ハザード

- DECODE2 の 2 段スコアボード `sb0`(EX)と `sb1`(WB)。マスク `reg_mask_t` は
  `gpr[7:0]`、`mem`、`seg[3:0]`、`stackop`、`io`(up:z86_package.sv:86-94)。
  `hazard = sb0∩rd_mask | sb1∩rd_mask` のときデコードを止める(up:decode.sv:104-107)。
- `CONFIG_FORWARDING_REGFILE=0` が既定。1 にするとレジスタファイルの同サイクル
  フォワーディングが入り、RAW の待ちが 2 から 1 に減る代わりに Fmax が約 5 MHz
  落ちる(up:z86_package.sv:5-7)。
- `mem` ビットは「直前の命令がメモリに書き、この命令がメモリを読む」場合に 1 命令分
  止めるだけの粗い仕組み(コメントに "TODO: make this finer-grained")。上流では
  modrm 形式のストアでしか立たなかった(ポートで拡張、`0c4176f`/`46e81fa`)。
- `id_ready` は `(~ex_valid|ex_ready) & 2サイクル目条件 & ~hazard & (~id_mem_rd|rd_ready)`。
  DECODE2 がロードを発行するので、`MOV r,[m]` でも EX は待たない設計になっている。
- 分岐は EX で確定する(`br_taken` は execute.sv の出力レジスタ)。`br_taken` の
  サイクルは EX が即座に `ex_ready=1`(up:execute.sv:165)、DECODE2 は `id_void`
  (up:decode.sv:110)で、どちらも中身を捨てる。分岐予測はない。分岐ペナルティの
  クロック数は上流に記載がない(**未確認**。ポートの実測値は第 3 節)。

### 1.6 割り込み(上流)

up:decode.sv:116-119, 298-301, 592-601, 659-685。

- `intr & IF & ~intra` をラッチ(`intr_latched`)し、NMI は `nmi_latched`。
- 命令境界(DECODE2 の `emit`)で **INT Ib(CDh)を注入**する。`ex_imm` は PIC の
  ベクタ(NMI なら 2)、`ex_ip_after = ip_this` で、戻り先は置き換えられた命令になる。
- `intra`(INTA)は注入開始(`start_int_service`)で立ち、`~nmi && ~intr` で落ちる。
  ao486 の `interrupt_do/interrupt_vector/interrupt_done` と同じで、**ベクタは要求と
  同時に用意されている**前提(8259 の INTA バスサイクルを CPU は回さない)。
- 上流の top では `.nmi ()` が未接続(up:z86.sv:379)。

### 1.7 上流の外部インターフェース

up:z86.sv:17-83 のポート名は **ao486 のトップ**(MiSTer-devel/ao486_MiSTer
`rtl/ao486/ao486.v`)と同じ: `a20_enable`、`interrupt_do/vector/done`、
`avm_*`、`dma_*`、`io_read_do/...`、`io_write_do/...`。ao486 を使う PC/AT
システムの CPU 部分を差し替える想定と読める。違いは次のとおり。

| | ao486 | z86 |
|---|---|---|
| `avm_address` | `[29:0]`(DWORD アドレス) | `[19:0]`(**バイト**アドレス。`sdram_sim` が `[19:2]` で引く) |
| I/O | `io_*_length[2:0]`、データ 32 ビット | `io_*_word`、データ 16 ビット |
| `dma_*` | CPU が DMA を受け、メモリ経路(とキャッシュ)を通す | **ポート宣言だけで未接続**。`dma_readdata` などはどこからも駆動されない(up:z86.sv:47-56) |
| `cache_disable` | あり | なし |

---

## 2. 上流の `cache` モジュール(実体は非キャッシュの調停器)

### 2.1 構成

| 項目 | 上流の実装 | 根拠 |
|---|---|---|
| キャッシュ構成・容量・ウェイ数 | **なし**(タグもデータ RAM もない)。`ld_hit` 出力は宣言だけで駆動されず、top でも未接続 | up:cache.sv:2, 13; up:z86.sv:208 |
| 「ライン」 | フェッチ用の 16 バイト = 32 ビット × 4 ビート(`avm_burstcount=4`)。結果は `ld_data[127:0]` レジスタに 1 本だけ持つ | up:cache.sv:107-110, 205-214 |
| 書き込み方針 | 毎回メモリへ直接書く(保持しないので実質ライトスルー)。1 回に 1 ストア。バッファなし | up:cache.sv:111-131, 235-251 |
| メモリ IF | 32 ビット Avalon-MM マスタ。`avm_address` はバイトアドレス、`byteenable` 4 ビット、`burstcount` 4 ビット | up:cache.sv:31-40 |
| 優先順位 | **ライン読み込み > ストア > データ読み込み**(コメントは「RAW を避けるため読み込みより先に書く」) | up:cache.sv:106-136, 194-204 |
| I/O | メモリ FSM とは**別の FSM**(`io_state`)。`io_read_do`/`io_write_do` は 1 クロックのパルス、`*_done` で完了 | up:cache.sv:150-161, 255-279 |
| 無効化 / スヌープ / DMA | なし | — |
| デバッグポート | `dbg_mem_*` は宣言のみで使っていない(テストベンチは `sdram_sim` に直接書く) | up:cache.sv:55-60; up:tests/z86_test.sv:61-69 |
| リソース | フリップフロップ数百個程度の FSM + 128 ビットレジスタと推定。数値の公表はない(**未確認**。測るなら `scripts/measure_core.sh`) | — |

**メモリ側の前提**: 上流には SDRAM コントローラがなく、Verilator 用の
`tests/sdram_sim.sv` しかない。このモデルは IDLE でコマンドを受け、次のクロックで
1 ワード目を返し、以降 1 クロックに 1 ワードずつ返す(up:sdram_sim.sv:92-106,
126-135)。`cpu_busy = (state != IDLE)`(up:sdram_sim.sv:40)。A0000-BFFFF には VGA
用の分岐があり、バイト単位でアクセスする(up:sdram_sim.sv:51-52)。対象は PC/AT +
VGA の構成で、README には "booting PC AT BIOS and running IBM BASIC in
Verilator simulation" とある。

**Avalon 規約から外れている点**(実機の SDRAM コントローラにつなぐと問題になる。
新しくキャッシュを書くときに引き継がないこと):

1. 読み込みコマンドは `mem_state==MEM_IDLE` の 1 クロックだけ組み合わせ回路で
   出し、`avm_waitrequest` を見ずに次の状態に進む(up:cache.sv:106-110, 132-136,
   194-202)。奇数アドレスのワード読みの 2 回目(up:cache.sv:138-142)も同じ。
   相手がそのクロックで必ず受け付ける前提になっている。
2. 書き込みも IDLE の 1 クロックだけ `avm_write=1` を出し、`MEM_WRITING` に入って
   から `~avm_waitrequest` を見ている(up:cache.sv:111-131, 235-244)。待たされた
   書き込みが保持されない。
3. `MEM_READING` の 2 ビート目判定は `rd_word` を**その時点の値で**見る
   (up:cache.sv:138, 218)。`rd_word` は decode/execute の出力をつなぎ替えた信号
   (up:z86.sv:215)なので、要求後に変わりうる。ポートは要求時に取り込む(`rd_isw`)。
4. `ld_offset`/`rd_offset` はリセットされない(2 ビットが 4 ビートで一周する
   ことに頼っている)。
5. `rd`(デコードと実行の OR、up:z86.sv:210-215)から `avm_read`/`io_read_do`
   までが組み合わせ回路でつながっている。
6. メモリ FSM と I/O FSM が並行に動くので、**I/O とメモリの間で順序が保証されない**
   (例: バンク切り替えの OUT と、出ているライン読み込み)。

### 2.2 ポートのプロトコル(CPU 側)

ポートの `z86_wbif` も CPU 側はこの信号名と意味をそのまま使っている(port:z86_wbif.sv:44-62)。

| 信号 | 方向 | 意味 |
|---|---|---|
| `ld_addr[19:0]` | fetch→ | 16 バイト境界のライン先頭(上流 fetch は常に整列済みのアドレスを出す) |
| `ld_req` | fetch→ | **トグル**。値を反転させると新しい要求 |
| `ld_ack` | →fetch | **トグル**。完了したら `ld_ack <= ld_req`。`ld_req != ld_ack` の間は要求が出ている |
| `ld_data[127:0]` | →fetch | ライン。byte i = `ld_data[8i+:8]`。次の読み込みが始まるまで値を保持する |
| `rd` | decode/execute→ | **1 クロックのパルス**(`rd_addr`/`rd_io`/`rd_word` はそのクロックだけ有効) |
| `rd_ready` | → | 1 = アイドルかデータ準備済み。`rd` の次のクロックで 0 になり、データが来たら 1 に戻る。初期値は 1 |
| `rd_data[15:0]` | → | `rd_ready` の立ち上がり以降で有効 |
| `wr_valid` | execute→ | `wr_ready` が来るまで**保持**(アドレスとデータも) |
| `wr_ready` | → | **1 クロックのパルス**。`wr_valid & wr_ready` で完了 |
| `wr_io`/`rd_io` | | 1 = I/O 空間(キャッシュを通さない) |

#### タイミング図(上流 `cache` + `sdram_sim`、待ちなし)

ライン読み込み(16 B = 4 ビート)。`E n` はクロックの立ち上がり、`C n` はその後のサイクル。

```
            E0    C1    E1    C2    E2    C3    E3    C4    E4    C5    E5    C6    E6
fetch     ld_req^=1 ─────────────────────────────────────────────────────────────── (待ち)
cache     IDLE  │ avm_read=1 │LOADING                                  │IDLE
                │ burst=4    │                                         │
avm_rdvalid     │     0      │  1(w0)  │  1(w1)  │  1(w2)  │  1(w3)   │
ld_data         │            │  [31:0] │ [63:32] │ [95:64] │[127:96]  │
ld_ack          │            │         │         │         │  ^=1 @E5 │
fetch                                                       ld_ack!=ld_ack_r → E6 で buffer へコピー、buf_valid=1
```
→ 要求から命令バッファが有効になるまで約 6 クロック。

データ読み込み(`rd` パルス)。

```
         C0                 E0            C1                E1         C2
rd       1 (addr,word)      │      0      │                 │
avm_read 1 (組み合わせ)      │             │                 │
mem_st   IDLE               │ READING     │                 │ IDLE
rdvalid                     │      1      │                 │
rd_ready 1                  │      0      │                 │ 1
rd_data                                         ─────────────┤ 有効
```
→ 2 クロック。キャッシュが忙しいときは `rd_pending` に退避して後で出す。

ストア(`wr_valid` のレベル保持 / `wr_ready` パルス)。

```
          C0              E0        C1            E1        C2         E2
wr_valid  1 ──────────────────────────────────────────────────────────┤0 (execute が落とす)
avm_write 1 (IDLE, 1clk)  │   0     │              │
mem_st    IDLE            │ WRITING │ ~waitreq     │ IDLE
wr_ready  0               │   0     │              │  1 (1clk) │ 0
```
奇数アドレス(`addr[1:0]==3`)へのワードアクセスは 2 回の Avalon アクセスに分ける
(`MEM_READING2`/`MEM_WRITING2`、2 回目は `addr+4` に `byteenable=0001`)。

I/O: `io_read_do`/`io_write_do` は IO_IDLE の 1 クロックだけ出るパルスで、
`io_*_done` を待つ。読んだデータは `rd_data`、完了は `rd_ready` か `wr_ready` で返す。

---

## 3. 性能と元のターゲット

### 3.1 上流の主張

| 主張 | 出典 |
|---|---|
| ほとんどの命令を 1 クロックで完了し、複雑な命令はマイクロコードで複数クロック | README; up:z86.sv:4-6 |
| 32 ビットバスで CPI=1 を維持できる(1 命令 3 バイトと仮定)。コメント上の想定は CPI=2 | up:z86.sv:8-10, 34-35 |
| レジスタファイルのフォワーディングを入れると Fmax が約 5 MHz 下がる | up:z86_package.sv:5-7 |
| 動作周波数(MHz)、CPI の実測値、286/386 とのベンチマーク比較 | **記載なし(未確認)** |
| 動作状況: "booting PC AT BIOS and running IBM BASIC in Verilator simulation"。FPGA での検証は WIP | README |
| テスト: SingleStepTests 8088 / 80186 テスト / 80286 テスト(`make test86/test186/test286`) | README; up:tests/Makefile |

### 3.2 元のターゲット基板

- 上流には基板のトップも制約ファイルもない。`ifndef VERILATOR` の側で
  `pll u_pll (.clkin(clk_g), .clkout0(clk))` を実体化している(up:z86.sv:87-89)が、
  `pll` モジュールはリポジトリにない。**ターゲット基板は未確認**。
- 状況証拠: ポート名が ao486 と同じで、sdram_sim に VGA 経路がある → ao486 系の
  PC/AT システムに載せる想定。同じ時期の作者の作品は 486tang(ao486 を Sipeed Tang
  Console 138K = Gowin GW5AST に移植、2025-09 公開、<https://github.com/nand2mario/486tang>)。
  Tang 系に載せる予定だった可能性はあるが、**推測**。
- 作者のブログ(<https://nand2mario.github.io/>)に z86 の記事はない(一覧を確認。
  2025-12 z8086、2026-05 z386、2026-08 z486、2026-09 Voodoo)。X の投稿は確認でき
  なかった(**未確認**)。z86 は 2025-07 に 2 コミットだけ公開された実験作で、
  パイプラインの考え方は後の z486 に引き継がれたと読める(z486 記事は z386 からの
  発展としか書いておらず、z86 には触れていない)。

### 3.3 参考: 作者の後継コアのキャッシュと性能(z86 の数値ではない)

| | z386 | z486 |
|---|---|---|
| 記事 | <https://nand2mario.github.io/posts/2026/z386/> | <https://nand2mario.github.io/posts/2026/z486/> |
| パイプライン | マイクロコード 386 | FI/D1/D2/EX(WB は EX のエッジでコミット)。プリフェッチキューは **32 バイト、16 バイトの I キャッシュラインで補充**(z86 のフェッチバッファと同じ形) |
| L1 | 統合 16 KB、4 ウェイ、16 B ライン、PLRU、ライトスルー + read-allocate、2 段のライトバッファ、VIPT | I/D 分離、各 8 KB(リリース構成では各 16 KB の記述もある)、4 ウェイ、16 B ライン、PIPT、D はライトスルー + 3 段のストアキュー |
| SDRAM | 1 ワード目まで 6〜7 クロック、16 B ラインのバーストで約 15 クロック、early restart | 記載なし |
| 一貫性 | 記事に記載なし | ソース: I キャッシュは CPU のストアで該当語を**パッチ**し、外部(DMA)の書き込みでは**無効化**する(`z486/l1_icache.sv:32-39`、`cache_unit.sv:98-100`)。自己書き換えコード用のテスト `tests/programs/smc_icache_patch_race.asm` がある |
| 周波数/性能 | DE10-Nano で 85 MHz。Doom 16.5 FPS(ao486 は 21.0) | 85 MHz、0.330 DMIPS/MHz、Dhrystone の CPI 2.80(ao486 は 4.56)、Doom 29.1 FPS |

### 3.4 ポートでの実測(参考)

| 測定 | 値 | 出典 |
|---|---|---|
| CPU クロック | `zet_clk` = `clk_chipset` 42.95 MHz にゲートをかけたもの(INTA サービス中と pause 中は止まる) | core_top.sv:248, 3431-3432; zet_cpu_bridge.sv:28-36 |
| 16 B 境界をまたぐ LOOP | 修正前 130 clk/iter → 4.2 clk/iter(`tb_z86_loop`) | commit `072340f` |
| ITF から BIOS への引き渡し(シミュレーション) | z86 2.07 s、Zet 2.32 s | commit `b79e86f` |
| 実機 SuperDepth | 10 MHz 設定で 40/40 回起動 | commit `17d11f0` |

PC-98 側のバスは i8288 系の 8 ビットバイトエンジンで、CE に合わせて進む
(zet_cpu_bridge.sv:3-4, 28-36)。CPU 内部のクロックが速くても、ライン読み込み
1 回のたびに 16 バイト分のバスサイクルを払うことになる。これがキャッシュを
戻したい理由。

---

## 4. ポートで入った変更

`git log --oneline -- fpga/core/z86` の古い順。ファイルごとの差分量(上流比、
`diff` の行数)は decode 400、execute 255、z86.sv 234、fetch 136、write_back 16、
regfile 7。divider / z86_package / ucode.asm / tools は**無変更**。`cache.sv` は
削除し、`z86_wbif.sv` を新しく書いた。

### 4.1 構造の変更(`c39ee2d`)

| 変更 | 内容 / 理由 |
|---|---|
| Quartus Lite 対応 | `inside` の除去、型付き配列 localparam、宣言初期化子の分離、`always_comb` → `always @*` |
| top のポート | PLL、Avalon、`io_*`、`dma_*`、`a20_enable`、debug reg/mem ポートを削除。**Zet と同じ形の Wishbone マスタ**(`wb_adr_o[19:1]`、`wb_sel_o`、`wb_tga_o`=I/O、`wb_cyc_o==wb_stb_o`)と `wb_tgc_i/o`(INTR/INTA)に置き換えた(port:z86.sv:17-48)。既存の `zet_cpu_bridge` を**変更せずに**使うため |
| `cache` → `z86_wbif` | CPU 側のポートは同じで、出口を Wishbone にした(第 4.3 節)。`ld_hit` と `dbg_mem` は削除 |
| 割り込み | ベクタは 8259 の INTA サイクルの後にしか存在しない。decode が `inta_req` を出し、top が `wb_tgc_o` を 1 パルス出す。ブリッジがクロックを止めて二重 INTA を回し、ベクタを `wb_dat_i` に載せる。z86 はそれを `pic_vec_r` に取り込み、`pic_vec_valid` が立つまで注入を待つ(port:z86.sv:57-86、port:decode.sv:83-96) |
| NMI | `1'b0` に固定(port:z86.sv:363) |
| 選択方法 | `config.tcl` の `PC98_Z86` で選ぶ。core_top.sv:3428-3455 で Zet と差し替える |

### 4.2 不具合修正と機能追加(コミット順)

| コミット | 区分 | 変更と理由 |
|---|---|---|
| `072340f` | fetch / 性能 | 順方向に境界をまたいで捨てた半分を、数クロックの間 `behind_ok` として残す。そこへ戻る分岐ではその半分を復元する(port:fetch.sv:79-85, 274-283)。16 B 境界で終わる LOOP が毎回 32 B を読み直していたため(130→4.2 clk/iter)。バッファ内判定を 20 ビットの相対値で行い、1 MB の折り返しにも対応した |
| `072340f` | リセット | CS:IP=F000:FFF0、DS=ES=SS=0、FLAGS=0002(port:write_back.sv:157-167、port:execute.sv:2298-2300)。ITF の `OUT 0F0h`(CPU だけのリセット)の後は IF=0 で戻る必要があるため |
| `63a8bb8` | wbif の順序 | **ストアをライン読み込みより先に出す**(上流とは逆、port:z86_wbif.sv:20-25)。パッチ直後に far jump すると、パッチ前のバイトを読んでいた(ITF の 0000:04F8 引き渡しスタブ) |
| `b79e86f` | I/O | `IO_GAP=64` clk(約 1.5 µs)の I/O リカバリを入れた。待っている間は後続を一切追い越させない(port:z86_wbif.sv:33-39, 120-121, 132-134)。ITF の PIT チェック(`JMP $+2` 2 回)が速すぎて失敗していた |
| `81cf223` | 割り込み / ハザード | `intra` は INT シーケンスが IF を落とした時点で終える(8259 が INTR を上げたままでも次を受けられるように)。PUSH/POP sreg のスコアボードのフィールドを `opcode[5:4]` から `[4:3]` に直した(POP DS が CS 扱いになっていた) |
| `0c4176f` | ハザード | XLAT は BX も待つ。MOV AL,moffs などデコード時に読む命令は、**出ている全ストア**を待つ。上流の `mem` ビットは modrm 形式のストアでしか立たなかった(port:decode.sv:829, 915) |
| `46e81fa` | デコード / ハザード | ENTER の命令長(3→4)。LEAVE の SP 書き込みポート。暗黙/マイクロコードで書くレジスタを `wr_mask` に追加(DX、POPA、BP/SP、ES/DS)。INT/POP/RET/文字列命令は飛行中のストアを待つ(port:decode.sv:945) |
| `ccefd1a` | デバッグ | JTAG プローブにレジスタを出す(`dbg_regs`、port:regfile.sv:24) |
| `d2a9707` | 割り込み | 古い IF で INTR を受けない(EX 内の CLI/POPF/IRET/INT を待つ)。`id_ucode_valid` → `rd_mask` の組み合わせループを解消した |
| `8cd61e5` → `6a6f743` | 割り込み | 注入は**パイプラインが空になってから**行う(EX と sb0/sb1 が空)。分岐でプリフィクス状態をクリアする(port:fetch.sv:243-249)。割り込みで命令を置き換えるサイクルにはデコード時の読みを出さない。`wb_tgc_o` は Wishbone サイクルが出ていないときだけ出す(port:z86.sv:79-83) |
| `12641d0` | 割り込み | MOV SS / POP SS / STI の後 1 命令は割り込みを禁止する(port:decode.sv:122-127, 768-770)。FreeDOS/FreeCOM のスタック切り替えが壊れていた |
| `4ab1570` | 合成 | execute のマイクロ op ブロックで推論されていたラッチを除去した(port:execute.sv:547)。quartus_fit の segfault の原因だった |
| `31c40c3` | **fetch の一貫性** | **CPU のストアで 32 B フェッチバッファをスヌープする**。バッファ内の半分か読み込み中の半分に当たったら全部捨てて、デコードに渡していない最初の命令からフェッチし直す。退避した半分に当たったら忘れる(port:fetch.sv:98-115, 229-240、配線は port:z86.sv:269-271 `snoop_wr = wr_valid & wr_ready & ~wr_io`)。286 の 6 B キューよりずっと先まで読んでいるので、解凍ルーチンやローダが書き換えたコードを実行していなかった |
| `2b8d8f4` | デバッグ | JTAG のデバッグ停止(`dbg_stop`/`dbg_stopped`、命令境界で止まる)(port:decode.sv:88-92, 134-137) |
| `ab9866e` | fetch | **taken branch では必ず**読み込み中のラインを `loading_drop` する(port:fetch.sv:250-260)。上流はバッファ外への分岐でしか落とさず、バッファ内分岐で `buf_start`/`buf_addr` が変わると、古い対応のままのデータが別の半分に書かれていた(FreeDOS のパス解析が壊れていた) |
| `57dfea1` | リセット | `ld_req`/`ld_ack` を**両方 0** にリセットする(port:fetch.sv:204-212、port:z86_wbif.sv:108)。上流は `ld_req <= ld_ack` で、wbif 側が逆向きにコピーしていたため、読み込み中にリセットされると互いに待ち合って FFFF0 で止まった。execute の保留中読みフラグもリセットする |
| `17d11f0` | リセット | CPU リセットで `wr_valid`/`br_taken`/WB の valid を落とす(port:execute.sv:2302-2310)。10 MHz では ack 前に OUT 0F0h が効き、同じ OUT を再発行してリセットループに入っていた |
| `95d931c` | 割り込み | 受け付けた INTR はデコードを止める。パイプラインが空になり、最後のストアがバスを離れ、INTR が数クロック安定し、IF と INTR がまだ立っている場合に限って INTA を出す(`int_boundary`/`int_settle`/`inta_req`、port:decode.sv:171-182)。`intra` は注入 1 回につき 1 パルス。8259 が要求を取り下げたときにスプリアス(IRQ7)が出ていた問題と、同じハンドラが 2 回走る問題の修正 |

### 4.3 `z86_wbif` の動作(上流 `cache` との違い)

| | 上流 `cache` | `z86_wbif` |
|---|---|---|
| バス | 32 ビット Avalon、バースト 4 | 16 ビット Wishbone(Zet の形)、**1 回に 1 ワード**、バーストなし |
| ライン読み込み | 4 ビートのバースト | ワード読みを 8 回順に出す(`S_LD`、port:z86_wbif.sv:146-178)。読み込みは常に最後まで走り、古いラインは fetch が `loading_drop` で捨てる |
| 優先順位 | ライン > ストア > 読み | **ストア > ライン > 読み**(port:z86_wbif.sv:131-165) |
| メモリと I/O | 別の FSM で並行 | **1 本の FSM で直列**(Wishbone が順序を守る) |
| 奇数アドレスのワード | 32 ビット境界(`addr[1:0]==3`)のときだけ分割 | 16 ビット境界(`addr[0]==1`)で分割し、奇数バイト → 次のワードの偶数バイトの順に出す(zet_wb_master と同じ順) |
| `rd_word` | 要求後もその時点の値を見る | 要求時に取り込む(`rd_isw`) |
| I/O リカバリ | なし | `IO_GAP` |
| 待ち | Avalon の `waitrequest` を部分的にしか見ない | `wb_ack_i` が来るまで `stb` を保持 |

タイミング図(`z86_wbif`、ack はブリッジ次第で可変)。

```
ライン読み込み:
clk      E0         E1 .. Ea0     ..  Ea7
ld_req   ^=1
st       IDLE →     S_LD ─────────────────── IDLE
stb      0          1 ───────────────────────┤0
adr      ─          L+0     L+1 ...   L+7    (ワードアドレス、sel=11)
ack                       ↑Ea0    ↑Ea1 ... ↑Ea7
ld_ack                                       ^=1 @Ea7

奇数番地へのワード書き込み (A 奇数):
st   IDLE → S_WR1 (adr=A>>1, sel=10, dat={lo,00}) ─ack→ S_WR2 (adr=(A>>1)+1, sel=01, dat={00,hi}) ─ack→ IDLE, wr_ready=1
```

---

## 5. キャッシュを戻す際の注意点

前提: 上流にキャッシュの実装はない(第 2 節)。以下は「z86 の CPU 側ポート
(`ld_*`/`rd*`/`wr*`)の内側に本物の L1 を置く」場合に満たすべき条件と、
PC-98 で追加で必要になる仕組みをまとめたもの。

### 5.1 上流の設計が暗黙に前提にしていること

| 前提 | 上流の扱い | キャッシュを入れると何が壊れるか |
|---|---|---|
| メモリは CPU 専用で、ほかに書き手がいない | `dma_*` は未接続。スヌープもない | PC-98 では DMA(uPD71071 互換。`docs/PC98_DMA_DESIGN.md`)が FDC や SCSI のデータを RAM に直接書く。キャッシュは古いデータを返す |
| 自己書き換えコードとの一貫性はない | フェッチバッファはストアで無効化されない | ポートは `31c40c3` で 32 B バッファのスヌープを入れた。I キャッシュを足すなら、**I キャッシュも同じストアで無効化かパッチ**する必要がある。そうしないと、バッファを捨ててフェッチし直しても I キャッシュから古いバイトが来る |
| ストアとライン読み込みの順序 | ライン読み込みが先 | ポートは逆順に直した(`63a8bb8`)。キャッシュを入れるなら「ストアが L1 と下位メモリの両方に反映されてから、同じラインのフィルとヒットを返す」ことを保証する(ライトスルー + ストアキューなら、フィル時にキューをフォワードするか、先に排出する) |
| メモリと I/O の順序 | 並行 FSM なので保証なし | PC-98 には **I/O でメモリマップが変わる**レジスタがある(下記)。OUT が完了するまで後続のフィルやヒットを止める必要がある |
| 全アドレスが普通の RAM | sdram_sim の VGA 窓以外は均一 | PC-98 には「読むと副作用がある」領域や「読んだ値が変換される」領域がある(下記)。キャッシュ不可の領域を判定する仕組みが要る |
| メモリが Avalon コマンドを即座に受け付ける | `waitrequest` を見ない箇所がある(第 2.1 節) | 実際の SDRAM コントローラ(`sdram_mp`)は待たせる。上流の FSM を流用してはいけない |

### 5.2 PC-98 で追加が必要なもの

1. **キャッシュ可能領域の限定**(ホワイトリスト方式)
   - キャッシュしてよいのは、ブリッジのプリフェッチャと同じく「SDRAM の普通の
     バイト」だけ: `pc98_sdram_hits(a) && !pc98_gvram_hits(a)`
     (fpga/core/pc98_sdram_map.svh:46-52、zet_cpu_bridge.sv:603-607)。
   - **キャッシュしてはいけない**領域:
     - A0000-A3FFF のテキスト VRAM と A4000 の CG ウィンドウ(BRAM 側が応答。
       CG ウィンドウは I/O で選んだフォントを返す。`pc98_cgwindow.sv`)。
     - A8000-BFFFF と E0000-E7FFF の G-VRAM。GRCG/EGC が読み書きを変換するため、
       読んだ値はメモリの中身ではなく演算結果になる(`pc98_grcg.sv`、`pc98_egc.sv`)。
       E0000 はアナログモードでだけ存在し、ポート 6Ah でマップが変わる
       (pc98_sdram_map.svh:33-40)。
     - C0000-CFFFF の EMS ウィンドウ(ポート 08E1h-08E9h で 16 KB 単位にバンクが
       変わる。`pc98_ems98.sv:1-37`)と、C0000-E7FFF の空き領域(FFh を返す必要が
       ある)、SCSI のオプション ROM(`pc98_scsi_rom.sv`)。
   - キャッシュするなら、領域判定を**物理アドレスと現在のマップ状態**から毎回
     計算し、タグには残さない。

2. **I/O 書き込みでのフラッシュ / 無効化**
   - F8000-FFFFF は ITF ROM と BIOS ROM のバンク切り替え(ポート 043Dh、
     `bios_shadow_flag`)。**同じアドレスで中身が変わる**。ブリッジのプリフェッチャは
     このフラグの変化で全窓を捨てている(zet_cpu_bridge.sv:629-636, 1080)。
     z86 の L1 も同じにするか、F8000-FFFFF をキャッシュしない。
   - EMS のバンクレジスタ、6Ah(アナログモード)、そのほかマップを動かす OUT。
     ブリッジは「**あらゆる I/O 書き込みでフラッシュ**」としている
     (zet_cpu_bridge.sv:597-598)。最初はこれに倣うのが安全。
   - z86 のフェッチバッファ(32 B)のスヌープは `~wr_io` のストアだけを見ている
     (port:z86.sv:269)。バンク切り替えの OUT の後のコードフェッチでも
     バッファを捨てる必要があるかどうかは**未確認**。現状は Wishbone の直列性と、
     切り替え直後に far jump する BIOS の作法に頼っている。

3. **DMA の書き込みによる無効化**
   - PC-98 の DMAC は CPU のバス経路を通らずに SDRAM に書く。ブリッジは DMA
     グラント中(`!bus_ours`)にプリフェッチ窓を全部捨てている
     (zet_cpu_bridge.sv:598-599)。
   - L1 では、(a) DMA グラントで全無効化(簡単。FDC の 1 セクタごとに L1 が
     空になる)か、(b) DMA の書き込みアドレスでライン単位に無効化(z486 の
     `invalidate_addr/invalidate_valid` 方式。z486/l1_icache.sv:32-39)のどちらか。
     (b) にするには、DMA の書き込みアドレスを CPU ドメインに渡す経路を新しく作る
     必要がある。
   - DMA の**読み**(メモリ → FDC)についても、ライトバックにするならダーティ
     ラインの排出が要る。**ライトスルーを強く推奨**する(z386/z486 とも D 側は
     ライトスルー)。

4. **自己書き換えコード**
   - ポートのフェッチバッファのスヌープ(`31c40c3`)は維持する。I キャッシュ(か
     統合キャッシュ)に入っているラインも、CPU のストアで更新するか無効化する。
     z486 は I キャッシュの該当ワードを**パッチ**している
     (z486/cache_unit.sv:185-232、テスト `smc_icache_patch_race.asm`)。
   - 統合キャッシュ(z386 方式)なら、ストアがキャッシュに反映されるので I/D 間の
     問題は消える。ただしフェッチバッファのスヌープは引き続き必要。

5. **リセットとトグルの約束**
   - `ld_req`/`ld_ack` は両方 0 にリセットする(`57dfea1`)。キャッシュ側の
     `ld_ack` も同じにする。CPU だけのリセット(OUT 0F0h)はライン読み込みの
     途中で来る。フィル中のリセットでは、フィル FSM を中断するか、最後まで走らせて
     結果を捨てる(ブリッジ側のバスサイクルは中断できない)。
   - リセット後に保留中のストアを再発行しない(`17d11f0`)。キャッシュに
     ストアキューを入れるなら、キューの扱い(リセット前に受け付けたストアは
     書くのか捨てるのか)を決めておくこと。現状、z86_wbif はリセットで FSM を
     IDLE に戻している(port:z86_wbif.sv:105-117)。

6. **INTA との排他**
   - ベクタは `wb_dat_i` に載ってくるので、`wb_tgc_o` を出せるのは Wishbone
     サイクルが出ていない間だけ(port:z86.sv:79-83)。キャッシュがヒットで
     バスを使わない時間が長くなっても条件は変わらない。ただし、フィルの途中で
     INTA を挟まないこと。`bus_quiet = ~wr_valid & ~wb_cyc_o & ~wb_stb_o`
     (port:z86.sv:371)にキャッシュのストアキューが空であることも加えること。
     そうしないと、INTA より前のストアがバスに出る前に割り込みが入る。

7. **I/O のタイミング**
   - `IO_GAP` は「I/O サイクルの終わりから次の I/O まで」の間隔。キャッシュで
     コードが速くなると、PC-98 のソフトの `JMP $+2` 待ちはさらに短くなる。
     IO_GAP はキャッシュを入れた後も維持し、必要なら伸ばす(`b79e86f`)。

8. **検証の足場**(既存)
   - `tb_z86_loop`(z86 単体 + 固定レイテンシの Wishbone メモリ。`+irq`、
     `+rst_at`、`+f0reset`、`+mem`、`+stop_pc`)、`scripts/sim_z86_tests.sh`、
     `z86_fuzz`(Unicorn と比較)、`sim/z86_tests/raw_smc`(自己書き換え)、
     `irq_withdraw`。キャッシュを入れたら、DMA 書き込みを模擬するモードと、
     043D バンク切り替えを挟むテストを追加すること。

### 5.3 推奨する最小構成(提案)

| 項目 | 推奨 | 理由 |
|---|---|---|
| 配置 | `z86_wbif` の手前(CPU 側ポートの内側) | 上流のポートの形を保ち、ブリッジは変えない |
| 種類 | 統合、ライトスルー、no-write-allocate、16 B ライン(= `ld_*` 1 回分) | 一貫性の問題が最小。`ld_data` の幅と合う |
| キャッシュ可能 | `pc98_sdram_hits && !pc98_gvram_hits`、かつ F8000-FFFFF と C0000-E7FFF を除く | 第 5.2 節 1・2 |
| 無効化 | 全 I/O 書き込み、DMA グラント、`bios_shadow_flag` の変化 → 全無効化(最初はフラッシュで十分) | ブリッジのプリフェッチャと同じ規則。実績がある |
| ストア | L1 に当たれば更新し、必ず下位にも出す。フェッチバッファのスヌープはそのまま | 自己書き換えコード対策 |
| 下位バス | まず Wishbone のワード単位のまま。次の段階でブリッジに SDRAM バーストのフィル経路を足す | 8 ビット i8288 経路を通る限り、フィルは遅い(第 3.4 節) |

---

## 参考 URL

- 上流リポジトリ: <https://github.com/nand2mario/z86>(ツリー: <https://github.com/nand2mario/z86/tree/fdc7c3906f197d91346a5acaa0b99eef5cc92478>)
- 上流 README: <https://github.com/nand2mario/z86/blob/fdc7c3906f197d91346a5acaa0b99eef5cc92478/README.md>
- 上流 cache: <https://github.com/nand2mario/z86/blob/fdc7c3906f197d91346a5acaa0b99eef5cc92478/src/cache.sv>
- 作者ブログ: <https://nand2mario.github.io/>(z386: <https://nand2mario.github.io/posts/2026/z386/>、z486: <https://nand2mario.github.io/posts/2026/z486/>)
- z486 ソース(I キャッシュのスヌープ/パッチ): <https://github.com/nand2mario/z486>
- 486tang: <https://github.com/nand2mario/486tang>
- ao486 トップ(ポート名の比較元): <https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/rtl/ao486/ao486.v>
- z386 のキャッシュ紹介記事(二次資料): <https://linuxiac.com/open-source-z386-brings-intel-80386-microcode-back-to-life/>
