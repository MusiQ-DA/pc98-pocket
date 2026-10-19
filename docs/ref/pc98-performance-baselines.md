# PC-98 性能ベースライン — 実機の速さと「速すぎる CPU」で壊れるソフト

作成: 2026-10-18 / 対象: `z86-port` ブランチ（worktree `/private/tmp/pc98-z86`, HEAD `95d931c`）

この文書の目的は二つある。

1. z86 コア（パイプライン化された 286 クラス）の速度モード「286 8/10/12 MHz」「turbo」に、数値の目標を与える。
2. CPU が速すぎると壊れるソフトの範囲を把握する。

凡例:
- **未確認** — 一次資料で裏が取れていないもの。
- **計算値** — 本文書で算出したもの。測定値ではない。
- **未測定** — 当コアでまだ測っていないもの。

---

## 0. 要約

- **実機の基準値（CPUBENCH 0.980 の「Ratio to the first PC9801」）**
  - V30 10 MHz 機（VM11/UV11）: **3.11**
  - 286 10 MHz（VX21/UX21）: **5.69**
  - 286 12 MHz（RX2/RX21/EX/DX）: **7.07**
  - 386DX 20 MHz（RA21/DA）: **13.49**
  - 486SX 16 MHz（H98 model80）: **20.0**
  - 出典はアーカイブ同梱の `CPURACE.TXT`（1992-01-19 集計、138 機種）。測定に使える `cpubench.hdm` は既にこのリポジトリにある。
- **SuperDepth は速度非依存の設計**
  - 必要環境は作者ドキュメントで「最低でも 286 10MHz 程度」（= Ratio 約 5.7）。
  - VSYNC 割り込みとタイマ割り込みを使い、DEPTH.EXE の中に GDC VSYNC のエッジ待ちループが 19 箇所ある。
  - CPU が速すぎて壊れるのではなく、遅すぎると処理落ちする種類のソフトである。
- **速すぎると壊れるソフトは実在する**（YAKSA、RELICS、ギガンテスなど。§3）。
  - 当時の対処は、CPU 切替スイッチで V30 / 低速モード（8 MHz 相当）に落とすこと。
  - 後年はキャッシュ無効化（HSB など）でも対処した。
- **提案（§5、2026-10 の bus-faithful 改造後）**
  - 「286 8MHz / 10MHz / 12MHz」は CE 1× + Ts/Tc バス + キャッシュなしで、各々 Ratio
    **4.57 / 5.69 / 7.07 ±10%**（VX2 / VX21 / RX21 相当）を目標とする。
  - turbo はキャッシュ ON で上限なし（既測定 28.55）。速すぎて壊れるソフトは 286 モードで救う。
  - **2026-10-19 達成**: fast-serve（pf ウィンドウ = BIU キュー給電: 早期リリース + CE
    プライシング + フィル中ヒット + クレジット、df38f4f + 95ac23f）で
    **4.60 / 5.68 / 7.07 / 28.55**（±1% 以内、§4.3・§5.1 参照）。pf は paced モードの
    retail 既定 ON（443247f; 7f85bf0 は STA 違反で撤退）。
  - 旧の duty 平均合わせ設計（CPUBENCH の数値だけ合わせて命令ごとのタイミングが ±2 倍に発散）
    は 2026-10-18 に退官した。

---

## 1. 実機ベンチマーク値

### 1.1 CPUBENCH 0.980（Dhrystone 30000 ループ、手最適化 asm）

- 出典: ZOBplus 速水祐 `CPUBENCH 0.980`（1992-07-22）の同梱 `CPURACE.TXT`「CPU スピードレース 結果 1992 1/19」。
  - アーカイブは <https://ftp.vector.co.jp/00/03/369/cpubench.lzh>。ローカルでは `testdisk/cpubench.lzh`。
  - `testdisk/build_cpubench.sh` が初回ビルド時に取得する。
- 「Ratio」は初代 PC-9801（8086 5 MHz）の実行時間 69.10 s に対する比である。
- 次の 2 列は本文書の**計算値**。
  - Dhry/s = 30000 / 実行時間
  - Ratio/MHz = 公称クロック 1 MHz あたりの Ratio
- 公称 10 MHz の V30 の実クロックは 2.4576 MHz × 4 = **9.8304 MHz**。8 MHz 系は 1.9968 MHz × 4 = 7.9872 MHz。

