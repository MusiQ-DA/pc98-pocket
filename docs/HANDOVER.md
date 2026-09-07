# 引継ぎドキュメント(2026-09-07 夜セッション)

PC-98 for Analogue Pocket プロジェクトの引き継ぎ資料。
次のセッション(人/AI問わず)は**この文書を読んでから作業を再開すること**。

- ゴール(唯一の正): `docs/GOAL.md` — 実機で PC-98 ソフトが GDC グラフィック+FM音源つきで動く
- メモリ設計の決定: `docs/P0_MEMORY.md`(決定C: G-RAM を SDRAM に置く)、
  `docs/P0_SDRAM_DESIGN.md`、`docs/P0_CACHE_DESIGN.md`

---

## 1. ★現在位置(2026-09-07 深夜。ここだけ読めば再開できる)

**sdram_mp は BIOS の起動シーケンスの「①チャイム」までは到達し、
その直後(②ジングル・③POST表示より手前)で止まる。
画面出力に到達する前なので、映像の問題ではない。メモリ系が本命のまま。**

### 1.1 確定している実機の状態

| 構成 | 起動音(上昇3音) | 画面 |
|---|---|---|
| 純KFSDRAM(testB1/B3/B4) | ✅ 鳴る | ✅ POST 表示 |
| sdram_mp(testB7b 以降) | ✅ **鳴る**(速度が違う) | ❌ 黒い(**信号は生きている**) |

**さらに決定的 — 動く KFSDRAM の完全なシーケンス**:

```
① 上昇3音のチャイム
② 「Intel のサウンドロゴ」風のジングル
③ BIOS POST 画面が出る
```

**sdram_mp は ① で止まる。** ②も③も来ない。

→ **故障点は ① と ② の間**。画面出力より手前なので「映像側の問題」ではない。
この区間は典型的には **BIOS のメモリサイジング/メモリテスト本体**。

**上昇する3音は正常な起動音であって、エラーコードではない。**
(XT の POST エラービープは全部同じ音程。ファームウェアにもRTLにもチャイムを鳴らす
コードは無く、ゲスト 8088 が 8253 を3回プログラムして鳴らしている。)

### 1.2 ★このセッションで犯した2つの誤診(繰り返さないこと)

1. **「ビープ3回 = base 64KB RAM failure」は誤り。** 動くビルドでも同じ音が鳴る。
   ユーザーに「音階が上がるか」を聞いて初めて分かった。**ビープは回数だけでなく
   音程を確認すること。**
2. **「CPU が1つ前の値を読んでいる」も実機とは合わない。**
   `sim/tb_cpu_timing.sv` は mp で 59/64 エラーを出すが、**BIOS コードは SDRAM 上
   (0xF0000〜)にあり、読み出しが 59/64 壊れていたら CPU は1命令も実行できない。**
   実機で起動音まで鳴る以上、TB の 8088 モデル(9サイクル固定サンプル)が厳しすぎる。
   → `tb_cpu_timing` の CPU_SAMPLE は実測に合わせて較正し直す必要がある。

### 1.3 本当に効いた修正

**SDRAM I/O 制約の追加**(§3)。testB6 まで無音だったものが testB7b で起動音まで到達した。
`dram_*` ピンが全て無制約で、Fitter に目標が無く配置がビルド毎に変わっていた(§3参照)。

### 1.4 未確定: `refresh_mode = stat_refresh | busy`(sdram_kf_shim.sv)

誤診 2 に基づいて入れた変更。**CPU の実行速度を実際に変えている**
(ユーザー観測: 起動音の速度が変わった)。良し悪しは未検証。
「レイテンシに依存しない正直なハンドシェイクになる」という点では単体で正当化できるが、
**根拠にした分析は間違っていた**ので、次のセッションは
「この1行を戻したビルド」との A/B を先に取ること。

### 1.5 ★POST 04 = base 64KB メモリテストの実コード(BIOS逆アセンブル済み)

`dist/testB15/Assets/pcxt/hiroya.PCXTDEV/boot.bin`(64KB、md5 c839f483…)を
`ndisasm -b16` で読んだ。**`out 0x80, al` = POST 進行コード**が27箇所にあり、地図になる。

失敗している区間は **POST 04(`F000:E11A`)**:

