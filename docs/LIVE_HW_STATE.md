# LIVE HARDWARE STATE — read before touching the Pocket (2026-09-28 ~09:00 JST)

> **ハードを共有している可能性への注意書き。** このセッション(Devin)は実機に
> 介入を残したまま止まっています。あなたが別エージェントなら、以下を読んで
> から作業してください。

## ★ RAM write-strobe 修正: 実機検証済み (2026-09-28 08:5x JST, commit 75187b8)

CI run 36358008905 のビットストリーム (USERCODE=0x0680F7B3) で
ブート経路をフル検証 — **周期性 DMA 書き込みドロップは解消**:

- BIOS の IPL 読み出しに JTAG で `fdc_ipl.hdm` セクタ 0 を供給
  → **0x1FE00 (DMAC→SDRAM 経路): 511/512 byte-exact**。唯一の差分は
  IPL 自身の `markpos` 変数 (実行の証拠)。修正前は 76/512 が
  pre-dirty 0xFF のまま残る周期性ドロップだった。
- IPL が自前で C0H0R1 を PIO 再読み → **0x40000: 512/512 byte-exact**。
- 画面に **"ISRDPE"** — IPL 全フロー走破 (result phase まで到達)。

再現手順: flash → `MGMOUNT=1` → req 待ち →
`MGSECT=/tmp/fdc_ipl.hex MGNOWAIT=1` (hex = `od -An -v -t x1 hdm` 出力)
→ 0x1FE00 dump → IPL の req で再 push → 0x40000 dump。

テスト stub 側の修正 2 点 (commit af41bbb): `putmark` の push/pop 不整合
(3 push vs 4 pop で ret がゴミへ) と `EOT=8→1` (NDMA は sector==eot まで
result phase に入らず .rs が永久ブロック)。

## 前回セッションからの状態: Pocket は復帰済み (要 再スリープ注意)

- ~03:58 JST に JTAG スキャンチェーンが全ゼロを返すようになり、
  SLD hub (`hub=00000000`) も応答しない = **FPGA 無設定**。
  直前までコアは正常動作していた → Pocket の auto-sleep か電源断が濃厚。
- `ap_core.svf` (USERCODE=067F6330, mgmt直叩き入り) の replay は
  **「コア実行中でないと nCONFIG が開かない」**ため失敗する。
  再開にはまず Pocket の電源ON + コア起動が必要。

## このセッションで実証済みのこと (commit 58104b3)

CI run 36333730260 のビットストリーム (PC98_PROBE_EXTRA 入り) で:

- **JTAG→CHIPSET mgmt 直叩きが完結** (write slot `0x86`, witness `0x27`):
  `MGMOUNT=1 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_mgmt.tcl` で
  firmware 無しに `present=01` が立つ (wr_seen=12, last=F200)。
- **FIFO 直 push → ゲストメモリ往復がバイト一致**: `MGSECT` で
  `fdc_ipl.hdm` の 1024B を `0xF20F` に push → `req` がちょうど 1024B で
  降り、stub が drain した sector_buf = 投入データ完全一致
  (E5フィルのセクタで実測)。
- **mgmt write の CDC 取りこぼし説は棄却**: 120ns パルスを clk_chipset が
  そのまま受けるので、JTAG ドライブの write は全部届く。
- **ゲスト stub 運用の罠**: stub は IF=0 で走る + iret 時 EOI を送るが、
  `.rs` 結果フェーズの長いタイムアウト中は ISR が in-service のまま
  残り IRQ1 再発火がブロックされる → 次発火まで数分待ち。

## 未解決/次の検証 (再開手順)

1. Pocket 電源ON → コア起動 → `scripts/jtag_flash.sh build/artifact_new/output_files/ap_core.sof`
   (SVF キャッシュ `build/svf_jtag/ap_core.svf` でも可)。
2. `MGMOUNT=1` で 2HD メディアを仮想マウント (firmware 不要)。
3. BASIC プロンプトで Enter キー注入 → BIOS ディスクブート →
   FDC req 発火 → `MGSECT=testdisk/fdc_ipl.hex SECTOFF=0 MGLEN=1024` で
   IPL sector を push → BIOS が DMAC 経由で 0x1FE00 にロード。
   IPL (`testdisk/fdc_ipl.asm`) は自身が PIO で C0H0R1 を再読みして
   `0x40000` に格納する → もう一度 req が立つ → 再 push。