| 機種（CPURACE.TXT 表記を整理） | CPU | 公称 MHz | Ratio | 実行時間 s | Dhry/s（計算） | Ratio/MHz（計算） |
|---|---|---|---|---|---|---|
| PC-9801（初代） | 8086 | 5 | 1.00 | 69.10 | 434 | 0.200 |
| PC-9801改 | V30 | 5 | 1.34 | 51.21 | 586 | 0.268 |
| PC-9801M / E | 8086 | 8 | 1.75 | 39.41 | 761 | 0.219 |
| PC-9801M改 / F改 | V30 | 8 | 2.30 | 29.94 | 1002 | 0.287 |
| PC-9801VM2 / VM21 / UV2 | V30 | 10 | 2.75 | 25.10 | 1195 | 0.275 |
| **PC-9801VM11 / UV11 / CV21 / LV21 / N** | **V30** | **10** | **3.11** | **22.17** | **1353** | 0.311 |
| PC-9801UF / NV | V30HL | 16 | 5.19 / 5.26 | 13.31 / 13.12 | 2254 | 0.324 |
| PC-9801VX2 | 80286 | 8 | 4.57 | 15.10 | 1987 | 0.571 |
| PC-98XA | 80286 | 8 | 4.79 | 14.41 | 2082 | 0.599 |
| **PC-9801VX21 / UX21** | **80286** | **10** | **5.69** | **12.14** | **2471** | 0.569 |
| EPSON PC-286V | 80286 | 10 | 5.39 | 12.81 | 2342 | 0.539 |
| **PC-9801RX2 / RX21 / EX / DX / LX5** | **80286** | **12** | **7.07** | **9.76** | **3074** | 0.589 |
| PC-98DO+ | V33A | 16 | 7.46 | 9.26 | 3240 | 0.466 |
| PC-9801RS21 | 386SX | 16 | 8.83 | 7.82 | 3836 | 0.552 |
| PC-9801DS / CS / ES | 386SX | 16 | 9.02 | 7.66 | 3916 | 0.564 |
| PC-9801RA2 | 386DX | 16 | 9.12 | 7.57 | 3963 | 0.570 |
| **PC-9801RA21 / DA** | **386DX** | **20** | **13.49** | **5.12** | **5859** | 0.674 |
| PC-H98 model80 | 486SX | 16 | 20.02 | 3.45 | 8696 | 1.251 |
| PC-H98 model90 | 486SX | 25 | 30.57 | 2.26 | 13274 | 1.223 |

読み取れること:

- **V30 は 1 MHz あたり約 0.29～0.31、286 / 386 は約 0.55～0.60。** 同じクロックでも 286 は V30 の約 2 倍速い。
  - 理由は、286 のバスサイクルが 2 クロック（V30 は 4 クロック）であることと、命令あたりのクロック数が少ないこと（§2）。
- **同じ V30 10 MHz でも VM2 / UV2（2.75）と VM11 / UV11（3.11）で約 13% 違う。**
  - 前期機のメモリウェイトが原因だと推測されるが、**未確認**。
  - VX2（286 8 MHz、4.57）と XA（4.79）の差も同じ性質のものと考えられる。
  - したがって「V30 10 MHz」の基準値には幅がある。
- 486 の値はベンチ本体（7208 B）が内蔵 8 KB キャッシュに収まるため過大になる（CPUBENCH.DOC の注意書き）。
- CPURACE.TXT の PC-9801F 行は Ratio 1.75 に対して実行時間が 56.26 s になっており、原表の誤記と思われる。

### 1.2 その他のベンチマーク

| ベンチ | 内容 | 入手できた数値 |
|---|---|---|
| CPUCHK 1.24（I-O DATA PK-486 付属） | PC-9801VX 10 MHz + 80287 = 1 とする比率 | RX の 80287 クロック別: 6 MHz 0.62 / 8 MHz 0.82 / 10 MHz 0.99 / 12 MHz 1.24（FPU 込みの値。出典: <http://www.amy.hi-ho.ne.jp/nakajima-jr/com/pc-9801/rx.htm>） |
| HDBENCH / BENCH98 / Landmark / Norton SI | — | まとまった PC-98 実機の値は今回見つからず、**未確認** |
| GRCG / EGC 塗り速度、VSYNC 間の描画量 | — | 実機の公表値は見つからず、**未確認**。代わりに np21w の VRAM ウェイトモデルを使う（§2.3） |

参考: EPSON PC-286 Model 0（286 10 MHz）は「当時の PC-9801VX より約 20% 高速」をうたっていた（ja.wikipedia「PC-9801シリーズ」）。CPURACE の値ではこうなる。

- PC-286V 5.39 対 VX2 4.57: +18%
- ただし VX21（10 MHz）の 5.69 よりは遅い。

### 1.3 VSYNC 1 フレームあたりの CPU クロック（計算値）

- 当コアの表示タイミングは 24.826 kHz / 440 ライン = **56.42 Hz**（`fpga/core/pc98_video_timing.sv`）。
- 1 フレームは 17.72 ms。

| CPU クロック | クロック数 / フレーム | Dhrystone / フレーム（CPURACE 換算） |
|---|---|---|
| 4.9152 MHz（V30 "5 MHz"） | 87,118 | 約 10（V30 5 MHz 586/s） |
| 9.8304 MHz（V30 "10 MHz"） | 174,236 | 約 24（VM11 1353/s） |
| 12 MHz（286） | 212,691 | 約 54（RX21 3074/s） |
| 20 MHz（386DX） | 354,484 | 約 104（RA21 5859/s） |

VSYNC 同期型のゲームでは、1 フレームの処理がこの予算に収まるかどうかで処理落ちの有無が決まる。

---

## 2. バスタイミングとウェイト

### 2.1 CPU 側の基本

