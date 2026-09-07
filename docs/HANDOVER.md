# 引継ぎドキュメント(2026-09-06 セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

---

## 1. プロジェクトの現在位置

**ベースを desaster/openfpga-PCXT にピボット済み**(2026-09-06決定)。

- 経緯: MacLCテンプレートベースのスクラッチchassisで
  「RS: Host commands ignored」(ブリッジコマンド無応答)を解決できず。
  desaster.PCXT(実機でDOSブート実績)をユーザー実機で確認し、
  ベースをそちらに変更した。
- 詳細: `docs/PIVOT.md`, `docs/PC98_MACHINE_SPEC.md`

### B0(ベースライン)ビルド: **完了済み・SD投入済み**(2026-09-07 確認)

- ローカルDocker(raetro/quartus:pocket)ビルドは 22:45 に**途中で中断**しており
  (`/tmp/pcxtbase_build.log` は Analysis&Synthesis 途中で切れている)、
  `pcxt-base/**/output_files/` は存在しない。**ローカルビルドの成果物はない。**
- 実際に成功したのは **GitHub Actions CI**(`.github/workflows/build.yml`、
  `pcxt-base/` をマウントしてコンパイル)。アーティファクトを
  `scripts/tools/getart2.py` で取得し、00:14 に testB0 としてパッケージ済み。
- 成果物:
  - `dist/testB0/Cores/hiroya.PCXT-dev/bitstream.rbf_r` (1,744,436 B)
    ※ 純正 desaster.PCXT の rbf_r は 1,741,140 B ─ **サイズが違う=別ビルド**、
      流用ではなく我々のパイプライン産であることが確認できる
  - 先頭非FFバイト = `56 56 56 56 6c 2f`(反転済み、検証OK)
  - `dist/hiroya.PCXT-dev.zip`
- **SDカード `/Volumes/ANALOGUE` に投入済み**:
  `Cores/hiroya.PCXT-dev/` (全JSON + bitstream.rbf_r)、`Platforms/pcxt.json`

#### B0 第1回 実機テスト: ❌ Load error in core: General error

そして**原因はビットストリームではなくパッケージ側だった**ことが判明した。
以下3件の不備が同時に存在していた(いずれもロード失敗を説明しうる)。

1. **フォルダ名が `<author>.<shortname>` と一致していなかった(最有力)**
   - フォルダ `hiroya.PCXT-dev` に対し core.json は author=hiroya /
     shortname=PCXTDEV → 導出名 `hiroya.PCXTDEV` で**不一致**
   - **SD内の全278コアを検査した結果、277コアがこの規約を厳守しており、
     破っていたのは我々のB0コアだけだった**
   - エラーが出なかった TestA は `hiroya.PC98` / author=hiroya /
     shortname=PC98 で**一致**していた
   - → **Pocketはコア識別とアセット解決に `<author>.<shortname>` を使う。
     フォルダ名を必ずこれに一致させること。**
2. **必須アセット boot.bin が未配置だった**
   data.json スロット1「PCXT BIOS」は `required: true` /
   `parameters: 0x203`(bit1 = core specific)で**コア固有アセットディレクトリ**
   を参照する。純正は `Assets/pcxt/desaster.PCXT/boot.bin`。我々のコア用は皆無。
   なお `Assets/pcxt/common/` は**空**で、core specific 指定なので common では届かない。
3. **data.json の IDE スロット `size_maximum` が `0x80000000`(2GiB)だった**
   純正リリース版は `0x40000000`(1GiB)。0x80000000 は符号付き32bitで負値になるため、
   パーサ次第でロード時バリデーションを落としうる。上流 main の新しい値を
   拾ってしまったものと思われる。**ベースライン検証には不要な差分**。

加えて、SD上の core.json が手編集で LF・末尾改行なしになっていた
(純正 desaster.PCXT の JSON も LF なので改行コード自体は問題ない)。

#### 対処: testB0b(単一変数化した再パッケージ)

`dist/testB0b/` として作り直し、SDへ投入済み(2026-09-07 01:07)。