4. **0x1FE00 (DMA 経路) と 0x40000 (PIO 経路) を `MODE=dump` で読み、
   イメージと比較** — DMAC/SDRAM 書き込み経路と FDC/FIFO 経路を分離。

## 破損の有力容疑 (floppy.v)

`floppy.v:1119,1132`: DMA モードで `dma_has_terminated` が立つと
**fifo が `8'h00` で埋められる** (TC 後の残りをゼロ埋め)。
DMAC が sector 途中で TC を出すと、以降の位置が位置保存型で 0x00 になる
= 観測されたブート時 IPL 破損 (~18% 散発ゼロ) と一致する注入経路。
upstream (dataslot→BRAM) のゼロ混入も未排除 — 上記 0x1FE00/0x40000
比較で切り分けられる。

## JTAG slot 早見表 (PC98_PROBE_EXTRA ビルド)

- write `0x81`: キーマトリクス byte (press `0x34`, release `0xB4`)
- write `0x84` / read `0x25`: guest メモリ master (jtag_memwrite.tcl)
- write `0x85` / read `0x26`: firmware FDD チャネル (要新版 firmware)
- write `0x86` / read `0x27`: **CHIPSET mgmt 直叩き** (jtag_mgmt.tcl)
  - write data = `{addr[15:0], data[15:0]}`; addr `0xF2nn`:
    reg0 present / 1 wrprot / 2 cyls / 3 spt / 4 total / 5 heads /
    6 secsize(0=512,1=1024) / **F = FIFO push**; bit7 = drive B
  - read `0x27` = `{wr_seen[7:0], last_addr[15:0], req[1:0], present[1:0]}`
    の packing = 実際は `{wr_seen,last,2'b00,req[7:6],2'b00,present[1:0]}`
- read `0x1F/0x20/0x21`: PIC {IRR,IMR,ISR,timer} / slave+kbd_irq / irq_level

### 旧セッション履歴 (IVT[8] draw_test の話)

以前のセッションで IVT[8] を draw_test に向けた記録は**揮発済み**
(FPGA 再構成で RAM ごと消えた)。以下は当時の記録として残す。

## 新しい JTAG ゲストメモリ経路(この bitstream で有効)

`POST_MONITOR` オフ・`PC98_PROBE_EXTRA` オンのデバッグビルド。
`sdram_selftest_master` (u_selftest) を JTAG から駆動 — HOLD/HLDA で
**実行中のゲストのバスを借りて** RAM を read/write する(実証済み: 0xA5 往復 OK)。

```
write slot 0x84 : 40-bit scan, waddr byte = 0x84
                  data = {2'b0, go(29), we(28), wdata(27:20), addr(19:0)}
                  go=1 で 1アクセス発行、st_done で自己解放
read  slot 0x25 : {16'h0, done(15), busy/req(14), 6'h0, rdata(7:0)}
```

スクリプト: `scripts/jtag_memwrite.tcl`

```bash
MODE=selftest   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_memwrite.tcl  # 往復検証
MODE=peek ADDR=0x80000  ...   # 1バイト読み
MODE=inject HEX=testdisk/draw_test.hex SEG=0x8000 VEC=0x08   # 注入+IVTハイジャック
```

注意: `MODE=inject` は `VEC` (default 0x08=timer auto-fire) の IVT を
ハイジャックする。**もう一度走らせると今走っているコードを上書きする**ので、
draw_test が既に動いているなら先にリセットすること。

TVRAM/GVRAM(0xA0000+, 0xB0000+ 等)はこの経路では `ram_rw_complete` が上がらず
読めない → テキスト確認は probe `0x1b` (dbg cell、read で auto-step) を使う。

## draw_test が描くもの(画面の見え方の期待値)

実行されれば: 16本の水平カラーバンド(パレット 0-15, GVRAM B/R/G/E 4プレーン)
+ GRCG TDW のシアン箱 + テキストラベル + 点滅ブロックカーソル。
**まだ実行していない** — 画面は BASIC プロンプトのまま。

## このセッションのまとめ

- ゴール: SDカード無しで `draw_test.hdm` のテストカードを出す(B案: JTAG→
  guest-mem 注入 + 割り込みベクタ起動)。