- **バスサイクル長の一般値（データシート由来。PC-98 個別の実測は未確認）**
  - V30 / 8086: 最小 4 クロック。V30 9.8304 MHz では 407 ns。
  - 80286: 最小 2 クロック（パイプライン）。12 MHz では 167 ns。
- **V30 9.8304 MHz の 4 クロックは PIT 入力 2.4576 MHz のちょうど 1 tick にあたる。**
  - `bench.asm` の tick 単位でいうと、V30 10 MHz のワードアクセス 1 回は 1 tick 以上かかる（計算値）。
- **286 機のメモリウェイトと I/O ウェイトの実機値（何ウェイトか）は、今回一次資料に当たれず未確認。**
  - 上表の VX2 対 XA、VM2 対 VM11 の差が、ウェイトの影響を示す間接的な証拠になる。

### 2.2 CPU 切替と低速モード（実機の仕様）

| 世代 | 構成 | 速度切替 | 出典 |
|---|---|---|---|
| VX（前期） | 80286 8 MHz + V30 10 MHz | ディップスイッチで起動時の CPU を選ぶ | ja.wikipedia |
| VX21 / UX21 | 80286 10 MHz + V30（UX は 10 MHz 品を 8 MHz 動作） | 同上 | ja.wikipedia |
| RX（二代目） | 80286 12 MHz + V30 8 MHz | 前面スライドスイッチで 286 を 12 / 10 MHz、**V30 モードは 8 MHz 固定**。システムクロック 12 MHz で「5 MHz 系」 | nakajima-jr rx.htm |
| RA2 / RA21 / RS / ES / EX | 386 / 286 + V30 8 MHz | V30 との排他動作 | ja.wikipedia |
| DA / DS / DX 以降 | V30 を廃止 | **VM / VF 相当の速度で動く低速モード**（機種によって 10 MHz 相当か 8 MHz 相当）とソフトウェアディップスイッチ | ja.wikipedia |
| FA | i486SX 16 MHz | DIP スイッチで「i486SX 16 MHz / 80386 20 MHz 相当 / V30 8 MHz 相当」の 3 段。V30 エミュレーションモードではメモリが 640 KB 固定になり、「100% 完全互換では無い」 | nakajima-jr fa.htm |

- ja.wikipedia は V30 を残した理由を次のように書いている。
  - ゲームなどごく少数のソフトが V30 固有の命令や**動作タイミング**に依存していた。
  - それらは 286 以降では正常に動かない。
- 当時の実機の答えは「CPU 種別とクロックを落とす」ことだった。

### 2.3 np21w の待ち時間モデル（当プロジェクトの挙動基準）

| 項目 | np21w の実装 | 備考 |
|---|---|---|
| I/O アクセス | 1 回ごとに `CPU_REMCLOCK -= iocore.busclock`、`busclock = pccore.multiple` | ベースクロック 1 tick（2.4576 MHz 系で **約 0.407 µs**）をすべての I/O に課す（`io/iocore.c:636`） |
| ポート 5Fh への書き込み（ARTIC ウェイトポート） | 20 クロック。値が 0x0B / 0x20 以外ならさらに 20 クロック | `io/artic.c` `artic_o5f`。ReactOS の PC-98 ヘッダは 5Fh を「約 600 ns の遅延ポート」と定義している（<https://doxygen.reactos.org/d0/db5/sdk_2include_2reactos_2drivers_2pc98_2cpu_8h_source.html>）。Linux PC-9800 パッチも `slow_down_io` に 0x5F を使う（<https://lkml.iu.edu/0304.0/1415.html>） |
| VRAM ウェイト | 既定 `wait[] = {1,1,6,1,8,1}`（`pccore.c:122`）。TRAM 表示中 / VSYNC 中、VRAM（GVRAM 平面）表示中 **+6** / VSYNC 中 +1、GRCG / EGC 経由 表示中 **+8** / VSYNC 中 +1（CPU クロック / アクセス） | VSYNC 期間で切り替わる（`pccore.c` `screenvsync` と表示開始処理）。当コアは 3cac3cf で 5 / 10 MHz 時のみ GVRAM 分を導入済み。TRAM の +1 は未導入 |

### 2.4 当コアの現状（読んだコードの範囲）

**速度選択（2026-10-18 の bus-faithful 改造後）**

- OSD「CPU Speed」は `286 8MHz / 286 10MHz / 286 12MHz / Turbo (max)` の 4 段（`firmware/settings_ui.c`）。
- `ce_generator` は CE 列を 1× の実機クロックで作る（`fpga/core/chipset/HDL/ce_generator.sv`）:
  8.013908（75/201） / 9.830393（92/201 = 2.4576 MHz ファミリの厳密値） / 11.967435（112/201） / 21.477273 MHz（chipset clock そのもの）。
  `sim/tb_ce_rates.sv` が全モードを 0.1% 以内で検証する。
- 「286 10MHz」は `clk_select=1`、turbo は `clk_select=3` である。
  - JTAG の `jtag_superdepth.tcl` では P=0x05 / 0x07。
  - `jtag_bench.sh` の speed 引数では 1 / 3。

**バス忠実（bus-faithful）モード: paced 設定は 3 層とも実機の 286 を模倣する**

