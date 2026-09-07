# 引継ぎドキュメント(2026-09-07 午後セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. 現在位置(ここだけ読めば再開できる)

**P0(メモリアーキテクチャ)の山場: 自作SDRAMコントローラ `sdram_mp` の実機証明。**
**testB6 を SD に投入済み・イジェクト済み。実機テスト待ち**(§2 の台帳参照)。

やっていること: desaster/openfpga-PCXT ベースのコアで SDRAM コントローラを
`KFSDRAM`(実績品)から自作 `sdram_mp`(マルチポート・バースト対応、PC-98 G-RAM 用)に
差し替える A/B。**全シミュレーションは緑なのに実機だけ BIOS まで届かない**バグを、
実機バイセクトで絞り込んでいる最中。

### 実機バイセクト台帳(全ビルド CI 成功・全シム合格のものだけ比較)

| テスト | run | 構成 | 実機結果 | 判定 |
|---|---|---|---|---|
| testB1 | #39 | 純KFSDRAM + 実firmware | ✅ BIOS POST | ベースライン(動作実績) |
| testB2 | #46 | shim + sdram_mp(2バグ修正済み) | ❌ スプラッシュ→真っ黒 | mp 経路が壊れている |
| testB3 | #49 | 現行ツリー + 純KFSDRAM | ✅ POST | **ツリー・KFSDRAM経路は健全** |
| testB4 | #51 | shimのグルー + 純KFSDRAM末端(`SDRAM_MP_KF_REF`) | ✅ POST | **shimグルーは無罪。犯人は sdram_mp 内部** |
| testB5 | #53 | mp + 幅キャスト定数 + 233µs INIT | ❌ 真っ黒 | 定数合成/INIT待ちの仮説は死んだ |
| **testB6** | **#54** | **mp + negedge DQキャプチャ** | **実機テスト待ち** | §2 の物理的根拠参照 |

症状(ユーザー観測): testB2/5 とも**スプラッシュ(ファームウェア描画)は出る→真っ黒**。
= picorv32 は正常・8088 は解放されているが、BIOS が SDRAM 依存コード
(スタック・メモリテスト)で死んでいる。メモリ破壊系と整合。

### testB6 の中身(現在最有力仮説の実装)

**デバイスクロックは逆相(180°)** — `pll.v` outclk_2 = 42.954545MHz + phase_shift 11640ps
(= 半周期)。SDRAM がリードデータを出す瞬間は**我々の falling edge と同相**。
posedge のみのサンプラは「1サイクル粒度の賭け」になり、実 tAC(最大~5.4ns)+ピン→FF
配線遅延次第で T+CL+1 も T+CL+2 も外れる(testB5 の失敗と tb_sdram_mp の1ワードずれで実証)。
KFSDRAM が同じピンで生きているのは、フリーランサンプラ+遅いフラグ消費でこの賭けを
回避しているから。

→ 修正: SDRAM コントローラの定石どおり **DQ を negedge で捕獲 → posedge で再登録**
(単発・バースト両方で窓の中央をサンプル)、`RD_DELAY = CAS_LATENCY + 1` のペアリング。

### testB6 の判定と次の一手

- ✅ **POST が出る** → sdram_mp 実機動作確定、P0 残作業へ(§5-A)
- ❌ **真っ黒** → ケーブル不要のデバッグ環境 **コア内蔵セルフテスト**を実装(§5-B)
  - 補足: Pocket は JTAG を外部に出していないので「デバッグケーブルを買う」は成立しない。
    ロジアナも BGA 内部配線に届かない。有償なら DE10-Nano+MiSTer SDRAM ボード
    (SignalTap が使える同じ Cyclone V。将来の G-RAM 開発用としての価値は大)

---

## 2. 技術知見(今回のセッションで確定したもの)

1. **rbf_r パッケージ変換は「バイト内ビット順のリバース」(0x6a→0x56)。XOR 0xFF ではない。**
   CI の生 rbf は `FF×128 + 6a 6a 6a 6a 36 f4` で始まり、ビット順反転すると正規形式
   `FF×128 + 56 56 56 56 6c 2f`(SD 内278コアすべてがこの形式)。
   実証: `bitrev(build/b1/ap_core.rbf) == dist/testB1/.../bitstream.rbf_r` が
   **全 1,741,492 バイト一致**(実機 BIOS 動作実績ペア)。XOR 0xFF に読み替えると
   `00×128` 始まりになり Load error。変換コードは `scripts/package.sh`。
   パッケージ手順: `dist/testB1` をコピーして bitstream.rbf_r だけ差し替え(過去実績あり)。
2. **dram_clk は clk_chipset と半周期(180°)逆相。** リードデータの起動は negedge 同相。
   SDRAM 入出力のタイミング設計はこの前提で行うこと(§1 の testB6 参照)。
3. **KFSDRAM(実績品)の設計値**: CL=2・BL=1・毎サイクルパイプラインREAD・
   リフレッシュは enable_refresh 駆動(バスアイドル時)+ 1024サイクル(23.8µs)強制。
   23.8µs は規格違反だが実機で動く = リフレッシュ間隔は致命要因になりにくい。
4. **自作モデルの教訓(2度やらかした)**:
   - モデルの DQ 駆動は実部品の「次データで置換されるまで保持」を再現すること
     (`sdram_model.sv` はスロット CL-1〜CL+1 の3スロット保持に修正済み)
   - **TB は必ず動作既知の参照(KFSDRAM)も同じ条件で通すこと**。
     参照が落ちるなら疑うべきはモデル/ TB 側
   - 同相クロックのモデルはこの基板では位相が違う。逆相+フライト遅延込みが
     `sim/sdram_board_model.sv`(T_CO=7ns / T_RET=8ns。実測値ではないので過信しない)