- 到達: ビットストリーム構築(GHA, native Windows)・フラッシュ・mem-write
  経路の実証・draw_test の注入とベクタ armed まで完了。**発火と画面確認は未実施**
  (ハード共有の可能性を受けて停止)。
- ボタン不動の原因は別件で判明済み: `postmon_shown=1` が `VKB_CTRL=1` を保持して
  `osd_active` が全ボタンをゲート → `postmon_shown=0` を firmware.vh に焼き込み済み。

再開するなら: IRQ0 をアンマスクして draw_test を発火させ、画面と probe 0x1b の
TVRAM ラベルで確認するだけ。

## 2026-09-28: no-media wedge = per-boot timing flake (not RAM regression)

検証シーケンス:
- `dc9a7e1` (RAM held-twin 修正版) 初回ブート wedge → RAM 修正を疑ったが
- `8848e35` (RAM 変更前) でも同一 wedge 再現 → **同じ bitstream で起動/停止が揺れる**
- `4a4aef0` / `8848e35` とも retry で "How many files" 到達 → 決定的バグではない

定量化: `scripts/boot_flake_test.sh` (JTAG reflash = 新規ブート試行) で
8848 を 5 連続 → **5/5 BOOT OK**。wedge 率は条件付きで低い。
注意: 成功時も `PIC1=0x053D0005` (ticks=5 停止) は BIOS 入力待ちの正常状態 —
wedge の判定は TVRAM テキスト有無で行うこと。

タイミング側の犯人特定 (run 525 sta_74a_intra.txt):
- 違反 -2.485ns、top100 全て同一 endpoint: `lpm_divide:Mod0` = `rtc_acc % 7`
- 起点 `pmp_wr_data_latch` (ブリッジ生データ) → Sakamoto/bcd2bin/加算 → 剰余器
- **ただしこのパスの出力は rtc_time (rtc_valid ロード 1 回のみ) — 実質休眠パス**
  → wedge の直接原因ではない可能性が高い。違反解消しても wedge が残るなら別経路
  (同期チェーンの metastability / SDRAM init 位相 / etc.) を疑う。

同時に発見した実バグ (`b662321` で修正済み):
- `{rtc_mo, rtc_acc % 7}` の `%7` が 32bit → concat 76bit → 48bit 代入で
  sec/min/hour が捨てられていた。`rtc_valid` ロードは常に壊れていた
  (weekday 機能追加以来)。`{1'b0, rtc_mo, rtc_wday_q}` に修正。
- `tb_rtc_roll.sv` 等価ベンチ: 新旧 ~1000 tick + 全月/年末境界で一致。

実機確認済み (8848):
- N-88 BASIC `Ok` 到達、`PRINT TIME$` が tick で進行 (00:00:00→00:00:01)
  ※ JTAG ブートでは host が RTC を送らないため 00:00:00 開始は正常
- `WIDTH 40` の TVRAM 偶数セル配置は正常 (描画側の stride 修正は ef77488+)

## 2026-09-28 (後半): FDD bind の確定事実 — ピッカーは Assets/pc98/common/ を見る

run 528 (c7547ce, clk_74a クリーン +2.827ns) をデプロイ → 起動は BIOS→ROM BASIC まで正常。
draw_test.hdm が bind されない問題の追跡結果:

**観測**
- `0x27`: wr_seen=4, fdd_present=00 — BIOS 起動後も mount 書き込み無し
- `FDCMD=mount` (JTAG 0x85): ok=0 — `FDD0_DISK_SIZE`=0 = **ホストが dataslot_update を一度も送っていない**
- `pc98_test.hdm` をピック → Inserted 成功 (wr_seen 4→12, present=01) — **bind→update→mount 経路は完全動作**
- `draw_test.hdm` をピック → 0x27 不変 (update すら来ない)

**原因**: ピッカーは `Assets/pc98/common/` をブラウズする。そこに **0 バイトの draw_test.hdm スタブ**が残っていて
(Sep 28 09:14 作成、過去のコピー失敗の残骸)、ユーザーが選んでいたのは常にその壊れた方。
0 バイト bind → update size=0 → `stable_size`=0 → mount しない。pc98_test.hdm は実ファイルなので動いた。