- z86 本体は `zet_clk`（clk_chipset 42.95 MHz のゲート版）でフルレートで回るが、バスアクセスは
  `cpu_bus_bridge` の 8288 バイトエンジンを通り、CE 歩調で刻まれる。
- CE は 1×（上記の周波数そのもの）= 実機 286 の CPU クロック。
- バスペアは 286 の Ts/Tc プロファイル（`pace_286`）: 連続バスサイクルは Ts+Tc の 2 クロック相当、
  アイドルからの最初のサイクルは +1 クロック、INTA は 8259 契約どおり faithful（`cpu_bus_bridge.sv`）。
- キャッシュ（`z86_cache`、16 KB）は **Turbo 専用**。paced モードは `clk_select==3` のときだけ
  cache_en（`core_top.sv`）。実機 VX2/VX21/RX にキャッシュはない。
- 旧設計の duty スロットル（Bresenham `thr_num/256`、CPUBENCH 平均合わせ）は **0 に退官**。
  JTAG slot 9 [19:12] のトリム override のため機構だけ残る。
  旧設計は「2× CE × V30 型 4T バイトエンジン × duty 平均合わせ」の 3 時間基が混在し、
  平均は合うが命令ごとのタイミングが ±2 倍に発散していた（実機整合性を失った原因）。

**I/O リカバリ**

- `z86_cache.sv` 内の `IO_GAP = 64` clk（42.95 MHz で約 1.49 µs）が、I/O サイクルの終わりから次の I/O の始まりまでの最小間隔になる。
  （旧 `z86_wbif` から `z86_cache` の WB パスへ移設済み）
- ITF の PIT チェック（OUT → `JMP $+2` ×2 → ラッチ）を通すために入れたもの。
- np21w の I/O 1 回あたり +0.407 µs より重い — bench.asm 09 IN71 で毎回測って差を追う。

---

## 3. CPU 速度に敏感な PC-98 ソフト

### 3.1 既知の事例

| タイトル | 年代 / 作者 | 症状 | 出典 |
|---|---|---|---|
| ギガンテス（COMPAC レーベル） | PC-9801M 登場直後 | 「5MHz 駆動の i8086 でも処理落ちしないが、V30 系では画面にゴミが表示され、386 以降では動作すらしない」 | <http://sunfang.la.coocan.jp/pc9801.htm> |
| YAKSA（ウルフチーム） | 未確認 | 「まともなウェイトなど最初っから入っていないので、486SX クラスのマシンでプレイすると」ゲームにならない | 同上 |
| RELICS（ボーステック） | 未確認 | 「まともなウェイトが入っていないので、486 以降の CPU などで実行するととんでもない事態」。雑誌が一時、新機種のスピード比べに使っていた | 同上 |
| AMD-98（アミューズメントボード） | ハード | 「80286 以降の CPU を搭載するマシンでは正常に動作しない」（I/O タイミング依存と推定、**未確認**） | 同上 |
| 野々村病院の人々 | エルフ | PC-9821Ra43（Celeron 433 MHz）で FM BGM が鳴らず、HSB でキャッシュを切ると鳴った（I/O タイミング依存の症状） | <https://pokug.net/entry/2025/08/02/191913> |
| 一般論 | — | V30 固有の命令や動作タイミングに依存する少数のソフトが 286 以降で動かず、そのために V30 搭載や V30 モードが続いた | ja.wikipedia「PC-9801シリーズ」 |

ここでいう「まともなウェイト」は、走査線割り込みや VSYNC のように CPU クロックで変動しないタイミングで描画レートを制御することを指す（sunfang の脚注 *6）。

**壊れ方は 2 種類ある。**

1. **ソフトループで時間を測るゲーム**（YAKSA、RELICS など）: 速すぎてゲームにならない。
2. **I/O の間隔を命令数で稼ぐコード**（AMD-98、FM 音源ドライバ、ITF の PIT チェック）: デバイスが追従できず誤動作する。

当コアでは、2 はすでに IO_GAP で対処している。1 は「10 MHz / 5 MHz」モードの正確さで対処する領域になる。

### 3.2 当時の対処法

| 方法 | 内容 | 出典 |
|---|---|---|
| CPU 切替 / 低速モード | V30 モード（8 MHz / 10 MHz）、DA 以降の「VM / VF 相当」低速モード、FA の 3 段スイッチ | §2.2 |
| キャッシュ無効化 | HSB（`HSB WI IC-`）で 486 以降の L1 を切る | pokug.net |
| GDC クロック | 5 MHz → 2.5 MHz（SuperDepth の `-G` オプションも同類） | pokug.net / DEPTH.DOC |
| 低速化 TSR | PC/AT では SLOW、AT-SLOW などがある（<https://sierrahelp.com/Utilities/SlowdownUtilities.html>）。PC-98 専用の定番の低速化 TSR 名は今回特定できず、**未確認**。Vector の CPU カテゴリには逆方向の CPUHIGH や CPUHALT がある（<https://www.vector.co.jp/vpack/filearea/dos/hardware/cpu>） | — |

### 3.3 SuperDepth（スーパーデプス）

