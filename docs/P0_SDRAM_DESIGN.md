# P0 手順2–3: SDRAM コントローラ設計と帯域実測(2026-09-07)

`docs/P0_MEMORY.md` の決定 C(G-RAM を SDRAM に置く)を成立させるための
コントローラ実装と、その成否を決める帯域測定の記録。

---

## 1. 結論: **ゲート通過。C を続行してよい**

3ポート競合での実測 **109.7 MB/s**(要求 30 MB/s に対し **3.6倍**)、
**SDRAM プロトコル違反 0 / データ誤り 0**。

**P0_MEMORY.md §7 の撤退ライン(A への後退)は発動しない。**

## 2. 移植元の再評価 — 「移植」ではなく「新規実装」になった

当初は `X68000_MiSTer` の `SDRAMC.vhd` を移植する計画だったが、
中身を読んだ結果 **移植する価値は限定的**と判明した。

| | KFSDRAM(現行) | SDRAMC.vhd(移植元候補) | sdram_mp(本実装) |
|---|---|---|---|
| クロック | 42.95 MHz | 80 MHz | **85.909 MHz** |
| ロウ内バースト | あり | あり | あり |
| 毎回 PRECHARGE | **する** | **する** | する |
| バンクインターリーブ | なし | **なし** | なし(将来余地) |
| ポート数 | 1 | 1 | **3(ラウンドロビン)** |
| 言語 | SystemVerilog | VHDL | SystemVerilog |

**SDRAMC は KFSDRAM と同じアーキテクチャ階級**だった。
差は (a) クロック (b) 呼び出し側が常に長いバーストでキャッシュに流し込む使い方、
の2点しかない。VHDL を混ぜる摩擦を負ってまで移植する利点がないため、
**SDRAMC を挙動リファレンスとし、SystemVerilog で新規に書いた**
(`pcxt-base/src/fpga/core/sdram_mp.sv`)。マルチポート化は本実装で追加。

## 3. 実装の要点

- **クロックは `clk_core` = 85.909091 MHz を流用する。**
  PLL(`pll.v`)は既にこれを outclk_1 として生成しており、
  `clk_chipset` (42.954545 MHz) の**正確に2倍**なので CDC が単純になる。
  → 実機統合時は outclk_2(現 42.95 MHz@180°)を 85.909 MHz の位相シフト版に
    変更すれば足りる。**PLL は素の `altera_pll` 実装なので数値の書き換えのみ。**
- **1トランザクション = ACTIVATE → CAS 連打(最大 BURST_MAX 語)→ PRECHARGE。**
  オーバーヘッド約8サイクルを 32 語で償却して効率 80%。
- **ラウンドロビン調停。** 1トランザクションずつ完結させ、read データは
  `grant` でタグ付けして共有バスに載せる。
- **アドレスは `{row, bank, col}`。** 連続するカラムブロックが別バンクに落ちるので、
  将来バンクインターリーブを足すときにデータ配置を変えずに済む。
- **バーストはカラム境界(512語)をまたいではならない。** 呼び出し側は
  アラインされたキャッシュラインフィルなので構造的に満たされる。
  コントローラは分割しない。
- **Pocket に `dram_cs` ピンは無い**ため CS は常時アサート扱いで、
  コマンドは RAS/CAS/WE のみで解釈する。`dq_io` は **アクティブLow の出力イネーブル**
  (`core_top` の `assign dram_dq = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;` に整合)。

### 実装中に潰したバグ

**read データが2サイクル早く valid になっていた。** `p_rvalid` の遅延は
CAS レイテンシだけでは足りず、`cmd` を出力側でレジスタする1サイクルと
`sdram_dq_in` を入力側でレジスタする1サイクルを足した
`RD_DELAY = CAS_LATENCY + 2` が正しい。テストベンチの読み戻し照合で検出した
(2語ぶんずれて全32語が不一致になる形で現れた)。

## 4. 検証環境

**ローカルで Verilator を動かせる。** ホストのシステム DNS は壊れているが、
**Docker Desktop はコンテナに独自リゾルバを提供しており apt が通る**ため、
`sim/Dockerfile` でシミュレーション用イメージを作れる。