**data.json のパラメータ semantics (実測)**:
- bit0 (0x01): user-reloadable — メニューにファイルピッカーを出す
- bit1 (0x02): 起動時に `filename` をロード — **deferload スロットでは効かない** (0x203 で実験、update 来ず)
- bit9 (0x200): ピックしたファイル名を永続化
- `filename` を deferload スロットに pin しても自動 bind しない (0x201/0x203 両方で失敗)
  → Floppy A の pin は除去 (同名ピックの no-op 化も回避)

**対処 (deploy.sh)**: テストイメージは `Assets/pc98/common/draw_test.hdm` に配置 — 
ピッカーが見る場所 = ユーザーの既存ディスクと同じフォルダ。
0 バイトスタブは実ファイルで上書き済み。

**残り検証**: draw_test.hdm (common/ 実ファイル) をピック → Inserted → コア再起動 → BIOS ブート確認。

## 2026-09-28 (夜): draw_test ブート成功 + 縦揺れの原因特定

**draw_test.hdm ブート確認** (run 531, JTAG フラッシュ): ピッカーで common/ の実ファイルを選択
→ Inserted → BIOS がディスクブート → 16色バンド + GRCG cyan box + TVRAM テキストが全表示。
GRCG・SDRAM 書き込み・表示 fetch が実機で全通し。

**残症状**: カラーバンドの境界が縦方向にわずかに揺れる (静的画像なので描画側の問題)。

**調査ログ (probe 0x29 = {max_fill_clk, skip, late})**:
- LA=1 時代: underrun モードあり (fill が間に合わないと 2 行前のデータを表示)
- LA=3 化 (2f3f689, 4-bank ring): max_fill=1559 clk (< 1730 = 1 ライン) なのに
  skip=0xFF 飽和 + late ~1.2/s 増加 — **物理的に矛盾** → line_edge 偽発火の可能性

**根本原因特定 (c673738)**: `vcount` の gray 化は連続値間のみ単ビット。
wrap 439→0 では gray が 6bit 同時反転 (gray(439)=0b101101100 → 0) → 2FF が中間値を
サンプル → `line_now` が 1-2clk のゴミ値 → 偽 line_edge → fetch walk が余分に PITCH 進む
→ そのフレーム残りの fill がずれた行を読む (edge 396 の w_wrap で毎フレーム再同期、
lines 0-2 は常に正しい、3-399 が k 行ずれ = バンド揺れ)。

- skip 飽和: 偽 edge が busy 中に出るたび加算 (~50-130/s)
- late ~1/s: ゴミ値が偶然 act_tgt に一致した時のみ
- max_fill=1559: fill は常に 1 ライン以内で完了、deadline 超過ゼロ

**修正**: `line_q`/`line_edge` を「+1 ステップ or 439→0 wrap」のみ受理に変更。
ゴミ値は拒否、真値は 1clk 後に受理。self-healing (rst 後も次フレーム line 1 で再同期)。

**probe 0x2A 追加**: {nfill[15:0], late_line[8:0], fill_len[15:9]} —
launch レート・late 発火行・fill 年齢をライブ観測。修正後は skip/late=0 が期待値。

**ROM SUM ERROR 調査ログ**:
- run 531 JTAG フラッシュ後に SUM ERROR → guest F8004 が bios.rom[0x10004]=0x02 に対し 0x03
  (1bit 反転、再読みで安定) — 他 5KB は一致。ROM 領域は write-protect で JTAG 修復不可。
- **同 .sof 再フラッシュで F8004=0x02 に復旧** → ブートごとのランダムなロード破壊。
  コード領域に当たればクラッシュ、検査領域なら SUM ERROR、無害なら正常起動 —
  「起きたり起きなかったり」の wedge 機構と一致する最有力候補。

**検証結果 (c673738, JTAG フラッシュ + draw_test 描画中)**:
- probe 0x29: `0x03E40000` — skip=0, late=0 が定常で継続 (旧ビルドは数秒で FF 飽和)
- probe 0x2a: nfill ~23500/s ≈ 400 fills/frame × 56.4fps — 全 edge が正常 launch
- 実機目視: **バンドの縦揺れ消失** — torn gray wrap が原因確定
- 副次的効果: skip/late/launch が正しい計測値として使えるようになった
  (以前は偽 edge でカウンタが意味をなさなかった)

**ROM イメージ検証器 (b6c7ee0, probe 0x2B-0x2D)**:
- リセット解除 ~3ms 後に JTAG メモリマスタ系の経路で E8000-FFFFF を自動走査し
  add/xor sum を計算 (0x84 書き込み bit30 で手動再実行も可)