一次資料は `testdisk/superdepth.hdm` 内の DEPTH.DOC と DEPTH.EXE。

- **作品**: Super Depth ver 1.00、(C)1991 alty & tacox / Bio_100%、第 1 回フリーソフトウェア大賞（weblio）。
- **動作環境**（DEPTH.DOC の原文）
  - 「PC-9801VM 以降の機種。要 16 色 要 MS-DOS Ver3.30 以降」
  - 「最低でも CPU は 286 10MHz 程度のものが必要です。V30 の場合でもゲームは出来ますが、処理が重くなってしまう場合があります。」
  - 「VSYNC 割り込み、タイマー割り込みを使用しているので、これを使用する TSR とは相性の悪い場合もあります。」
  - `-G`: 「CDG のクロックを強制的に 2.5MHz にします。PC-9801VM でゲームをやって画面がおかしくなったときは」
- **バイナリ確認**（本文書で実施）
  - DEPTH.EXE（イメージオフセット 0x3AC00–0x4C400）に `E4 60 A8 20 75 FA E4 60 A8 20 74 FA` が **19 箇所**ある。
    - これは `IN AL,60h / TEST AL,20h / JNZ $-4` → `… / JZ $-4` で、GDC ステータスの VSYNC ビットの立ち上がりエッジを待つループ。
  - そのほかに `OUT 64h`（CRTV 割り込みのリセット）が 3 箇所ある。
  - PIT ch0 の設定（`MOV AX,36h / OUT 77h` → `OUT 71h` ×2）もある。
- **結論**
  - SuperDepth はフレームを VSYNC に同期させる設計なので、CPU が速すぎても壊れない。
  - 必要なのは下限の速度で、286 10 MHz ≒ CPUBENCH Ratio 5.7 が作者の推奨。
  - 当コアで turbo 時に START が失敗した不具合は、プリフェッチエンジンが古いバイトを返す問題や DMA と CPU の競合など、ハードの不具合だった（`docs/` やメモリノート、git log f735517 / 17d11f0 を参照）。速度依存の問題ではない。
  - 17d11f0 では turbo と 10 MHz の両方で 40/40 回成功している。
- **未確認**: 実機の V30 10 MHz で処理落ちがどの程度出るか。

---

## 4. ローカルの計測ツール

### 4.1 `testdisk/cpubench.hdm` — CPUBENCH 0.980（FreeDOS(98) 起動）

- **ビルド**: `testdisk/build_cpubench.sh`
  - `cpubench.lzh` を Vector から取得する。
  - `neon125.hdm` から KERNEL.SYS と COMMAND.COM を取り出し、2HD の raw イメージを組む。
  - AUTOEXEC は `CPUBENCH -p` のみ。
- **測るもの**: 手最適化した Dhrystone 30000 ループ（コード + データ + スタックで 7208 B、64 KB 境界に転送して実行）の実行時間。
  - 結果は「Ratio to the first PC9801」と「Execute time」。
  - I/O 命令も INT 命令も含まない、純粋な CPU とメモリの指標である。
  - `-aXXXX` で実行セグメントを指定できる。たとえば `-aA800` なら GVRAM 上での速度も測れる（CPUBENCH.DOC）。
- **実機で走らせる**: `scripts/jtag_bench.sh testdisk/cpubench.hdm <speed> ["Execute time"] [timeout]`
  - speed は 0 = 5 MHz、1 = 10 MHz、2 = 20 MHz、3 = turbo、`clear` = OSD の設定に従う。
  - 処理の流れ:
    1. `fdd_ramimg` にアップロードする。
    2. probe slot 0x89 で速度を固定する（bit2 = override、bit[1:0] = sel、`scripts/jtag_hdload.tcl:155`）。
    3. マウントしてゲストをリセットする。
    4. 20 秒ごとに `jtag_screen.tcl` で TVRAM を読み、marker が出たら画面を出力する。
  - 前提: PC98_JTAG ビルドが Pocket で動いていること（AGENTS.md）。
  - FDD マウントは書き込み禁止なので、結果は画面にしか出ない（`docs/NP2KAI_HARNESS.md`）。
- **エミュレータ**: `tools/np2run/np2run.c`（np2kai libretro のヘッドレスドライバ）。
  - `./np2run 7200 cpubench.hdm -mark "Execute time"`

### 4.2 `testdisk/bench.hdm` — bench.asm（DOS なし、ベアメタルの IPL ベンチ）

- **ビルド**: `testdisk/build_bench.sh`（NASM → stage1 1024 B + stage2 ≤ 7 KB → 2HD raw）。
- **計時**: PIT counter0 をモード 2、分周 65536 に再設定する。tick = 1/2.4576 MHz = 0.4069 µs。
  - 1 チャンク < 65536 tick に分けて (v0 − v1) mod 65536 を積算するので、IRQ の影響を受けない。
  - FDC テストだけは INT 08h でラップ回数を数える。
- **出力**
  - TVRAM に `NN NAME .... TTTTTTTTTT`。
  - 物理 0x70000 にメールボックスを書く。word[0] = 0xBEEF（全テスト完了の印）、word[1] = 件数、各レコード = {id, tick_lo, tick_hi, units_lo, units_hi}。
  - np2run は `-beef 0x70000` で読める。

