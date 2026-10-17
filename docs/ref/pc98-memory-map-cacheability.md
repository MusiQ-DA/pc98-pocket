# PC-98 物理メモリマップとキャッシュ可否(リファレンス)

作成: 2026-10-18。対象: z86 にキャッシュを足すための調査メモ(worktree `/private/tmp/pc98-z86`、HEAD `95d931c`)。

対象機種: **PC-9801 VM/VX/RA/UV 級、ノーマルモード(640×400)、1MB リアルモード**。
本文の最後に 286/386 級で増えるものを別の節にまとめる。
ハイレゾモード(PC-98XA/XL/H98 系)は扱わない。触れる箇所では明記する。

## 0. 出典と表記

| 略記 | 出典 |
|---|---|
| `np21w <path>:<line>` | NP21/W 0.86 rev106 のソース。`~/repo/np21w/np21w-src-rev106/` に展開済み。挙動の正はこれ(AGENTS.md) |
| `core <path>:<line>` | このコア。`/private/tmp/pc98-z86/fpga/core/` からの相対パス |
| `[UNDOC-MEM]` | Undocumented 9801/9821 Vol.2「メモリ制御」 <https://www.webtech.co.jp/company/doc/undocumented_mem/io_mem.txt> |
| `[UNDOC-DMA]` | 同「DMAコントローラ」 <https://www.webtech.co.jp/company/doc/undocumented_mem/io_dma.txt> |
| `[UNDOC-DISP]` | 同「表示制御」 <https://www.webtech.co.jp/company/doc/undocumented_mem/io_disp.txt> |
| `[UNDOC-EGC]` | 同「EGC」 <https://www.webtech.co.jp/company/doc/undocumented_mem/io_egc.txt> |
| `[UNDOC-SND]` | 同「サウンド」 <https://www.webtech.co.jp/company/doc/undocumented_mem/io_sound.txt> |
| `[LKML-DMA]` | Linux PC-9800 サブアーキテクチャ DMA パッチ <https://lkml.iu.edu/0304.0/1417.html> |
| `[MAME-27]` | MAME `pc9801_27.cpp`(SASI ボード) <https://git.redump.net/mame/plain/src/devices/bus/pc98_cbus/pc9801_27.cpp> |

「**未確認**」と書いた項目は、どの出典でも裏付けが取れていない。

np21w の仕組みについて一点だけ先に書いておく。np21w のメモリアクセスは、32KB 単位のハンドラ表
`memfn0`(`np21w i386c/cpumem.c:424`)で振り分けられる。添字は `address >> 15` である。
I/O ポートへの書き込みでこの表のエントリを差し替えることで、バンク切り替えが実装されている
(`memm_arch`: `np21w i386c/cpumem.c:512`、`memm_vram`: `np21w i386c/cpumem.c:540`)。
**「ハンドラ表を張り替える I/O」は、そのままキャッシュの無効化トリガの一覧になる。**

---

## 1. 早見表(1MB 空間)

列の意味:

- **R副作用 / W副作用**: 読み出し・書き込みが、メモリ内容以外の状態を変えるか、計算結果を返すか。
- **バンク**: 同じアドレスの中身を切り替える I/O の有無。
- **キャッシュ**: §8 の提案の要約。I = 命令フェッチ、D = データ。

| 範囲 | 中身 | R副作用 | W副作用 | バンク(切替 I/O) | キャッシュ | 本コアの実装 |
|---|---|---|---|---|---|---|
| 00000-7FFFF | メイン RAM | なし | なし | なし | **I+D 可**(DMA スヌープ必須) | SDRAM(`core pc98_sdram_map.svh:48`) |
| 80000-9FFFF | メイン RAM(640KB 機)。386 機では RAM ウィンドウ | なし | なし | V30 機: なし(DIP SW 3-6 で切り離しのみ)。386 機: **0461h**、**043Fh 80h/82h** | **I+D 可**(V30 級)。386 級ではウィンドウ書換で無効化 | SDRAM。0461h は未実装 |
| A0000-A1FFF | テキスト VRAM(文字コード) | なし | 表示更新 | なし | 可能だが非推奨(§8) | BRAM(`core chipset/HDL/Peripherals.sv:366`) |
| A2000-A3FDF | テキスト VRAM(アトリビュート、偶数番地のみ有効) | なし | 表示更新 | なし | 可能だが非推奨 | BRAM |
| A3FE0-A3FFF | アトリビュート末尾。**A3FE2+4n の 8 バイトがメモリスイッチ** | なし | **書き込み禁止**(ポート 68h NVMW) | なし | **キャッシュ禁止** | 専用レジスタ(`core pc98_tvram.sv:167`) |
| A4000-A4FFF | CG ウィンドウ(漢字 ROM / 外字 RAM の窓) | **ポート A1h/A3h/A5h の状態で中身が変わる** | 外字 RAM に書く | **A1h/A3h/A5h** | **キャッシュ禁止** | `core pc98_cgwindow.sv` |
| A5000-A7FFF | 空き(np21w では素の mem) | なし | なし | なし | 禁止(穴) | SDRAM 対象外(`core pc98_sdram_map.svh:50`) |
| A8000-AFFFF | G-VRAM プレーン B | **GRCG TCR / EGC で計算値を返し、EGC 状態も変わる** | GRCG TDW/RMW・EGC で変換される | **A6h**(描画ページ)、**7Ch**、**6Ah**(EGC) | **キャッシュ禁止** | SDRAM + `pc98_gvram_seq` |
| B0000-B7FFF | G-VRAM プレーン R | 同上 | 同上 | 同上。一部機種は **043Fh 20h/22h** で B バンク EMS | **キャッシュ禁止** | 同上 |
| B8000-BFFFF | G-VRAM プレーン G | 同上 | 同上 | 同上 | **キャッシュ禁止** | 同上 |
| C0000-CFFFF | EMS フレーム(16KB×4)/ サウンド BIOS ROM(CC000 既定)/ 拡張 ROM | なし | なし | **08E1h/08E3h/08E5h/08E7h/08E9h**(NEC EMS) | 条件付き(EMS ポート書込で無効化) | 未マップ時は空き(FFh)、EMS 時は SDRAM(`core chipset/HDL/RAM.sv:254`) |
| D0000-DFFFF | 拡張 ROM / RAM(SASI D0000、SCSI D2000、GP-IB D4000、IDE D8000 など) | なし | 4KB 単位で RAM/ROM | ボード固有(SCSI の MEMBANK、IDE 1E8Eh、386 機の 053Dh/043Fh/063Ch) | 条件付き(既定は禁止。§8) | D0000-D00FF xrom、D2000-D2FFF SCSI ROM のみ |
| E0000-E7FFF | G-VRAM プレーン E(16 色モード時のみ)。8 色時は空き | 16 色時はプレーン B〜G と同じ | 同左 | **6Ah**(bit0 16 色モード)で有無が変わる | **キャッシュ禁止** | analog 時のみ SDRAM(`core pc98_sdram_map.svh:51`) |
| E8000-F7FFF | システム BIOS ROM | なし | 書けない(ROM) | 386 機: **053Dh bit1**(BIOS RAM シャドウ) | **I+D 可**(読み専用) | SDRAM、書込保護(`core chipset/HDL/RAM.sv:277`) |
| F8000-FFFFF | BIOS ROM 末尾 32KB **または** ITF ROM | なし | 書けない | **043Dh**(10h=ITF / 12h=BIOS) | **I+D 可**。ただし 043Dh 書込で無効化 | SDRAM。ITF は 1F8000 のシャドウ(`core chipset/HDL/RAM.sv:269`) |