```asm
E11A: mov al,4 ; out 0x80,al        ← POST 04
E11E: xor si,si / xor di,di / mov ds,di / mov es,di
E12A: mov ax,0x55aa
E12D: mov cx,0x4000
E130: rep stosw                     ← 0000:0000 から 32KB 連続ワード書き
E135: lodsw / cmp ax,0x55aa
E139: jnz E15F                      ← 不一致 → POST 54 + エラー音
E141: mov ax,0xaa55 … 同じことを別パターンで
E15D: jmp E188                      ← 合格
E15F: mov al,0x54 ; out 0x80,al ; PIT でエラー音
```

**主要な POST コード**: 00,01,02,03,04,05,06,07,08,09,10,11,12(進行)/
21,22,24,25,30,31,32,40,41,42,43,52,54,55(分岐・失敗)。
`E0C0` には「連続音を鳴らして `hlt`」の致命エラーハンドラがある。

### 1.6 ★シミュレーションでは再現できない(= 物理側の疑い)

`sim/tb_bios_memtest.sv`(新規)で **BIOS のコードそのもの**を再現した:
`rep stosw`/`lodsw` を8088のバスサイクル(9 chipset/T、4T)で隙間なく連射し、
さらに **0xFE130 からの命令フェッチを混ぜる**(BIOSコードはSDRAM上にあるので実機では必ず混ざる。
既存TBもセルフテストもこれをやっていなかった)。

**結果: ref / mp / mp_kfref すべて PASS。** 実機だけ落ちる。

→ **「全シム緑・実機だけ失敗」の型に戻った。** これは §3 の SDRAM I/O 無制約と同じ
物理クラスの疑いが濃い(実際、症状を動かしたのは制約の追加だった)。

**未解決の物理的容疑**: 読み出しパスの setup が -2.4ns 不足している件(§4)。
KFSDRAM も同値なので「制約値が悲観的」と結論したが、
**インターフェースが本当にマージナルで、mp の配置だけが線を越えている**可能性は消えていない。

### 1.7 次にやること

**故障点は「1つ目の起動音」と「2つ目のジングル」の間**に絞られた。
この2音の間で BIOS が何をしているかを特定するのが最短路。

1. **★POST コードを実機で見る**(最有力・情報量最大)。
   `out 0x80, al` を RTL で捕まえて最後の値を保持し、MMIO でソフトコアに渡して
   **OSD に表示**する。セルフテストの表示経路は動作確認済み(testB14)なので流用できる。
   これで「BIOS がどこまで進んだか」が実機で直接読める。
   予想は POST 04 で止まる(= メモリテスト)だが、確認する価値は非常に高い。
   ついでに **失敗アドレスも取れる**: POST 54 に入った瞬間の CPU アドレス/データを保持すればよい。
2. **物理側**: `-max` を実測ベースに較正し直す(§4 の -2.4ns)。
   姉妹コアの 5.9ns も 3.5ns も根拠が弱い。SDRAM の型番と tAC を確定させるのが本筋。
   `FAST_INPUT_REGISTER` は既に入っているが効果は 0.009ns だった。
3. `refresh_mode = stat_refresh | busy` の A/B(§1.4)。
   なお待ち状態の挿入は `idle` 側の修正だけで起きている(tb_bios_memtest で確認)。
4. `tb_cpu_timing` の CPU_SAMPLE 較正(§1.2-2)

## 2. ★セルフテストが表示されない件(現在の作業対象)

### 2.1 経緯

実機で「どのアドレスで何が壊れたか」を見るためのコア内蔵セルフテストを実装した
(設計: `docs/P0_SELFTEST_SPEC.md`)。**3ビルド出して実機表示は一度もゼロ。**