| ID | 名前 | 内容 | units | 計る対象 | V30 9.83 MHz の下限目安（計算値） |
|---|---|---|---|---|---|
| 01 | ALU5OP | add / adc / xor / sub / add + loop を 500 回 × 20 | 10000 反復 | ALU とフェッチ | — |
| 02 | LOOP | 空の `loop` 500 回 × 20 | 10000 | 分岐 | V30 LOOP（成立）13 clk ⇒ 約 3.25 tick / 反復（V30 のクロック数は**未確認**） |
| 03 | MUL | `mul bx` + add を 200 回 × 20 | 4000 | 乗算器 | — |
| 04 | STOSW32K | `rep stosw` 2048 語 × 8（0x50000） | 32768 語 | メモリ書き込み帯域 | ≥ 1 tick / 語（4 clk バス） |
| 05 | MOVSW32K | `rep movsw` 2048 語 × 8 | 32768 語 | 読み書き帯域 | ≥ 2 tick / 語 |
| 06 | LODSW32K | `rep lodsw` 2048 語 × 8 | 32768 語 | 読み出し帯域 | ≥ 1 tick / 語 |
| 07 | TVRAM8K | TVRAM への `rep stosw` | 8192 語 | TRAM ウェイト | ≥ 1 tick / 語（np21w では +1 clk） |
| 08 | GVRAM16K | A800 平面への `rep stosb`（GRCG オフ） | 16384 B | VRAM ウェイト | 表示中は 1 B あたり 4 + 6 clk（np21w） |
| 09 | IN71 | `in al,dx`（PIT ch0）512 回 × 16 | 8192 回 | I/O 1 回のコスト | np21w では命令 + 0.407 µs、当コアでは IO_GAP 1.49 µs が効く |
| 10 | NEARCALL | near call / ret を 500 回 × 20 | 10000 | スタックと分岐 | — |
| 11 | FARCALL | far call / retf を 500 回 × 20 | 10000 | セグメントロード | — |
| 13 | NEAR2ALGN | 10 と同じだが 32 B 境界に揃える | 10000 | フェッチ境界の影響 | — |
| 14 | PUSHPOP | push / pop を 500 回 × 20 | 10000 | スタックトラフィック | — |
| 12 | FDC32SEC | INT 1Bh で 2 シリンダ（1 KB × 32 セクタ） | 32 セクタ | FDC と DMA の実時間（CPU 非依存であるべき） | — |

- **実機で走らせる**: `scripts/jtag_bench.sh testdisk/bench.hdm <speed> "FDC32SEC" 120`
  - 最後に表示されるのが FDC 行なので、この marker が出れば全テスト完了。
  - 数値欄まで描画されたかは 0xBEEF で確認する。

### 4.3 過去の計測記録（docs / git log）

| 出典 | 内容 |
|---|---|
| `docs/NP2KAI_HARNESS.md` | np2kai（i386c）CPUBENCH: mult=4（9.83 MHz の VM 設定）で **Ratio 7.22 / 9.57 s**、mult=1 で **1.79 / 38.47 s**。「同じ公称クロックでも実機より約 2.3 倍速い。np2kai は上限としてしか使えない」。設定ファイルが残っていたときの 36.17 は誤り |
| 2115475（2026-10-09） | Zet 時代の tb_mem_perf、speed3: phase1 45.5k → 33.0k clk、phase7 87.5k → 49.9k（fill-on-miss 導入）。「ハードのベンチが speed1 で頭打ち」だった原因の分析 |
| `docs/PORT_OCCUPANCY.md` | SDRAM ポート A のバイト読み出し（行ヒット）は約 6～8 cycle（140～190 ns @ 42.95 MHz）。アービタはボトルネックではない |
| b94c33c / c142135 | bench.asm の 12 テスト版の導入と np2run `-beef` |
| 17d11f0（2026-10-17） | z86: SuperDepth の START → プレイが turbo / 10 MHz とも 40/40 回成功（速度の数値ではない） |
| 3864cd8（2026-10-19、USERCODE 0x07d93abf） | bus-faithful + pfスヌープ修正。CPUBENCH: pf OFF（当時の retail 既定）= **1.36 / 1.52 / 1.63**（8/10/12 MHz）、pf ON（HDPFDIS=1）= **3.19 / 3.36 / 3.54**（CE +50% に対し比 +11% のみ = 語サーブのフルバスペアが供給天井）、Turbo = **28.55**（全段階で不変、cache 支配） |
| 95ac23f（2026-10-19、USERCODE 0x07d3d6af、HDPFDIS=1） | **fast-serve**（BIU キュー給電: fillm 早期リリース + CE プライシング + フィル中ヒット + クレジット）実装後: **4.60 / 5.68 / 7.07 / 28.55**（8/10/12 MHz / Turbo、Execute 15.00 / 12.16 / 9.77 / 2.42 s）— §5.1 の目標 4.57 / 5.69 / 7.07 を **±1% 以内**で直撃、Turbo 回帰なし |
| 7f85bf0（2026-10-19） | pf を paced 既定 ON に変更したが **グレービルド**（STA: メインコアクロック域 setup −0.039 ns 違反 → 実機 pf ON で供給劣化 3.40 級 + Turbo pf ON 死亡）。撤退し 443247f が後継 |
| 443247f（2026-10-19、CI 39197520800、STA +1.426 ns 健全） | pf 既定 ON を `jtag_pf_dis` 既定 0 + 素線 pf_disable で再実装。ウォーム（ライブ JTAG リフラッシュ直後）は後述の状態問題で 3.40 級、**コールド（電源サイクル後）は 5.68 / 7.07 / 4.60 / 28.55 を再現**（95ac23f と Execute time 0.01 s 桁で一致）。**実機状態依存の発見**: ライブリフラッシュ後のウォーム再初期化では pf ON 高負荷時のみ供給劣化（3 ビルドで Execute time 0.1 s 単位の同一値 = ビルド/STA 差ではない）。運用ルール: `jtag_flash.sh` 後はベンチ前に必ずポケットの電源サイクル。SD メニューからコアをロードする実ユーザーはフル初期化されるため影響なし |
| SuperDepth 回帰（2026-10-19、95ac23f コールド） | 286 10 MHz + pf ON（P=0x0D、fast-serve 全機能）**fails=0/40**、pf OFF 対照（P=0x05）fails=0/10 — 旧 3/50 RET 腐敗はスヌープ修正（commit 3）+ fast-serve 層で根治。pf 既定 ON の安全性裏付け完了 |