---

## 2. 領域ごとの詳細

### 2.1 00000-9FFFF メイン RAM

| 項目 | 内容 | 出典 |
|---|---|---|
| np21w の扱い | 00000-9FFFF はすべて `memmain_rd*/wr*`、つまり素の配列アクセスで、副作用はない | `np21w i386c/cpumem.c:424-475`(表の `// 00`〜`// 80` 行)、`:310-350` |
| 実装量 | 640KB として数えるかどうかはメモリスイッチ A3FEAh の下位ビットで決まる(128KB 単位。04 = 640KB) | `core pc98_tvram.sv:36-43` |
| 80000-9FFFF の切り離し | ノーマルモードでは、拡張スロット上の I/O バンクメモリ用に 8,9 バンクを切り離せる。通常は DIP SW 3-6 で設定する | [UNDOC-MEM]「BIOS/ITFバンク切換」解説 |
| 80000-9FFFF の RAM ウィンドウ(386 機) | **I/O 0461h**: 8,9 バンク(80000-9FFFF)に任意の 128KB を写す。値の bit7-1 がアドレス bit23-17。リセット時は 80000 を指す。**V30 動作時でも 1MB 超の RAM が見える**。486 以上の機種では、この I/O への WRITE で FLUSH# がアサートされる | [UNDOC-MEM] I/O 0461h |
| A0000-BFFFF の RAM ウィンドウ(386 機) | **I/O 0463h**: 0A,0B バンク用。通常状態ではアクセスできない | [UNDOC-MEM] I/O 0463h |
| 8,9 バンク制御 | **I/O 043Fh** に 80h を書くと内部 RAM、82h を書くと拡張スロット | [UNDOC-MEM] I/O 043Fh |
| ハイレゾの同種機能 | I/O 0091h / 0093h(ハイレゾ専用。本コアの対象外) | [UNDOC-MEM]「メモリウィンドウ」 |
| np21w の 0461h/0463h | **実装なし**。grep `0461`/`0463` で io/・cbus/ に該当がない | `np21w io/`, `np21w cbus/` |
| 本コア | SDRAM。`pc98_sdram_hits` が `a[19:16] < C` で真になる | `core pc98_sdram_map.svh:46-52` |

**VM/VX/UV(V30 機)には 0461h/0463h が存在しない**。これらは [UNDOC-MEM] で「対象 ノーマル」とされているが、機能そのものは 386 機向けの記述である。
RA は 386 機なので該当する(043Fh の項に「PC-9801RA2 では次の OUT 0461h まで反映されない」とある)。
VX(286)に 0461h があるかどうかは **未確認**。

### 2.2 A0000-A3FFF テキスト VRAM とメモリスイッチ

| 項目 | 内容 | 出典 |
|---|---|---|
| レイアウト | 文字コード A0000+idx×2(下位)と +1(上位)。アトリビュート A2000+idx×2 | `np21w vram/maketext.c`(`core` 側の要約は `docs/PC98_MACHINE_SPEC.md` の TVRAM 注記) |
| 読み出し | `memtram_rd8`: A0000-A3FFF は `mem[address]` を返すだけ(ウェイトを課す以外の副作用はない) | `np21w mem/memtram.c:13-27` |
| 書き込み(文字) | `mem` に書き、`tramupdate` と `gdcs.textdisp` を立てる。これは表示の再描画通知で、メモリ意味論には影響しない | `np21w mem/memtram.c:65-72` |
| 書き込み(アトリビュート) | **偶数番地だけが書ける**(奇数番地への書き込みは捨てられる) | `np21w mem/memtram.c:74-80` |
| メモリスイッチ | A3FE0-A3FFF のうち偶数番地かつ `address & 2` のもの、つまり **A3FE2, A3FE6, …, A3FFE の 8 バイト**。書き込めるのは `gdcs.msw_accessable` が立っているときだけ | `np21w mem/memtram.c:81-88`、`:151` |
| 書き込み許可 | **ポート 68h(モード F/F 1)**。0Dh で許可、0Ch で禁止(NVMW PERMIT)。np21w は `gdc.mode1` の bit6 を `msw_accessable` に写す | [UNDOC-DISP] I/O 0068h、`np21w io/gdc.c:493-521` |
| 依頼文にあった「ポート 6Eh」 | **誤り**。メモリスイッチの書き込み保護は 68h で行う。6Eh はモード F/F 2 系(拡張表示の設定) | [UNDOC-DISP] I/O 006Eh |
| 本コア | BRAM で実装している。A0000-A3FFF の選択は `~iorq && ~address_enable_n && address[19:14]==101000b`。**AEN で修飾しているので DMA は届かない** | `core chipset/HDL/Peripherals.sv:366-369` |
| 本コアのメモリスイッチ | 8 バイトを専用レジスタに持ち、ゲストからの書き込みを**無条件に捨てる**(ポート 68h を見ていない)。np21w との差分 | `core pc98_tvram.sv:44-53`、`:145-168` |

キャッシュ上の論点は次のとおり。