- コア名を **`hiroya.PCXTDEV`** に統一(フォルダ名 = author.shortname)
- **JSONは純正 desaster.PCXT からそのままコピー**し、core.json の
  `shortname` / `author` / `description` の3行のみ最小編集
  → data.json の 0x80000000 問題も自動的に解消
- `Assets/pcxt/hiroya.PCXTDEV/boot.bin` を配置
- 旧 `hiroya.PCXT-dev`(Cores / Assets 両方)は撤去

**検証済み**:
- SD全コアで フォルダ名 == author.shortname → 不一致 0 件
- 純正 desaster.PCXT との差分は **bitstream.rbf_r と core.json の3行のみ**
  → 実質**ビットストリームだけが変数**の理想的なA/Bになった
- SD上の rbf_r は dist と byte 一致(コピー健全)

#### B0 のビルド自体は健全(CIレポートで確認済み)

`/private/tmp/bitstream_b0/ap_core.fit.rpt` より:

- Fitter Status: **Successful**、Quartus Prime 18.1.1 Build 646 Lite
- Logic utilization 12,049 / 18,480 ALM (65%)、RAM 193/308 (63%)、
  DSP 16/66 (24%)、pins 224/224
- **Error 0 件 / Critical Warning 0 件**
- raetroイメージの Quartus は `/opt/intelFPGA/quartus` の**1つだけ**
  (バージョン取り違えの余地はない)

また、過去の Test 1–3 は「Core not ready to run」「RS: Host commands ignored」
= **ビットストリームのロードには成功していた**段階のエラーである。
つまり **raetroビルドのbitstreamは実機でロードできる**ことが既に示されており、
「raetroイメージが悪い」という仮説の根拠は弱い。

#### B0 第2回 実機テスト(testB0b): ✅ ロード成功・画面表示

**"Load error in core: General error" は解消。** 上記パッケージ不備3件が原因だったと確定。
→ **我々のビルドパイプライン(raetro/quartus:pocket + CI + パッケージ手順)は健全。**

ただし **BIOSに進まない。これは想定どおりの挙動**で、原因は firmware.vh の NOPスタブ。

RTL上の根拠(`src/fpga/core/`):
- `softcpu_subsystem.sv:220` `reg soft_guest_hold_r = 1'b1;`
  — **ゲスト(8088)は電源投入時リセット保持で起動する**
- 解除できるのは picorv32 のファームウェアだけ:
  `main.c` の `*SOFT_GUEST_HOLD = 0;`(MMIO 0x2000001C, bit0)
- `core_top.sv:473` `reset_wire = ... | soft_guest_hold;`
- `core_top.sv:1506` スプラッシュも `bios_ever_loaded_28 & ~soft_guest_hold_28` 待ち

NOPスタブ(6144×0x00000013)は一度もこのストアを実行しないので、
**8088は永久にリセット保持のまま**。BIOSに進まないのは必然。

#### firmware を実ビルドした(2026-09-07)

- **RISC-V GNUツールチェーンは不要。上流の Makefile は LLVM を使う**
  (`clang --target=riscv32 -march=rv32im` + `ld.lld` + `llvm-objcopy`)。
- ローカルに **Homebrew LLVM 23(riscv32対応)+ lld が導入済み**。
  `export PATH=/opt/homebrew/opt/llvm/bin:$PATH` で `make` が通る。
  ※ Apple の `/usr/bin/clang` は riscv ターゲット非対応なので使えない。
- **要修正点1件**: LLVM 23 では `vkb_layout.c` の文字列長ループを
  LoopIdiomRecognize が `strlen` 呼び出しに書き換えてしまい、
  ベアメタルリンクで `undefined symbol: strlen` になる。
  → Makefile の CFLAGS に **`-ffreestanding`** を追加して解決(コミット済み)。
- 成果物: text 17,442 + data 184 = 17,626 B → **4,407 / 6144 ワード**(ROM 24KB に収まる)
  先頭ワード `1580006f` = `jal x0,+0x158`(リセットベクタ)で NOP埋めではないことを確認。