---

## 5. コアの性能目標の提案

### 5.1 目標値（bus-faithful 改造後の 2026-10 版）

**2026-10-19 実測で全モード達成**（95ac23f、§4.3 の表参照）: 4.60 / 5.68 / 7.07 / 28.55 —
目標に対し +0.7% / −0.2% / ±0% / 回帰なし。fast-serve（BIU キュー給電）の設計根拠は
`cpu_bus_bridge.sv` の pf ウィンドウコメント参照。

| モード（OSD） | 参照機 | CPUBENCH Ratio 目標 | **実測（2026-10-19）** | Execute time 目安 | 根拠 |
|---|---|---|---|---|---|
| 286 8MHz | PC-9801VX2（i286 8 MHz） | 4.57（±10%） | **4.60**（+0.7%） | ~34 s → 実 15.00 s（pf ON） | CE 1× + Ts/Tc + BIU キュー給電（fast-serve）でバスが実機 286 と同価 |
| 286 10MHz | PC-9801VX21/UX21（i286 10 MHz） | 5.69（±10%） | **5.68**（−0.2%） | ~28 s → 実 12.16 s | 同上。92/201 はファミリ厳密値 |
| 286 12MHz | PC-9801RX21/EX/DX（i286 12 MHz） | 7.07（±10%） | **7.07**（±0%） | ~22 s → 実 9.77 s | 同上 |
| **Turbo** | 上限なし（cache ON） | ≥ 7.1 必達 | **28.55**（回帰なし） | ≤ 5.8 s → 実 2.42 s | キャッシュは Turbo 専用。速すぎて壊れるソフト（§3.1）は 286 モードで救う |

（Execute time 目安は pf OFF 時代の見積り。pf ON の実測は目安より短い = Ratio は Ratio で
正しく、元の目安が速度分だけ保守的だった。）

補助の目標（bench.asm。Turbo の値と実機の計算値を比べ、286 モードが実機比で過不足ないかを見る）:

- **04 / 06（STOSW / LODSW）**: 286 モードで 1 語あたり実機 286 のバス価格（2 クロック + ウェイト）に近いこと。
  - 大きく下回るならバス歩調が緩い、上回るなら 4T 残留か VRAM ウェイトの過大。
- **08 GVRAM16K**: 286 モードでは STOSW 系より明らかに遅いこと（np21w の +6 clk / アクセス、表示期間中）。
  - turbo ではウェイトをスキップする仕様（3cac3cf）。
- **09 IN71**: 1 回あたり約 1～1.5 µs（≈ 2.5～3.7 tick）。現状 IO_GAP=64 clk ≈ 1.49 µs。
  - IO_GAP を縮めるなら ITF の PIT チェックで回帰がないか確認すること。
- **12 FDC32SEC**: 速度モードによらず一定であること（FDD のペーシングは CPU から独立）。
  - FDD Turbo オプション（cdfb70f）のオンとオフで別々に記録する。

未解決の既知ギャップ（実測後に段階的に詰める）:

- 非 SDRAM アラインドワード（VRAM/GVRAM/TVRAM）はまだ 2 バイトペア（~4-5 クロック）。
  実機 286 は 2 クロック + ウェイト — GRCG/EGC バイトレーンの再構成が必要（stage-2）。
- 命令ごとのサイクル課金（np21w の per-instruction テーブル、option A）は MUL/LOOP 系が
  まだ合わない場合の次の一手。

### 5.2 計測手順（提案）

1. **準備**
   - CI の `.sof`（PC98_JTAG ビルド）を `scripts/jtag_flash.sh` で書き込む。
   - Pocket 上でコアを再起動して slot を送り直す（メモリノート: reflash 後に FFFF0 で止まる件）。