- loader FSM がコミットした書き込み値の stream sum + 語数も同時採取
- クリーンなブートの期待値: `0x2B=38001C78` `0x2C=C0003800` `0x2D=1C78FFFF`
- 解釈: str==期待値 かつ walk!=str → RAM.sv/sdram_mp 書き込み経路の損失 /
  str!=期待値 → bridge/host 側 / 全一致 → イメージ健全
- 3 ブート x 8KB 手動スキャンは全て 0 diff — 破壊頻度は低い (~1/数ブート)

**walk の読み出し経路自体が化ける件 (3475dca 系ビルドで実測)**:
- stream 側は完全一致 (cnt=C000, add=3800, xor=1C78) なのに walk sum が
  毎回全然違う値 (5041424B 等) — 非決定的 = **読み出し側**の問題
- 原因特定 (BUS_ARBITER の精読): `address_enable_n`(=HLDA) は cpu_ce_posedge
  でしか更新されず、walk はバイト間で ext_access_request を ~2clk しか
  落とさない。ギャップに posedge が挟まると aen は 0 化 (mux は CPU 側に
  復帰) するが、selftest master がその posedge **前**に aen=1 を読んで
  strobe を出すと、アクセス途中で mux が CPU アドレスに切り替わる。
  `memory_read_n` は `ab_memory_read_n`(=8288/DMA がコマンドを出していな
  い) なら ext strobe を通すので、CPU の fetch アドレスを読んで完了する
  = 再現性のないゴミバイト。単発の手動 memrd は JTAG 応答が ~ms 単位で
  遅いためこの窓に当たらず正常だった。
- 正しい証明: req 保持中は hold_request_ff_2 が sticky なので aen は
  posedge ごとに hold_acknowledge=1 を取り続け落ちない。一方 aen=1 でも
  ff_2=0 (降下予約済み) の stale 状態は次 posedge で必ず落ちる。よって
  **「req 保持中に aen が 1 cpu_ce 周期以上連続 high」を持って真の
  grant とする**のが必要十分。
- strict-v1 (3475dca, flash済み) は stale-1 を即座に受けるためまだ化ける。
  strict-v2 (2a6cdf4): `grant_stable` カウンタで連続 high ≥16clk を要求。
  なお「low→high エッジ必須」版は棄却 — ギャップに cpu_ce_negedge が
  無いと aen が落ちずエッジが来ない = walk ハング (単体ベンチで確認済)。
- sim/tb_strict_grant.sv: stale window での strobe 禁止 + 連続 grant の
  非デッドロックを検証 (CI ステップ追加済み)

**strict-v2 (run 543 / 355fe20) を実機投入してもまだ化ける件**:
- 手動 walk 3 回: `2B=2AE5F91C / 31B94D92 / 2D4C57E1` — 依然非決定的。
  `2C=C0003800` `2D=1C78FFFF` は常に正しい (stream 側は完璧)。
- 第二の化け経路を特定: walk はバイト間で `run`(=ext_access_request) を
  ~2clk 落とす → ギャップに cpu_ce_posedge が挟まると aen が落ち、その
  窓で CPU のメモリアクセスが受理される。その完了は我々がバスを取り
  返した**後**に COMPLETE へ到達しうる (`~read_flag→COMPLETE` は
  strobe 切断後も発火) → `ram_rw_complete` が我々の S_ACCESS 中に発火
  → **CPU の読み出しバイトを我々のデータとして加算**。単発 memrd が
  常に正しいのは間隔が ms オーダーで競合窓に当たらないため。
- strict-v3 (ec89281): **walk 中 `run` を保持** → aen が一度も落ちない
  → CPU コマンドは常に 8288 でゲート → walk 中の complete は全て我々の
  もの (≒ walk 中ゲストを ~100ms 凍結するのと同効果)。加えて
  S_GRANT で `!ram_rw_complete` 排水 (初バイトの pre-grant 外国人完了を
  待つ) + S_ACCESS で「strobe 中に line が low を見た」ことを受理条件化
  (entry 時点の stale complete 拒否)。ベンチ 4 phase 全 PASS。