- 読み出しに副作用はない。
- 書き込める主体は CPU だけである(DMA は AEN で遮断されている)。
- ただし、メモリスイッチのセルは「書いても値が変わらない」。本コアの奇数セルや、np21w で 68h が禁止のときの A3FE2+4n がそうである。アトリビュートの奇数番地も同じで、捨てられる。
  したがって write-through で「書いた値をキャッシュにも反映する」実装にすると、**実メモリとキャッシュが食い違う**。
  キャッシュするなら、これらの番地は書き込み時に無効化するか、そもそもキャッシュの対象から外す。

### 2.3 A4000-A4FFF CG ウィンドウ

| 項目 | 内容 | 出典 |
|---|---|---|
| 読み出し | `fontrom[cgwindow.high/low + ((address>>1)&0x0F)]`。**値はポート A1h/A3h(文字コード)と A5h(ライン)の設定で決まる**。メモリとしての中身は存在しない | `np21w mem/memtram.c:17-26`、`np21w io/cgrom.c:67,107,147` |
| 書き込み | 奇数番地への書き込みは、`cgwindow.writable` が立っている(外字コード)ときだけ `fontrom` に入る | `np21w mem/memtram.c:89-94`、`np21w io/cgrom.c:17,30,181` |
| A5000-A7FFF | np21w では `memtram` 経由の素の `mem`。実機では未使用(**未確認**) | `np21w mem/memtram.c:27` |
| 本コア | `pc98_cgwindow.sv` が読み出しと書き込みの両方を担当する。SDRAM の外にある | `core pc98_cgwindow.sv:82-110`、`core chipset/HDL/Peripherals.sv:370-372` |

**キャッシュ禁止**。同じアドレスの値が I/O 書き込みだけで変わる、典型的なメモリマップド I/O である。

### 2.4 A8000-BFFFF / E0000-E7FFF グラフィック VRAM

#### アクセスハンドラの選び方(np21w)

`vramop.operate` の下位 4 ビットで `vacctbl[16]` から 1 つが選ばれ、A8000, B0000, B8000, E0000 の 4 窓に同じハンドラが張られる(`np21w i386c/cpumem.c:493-510`、`:540-620`)。
ビットの意味は `np21w vram/vram.h:28-32` による。

| bit | 意味 | 変える I/O |
|---|---|---|
| 0 `VOPBIT_ACCESS` | 描画(アクセス)ページ 0/1 | **A6h** bit0(`np21w io/gdc.c:752-760`) |
| 1 `VOPBIT_EGC` | EGC 有効 | **6Ah** に 05h/04h(mode2 bit2。EGC 拡張モードが許可され、GRCG chip==3 のとき)(`np21w io/gdc.c:548-553`) |
| 2-3 `VOPBIT_GRCG` | GRCG モード(7Ch の bit7:CG, bit6:RMW) | **7Ch**(`np21w io/crtc.c:20-31`) |
| 4 `VOPBIT_ANALOG` | 16 色モード。**0 なら E0000 が空き(N/C)になる** | **6Ah** に 01h/00h(`np21w io/gdc.c:536-545`、`np21w i386c/cpumem.c:613-620`) |

| vacctbl | 読み | 書き | 意味 |
|---|---|---|---|
| 0x0-0x7 | `memvram0/1_rd` | `memvram0/1_wr` | 素の VRAM(ページ 0/1) |
| 0x8-0x9 | **`memtcr*_rd`** | **`memtdw*_wr`** | GRCG TCR 読み / TDW 書き |
| 0xC-0xD | `memvram*_rd` | **`memrmw*_wr`** | GRCG RMW |
| 0xA,0xB,0xE,0xF | **`memegc_rd`** | **`memegc_wr`** | EGC |

#### 副作用

| モード | 読み出し | 書き込み | 出典 |
|---|---|---|---|
| 素 | なし(ページ選択だけ効く) | 表示更新通知のみ | `np21w mem/memvram.c:12-33` |
| GRCG TCR(7Ch=1x00pppp) | **4 プレーンとタイルレジスタを比較した結果を返す**。`~((VRAM_B^tile0)\|(VRAM_R^tile1)\|…)`、マスクされたプレーンは除く | — | `np21w mem/memvram.c:161-200`、[UNDOC-DISP]「グラフィックチャージャ」 |
| GRCG TDW | — | **CPU のデータは無視され**、有効な全プレーンにタイル値が書かれる | `np21w mem/memvram.c:113-156`、[UNDOC-DISP] |
| GRCG RMW(7Ch=11xxpppp) | 素(現在のページ) | 書いた値をビットマスクとして、全有効プレーンを読んで変更して書き戻す | `np21w mem/memvram.c:40-110`、[UNDOC-DISP] |
| EGC | **`egc_readbyte`: `lastvram` を 4 プレーン分更新し、シフタに入力し、ope の条件次第で `patreg` を読み込む**。返すのはシフタ出力かプレーン値 | 論理演算・シフト付きで 4 プレーンに書き込む | `np21w mem/memegc.c:1084-1124`、`:1367-1410`、[UNDOC-EGC] |

EGC のレジスタは 4A0h-4AFh(`np21w io/egc.c:136`、[UNDOC-EGC])。
GRCG のタイルは 7Eh に書き、7Ch への書き込みでタイルカウンタがリセットされる(`np21w io/crtc.c:20-45`)。

#### 表示ページと描画ページ

| ポート | 意味 | 出典 |
|---|---|---|
| A4h | **表示**ページ(bit0)。CPU から見えるメモリは変わらない | `np21w io/gdc.c:743-750`、[UNDOC-DISP] I/O 00A4h |
| A6h | **描画(アクセス)**ページ(bit0)。**同じアドレスの中身がページ 0 と 1 で入れ替わる** | `np21w io/gdc.c:752-760`、[UNDOC-DISP] I/O 00A6h |

#### CPU 以外に VRAM を書く主体

| 主体 | np21w | 本コア |
|---|---|---|
| GDC(μPD7220 スレーブ)の描画コマンド | `np21w io/gdc_sub.c`(gdcsub_write)、`np21w io/gdc_pset.c`(GRCG/EGC 経由の描画) | ソフトコアの GDC エンジンが `pc98_gvram_seq` のサービスチャネルで書く(`core pc98_gvram_seq.sv:163-175`、`:286-292`、`core pc98_gdc.sv:136-145`) |
| DMA | `MEMP_WRITE8` はメモリマップ全体を通るので、理屈の上では VRAM にも届く(`np21w mem/dmav30.c:32`) | DMA のアドレスも RAM.sv の選択を通る。グラフィック窓への DMA が `gvram_seq` を経由するかどうかは **未確認** |