```bash
docker build -t pc98-sim sim/     # 一度だけ
bash sim/run.sh tb_sdram_mp       # 整合性 + 単ポート帯域
bash sim/run.sh tb_sdram_load     # 3ポート競合帯域
```

`sim/run.sh` は Docker Desktop の資格情報ヘルパを迂回する
(SSH セッションには GUI キーチェーンが無く `docker-credential-desktop` が失敗する)。

### 落とし穴

- **Verilator 5.020 の `--timing` で `fork/join` を使い、分岐からクロック待ちを
  含むタスクを呼ぶと SIGSEGV する。** 3ポート競合は `always_ff` の
  ステートマシンで書くこと(`tb_sdram_load.sv`)。
- コメント行を `// verilator` で始めるとディレクティブと誤認される。
- `$display` の書式文字列を隣接文字列リテラルで折り返せない。

## 5. 測定結果

### 単ポート(`tb_sdram_mp`)

```
test 1 write/read-back : 32 words checked, 0 errors
test 2 sequential read : 2048 words in 2916 cycles -> 120.7 MB/s
protocol violations: 0   data errors: 0   RESULT: PASS
```

### 3ポート競合(`tb_sdram_load`、20,000 サイクル)

| ポート | 想定負荷 | バースト | 語数 | 帯域 | 最悪グラント待ち |
|---|---|---:|---:|---:|---:|
| 0 display | 32語 連続読み | 194 | 6,208 | **53.3 MB/s** | 69 cyc |
| 1 EGC | 32語 read→write | 193 | 6,176 | **53.1 MB/s** | 69 cyc |
| 2 CPU | 2語 散在 read/write | 193 | 386 | 3.3 MB/s | 99 cyc |
| **合計** | | | **12,770** | **109.7 MB/s** | 違反 0 |

- **要求 30 MB/s に対し 3.6倍。**
- バースト数が 194/193/193 で揃っており、**ラウンドロビンは公平**。
  飢餓は発生していない。

### 留意点: CPU ポートの最悪待ち時間

**99 サイクル = 1.15 µs。** V30 @ 8MHz のバスサイクル(約 500 ns)の
2回ぶんに相当する。現状は許容範囲だが、実機で CPU が遅いと感じたら
以下で改善できる(いずれも本実装の構造を変えずに可能):

1. `BURST_MAX` を 32 → 16 に下げる(最悪待ちが約半分、帯域は 80%→67% に低下)
2. CPU ポートに重み付き優先度を与える
3. バンクインターリーブを入れてトランザクション間の隙間を詰める

## 6. 次にやること

1. **BRAM キャッシュ層の設計**(P0 手順4)
   - 表示ラインバッファ(4プレーン分)/ EGC ワーキングセット / CPU アクセスキャッシュ
   - 見積り 20 M10K(`P0_MEMORY.md` §6 の C 試算)
2. **実機統合**
   - PLL outclk_2 を 85.909 MHz 位相シフト版へ変更
   - `KFSDRAM` を `sdram_mp` に差し替え、PCXT が引き続き DOS ブートするか確認
     (既知動作との A/B が取れるうちにやる)
3. その後 P1 へ


---

## 7. 実機 A/B 失敗と、そこから判明したこと(2026-09-07)