- **strict-v3 実機 (run 545): `0x2B=38001C78` — 期待値と完全一致**。
  walk はついに信用できる: 格納イメージ 96KB 全バイト正しいと証明可。

**重大な回帰発見 (POST が "MEMORY XXXKB OK" に到達しない件)**:
- 症状: POST が早期に停滞。TVRAM 全空 (テキスト一切書かれず)、
  IVT 全ゼロ、bios イメージは全 96KB JTAG 比較で 0 diff (完璧)、
  CPU は実行中 (processor_ready 揺れ) だが PIC irr pending のまま
  isr=0 で進まない。毎回再現 = 確定的。
- バイセクト: c673738 = 正常に "How many files" プロンプトまでブート
  (再フラッシュで再現確認)。b6c7ee0 = 同じ停滞症状 → **回帰は
  b6c7ee0 (verifier コミット) で入った**。間に docs コミットのみ。
- 容疑者 = 自動 walk: reset_wire 落下 +3ms (POST 最脆弱期) に 96K バイト
  分のバス借用が走る。strict-v3 の完全保持でもダメだったので単なる
  arbitration tear ではない — 未解決の teardown 機構が残っている
  (guest access の中断/再開か、port 共有状態の不整合か)。
- 暫定措置 (92f5f35): 自動 walk の発火を reset_wire 落下 +~6.2s に遅延
  (POST の脆弱期を安全に通過してから。イメージは静的なので検出能力は
  不変)。手動 walk (0x84 bit30) はそのまま。

**遅延 walk (92f5f35, run 546) 実機結果 — POST 復活**:
- フラッシュ後: BIOS POST が `How many files(0-15)?` (BASIC プロンプト)
  まで完走。ファンクションキー行も正常表示。回帰解消を確認。
- 自動 walk は +6.2s で発射し `0x2B=38001C78` 完走 (期待値一致)。
  0x2C=C0003800 / 0x2D=1C78FFFF も全て正しい。
- **実行中ゲストへの手動 walk も 38001C78 で完走しゲスト無傷**
  (BASIC プロンプト維持、0x28 活動ビット揺れ継続) →
  freeze/resume 機構自体は安全で、+3ms で死んだのは POST 超初期
  (IVT 設定前〜割り込み初期化中) の凍結に特有の問題と確定。
- walk は「何時でも撃てる」わけではなく「POST 安定後に撃つ」こと
  が条件と分かった — 遅延発射は対症療法ではなく正しい使い方。

## +3ms POST 殺しのメカニズム bisect (セッション継続)

残る謎「なぜ +3ms のバス借用が POST を殺すか」を2方向から攻めた:

- **sim 再現 (tb_pc98_boot)**: arbiter の ff1/ff2/aen チェーンを忠実に
  モデル化 (`+freeze_start_us`/`+freeze_len_us`)、bridge の
  `address_enable_n` に接続。+3ms×46ms の凍結は発射→許可→解放まで
  正常動作し、**ゲストは解放後に GDC 初期化を普通に続行** — 
  凍結単体では sim の POST は殺せない (凍結以外の要因、つまり
  ext 側がバスを駆動する事自体、が残る容疑)。
- **ウォーム/コールド差 (実機で判明)**: Reset PC (ウォーム) 後の
  +3ms ストローブ walk は POST が完走 (`How many files` 到達)。
  一方コールドブート (JTAG リフラッシュ) で b6c7ee0 は**再び同じ
  死亡** (imr=FF, ticks=1, TVRAM 空) — **+3ms 脆弱窓はコールド POST
  固有**。BIOS が warm-boot 署名を検出して ITF/初期化をスキップする
  ためと考えられる (warm でも `####` 進行バーは出た)。
- **bisect 機構 (3b5132e)**: slot 0x84 bit31 で実験フラグをアーム —
  [21]=rv_early (+3ms 発射, one-shot)、[20]=rv_hold_only (selftest
  master が grant を取ったままストローブ無しで ~46ms バスを保持)。
  tb_strict_grant phase 6 で hold_only 動作を検証済み。
- **決定実験 (4ba2f60 debug build)**: rv_early=1, rv_hold_only=1 を
  config 時点でアーム → **コールドブートで自動的に +3ms・46ms
  純粋凍結が発射**。POST が死ねば犯人は「凍結そのもの(タイミング/
  中断)」、生きれば「ストローブ駆動」。発射確認は 0x2D 下位16bit
  (hold_only では jt_st_addr が E8000 に留まる)。