#### 本コアの実装

| 項目 | 出典 |
|---|---|
| 窓の判定 `pc98_gvram_hits`(A8000-BFFFF、analog 時は E0000-E7FFF も) | `core pc98_sdram_map.svh:57-62` |
| ページ 1 は SDRAM 0x600000 にあり、ゲストのアドレス空間には現れない(`gvram_page1_flag`) | `core pc98_sdram_map.svh:72-80`、`core chipset/HDL/RAM.sv:286-290` |
| A4h/A6h のデコード | `core chipset/HDL/Peripherals.sv:1680-1689` |
| 7Ch/7Eh のデコード | `core chipset/HDL/Peripherals.sv:1812-1830` |
| 68h/6Ah のデコード | `core chipset/HDL/Peripherals.sv:1611-1640` |
| **EGC は現在の worktree では外されている**(EGC=0、GRCG のみ)。main 系統では EGC の作業が進んでいる(コミット ce55835 ほか)ので、マージ後は EGC の副作用が加わる | `core chipset/HDL/Chipset.sv:573-578` |
| VRAM ウェイト(np21w の MEMWAIT_VRAM/GRCG を再現) | `core chipset/HDL/Chipset.sv:646-665` |

**キャッシュ禁止(I も D も)**。理由は 4 つある。

1. TCR と EGC は読み出しが計算か状態変化である。
2. TDW/RMW/EGC は書いた値とメモリに入る値が一致しない。
3. GDC(ソフトコア)という別の書き手がいる。
4. A6h, 7Ch, 6Ah の書き込みだけで、同じアドレスの意味が変わる。

既存のプリフェッチ窓も、この範囲をフェッチ対象から外している(`core zet_cpu_bridge.sv:603-607`、`:742-747`)。

### 2.5 C0000-DFFFF 拡張 ROM / RAM / EMS

#### np21w の既定の割り当て

| 範囲 | 読み | 書き | 出典 |
|---|---|---|---|
| C0000-CFFFF | `memems_rd`: `CPU_EMSPTR[(a>>14)&3]` 経由。リセット時は C0000 等に恒等マップ(素の mem) | `memems_wr` | `np21w i386c/cpumem.c:431,441`、`np21w mem/memems.c`、`np21w io/emsio.c:50-57` |
| D0000-DFFFF | `memmain_rd` | `memd000_wr`: **`CPU_RAM_D000` の 4KB 単位ビットが立っているときだけ書ける**(立っていなければ ROM 扱い) | `np21w i386c/cpumem.c:431,441`、`np21w mem/memepp.c:10-40` |

#### 載るもの(np21w)

| 範囲 | 中身 | バンク / 制御 | 出典 |
|---|---|---|---|
| CC000-CFFFF(既定) | サウンド BIOS ROM(-26/-86/-118/-14 ボード)。ジャンパで C8000/CC000/D0000/D4000 に置ける | ボード上のジャンパ | `np21w cbus/board86.c:158`、`np21w sound/soundrom.c:250-262`、`:1955-1960` |
| C0000-CFFFF | NEC EMS(PC-9801-53 系)の 16KB×4 フレーム。ハードウェア EMS はアドレスが固定なので、サウンド ROM と共存させるには ROM を切り離す必要がある | **08E1h/08E3h/08E5h/08E7h**(ページ)、**08E9h**(MB 選択) | `np21w io/emsio.c:9-30,69-74`、[UNDOC-MEM]「EMSボード用制御ポート」 |
| D0000-D0FFF | SASI BIOS(`sasi.rom`) | — | `np21w cbus/sasiio.c:452-466` |
| D2000-D3FFF | SCSI(-55)BIOS。**SCSI 制御レジスタ MEMBANK の bit6 で 2 つのバンクを切り替え、`mem+D2000` に丸ごとコピーする** | SCSI 制御 MEMBANK | `np21w cbus/scsiio.c:108-116`、`:728-746` |
| D4000-D5FFF | GP-IB BIOS | — | `np21w cbus/gpibio.c:343-346` |
| D8000-D9FFF(既定) | IDE BIOS。DA000-DBFFF は RAM(ポート **1E8Eh** に 81h で接続) | 1E8Eh | `np21w cbus/ideio.c:1480-1496`、`:1921-1965` |
| D0000-DFFFF | 設定で RAM にもできる(`useram_d` または EPSON 機で `CPU_RAM_D000=0xffff`) | — | `np21w pccore.c:846-850` |

386 機の追加機能。

| I/O | 機能 | 出典 |
|---|---|---|
| 053Dh | bit7 サウンド BIOS、bit6 SASI 内蔵 HD-BIOS(D7000)、bit5 SCSI、bit4 IDE のイネーブル。bit2 BIOS RAM のアクセス許可。bit1 BIOS RAM/ROM 選択。読み出し不可 | [UNDOC-MEM] I/O 053Dh |
| 043Fh C0h/C2h, C0h/C4h | 内蔵 SASI/SCSI BIOS の RAM/ROM 切替 | [UNDOC-MEM] I/O 043Fh |
| 063Ch | D8000-DFFFF の ROM バンク(IDE BIOS / PCI BIOS / PnP)。9821 系 | [UNDOC-MEM] I/O 063Ch |
| 043Fh 20h/22h | B0000-BFFFF の VRAM/EMS 切替(B バンク EMS 搭載機) | [UNDOC-MEM] I/O 043Fh |

#### 本コア

| 範囲 | 実装 | 出典 |
|---|---|---|
| C0000-CFFFF | 窓がマップされていれば SDRAM プール(0x800000-)。されていなければ選択なし(空き)。リセット時は全窓が未マップ | `core chipset/HDL/RAM.sv:252-258`、`:291-295`、`core pc98_ems98.sv:7-15,70`、`docs/PC98_MACHINE_SPEC.md`「1MB 以上のメモリ」節 |
| D0000-D00FF | xrom(ディスク BIOS 拡張。`Chipset.sv` 内の定数配列) | `core chipset/HDL/Chipset.sv:793`、`:820-` |
| D2000-D2FFF | SCSI(-55)option ROM(`pc98_scsi_rom`、4KB、バンクなし) | `core chipset/HDL/Peripherals.sv:2122-2129`、`core pc98_scsi_rom.sv:1-20` |
| その他 C0000-E7FFF | SDRAM は応答しない。ここで応答すると POST が存在しない拡張を数えて D0000 で止まる | `core chipset/HDL/RAM.sv:234-243`、`core pc98_sdram_map.svh:15-20` |
| サウンド BIOS ROM | 未実装(`sound.rom` はステージングしてあるだけ) | `docs/PC98_MACHINE_SPEC.md` ROM 資産表 |