| ビルド | 出力手段 | 実機 |
|---|---|---|
| testB9 (#61) | OSD オーバーレイ(結果表示のみ) | スプラッシュのまま |
| testB10 (#63) | OSD + **アクセス前にバナー** + 進捗 + パイロット | スプラッシュのまま |
| testB11 (#64) | **CGA テキストVRAM 直書き**(0xB8000) | スプラッシュのまま |

testB11 の1行目 `SELFTEST START` は **SDRAM を一切使わない CGA VRAM への書き込み**。
それすら出ない。

### 2.2 潰した箇所(すべてシミュレーションで検証済み)

| 検証項目 | 手段 | 結果 |
|---|---|---|
| ファームにコードが入っているか | `llvm-nm` / `llvm-objdump` | ✅ `sdram_selftest_run` @0x31f8、main から呼出 |
| スピンループがハングしないか | 逆アセンブル | ✅ 上限2000(`li a0,0x7cf`) |
| RAM.sv レベルの ext シーケンス | **`sim/tb_ext_access.sv`(新規)** | ✅ 書き/読み/バンク1 正常(ref/mp両方) |
| CGA VRAM がガードで抜けるか | 同上 | ✅ complete=0 / 200サイクル(想定通り) |
| リセット中の 8088 status | `biu_max.v:280` | ✅ `S2_S0_OUT = 3'b111`(passive) |
| **Bus_Arbiter のホールド調停** | **`sim/tb_ext_arbiter.sv`(新規)** | ✅ granted、3アクセス完了(KF 4〜7 / mp 15サイクル) |

**= ext ポート → 調停 → RAM.sv → SDRAM の全経路は正常。**

### 2.3 残っている未検証区間(ここに原因がある)

1. **`core_top.sv` のセルフテスト・シーケンサ**(`st_state` FSM、l.1490付近)
2. **`softcpu_subsystem.sv` の MMIO**(region `0x5`、l.243付近)
3. その間の clk_pico ↔ clk_chipset ハンドシェイク

目視精査では**両方とも正しく見える**(FSM の状態遷移、`cpu_mem_addr[3:2]` デコード、
`cpu_mem_ready` によるコミット、st_req/st_done のハンドシェイク)。見つけられていない。

### 2.4 次の一手

**softcpu_subsystem + core_top のシーケンサをシミュレーションする。**
picorv32 / altsyncram / synch_3 のスタブが要る。これで最後の区間が埋まる。

> ⚠️ **CHIPSET 丸ごとは Verilator で elaborate できない。**
> `Peripherals.sv:1385` が `ide0_data_bus_out` にブロッキング/ノンブロッキング混在代入
> (`%Error-BLKANDNBLK`)。arbiter 単体なら通る(`sim/stub_saa1099.sv`、`sim/stub_vhdl.sv`
> = uart_16750 と dpram の VHDL スタブが必要。`-Wno-PROCASSWIRE` も要る)。

### 2.5 この失敗から得た教訓(繰り返さないこと)

**自分が新しく書いた RTL をシミュレーションせずに実機へ出した。**
このプロジェクトは「動作既知の参照を同じ TB に通す」という鉄則で何度も救われてきたのに、
その鉄則を他人のコード(sdram_mp)にだけ適用し、自分の追加コードには適用しなかった。
実機3往復を無駄にした。**新規 RTL は必ず TB を通してから SD に載せること。**

## 3. 技術知見(これまでのセッションで確定したもの)

1. **rbf_r パッケージ変換は「バイト内ビット順のリバース」(0x6a→0x56)。XOR 0xFF ではない。**
   CI の生 rbf は `FF×128 + 6a 6a 6a 6a 36 f4` で始まり、ビット順反転すると正規形式
   `FF×128 + 56 56 56 56 6c 2f`(SD 内278コアすべてがこの形式)。
   実証: `bitrev(build/b1/ap_core.rbf) == dist/testB1/.../bitstream.rbf_r` が
   **全 1,741,492 バイト一致**(実機 BIOS 動作実績ペア)。XOR 0xFF に読み替えると
   `00×128` 始まりになり Load error。変換コードは `scripts/package.sh`。
   パッケージ手順: `dist/testB1` をコピーして bitstream.rbf_r だけ差し替え(過去実績あり)。
2. **dram_clk は clk_chipset と半周期(180°)逆相。** リードデータの *launch* が negedge 同相
   ということは、**有効窓の中央は posedge** という意味。「逆相だから negedge で取る」は
   逆向きの誤り(testB6 で1ビルド失った)。KFSDRAM の実サンプル点 P+CL+1 posedge に
   合わせるのが唯一の正。導出は §1.1。
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
5. **SDC は `pcxt-base/src/fpga/core/core_constraints.sdc` が唯一の正**(47行→現在)。
   `apf/apf_constraints.sdc` が `read_sdc` で読む。リポジトリ直下の
   `src/fpga/core/core_constraints.sdc`(185行)は**姉妹プロジェクト由来でビルドされない**
   — PLL インスタンス名が `ic|mp1|mf_pllbase_inst|...` でこの設計には存在しない。
   数値の参照元としては有用(同一基板・同一 SDRAM 部品)だが、そのままコピーしないこと。
6. **STA の "worst-case slack" は制約したパスについてしか語らない。**
   `Unconstrained Input/Output Ports` セクションを必ず見ること。今回 SDRAM 全ピンが
   そこに並んでいた = 解析パス0本。`scripts/check_sdram_paths.tcl` が CI でこれを見張る。
7. **シミュレーション環境**: Docker `pc98-sim` イメージ(Verilator 5.020)。
   `bash sim/run_ph.sh` で tb_ram_ab を ref / mp / mp_kfref の3モード実行。
   CI(`.github/workflows/build.yml`)に全TB+ボードタイミング版を回帰登録済み。
   落とし穴: Verilator 5.020 の `fork/join` は SIGSEGV。コメント内に "verilator"
   という単語を書くとディレクティブ誤解析でエラー。
8. **ビルドは CI 一択**(13〜15分)。ローカル Docker は45分以上かかる(検証済み、使わない)。
   DNS 故障中は `scripts/tools/ghpush2.py` で push(履歴維持)、`getartifact.py <run> <dest>`
   で成果物取得、`ghpoll2.py` で状況(たまにタイムアウトするので `ghlib` 直叩きも可)。
   `diskutil eject /dev/disk4` は今回のセッションでは成功した(以前は権限エラーだった。
   失敗したら Finder をユーザーに依頼)。
9. **`SDRAM_USE_MP`(config.tcl)** = shim 経由で mp を有効化。
   `SDRAM_MP_KF_REF` も追加すると shim の末端が純KFSDRAM に変わる(バイセクト用。
   testB4 の構成。enable_refresh を KFSDRAM に直結しないとリフレッシュ間隔違反になる)。
   コメントアウトで完全にKFSDRAMに戻る(testB3 の構成)。

## 4. 環境の注意事項

- **システムDNSが壊れている**(scutil --dns → No DNS configuration available)。
  すべてのネットワークは dig ピン留め(scripts/tools/ghlib.py が内蔵)。
  修復: `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8`(ユーザー作業)
- Docker Desktop はコンテナ内 DNS が生きている(sim イメージの構築/実行は可)
- firmware ビルドは Homebrew LLVM 23(`export PATH=/opt/homebrew/opt/llvm/bin:$PATH`)
- ROM 資産: `~/Documents/lodemnc/np2rom/`(bios.rom 96KB / font.rom 288KB / sound.rom 16KB)
- 参照ソース: `~/repo/_refs/`(X68000_MiSTer, NP2kai — np2 は挙動リファレンス専用)

## 5. 次セッションの作業リスト(優先順)

### A. testB7 が ✅ の場合(P0 完了へ)

1. HANDOVER に結果を記録・commit → **P0 手順4: `gram_cache.sv` の実装**
   (設計済み: `docs/P0_CACHE_DESIGN.md`。プレーンインターリーブ配置、
   表示ラインバッファ1 + ライトバックキャッシュ8 ≒ M10K 10ブロック)
2. その後 85.9MHz 化(クロック配線が CHIPSET〜core_top に波及する別変更)、
   PCXT が引き続き DOS ブートするか確認 → P1(PC-98メモリマップ)へ

### B. testB7 が ❌ の場合(SDRAM の実 slack を読んでから、セルフテストへ)

0. **先に `ap_core.sta.rpt` の SDRAM パス slack を読む**(§1.2 で初めて数字が出るようになった)。
   閉じていないなら `FAST_INPUT_REGISTER`/`FAST_OUTPUT_REGISTER` を dram_* に付けるのが先。
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

## 6. 現在のSD / 成果物の状態

- **SD(`/Volumes/ANALOGUE`)= testB11(セルフテスト版)投入済み**(2026-09-07 夜)
  - Pocket は USB 挿しっぱなしで運用中。物理抜き差しは不要で、
    Pocket 側で USB アクセスモードに入ると Mac にマウントされる。
    書き込み後の `diskutil eject` は**残すこと**(macOS の書き込みキャッシュを流すため)
  - `Cores/hiroya.PCXTDEV/`(JSON/boot.bin は testB1 流用・検証済み)
- ローカル: `dist/testB1` 〜 `dist/testB11`、`build/artifact_{42,46,49,51,53,54,57,58,59,60,61,63,64}/`
  (git 管理外。run#54 の fit/sta レポート入り)
- リモート main = `271f84f774`(ローカル `f8f93d5` まで反映。履歴維持 push)

## 7. 大事な約束事(以前から継続)

- np2 のコードは移植しない(挙動リファレンスとしてのみ使用)
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は dig ピン留め curl / ghlib 系ツールで回避する
- **自作 RTL を自作モデルで検証するときは、動作既知の参照実装を同じ TB に通すこと**