5. **シミュレーション環境**: Docker `pc98-sim` イメージ(Verilator 5.020)。
   `bash sim/run_ph.sh` で tb_ram_ab を ref / mp / mp_kfref の3モード実行。
   CI(`.github/workflows/build.yml`)に全TB+ボードタイミング版を回帰登録済み。
   落とし穴: Verilator 5.020 の `fork/join` は SIGSEGV。コメント内に "verilator"
   という単語を書くとディレクティブ誤解析でエラー。
6. **ビルドは CI 一択**(13〜15分)。ローカル Docker は45分以上かかる(検証済み、使わない)。
   DNS 故障中は `scripts/tools/ghpush2.py` で push(履歴維持)、`getartifact.py <run> <dest>`
   で成果物取得、`ghpoll2.py` で状況(たまにタイムアウトするので `ghlib` 直叩きも可)。
   `diskutil eject /dev/disk4` は今回のセッションでは成功した(以前は権限エラーだった。
   失敗したら Finder をユーザーに依頼)。
7. **`SDRAM_USE_MP`(config.tcl)** = shim 経由で mp を有効化。
   `SDRAM_MP_KF_REF` も追加すると shim の末端が純KFSDRAM に変わる(バイセクト用。
   testB4 の構成。enable_refresh を KFSDRAM に直結しないとリフレッシュ間隔違反になる)。
   コメントアウトで完全にKFSDRAMに戻る(testB3 の構成)。

## 3. 環境の注意事項

- **システムDNSが壊れている**(scutil --dns → No DNS configuration available)。
  すべてのネットワークは dig ピン留め(scripts/tools/ghlib.py が内蔵)。
  修復: `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8`(ユーザー作業)
- Docker Desktop はコンテナ内 DNS が生きている(sim イメージの構築/実行は可)
- firmware ビルドは Homebrew LLVM 23(`export PATH=/opt/homebrew/opt/llvm/bin:$PATH`)
- ROM 資産: `~/Documents/lodemnc/np2rom/`(bios.rom 96KB / font.rom 288KB / sound.rom 16KB)
- 参照ソース: `~/repo/_refs/`(X68000_MiSTer, NP2kai — np2 は挙動リファレンス専用)

## 4. 次セッションの作業リスト(優先順)

### A. testB6 が ✅ の場合(P0 完了へ)

1. HANDOVER に結果を記録・commit → **P0 手順4: `gram_cache.sv` の実装**
   (設計済み: `docs/P0_CACHE_DESIGN.md`。プレーンインターリーブ配置、
   表示ラインバッファ1 + ライトバックキャッシュ8 ≒ M10K 10ブロック)
2. その後 85.9MHz 化(クロック配線が CHIPSET〜core_top に波及する別変更)、
   PCXT が引き続き DOS ブートするか確認 → P1(PC-98メモリマップ)へ

### B. testB6 が ❌ の場合(セルフテストを実装)

1. **コア内蔵 SDRAM セルフテスト**: 起動時にパターン書き→読み戻しを mp 経路で実行し、
   **OSD(スプラッシュ描画と同じ経路)に「最初の不一致アドレス/got/want」を表示**。
   実装先の候補: softcpu firmware(`pcxt-base/src/firmware/`、MMIO 経路は
   softcpu_subsystem.sv の FDD/IDE サービスがゲストRAMへ書く経路を流用)
   か、shim 内の独立テストFSM+bridge 窓。これで実機テストが「黒かどうか」から
   「どこでどう壊れるか」に変わり、残りの切り分けが一気に速くなる
2. 並行候補: mp のリフレッシュ設計を KFSDRAM 型(enable_refresh 駆動)に寄せる、
   T_RCD/T_RP を KFSDRAM と同一サイクルに寄せる、CL=3 化 — セルフテストの観察結果が出てから

### C. 共通

- 実機テストはユーザー担当。SD 投入・イジェクト・ビルド・解析はこちら
- CI 待ちの間は次のタスクへ(ビルドは15分)
- `/goal` 継続用プロンプト(更新版):

```
docs/GOAL.md のゴール(実機で PC-98 ソフトが GDC グラフィックと FM音源つきで
実用速度で動く)に向けて進める。現在地と次の一手は docs/HANDOVER.md §1/§4 を唯一の正とし、
メモリ設計の判断は docs/P0_MEMORY.md に従う。

1イテレーションで (1) 未完タスクを1つ進める (2) 結果を HANDOVER.md に反映
(3) commit する (4) 必要なら scripts/tools/ghpush2.py で push する。

停止条件:
- 実機テストが必要になったら、SD への投入まで済ませてユーザーに依頼し停止する
- 実機バイセクトの結果が想定外だったら、深追いせず次の仮説を1つだけ用意して報告する

CI ビルド待ちの間は待たずに次のタスクへ進む。
np2 のコードは移植しない(挙動リファレンスのみ)。
```

## 5. 現在のSD / 成果物の状態

- **SD(`/Volumes/ANALOGUE`)= testB6 投入済み・イジェクト済み**(2026-09-07 夕)
  - `Cores/hiroya.PCXTDEV/`(JSON/boot.bin は testB1 流用・検証済み)
- ローカル: `dist/testB1` 〜 `dist/testB6`、`build/artifact_{42,46,49,51,53,54}/`
  (git 管理外。run#54 の fit/sta レポート入り)
- リモート main = `271f84f774`(ローカル `f8f93d5` まで反映。履歴維持 push)

## 6. 大事な約束事(以前から継続)

- np2 のコードは移植しない(挙動リファレンスとしてのみ使用)
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は dig ピン留め curl / ghlib 系ツールで回避する
- **自作 RTL を自作モデルで検証するときは、動作既知の参照実装を同じ TB に通すこと**