### 2.6 E8000-FFFFF BIOS / ITF

| 項目 | 内容 | 出典 |
|---|---|---|
| np21w の読み | E8000-F7FFF は `memmain`。F8000-FFFFF は `memf800_rd`(`CPU_ITFBANK` なら `+VRAM_STEP`、つまり ITF のコピーを読む) | `np21w i386c/cpumem.c:485-490,512-538`、`np21w mem/memepp.c:47-66` |
| np21w の書き | E8000-FFFFF は `memnc_wr`(捨てる)。EPSON 機は `memepson_wr` でシャドウ RAM に書ける | `np21w i386c/cpumem.c:485-490`、`np21w mem/memepp.c:72-90` |
| 043Dh | **10h = ITF、12h = BIOS**(NEC)。EPSON 機は 043Fh 42h/40h で許可を切り替え、043Dh 02h/00h で選ぶ | `np21w io/necio.c:25-37,56`、`np21w io/epsonio.c:9-60,121-122` |
| 実機の仕様 | ITF を選ぶと F8000-FFFFF が ITF ROM になり、そのとき E8000-F7FFF は不定。**リセット時は ITF**、ディスクブート時は BIOS。**486 以上の機種では ITF 選択中はキャッシュが効かず、BIOS 選択中は効く。043Dh への WRITE で FLUSH# がアサートされる** | [UNDOC-MEM] I/O 043Dh |
| 043Fh A0h | キャッシュフラッシュ(PC-9801FA など、INVD が使えない機種向け) | [UNDOC-MEM] I/O 043Fh |
| 043Fh E0h-E7h | F8000-FFFFF に出す ROM バンクを直接指定する(9821Af 以降、フラッシュ ROM の書き換え用) | [UNDOC-MEM] I/O 043Fh |
| 本コア: 配置 | BIOS は SDRAM の E8000-FFFFF にある。ITF は SDRAM 1F8000(`latch_address` の bit20 を `bios_shadow_select` で立てる) | `core chipset/HDL/RAM.sv:261-269`、`:300` |
| 本コア: 書込保護 | `bios_protect_flag[1]` が F0000-FFFFF と E8000-EFFFF を保護する | `core chipset/HDL/RAM.sv:274-278` |
| 本コア: 043Dh | 2 サイクルで修飾したうえで 10h→`itf_bank=1`、12h→0 | `core core_top.sv:2980-2987`、`:3047-3072` |
| 本コア: リセット値 | **BIOS(0)**。実機(ITF)とは異なる。V30 では 386 用 ITF を実行できないための選択で、`PC98_BOOT_ITF` で戻せる | `core core_top.sv:2962-2984` |
| 本コア: ローダ | リセット中に `bios_access_request`(HOLD)で BIOS/ITF/FONT を SDRAM に書き込む | `core core_top.sv:2540-2580`、`core chipset/HDL/Bus_Arbiter.sv:74` |

---

## 3. メモリマップを動かす I/O ポート一覧

このポートへの書き込みは、キャッシュ(およびプリフェッチ窓)の無効化トリガの候補になる。

| ポート | 書き込み値 | 影響範囲 | 対象機 | np21w | 本コア |
|---|---|---|---|---|---|
| 0068h | 0Ch/0Dh | A3FE2+4n の書き込み可否 | 全機種 | `io/gdc.c:493-521` | 無視(常に保護) |
| 006Ah | 00h/01h | E0000-E7FFF の有無(8 色/16 色) | VM 以降(16 色機) | `io/gdc.c:536-545` | `Peripherals.sv:1633-` |
| 006Ah | 04h/05h | A8000-BFFFF, E0000 の EGC 有効化 | EGC 機 | `io/gdc.c:548-553` | EGC=0 のため無効 |
| 007Ch | GRCG モード | VRAM の読み書きの意味 | GRCG 機 | `io/crtc.c:20-31` | `Peripherals.sv:1812` |
| 00A6h | bit0 | VRAM の描画ページ | VM 以降 | `io/gdc.c:752-760` | `Peripherals.sv:1681-1689` |
| 00A1h/A3h/A5h | 文字コード / ライン | A4000-A4FFF の中身 | 全機種 | `io/cgrom.c:67-181` | `pc98_cgwindow.sv` |
| 04A0h-04AFh | EGC レジスタ | EGC 経由の VRAM 読み書き | EGC 機 | `io/egc.c:136` | EGC=0 |
| 043Dh | 10h/12h | F8000-FFFFF(ITF/BIOS) | ITF 搭載機 | `io/necio.c:25-37` | `core_top.sv:3069-3070` |
| 043Fh | 20h/22h, 80h/82h, A0h, C0h-C4h, E0h-E7h | B バンク EMS、8,9 バンク、キャッシュフラッシュ、内蔵 HD-BIOS、ROM バンク | 主に 386 以降(EPSON は 40h/42h) | EPSON のみ(`io/epsonio.c:122`) | 未実装 |
| 0461h / 0463h | 128KB 単位のアドレス | 80000-9FFFF / A0000-BFFFF の RAM ウィンドウ | 386 ノーマル機 | 未実装 | 未実装 |
| 053Dh | ビットフィールド | サウンド BIOS / HD-BIOS / BIOS RAM シャドウ | 386 以上(PCI 機を除く) | 未実装 | 未実装 |
| 08E1h-08E7h, 08E9h | ページ / MB | C0000-CFFFF の EMS フレーム | -53 系 EMS | `io/emsio.c:9-30` | `pc98_ems98.sv:70` |
| SCSI 制御 MEMBANK | bit6 | D2000-D3FFF の ROM バンク | -55 系 | `cbus/scsiio.c:108-116` | なし(4KB 固定) |
| 1E8Eh | 81h | DA000-DBFFF の RAM 接続 | IDE 機 | `cbus/ideio.c:1480-1496` | 未実装 |
| 00F2h / 00F6h(02h/03h) | — | A20 の有効/無効(286 以上) | 286 以上 | `io/cpuio.c:37-42,83-95` | V30 のため無関係 |
| 00F0h | 任意 | CPU リセット | 全機種 | `io/cpuio.c:13-25` | `core_top.sv`(OUT F0h 節) |