2. **イメージ作成**
   - `testdisk/build_cpubench.sh`
   - `testdisk/build_bench.sh`
3. **CPUBENCH を全速度で測る**
   ```sh
   for s in 0 1 2 3; do
     scripts/jtag_bench.sh testdisk/cpubench.hdm $s "Execute time" 420 \
       | grep -E "Ratio|Execute" | sed "s/^/spd$s /"
   done
   ```
   - 各速度で 3 回測り、中央値を取る。CPUBENCH は計時に BIOS タイマを使うので、ばらつきを見る。
4. **bench.asm を全速度で測る**: `scripts/jtag_bench.sh testdisk/bench.hdm $s "FDC32SEC" 120`
   - 画面の TTTT（tick）を units で割って tick / unit にする。
   - 同じイメージを `np2run -beef 0x70000` でも取り、np21w / np2kai の参照列とする（np2kai は上限としてしか使えない点に注意）。
5. **プリフェッチなどのスイッチを記録する**
   - 結果は slot 9 / 0x89 の設定（pf_dis など）と一緒に記録する。**2026-10-19 以降: pf ウィンドウは
     fast-serve（BIU キュー給電）の中核で、paced モードでは retail 既定 ON（443247f。7f85bf0 は
     STA 違反のグレービルドで撤退）。ただしライブ JTAG リフラッシュ直後のウォーム状態では
     pf ON 高負荷時に供給が劣化する（3.40 級）— 電源サイクル後に測定すること（§4.3）**。
     Turbo は pf OFF + cache ON。**
   - CI の run 番号と USERCODE も添える。
6. **判定**: §5.1 の表に当てはめる。10 MHz が上限を超えた場合は、ソフト側を直さずバス側のペーシングで落とす（メモリノート z86 port の方針）。
7. **記録先**: この文書の §4.3 の表に追記する（日付、コミット、速度、Ratio、主要 tick / unit）。

### 5.3 未解決 / 未確認の一覧

- 286 機のメモリウェイトと I/O ウェイトの実機値（何ウェイト挿入されるか）、VM2 と VM11 で差が出る原因。
- PC-98 実機の HDBENCH / BENCH98 / Landmark の値、GRCG / EGC 塗りつぶし速度の実測値。
- PC-98 専用の定番低速化 TSR の名前。
- 実機の V30 10 MHz で SuperDepth がどの程度処理落ちするか。
- ~~z86 コアの CPUBENCH と bench.asm の実測値（全速度）~~ → **CPUBENCH は 2026-10-19 に全速度で取得済み（§4.3 / §5.1）**。bench.asm per-test（09 IN71 の IO_GAP、12 FDC32SEC の速度非依存性、08 GVRAM のウェイト形状）は未測定 — 次の検収項目。

## 参照

- `testdisk/cpubench.lzh`（CPUBENCH.DOC、CPURACE.TXT）— <https://ftp.vector.co.jp/00/03/369/cpubench.lzh>
- `testdisk/bench.asm`、`testdisk/build_bench.sh`、`testdisk/build_cpubench.sh`、`scripts/jtag_bench.sh`、`scripts/jtag_hdload.tcl`、`tools/np2run/np2run.c`、`docs/NP2KAI_HARNESS.md`、`docs/PORT_OCCUPANCY.md`
- `testdisk/superdepth.hdm`（DEPTH.DOC、DEPTH.EXE）
- np21w rev106: `pccore.c`（wait[] の既定値、screenvsync）、`io/iocore.c`（busclock）、`io/artic.c`（5Fh）、`mem/memvram.c`、`mem/memtram.c`
- 当コア: `fpga/core/chipset/HDL/ce_generator.sv`、`fpga/core/cpu_bus_bridge.sv`、`fpga/core/core_top.sv`、`fpga/core/pc98_video_timing.sv`、`firmware/settings_ui.c`
- ja.wikipedia「PC-9801シリーズ」— <https://ja.wikipedia.org/wiki/PC-9801%E3%82%B7%E3%83%AA%E3%83%BC%E3%82%BA>
- 第三研究所 PC-9801RX21 / FA — <http://www.amy.hi-ho.ne.jp/nakajima-jr/com/pc-9801/rx.htm>、<http://www.amy.hi-ho.ne.jp/nakajima-jr/com/pc-9801/fa.htm>
- レビュー・PC-9801 — <http://sunfang.la.coocan.jp/pc9801.htm>
- PokuG（HSB でキャッシュを無効化）— <https://pokug.net/entry/2025/08/02/191913>
- weblio「SuperDepth」— <https://www.weblio.jp/content/SuperDepth>
- ReactOS PC-98 cpu.h — <https://doxygen.reactos.org/d0/db5/sdk_2include_2reactos_2drivers_2pc98_2cpu_8h_source.html>
- Linux PC-9800 パッチ — <https://lkml.iu.edu/0304.0/1415.html>
- Sierra Help「Slowdown Utilities」— <https://sierrahelp.com/Utilities/SlowdownUtilities.html>