`SDRAM_USE_MP=1` のビルド(CI run#42)は **実機で BIOS が出なかった**。
KFSDRAM 版(run#39)は同じ SD・同じ JSON で BIOS に到達するので、
**差分はコントローラだけ**。

### 特定したバグ: `idle` と `refresh_mode` の意味を取り違えていた

`RAM.sv` は SDRAM コントローラの状態を2つの経路で使っている:

```systemverilog
// RAM.sv:374 付近
else if (state == IDLE)                        access_ready <= idle;
else if ((write_command) && (refresh_mode))    access_ready <= 1'b0;
else if ((read_command)  && (refresh_mode))    access_ready <= 1'b0;
```

- **KFSDRAM**: `idle = (state == IDLE)` — **リフレッシュ中は 0**。
  `refresh_mode = (state == REFRESH_PALL) || (state == REFRESH)`
- **旧 `sdram_kf_shim`**: `idle = init_done & ~busy`(リフレッシュ中も **1**)、
  `refresh_mode = 1'b0` **固定**

つまりリフレッシュ中に来た CPU アクセスに対し「**いつでも受け付けられる / 待つ必要なし**」
と答えていた。RAM.sv はウェイトを入れずにバスサイクルを終わらせるので、
**データが動く前にアクセスが完了したことになる**。リフレッシュは 7.45µs ごとに
走るので、BIOS ロード中に確実に踏む。

**修正**: `sdram_mp` に `stat_idle` / `stat_refresh` を追加し、
シムは `idle = stat_idle & ~busy` / `refresh_mode = stat_refresh` を返す。
`stat_idle` は「**このサイクルにコマンドを受け付けられる**」の意味で、
リフレッシュ中とリフレッシュ待ち中は 0。

### なぜシミュレーションで検出できなかったか

**テストベンチが `access_complete` を待っていて、`memory_access_ready` の経路を
一度も踏んでいなかった。** RAM.sv が唯一ウェイトを入れるのが
`refresh_mode` 衝突なので、そこを踏まないテストは
このバグに対して**構造的に盲目**だった。

→ `tb_ram_ab.sv` は **CPU バスサイクルを模して `memory_access_ready` を見る**
方式に書き直した(8088 @4.77MHz は 1 バスサイクル ≒ 36 チップセットクロック)。

### モデルの誤りも2件見つかった

1. **tRCD を 2 サイクル必須にしていた。** KFSDRAM は ACTIVATE の
   1サイクル後に CAS を出す。42.95MHz(23.3ns)なら tRCD 15-20ns は
   1サイクルで足りるので **KFSDRAM が正しく、モデルが厳しすぎた**
2. **リードデータ窓が1サイクルしかなかった。** 実部品の DQ はサンプリング縁の
   前後で有効で、コントローラによって latch する位置が1サイクル違う。
   2サイクルに広げた

### テストベンチの妥当化と、そこで見つかった2件目のバグ

TB が参照の KFSDRAM を PASS させられなかった原因は、**モデルの DQ 駆動窓が
1サイクル遅かった**こと。実部品は READ を取り込んだ縁 N に対し **N+CL の縁で
サンプル可能**になるので、`rd_vld[0]` を「コマンドを見た縁の直後」に立てる実装では
**`rd_vld[cas_lat-1]`** が正しい。`rd_vld[cas_lat]` は丸一サイクル遅い。

モデルを直すと **KFSDRAM が PASS**(= TB がオラクルとして妥当になった)。
そして同時に **`sdram_mp` が FAIL** し、**2件目の実機バグ**が露出した:

> **`RD_DELAY = CAS_LATENCY + 2` は1サイクル遅い。正しくは `+1`。**
>
> cmd をレジスタするので、縁 T で発行した READ は T+1 に部品へ届き、
> データは **T+1+CL** でサンプル可能。`rd_pipe[0]` は T で立つので、
> `p_rvalid` を作るスロットは `rd_pipe[CAS_LATENCY]` = `RD_DELAY-1`。

**これはシミュレーションが「モデルとコントローラで同じ誤解を共有していた」
典型例。** モデルが1サイクル遅く駆動し、コントローラが1サイクル遅く拾って
いたので辻褄が合っていた。**参照実装を同じ TB に通すことでしか露呈しない。**

### 最終結果(2026-09-07)

| テスト | 結果 |
|---|---|
| `tb_ram_ab` + **KFSDRAM(参照)** | **PASS** ← TB 妥当性の条件 |
| `tb_ram_ab` + `sdram_mp` | **PASS** |
| `tb_sdram_mp` | PASS / 123.4 MB/s |
| `tb_sdram_load` | PASS / **111.7 MB/s**(3ポート合計) |
| `tb_sdram_shim` | PASS |

**教訓: 自作モデルで自作 RTL を検証するときは、必ず「動作既知の参照実装」を
同じテストベンチに通すこと。** 参照が落ちるなら、疑うべきはモデルである。