---

## 4. DMA(μPD71071 / 8237 互換)

### 4.1 レジスタ配置

| ポート | 内容 | 出典 |
|---|---|---|
| 01h-0Fh 奇数 | ch0-3 のアドレスとカウント | [UNDOC-DMA]、`np21w io/dmac.c:352-353` |
| 11h-1Fh 奇数 | ステータス、コマンド、マスク、モードなど | [UNDOC-DMA] |
| 21h/23h/25h/27h | ch1/ch2/ch3/ch0 のバンク(A16 以上)アドレス | [UNDOC-DMA]、[LKML-DMA] |
| 29h | バンクのインクリメント境界(64KB/1MB/16MB) | [UNDOC-DMA] I/O 0029h |
| 0E05h-0E0Bh | ch0-3 の拡張バンク(16MB 超) | [UNDOC-DMA]、`np21w io/dmac.c:355-358` |
| 本コア | `upd71071` を i8237 互換モードで、ポート間隔 2 倍の配置にしている | `core chipset/HDL/Peripherals.sv:273,287`、`docs/PC98_DMA_DESIGN.md` |

### 4.2 チャネルの割り当て

| ch | PC-9801初代/E/F/M/**VM2/VF/U/UV2/UV21** | PC-9801 T/DA/DS/DX/CS/FA/FS/FX, 9821A | 「その他の機種」(**VX/RA 等**は**未確認**だがここに入ると推定) | np21w | 本コア |
|---|---|---|---|---|---|
| 0 | なし(F3/M3/**VM4** は内蔵 SASI)。拡張スロット DRQ00 | 内蔵 HD(DIP 3-3 OFF) | なし。拡張スロット | SASI(`cbus/sasiio.c:16,452`)、CS4231(118)の選択肢(`cbus/cs4231io.c:12`) | **DRQ0 は 0 に固定**(SCSI は PIO)(`Chipset.sv:294-300`) |
| 1 | **メモリリフレッシュ** | 内蔵 HD(DIP 3-3 ON) | なし | CS4231 の選択肢 | `dma_request[1]` は 0 に固定(`core_top.sv:3179`) |
| 2 | FD(1MB I/F モード) | FD(1MB) | FD(1MB) | `FDC_DMACH2HD=2`(`io/fdc.c:23,1245`) | FDC の DREQ(`Chipset.sv:380`) |
| 3 | FD(640KB I/F モード)。拡張スロット DRQ30 | FD(640KB) | FD(640KB) | `FDC_DMACH2DD=3`(`io/fdc.c:24,1246`)、CS4231 の選択肢 | FDC の DREQ と外部 `dma_request[3]` の OR(`Chipset.sv:380`) |

機種別の表の出典は [UNDOC-DMA](機種ごとの 4 つの表)。SASI ボード(-27)が ch0 を使うことは [MAME-27] でも確認できる。
両用 FD I/F が ch2 と ch3 のどちらを使うかは DIP SW 3-1/3-2 で決まる([UNDOC-DMA] 注記)。
本コアは FDC の要求を ch2 と ch3 の両方に出していて、BIOS がプログラムした側だけが動く(`core chipset/HDL/Chipset.sv:375-380`)。

### 4.3 DMA がメモリに書くときの経路

| 項目 | 内容 | 出典 |
|---|---|---|
| np21w | port→mem 転送は `MEMP_WRITE8(ch->adrs.d, …)` で、**CPU と同じメモリマップを通る** | `np21w mem/dmav30.c:28-37` |
| 本コア: アドレス | HOLD 中は `Bus_Arbiter` が `{dma_page_register, dma_address_out}` をバスに出す | `core chipset/HDL/Bus_Arbiter.sv:396-410` |
| 本コア: 書き込み先 | RAM.sv のポート A(CPU と共用)から SDRAM へ書く。**CPU ブリッジを経由しない** | `core sdram_shim.sv:318-322`、`core zet_cpu_bridge.sv:595-600` |
| 本コア: TVRAM | AEN で修飾しているので、DMA は届かない | `core chipset/HDL/Peripherals.sv:366-369` |
| 転送方向 | FDC の READ DATA は I/O→メモリ(**キャッシュを無効化する必要がある**)。WRITE DATA はメモリ→I/O(**write-back キャッシュならフラッシュが必要**) | 一般論。モード bit3-2 の意味は `np21w mem/dmav30.c:25-36` |

### 4.4 DMA 以外でメモリを書く主体

| 主体 | 書く範囲 | 実装の有無 | 出典 |
|---|---|---|---|
| GDC 描画(ソフトコアの GDC エンジン) | G-VRAM(ページ 0/1) | **あり** | `core pc98_gvram_seq.sv:163-175`、`np21w io/gdc_sub.c` |
| ROM ローダ(HOLD / `ext_access_request`) | E8000-FFFFF, 1F8000(ITF), 0x400000-(FONT) | あり。**リセット中のみ**(と想定。実行中のロードは**未確認**) | `core core_top.sv:2540-2580`、`core chipset/HDL/Bus_Arbiter.sv:74` |
| `fdd_ramimg`(SDRAM ポート E) | FDD イメージの領域(ゲスト空間の外) | あり | `core sdram_shim.sv:147-160`。ゲスト空間と重ならないこと自体は**未確認** |
| 86 ボード PCM | なし(I/O FIFO 経由。np21w の `board86.c` に `dmac_attach` はない) | — | `np21w cbus/board86.c`(dmac_attach を grep して該当なし)、[UNDOC-SND] |
| 118(CS4231) PCM | DMA ch0/1/3 を選べる。メモリに無音を書き戻すこともある | 本コアにはない | `np21w cbus/cs4231io.c:12,391-398`、`np21w sound/cs4231c.c:601-607`、[UNDOC-SND] |
| SB16(CT1741) | DMA | 本コアにはない | `np21w cbus/ct1741io.c:649` |
| EMS | C0000-CFFFF の窓を書けるのは CPU だけ | あり | `core chipset/HDL/RAM.sv:291-295` |
| 表示 / フォント / CG フェッチ(ポート B/C/D) | 読み出しのみ | — | `core sdram_shim.sv:100-145` |

---

## 5. 286/386 級で増えるもの(参考。V30 コアでは発生しない)

| 範囲 / 機能 | 内容 | 出典 |
|---|---|---|
| 100000-EFFFFF | 拡張(プロテクト)メモリ。A20 は F2h(有効)と F6h 02h/03h で制御 | `np21w io/cpuio.c:37-42,83-95` |
| F00000-FFFFFF | 「16MB システム空間」。システム用(ROM と VRAM のミラーや拡張 VRAM)か通常 RAM かを **043Bh bit2** で選ぶ | [UNDOC-MEM] I/O 043Bh |
| np21w の 16MB 空間 | FA0000-FFFFFF は `memsys_*` が `address-0xF00000` で `memfn0` に折り返すので、A0000-FFFFF のミラーになる | `np21w i386c/cpumem.c:689-723,726-760` |
| BIOS RAM シャドウ | 053Dh bit1 で E8000-FFFFF を RAM にする。bit2 でアクセスを許可する | [UNDOC-MEM] I/O 053Dh |
| RAM ウィンドウ | 0461h / 0463h(§2.1) | [UNDOC-MEM] |
| 実機のキャッシュ制御の先例 | 486 以上の機種は 043Dh/043Fh/0461h/0463h への WRITE で FLUSH# をアサートする。043Fh A0h でキャッシュフラッシュ。ITF 選択中は ITF がキャッシュされない。063Fh で L1/L2 の WB/WT と有効/無効を切り替える | [UNDOC-MEM] I/O 043Dh/043Fh/0461h/0463h/063Fh |
| 実機の 486 系チップセットが A0000-FFFFF をどう non-cacheable 指定していたか | **未確認** | — |

---

## 6. 既存のプリフェッチ窓の無効化規則(本コアの先例)

`zet_cpu_bridge` には 32 バイト × 2 窓の読み出しプリフェッチがあり、これがキャッシュの縮小版として既に動いている。
採用している規則は次のとおり(`core zet_cpu_bridge.sv:578-640`、`:1222-1245`)。

| 規則 | 内容 | 行 |
|---|---|---|
| 対象 | `pc98_sdram_hits && !pc98_gvram_hits`。素の SDRAM だけを対象にし、グラフィック窓、穴、I/O は除く。シャドウ境界の 32KB ブロックをまたがない | `:603-607`、`:742-747` |
| ゲストの書き込み | 重なるセクタを書き込みが SDRAM に届く前に無効化する(`pf_wkill` のときは全窓) | `:595-598`、`:1234-1235` |
| I/O 書き込み | **すべての I/O 書き込みで全窓をフラッシュする**(バンク、シャドウ、ウェイトのレジスタが地図を動かすため) | `:597-598`、`:1233` |
| DMA | `!bus_ours`(HOLD 許可)で全窓をフラッシュする。DMAC の書き込みはブリッジを通らないため | `:598-600`、`:1233` |
| F バンク | `bios_shadow_flag` のエッジで全窓をフラッシュする | `:629-636`、`:1233` |

z86 本体には元々 `cache` モジュールがあったが、本コアでは `z86_wbif` に置き換えて、キャッシュなしで Wishbone 化している。
そのとき「書き込みをライン読みより先に出す」順序にした。これは ITF のハンドオーバ用スタブ 0000:04F8 を書き換えた直後に far jump する経路で、書き換え前のバイトを読む不具合があったためである(`core z86/z86_wbif.sv:1-27`)。
**自己書き換えコードに対する I キャッシュのコヒーレンスは、実際のブート経路で要求されている。**

---

## 7. 未確認事項のまとめ

| 項目 | 状況 |
|---|---|
| VX(286)/RA に 0461h/0463h/043Fh 80h/82h があるか | [UNDOC-MEM] は「386 機」「RA2」に言及している。VX は未確認 |
| VX/UV/RA の DMA チャネル表がどの区分に入るか | [UNDOC-DMA] の明示リストにない。「その他の機種」区分と推定 |
| A5000-A7FFF の実機での挙動 | 未確認(np21w は素の mem) |
| 本コアで DMA がグラフィック窓(A8000-)に当たったときの経路 | 未確認 |
| `fdd_ramimg` の SDRAM 領域がゲストの 1MB とも EMS プールとも重ならないこと | 未確認(sdram_shim の記述のみ) |
| ROM ローダが実行中(リセット外)にゲスト可視の SDRAM を書くことがあるか | 未確認(FONT は 0x400000 でゲストからは見えない) |
| 486 機が A0000-FFFFF をどう non-cacheable に指定していたか | 未確認 |

---

## 8. キャッシュ方針の提案

前提は、z86 の前段(`z86_wbif` とブリッジの間、または `z86_wbif` の内部)に、ゲストの物理アドレス(20 ビット)でタグを持つ I/D キャッシュを置くことである。

### 8.1 キャッシュ可 / 不可の範囲

| 範囲 | I | D | 書き込み方針 | 根拠 |
|---|---|---|---|---|
| **00000-9FFFF** | ○ | ○ | **write-through + no-write-allocate を推奨**(WB にするなら DMA 読み出しのスヌープとフラッシュが必要) | 副作用がない(§2.1)。他の書き手は DMA だけで(§4)、DMA はブリッジを迂回する(`core zet_cpu_bridge.sv:598`)。WT なら FDC の WRITE DATA(メモリ→FDC)は SDRAM の値をそのまま読めるので、スヌープは DMA の**書き込み**だけでよい |
| **E8000-F7FFF** | ○ | ○ | 読み専用。書き込みでキャッシュを更新しない(RAM.sv が書き込みを捨てるので、更新すると食い違う) | ROM で書き込み保護されている(`core chipset/HDL/RAM.sv:277`)。386 機の 053Dh シャドウはこのコアにない |
| **F8000-FFFFF** | ○ | ○ | 読み専用。**043Dh 書き込み(`bios_shadow_flag` の変化)で範囲を無効化する**。または bank ビットをタグに含める | ITF/BIOS のバンク(§2.6)。実機の 486 機も 043Dh で FLUSH# する([UNDOC-MEM]) |
| C0000-CFFFF(EMS) | △ | △ | WT。**08E1h-08E9h 書き込みで C0000-CFFFF を無効化する**。または窓ごとのマップ値をタグに含める | 同じアドレスの中身がページ書き込みで変わる(`np21w io/emsio.c:9-30`)。未マップ時は空き(FFh)なので、マップされていない窓は対象外にする |
| D0000-D00FF(xrom)、D2000-D2FFF(SCSI ROM) | △ | △ | 読み専用 | 本コアでは静的な ROM(BRAM/定数)。ただし np21w と実機では SCSI ROM がバンク切替され(`np21w cbus/scsiio.c:108-116`)、D0000-DFFFF は 4KB 単位で RAM にもなる。**初期実装では対象外にし、効果を測ってから入れる** |
| C0000-DFFFF のそれ以外(穴) | × | × | — | 何も応答しない。POST の容量探索がこの FFh を見ている(`core chipset/HDL/RAM.sv:234-243`) |
| A0000-A3FFF(TVRAM) | × | △ | 入れるとしても WT。かつ A3FE0-A3FFF と、アトリビュートの奇数番地は対象外 | 副作用はなく、書くのは CPU だけ(DMA は AEN で遮断)。ただし「書いても値が変わらない」番地がある(§2.2)。BRAM で既に速いので**利点は小さく、非推奨** |
| **A3FE0-A3FFF** | × | × | — | メモリスイッチ。書き込み保護の規則が np21w(68h)と本コア(常に保護)で異なる |
| **A4000-A4FFF**(CG 窓) | × | × | — | 中身がポート A1h/A3h/A5h で変わる(§2.3) |
| A5000-A7FFF | × | × | — | 穴 |
| **A8000-BFFFF** | × | × | — | TCR/EGC の読み出し副作用、TDW/RMW/EGC の書き込み変換、GDC という別の書き手、A6h/7Ch/6Ah による意味の切り替え(§2.4) |
| **E0000-E7FFF** | × | × | — | 16 色時はプレーン E(上と同じ理由)、8 色時は穴。6Ah で有無が変わる |

実装上の判定は `pc98_sdram_hits(a, analog) && !pc98_gvram_hits(a, analog)` から A0000-A7FFF を除いたものになり、プリフェッチ窓の `pf_ok`(`core zet_cpu_bridge.sv:742-747`)と同じ式になる。
C0000-CFFFF を入れる場合は、`ems98_win`(`core chipset/HDL/RAM.sv:254`)の項を足す。

**判定はアドレスだけで決まるべきである。** 6Ah(16 色モード)で E0000 の可否が変わるが、E0000 は常にキャッシュ不可にしておけば、`analog_mode` を判定に含める必要がなくなる。

### 8.2 無効化トリガ

| # | トリガ | 動作 | 根拠 |
|---|---|---|---|
| T1 | **DMA の書き込み**(HOLD 中に `~memory_write_n` で、アドレスはバス上の `{page, dma_address}`) | 該当ラインを無効化する(アドレススヌープ)。単純にするなら HOLD 許可で全フラッシュでもよいが、FD 転送中はバイトごとに HOLD が立つのでキャッシュが実質止まる | `core chipset/HDL/Bus_Arbiter.sv:396-410`、`np21w mem/dmav30.c:32`。プリフェッチ窓は全フラッシュを採用(`core zet_cpu_bridge.sv:1233`) |
| T2 | **043Dh 書き込み**、または `bios_shadow_flag` の変化 | F8000-FFFFF を無効化する(全フラッシュでも可。頻度はブート時の数回) | `core core_top.sv:3069-3087`、`core zet_cpu_bridge.sv:629-636`、[UNDOC-MEM] 043Dh |
| T3 | **08E1h/08E3h/08E5h/08E7h/08E9h 書き込み** | C0000-CFFFF をキャッシュしている場合はその範囲を無効化する。EMS ドライバは頻繁に書くので、窓単位(16KB)の無効化が望ましい | `core pc98_ems98.sv:70`、`np21w io/emsio.c:9-30` |
| T4 | **CPU 自身の書き込み** | D キャッシュは WT で更新する。**I キャッシュの同一ラインは無効化する**(自己書き換えコード対策)。ROM 範囲(E8000-FFFFF)への書き込みではキャッシュを更新しない | `core z86/z86_wbif.sv:20-24`(ITF スタブ 0000:04F8) |
| T5 | **ROM ローダの HOLD**(`ext_access_request`) / リセット / OUT F0h | 全フラッシュする | `core core_top.sv:2540-2580`、`core chipset/HDL/Bus_Arbiter.sv:74` |
| T6 | 将来、043Fh / 0461h / 0463h / 053Dh / 1E8Eh / SCSI MEMBANK / D0000 RAM 化を実装した場合 | 影響範囲を無効化する。実機の 486 機は 043Dh/043Fh/0461h/0463h の WRITE で FLUSH# する | [UNDOC-MEM] |
| T7 | (VRAM と CG 窓をキャッシュしないなら)A4h/A6h/6Ah/7Ch/7Eh/4A0h/A1h-A5h/68h | **トリガ不要** | §8.1 でキャッシュ対象から外しているため |

**「すべての I/O 書き込みでフラッシュ」は採らない。**
プリフェッチ窓はこの規則で正しさを担保している(`core zet_cpu_bridge.sv:1233`)。しかしキャッシュでこれをやると、GDC/PIC EOI/PIT/OPNA など毎秒数千回の OUT でキャッシュが空になり、効果がなくなる。
上の T2/T3/T6 のポートだけをホワイトリストでデコードする。
ポートを足したときの漏れを防ぐため、§3 の表を正とし、新しいバンク I/O を実装する変更ではこの表を必ず更新すること。

### 8.3 方針の根拠のまとめ

1. **副作用のある窓(VRAM、CG、メモリスイッチ)をアドレスで除外すれば、残りは「メモリらしいメモリ」になる。** その書き手は CPU と DMA とローダだけである。
2. **write-through を推奨する理由。** DMA の読み出し方向(メモリ→FDC)にスヌープが要らなくなる。さらに `zet_cpu_bridge` の posted write queue と 8288 のペーシングを含めた既存の書き込み順序の保証(`core zet_cpu_bridge.sv:665-680`)を変えずに済む。
3. **バンクは「切り替え I/O で範囲を無効化」で十分である。** 本コアのバンク切り替えは 043Dh(ブート時の数回)と EMS(ドライバ次第で頻繁)の 2 つしかない。EMS をキャッシュ対象から外せば、残るのは 043Dh だけになる。
4. **実機も同じ考え方をしている。** 486 機の PC-98 は、ITF 選択中はキャッシュせず、043Dh/043Fh/0461h/0463h の書き込みで FLUSH# する([UNDOC-MEM])。