- **hold-only 結果 (run 36448740328)**: コールド +3ms・46ms 凍結で
  **POST 完走** (`How many files`, 0x2B=0, 0x2D=E8000) → 犯人は凍結
  ではなく **ストローブ駆動**と確定。
- **shotgun v1 (db03485)**: コールド1発で hold@3ms → read@65ms →
  256B walk@125ms → full walk@188ms を順次発射。**全ショット生存**
  (0x2E shot=4, 0x2B=38001C78 正値, BASIC 到達) → ストローブも
  +65ms 以降なら安全。致死窓 = 「+3〜65ms 内のストローブ」に限定。
- **shotgun v2**: 窓の閉じる境界を bracket — read@3/16/48ms と
  256B walk@8/28/80ms を交互配置 + full walk@140ms 対照。
  **liveness witness 追加**: ショット間のゲストバスサイクル数
  (rv_act) を各発射時に採点し、活動 64 未満で発射したショットを
  rv_deadshot にラッチ (0x2E[19:16]、犯人 = deadshot-1) —
  ゲスト死後も残りショットは発射し続けるため、署名だけでは
  犯人ショットが特定できないことへの対策。
- **shotgun v2 結果 (0718a7b の前の 56ebf4c ビルド、時刻は
  rv_delay[27:16] マッチで ~1.5ms 解像度に削減)**: 全6ショット
  **生存** — read@+1.5ms すら生きた (0x2E: deadshot=F, act=F,
  shot=6 完走, BASIC 到達)。→「窓内の1ストローブ」は致死でない。
  残る変数は**バス借り/解放のカデンス**: 致死ビルド b6c7ee0 は
  strict-grant 前で、walk が毎バイト `run` を落とす (~96K回の
  borrow/release)。v1/v2 の strict walk は連続保持だった。
- **shotgun v3 (0718a7b→8d1cb28 single-shot 化)**: b6c7ee0 カデンス
  厳密再現 — non-strict FULL walk@+1.5ms のみ (fitter 1848 LAB 制約で
  2nd shot を削除、rv_live は walk 完了でクリア→以後の guest_cyc で
  セットする sticky フラグに変更 = 「嵐を生き延びたか」の直接判定)。
- **v3 結果 + 重要な訂正**: 生存 (0x2E=0x301, 0x2B=38001C78 正値,
  BASIC 到達) — ただし後のコード精読で **shot0 は strict に化けて
  いた**と判明: `st_strict` に `rv_done` を食わせており、発射の
  1clk 後に rv_shot=1→rv_done=1→strict=1 に反転。よって v3 が実測
  したのは「strict walk@+1.5ms」で、**non-strict borrow/release
  カデンスは現行ツリーで一度もテストされていなかった**。
- **shotgun v4 (5bea7e9)**: 真の non-strict full walk@+3ms —
  st_strict を ~rv_seq 駆動に修正 + 発射を b6c7ee0 と同一時刻に。
  これが死ねばカデンスそのものが犯人 (era 差不要)、生きれば
  b6c7ee0 固有のツリー差分が残る。
- **era 分離 bisect (96eba7b, bisect-b6-nowalk)**: b6c7ee0 ツリーで
  rv_walk_go=0 だけの変更 → **POST 完走** (`How many files`,
  0x1F=053D0005)。同一ツリーで auto-walk ON=3/3死亡 vs OFF=起動
  → **+3ms walk は死の必要条件確定** (co-factor 単独では殺さない)。
- **b6nw 手動 walk (POST 後)**: 0x84 bit30 で full walk 発射 →
  署名ゴミ (0x828B6D0C) だが**ゲスト生存** (0x1F=053D0005 維持)。
  → b6c7ee0 時代の non-strict walk は安全時刻でも読み出し破損
  (guest byte 折り込み = 4c5b18d/ec89281 で後に修正済みの既知バグ)。
  誤読単体は致死でない → 死は「脆弱窓 + 時代固有の破損」の複合。
- **shotgun v4 (e3b162e)**: v3 と同一ツリー・同一構成で発射時刻のみ
  b6c7ee0 と一致 (+3ms, rv_delay[27:16]==2) — 「v3 が生きたのは
  +1.5ms だったからか、ツリー内容が違うからか」を分離する対照。