**次のビルドで 8088 が解放され、FDD/IDEサービスと OSD も動くようになるはず。**

### B0 実機テストの判定基準

- ✅ BIOS POST 表示 → **我々のビルドパイプラインは健全** → 自作機械層のRTLを
  疑って部分ビセクト → P1へ
- ❌ testB0b でも Load error → パッケージ要因は出し切ったので、
  次はビルド環境を疑う。MacLCソースを raetro でビルドして実機テストする
  A/B が最短(MacLCの純正rbfは TestA で動作実績があるため差分が取れる)

---

## 2. 未解決の最重要課題

**自作ビットストリームがPocketで「Load error in core General error」/
「RS: Host commands ignored」を起こす問題。**

確定している事実:

| テスト | ビットストリーム | パッケージ | 結果 |
|---|---|---|---|
| TestA | MacLCのrbf_r(実績品) | 我々のJSON群 | ✅ エラーなし |
| Test 1 | 自作(run#28, ステータス定数, endian=1) | 我々のJSON群 | ❌ Core not ready to run |
| Test 2 | 自作(run#32/34, ステータス遷移, endian=1) | 我々のJSON群 | ❌ RS: Host commands ignored |
| Test 3 | 自作(run#36, ステータス遷移, endian=0) | 我々のJSON群 | ❌ RS: Host commands ignored |

- パッケージ(JSON群)は TestA で実証済み → **ビットストリーム側が原因**
- endian=0/1 両方、ステータス遷移あり/なし両方で失敗
- → **raetroイメージのQuartusビルドに起因する疑い**が濃厚(B0で検証中)

**B0の実機テストが分水嶺**:
- B0のrbf(無改修PCXT)が実機でBIOS POST表示 → パイプライン確定、
  自作機械層のRTLを疑って部分ビセクト
- B0のrbfも同じエラー → raetroイメージのQuartus設定/ビルド環境の問題
  (例: 圧縮設定、Quartusバージョン、Image内デフォルト設定の差分)

---

## 3. 環境の重要な注意事項(次セッションで必ず躓くポイント)

### 3.1 システムDNSが壊れている

- `scutil --dns` → "No DNS configuration available"
- curl / git / gh による名前解決が**全滅**する
- `dig @1.1.1.1 <host>` は生きているので、**全ネットワーク操作を
  digピン留めcurl(`--resolve host:443:IP`)で実行**する
- 修正はユーザー側で可能: `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8`

### 3.2 Docker Desktop

- 一度壊れていたが再インストール済み、デーモン稼働
- イメージ `raetro/quartus:pocket` プル済み(18.2GB展開)
- **ファイル共有キャッシュが古いファイルを返すことがある**
  → ビルドスクリプトは毎回新規tempディレクトリにツリーをコピーする方式([_pcxtbase/build-docker.sh参照])
- SSHセッションから `diskutil eject` / `umount` が権限エラーになる
  → Finder/ejectはユーザーに依頼

### 3.3 ヘルパースクリプト

`scripts/tools/` に保存済み(元は /tmp にあって消失危険だったもの):

| スクリプト | 用途 |
|---|---|
| ghlib.py | GitHub API共通ライブラリ(digピン留め+リトライ) |
| ghpush.py | リポジトリツリーをAPI経由でコミット+push(git push不要) |
| getart2.py | Actionsアーティファクトのダウンロード(302リダイレクト対応) |
| cilogs.py | Actionsジョブログの取得 |
| dl_release.py | GitHubリリースzipのダウンロード(302対応) |
| ghpoll2.py | Actionsの実行状況ポーリング |

※ これらは api.github.com / github.com / objects.githubusercontent.com 等の
   ホスト解決に dig を使う。DNS修復後は不要になる。

---

## 4. 確定した技術知見(今後の設計に活用)

1. **Pocket FPGA = Cyclone V 5CEBA4F23C8, 18,480 ALM / 308 M10K**
   (DE10-Nanoの約44%/55%)。MacLCの実測: emuだけで20,900 ALM = 113%オーバー。
2. **bridge_endian_little は常時0**(フレームワーク語順規約)。
   ゲストCPUのエンディアンと無関係。1にすると全コマンド無視される。
3. **ステータス遷移(1→2→3→4)はOSが観測する**。定数1だと
   「Core not ready to run」になった実績あり(ただしTest 1では
   ステータス以外の要因も混在)。
4. **rbf_r はバイトごとビット反転必須**(反転なし→Load error General error)。
   検証方法: 先頭非FFバイトが `56 56 56 56 6c 2f` になっていること。
5. **/Cores/ ルートにファイルが散落するとフレームワークエラーの原因になる**
   (実測: `cp -R dir/ dst/` の書き方ミスで発生)。
5b. **コアのフォルダ名は `<author>.<shortname>`(core.json の値)と
   完全一致させること。** 不一致だと "Load error in core: General error" になる。
   SD内278コア中277コアがこの規約を厳守している(実測)。
   アセットも `Assets/<platform>/<author>.<shortname>/` で解決される。
5c. **data.json の `size_maximum` に `0x80000000` 以上を書かない。**
   符号付き32bitで負値になる。純正PCXTのIDEスロットは `0x40000000`。
6. **openfpga-PCXTの picorv32 ファームウェア(firmware.vh)はリポジトリ未同梱**。
   **LLVM(clang --target=riscv32 + ld.lld + llvm-objcopy)でビルドする。GNUツールチェーンは不要。**
   ローカルは Homebrew LLVM 23 でビルド可:
   `export PATH=/opt/homebrew/opt/llvm/bin:$PATH && make -C pcxt-base/src/firmware`
   (Apple clang は riscv 非対応。LLVM 23 では `-ffreestanding` が必須 → Makefile に追加済み)
6b. **picorv32 は「ブートマスタ」である。** `soft_guest_hold` は 1 で起動し、
   ファームウェアが `*SOFT_GUEST_HOLD = 0`(0x2000001C)を書くまで
   **ゲストCPU(8088)はリセット保持のまま**。firmware.vh をスタブにすると
   コアはロードできてもゲストが一切動かない。PC-98機械層でも同じ制約がかかる。
7. **np2のI/Oマップは np2ソースの `iocore_attach*` 呼び出しから機械抽出可能**
   (低域0x00-0xF0は抽出済み: PC98_MACHINE_SPEC.md 参照)。
8. **容量予算(B0実測)**: シャーシ(CHIPSET以外)= 5,621 ALM / 146 M10K / 9 DSP。
   **PC-98機械層に使えるのは 12,859 ALM / 162 M10K / 57 DSP。**
   ALMは余裕、**ボトルネックは M10K(162ブロック≒202KB)**。詳細 GOAL.md §4。
9. **ROM資産の実測**: FONT.ROM は 288KB で **BRAMに入らない**(M10K全体の75%)。
   sound.rom は 16KB のサウンドボードBIOSで、**YM2608リズムROMではない**。
   リズム音源は np2 が `2608_*.WAV` で代用しており、**ダンプが存在しない**。詳細 GOAL.md R2/R3。

---

## 5. 次のセッションの作業リスト(優先順)

> **ゴールと完了条件は `docs/GOAL.md`(確定版)を参照。** 「本命」= 実機で
> PC-98 ソフトが GDC グラフィック + FM音源つきで実用速度で動くこと。

1. ~~**B1 実機テスト**~~ ✅ **2026-09-07 BIOS 到達を確認**
   - 実 firmware(CI run#39)で **BIOS が動作**。NOPスタブ時に 8088 が
     リセット保持だった件は解消 = **picorv32 のブートマスタ経路が実機で通った**
   - ※ DOS ブートは**未確認**。データスロット3/4(FDD)は deferload で
     イメージ未投入のため。PC-98 側の作業には影響しない
2. ~~**P0 手順5: 実機統合の下準備**~~ ✅ **完了**
   - `sdram_kf_shim.sv`(KFSDRAM と同一ポート)経由で `sdram_mp` を
     RAM.sv に差し込めるようにした。`config.tcl` の `SDRAM_USE_MP` で切替
   - **A/B(run#42)は実機で BIOS が出なかった。** 原因を特定して修正済み:
     シムが `idle` を「転送が無い」の意味で返していたが、KFSDRAM の `idle` は
     「コントローラが IDLE 状態」= **リフレッシュ中は 0**。加えて `refresh_mode` を
     0 固定にしていた。RAM.sv はこの2つで CPU にウェイトを入れるので、
     **リフレッシュ中のアクセスがデータ転送前に完了扱いになっていた**
     (詳細 `docs/P0_SDRAM_DESIGN.md` §7)
   - **SD は動作する B1(KFSDRAM 版)に復旧済み**
   - **TB を妥当化し、2件目のバグも発見・修正した**:
     モデルの DQ 駆動窓が1サイクル遅く(`rd_vld[cas_lat]` → 正しくは `[cas_lat-1]`)、
     直したら参照 KFSDRAM が PASS すると同時に `sdram_mp` が FAIL。
     **`RD_DELAY = CAS_LATENCY+2` は1サイクル遅く、正しくは `+1`**。
     モデルとコントローラが同じ誤解を共有していたため辻褄が合っていた
   - **現在は参照・シムとも PASS。TB がオラクルとして機能している**
   - CI に `tb_ram_ab` を両モードで回帰登録済み
   - **次の CI ビルド完成後、実機で再テストが必要**
   - シムは 42.95MHz 据え置き。85.9MHz 化はクロック配線が CHIPSET〜core_top まで
     波及して検証の変数が増えるため分離した(Fmax は Fitter で別途評価)
2. ~~**P0 手順2: SDRAM コントローラの置換**~~ ✅ **完了**
   → `pcxt-base/src/fpga/core/sdram_mp.sv`(新規実装。詳細 `docs/P0_SDRAM_DESIGN.md`)
   - SDRAMC.vhd は KFSDRAM と同アーキテクチャ階級だったため**移植せず新規実装**。
     マルチポート化とクロック 85.909 MHz 化が実質的な差分
3. ~~**P0 手順3: 帯域の実測**~~ ✅ **ゲート通過**
   - 3ポート競合 **109.7 MB/s**(要求 30 MB/s の **3.6倍**)、プロトコル違反 0
   - **撤退ライン(A への後退)は発動しない。C を続行**
4. ~~**P0 手順4: BRAM キャッシュ層の設計**~~ ✅ **設計完了 → `docs/P0_CACHE_DESIGN.md`**
   - **最重要: 4プレーンをワード単位でインターリーブして SDRAM に置く。**
     プレーンごとに 32KB 離すと CPU/EGC の1操作が4つの別ロウになり帯域が一桁落ちる
   - np2 `mem/memegc.c` で「EGC は常に同一 `ad` の4プレーンを EGCQUAD として
     1操作で扱う」ことを確認済み → 前提は成立
   - 表示ラインバッファ 1 M10K + CPU/EGC ライトバックキャッシュ 8 M10K = **計約10**
     (見積り20の半分)。BRAM 収支は **199/308、余裕109**
   - 実装(`gram_cache.sv`)と EGC 相当トレースでのヒット率測定が残り
5. **実機統合**: PLL outclk_2 を 85.909 MHz 位相シフト版へ変更 →
   `KFSDRAM` を `sdram_mp` に差し替え → **PCXT が引き続き DOS ブートするか A/B 確認**
   (既知動作と比較できるうちにやる)
6. **P1: PC-98メモリマップ** / **P2: TVRAM** / **P3: GDC** / **P4: FDC→DOS** /
   **P5: BEEP→OPN→OPNA** / **P6: EGC** / **P7: 入力・詰め**

### ビルド時間の実測(2026-09-07)

**CI(GitHub Actions)は 13〜14分で完了する。** 「1〜2時間かかる」は誤り。

| run | 内容 | 所要 |
|---|---|---:|
| #39 | quartus のみ | 13.4 分 |
| #40, #41 | sim + quartus | 13.5 / 14.2 分 |

- **sim ジョブは CI で通っている**(run#40, #41 とも `sim: success`)
**ローカル Docker ビルドは CI より遅い。CI を主経路にすること。**

| 経路 | 所要 |
|---|---|
| CI(GitHub Actions) | **12.8〜14.2 分**(全工程) |
| ローカル Docker `--fast` | **45分でまだ Analysis & Synthesis 中**(打ち切り) |

- 単純な CPU ベンチでは amd64 エミュレーションはネイティブ比 **約2倍**
  (0.476s vs 0.237s)で、QEMU にしては速い(実質 Rosetta 相当)。
  **にもかかわらず Quartus では 3.5倍以上の差が出る。**
  ベンチが軽すぎて実態を表していない(Quartus はメモリ常駐量が大きい)
- **Docker VM のメモリが 8GB しかない**(ホストは 64GB / 20コア)。これが最有力。
  VM リソースは `settings-store.json` に無く `docker desktop` CLI にも設定コマンドが
  ないため、**変更は Docker Desktop の GUI(Settings → Resources)から**。
  24GB 程度に上げれば改善する可能性がある(**未検証**)
- ローカル化の価値は速度ではなく **push 不要 / キュー待ちなし**。
  実際 run#42/43 は直列待ちしていた

### シミュレーション環境(重要)

**ローカルで Verilator が動く。** ホストの DNS は壊れているが
**Docker Desktop はコンテナに独自リゾルバを提供するので apt が通る**。

```bash
docker build -t pc98-sim sim/     # 一度だけ
bash sim/run.sh tb_sdram_mp       # 整合性 + 単ポート帯域
bash sim/run.sh tb_sdram_load     # 3ポート競合帯域
```

CI(`.github/workflows/build.yml` の `sim` ジョブ)でも回帰実行する。
落とし穴は `docs/P0_SDRAM_DESIGN.md` §4 を参照
(Verilator 5.020 の `fork/join` は SIGSEGV する、など)。

### 参照ソースの置き場所(重要)

`/tmp` は再起動で消えるため `~/repo/_refs/` に永続化済み:

| パス | 内容 |
|---|---|
| `~/repo/_refs/x68-memory/` | X68000_MiSTer の `rtl/memory/` 一式(SDRAMC/cachecont/gvram_*) |
| `~/repo/_refs/X68000_MiSTer-master.tar.gz` | 同リポジトリ全体 |
| `~/repo/_refs/NP2kai-master.tar.gz` | np2 ソース(**挙動リファレンス専用。コード移植はしない**) |

再取得する場合(DNS 故障中なので dig ピン留めが必要):

```bash
IP=$(dig +short codeload.github.com @1.1.1.1 | tail -1)
curl -sS -L --resolve "codeload.github.com:443:$IP" \
  -o out.tar.gz https://codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>
```

## 6. ユーザー環境メモ

- Pocketファームウェア 2.7(pocket_firmware_2_7.bin)
- SDカード: 15GB、多数のコア導入済み(pupdate管理)
- desaster.PCXT がインストール済みでDOSブート実績あり
  (実配置は `Assets/pcxt/desaster.PCXT/boot.bin`。`Assets/pcxt/common/` は**空**。
   PCXTのBIOSスロットは core specific 指定なので common には置けない)
- **PC-98用ROM資産あり**: `~/Documents/lodemnc/np2rom/`
  (bios.rom 96KB ✓ / font.rom 288KB ✓ / sound.rom 16KB / ITF.ROM)
  → PC-98コアのAssetsは `Assets/pc98/common/` に置く想定

## 7. 大事な約束事

- **np2のコードは移植しない**(挙動リファレンスとしてのみ使用)
- MCL86はMIT、TVRAM/GDC/OPNA周りは新規設計+既存OSS参考
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は、必ず dig ピン留め curl で回避する
