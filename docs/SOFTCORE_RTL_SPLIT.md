# softcore / RTL 担当区分けの確認（2026-09-22）

結論: **「ゲストからバス・タイミングとして見えるものは RTL、自己ペースで
遅延に耐えるものは softcore」という原則に現状の実装は一貫しており、
大半は適切**。ただし確認時に潜在一件（GDC 描画サーバー）と、
未配置の必須パーツ三件（DMAC / EGC / GVRAM 表示フェッチ）が判明した。

数値は run#359 のフィット実測（`build/artifact_359/output_files/ap_core.fit.rpt`）
と `softcpu_subsystem.sv` / `pc98_gdc.sv` / firmware 各ファイルの読みに基づく。

---

## 1. 原則

| 観点 | RTL に置く | softcore に置く |
|---|---|---|
| ゲスト CPU から見えるもの | バス応答・I/O ポート・割り込み・DMA の**タイミング**そのもの | — |
| リアルタイム制約 | 走査線デッドライン（映像 fetch）、サンプルレート（音源合成） | 人間ペース（UI）、準静的（計器読み） |
| スループット由来 | 1 バスを複数メモリアクセスに展開する類（正速の生命線） | APF dataslot との間の塊データ移動 |
| 決定論 | D5「正速」判定にかかるものは全て | 失敗しても画面が乱れる程度のもの |

## 2. 現状のマップ（いずれも適切）

### RTL 側

| ブロック | ファイル | なぜ RTL で正しい |
|---|---|---|
| V30 CPU（nuV30 + `v30_cpu_bridge`） | core_top | サイクル精度を D5 と引き換えに取得（7,753 ALM 実測、`scripts/measure_core.sh`） |
| ラスタ・テキスト描画・行バッファ・カーソル | `pc98_video_timing` / `pc98_text_render` / `pc98_glyph_rowbuf` | 走査線デッドライン。fetch は1文字先行の二段シフト |
| GDC 表示系レジスタ ×2 | `pc98_gdc`（MASTER=1/0） | ポート直結の即時応答。CSRW/CSRFORM/SCROLL/PITCH |
| モードフリップフロップ | `pc98_gdc_mode1` / `mode2` | OUT 68h の即時性（bitac は1文字単位で効く） |
| GRCG + 平面展開 | `pc98_grcg` + `pc98_gvram_seq` | **1 CPU バスを最大 8 メモリアクセスに展開**しゲストを cpu_ready で待たせる。D5 の本体。RAM.sv を包む構成も正しい（実績パスを汚さない） |
| TVRAM / CG 窓 / フォント | `pc98_tvram` / `pc98_cgwindow` / `pc98_font_*` | ゲスト可視の読み出しタイミング + 走査同期 fetch |
| PIC×2 / PIT / 8251 キード / BEEP / RTC | KFPC-XT 系 + `pc98_upd4990` | 割り込み・ポーリングのタイミングが仕様 |
| FDC（uPD765）・SCSI の**プロトコル部** | `floppy.v`（CHIPSET）+ `pc98_fdc_glue` / `pc98_scsi` | DRQ/INT/ステータス遷移の握手 |
| OPNA（YM2608）合成 | `pc98_opna`（jt12 ラップ） | サンプルレート・リアルタイム |
| SDRAM コントローラ | `sdram_mp`（PORTS=3）+ `sdram_kf_shim` | R1 解決済みの土台 |

### softcore 側（picorv32 @ 42.95/6 ≈ 7.16MHz、ROM 32KB / RAM 8KB）

| 機能 | ファイル | なぜ softcore で正しい |
|---|---|---|
| OSD / VKB / 設定 UI / パッド | `vkb_ui.c` / `settings_ui.c` / `dpad.c` | 人間ペース。VKB の make/break 対は 8251 へのバイト送出だけ |
| POST モニタ計器 | `postmon.c` | 準静的カウンタの読み出しと描画。MMIO 0x5000xxxx 経由 |
| ディスクイメージ streaming | `fdd_service.c` / `scsi_service.c` / `ide_service.c` | APF dataslot → mgmt FIFO。自己ペースで遅延に耐える |
| 設定ステージング + ゲスト hold | `main.c`（`SOFT_GUEST_HOLD`） | ブート時のみの仕事 |
| SDRAM セルフテスト | `sdramtest.c` | 診断ビルド専用。ゲスト停止中しか動かない設計と整合 |

**プロトコルは RTL / 塊データは softcore**（FDC・SCSI）の分割が特に良い塩梅。

## 3. ⚠ 潜在一件: GDC 描画サーバーは配線だけで、最初の VECTE で固まる

`pc98_gdc.sv` は EXECUTE 系（VECTE 0x6C 等）を受信すると:

1. `draw_pending` を立て、VECTW/EAD/TEXTW/ZOOM/WRITE モードのスナップショット 19 バイトを確保
2. **ステータスの FIFO-empty ビット（bit2）を意図的に落とす** — 実機 7220 の
   バックプレッシャの再現。「FIFO empty 待ち」ループを持つソフトはここで待つ
3. `draw_req` を出し、softcore が done-level（`0x5000015C`/`0x5000019C`）を
   トグルするのを待つ。完了時は np2 の `gdc_vectreset` 相当の VECTW 初期化も RTL 側で行う

問題:

- **サーバー側ファームウェアが存在しない**（両アドレスへ書くコードが
  firmware 中にゼロ）。→ VECTE が一度でも来ると fifo_empty が永久に立たず、
  待ちループは全員ハング。BIOS が今のところ VECTE を使わないだけで発症していない
- **softcore にゲスト実行中のメモリ書き込み経路がない**。`st_*`（セルフテスト
  マスタ）はゲスト hold 中しか仲裁に勝てない（`main.c` の
  `postmon_capture_rom` コメント）。描画するには GVRAM への専用 SDRAM
  ポート（port D）か既存ポートの仲裁追加が別途必要
- **能力が足りない可能性**。picorv32 実効 1〜2 MIPS に対し、7220 の描画は
  語/メモリサイクル程度。線分多用タイトル（Thexder 級）は 1〜2 桁足りない見込み
- 追加の EXECUTE は pending 中 unknown 計器に落ちる（キューなし）

`PC98_GDC_DESIGN.md` の「第3期はやらない。未実装コマンド計器（unk_cmd/unk_count、
パネル表示済み）で使用実績を見てから判断」は正しいシーケンシング。ただし上記の
ハングは計器としても危険なので:

> **推奨**: サーバー未搭載の間、VECTE/TEXTE を no-op 即完了
> （または数フレームでタイムアウト完了）させる暫定パッチ。
> 実装段になったら内側のピクセルループは `pc98_gvram_seq` の平面 RMW
> 機構の拡張（RTL）に寄せるのが面積的にも自然。

## 4. 未配置の必須パーツと置き場所

| パーツ | 必要な時期 | 置く場所 | 根拠 | 状況 |
|---|---|---|---|---|
| **DMAC uPD71071** | P4 / D1（DOS 起動・FDC の DMA 転送） | **RTL** | バスマスタ。DRQ/DACK をゲストがタイミングとして観測。softcore@7MHz では追従不可 | 未実装 |
| **EGC** | P6 / D5（正速） | **RTL** | バス展開型の平面演算。`pc98_gvram_seq` パターンの延長。softcore 置きは物理的に正速不可 | 未実装（GRCG のみ） |
| **GVRAM 表示フェッチ** | P3 / D2 | **RTL** | SDRAM port B はフォント用で 16 行に 1 回程度の低負荷 — 共有スケジューリングか port D 追加。**追加時は R1 の規則「data_loader DROP=0 を再確認」を守ること** | 未実装 |
| OPNA リズム音源 | P5 / D4 | **ビルド時アセット変換**（WAV→ADPCM-A）+ SDRAM 配置 + RTL フェッチ | 実行時の softcore の仕事ではない（GOAL R3「未設計」） | 未設計 |

## 5. 資源との突き合わせ（run#359 実測）

| 資源 | 使用 | 余り | 備考 |
|---|---:|---:|---|
| ALM | 17,327 / 18,480（94%） | **約 1,150** | DMAC（概算 ~1K）と EGC は両方載らない。撤退線（`config.tcl` コメント: post_monitor 484 / audio / floppy 833）の発動条件を事前に決めておくこと。post_monitor はデバッグの生命線なので最後まで残す順序を推奨 |
| M10K | 201 / 308（65%） | 107 | GVRAM ラインバッファ等には十分 |
| DSP | 11 / 66（17%） | 55 | 余裕 |
| softcore ROM/RAM | 32KB / 8KB | — | postmon が -Os/-Oz 済み。GDC サーバー等の追加で要監視 |
| FDC 2HD スループット | — | — | 1.2MB/s = 1バイト/1.6µs ≈ **11 cycle/byte @7.16MHz**。mgmt FIFO のバースト転送で捌ける設計なら問題なし。**P4 で実測** |

## 6. アクション

1. **VECTE 暫定即完了パッチ**（サーバー未搭載の間のハング防止）— 小変更、
   次回デプロイに乗せられる
2. **DMAC / EGC を RTL と明文化**（GOAL のスコープ表に配置方針を追記）
3. GDC 描画サーバーの実装形態決定: ピクセルループは `pc98_gvram_seq` 拡張（RTL）、
   コマンド解釈は現行の handshake を流用。タイトル実測（unk 計器）を入れてから
4. GVRAM フェッチのポート設計（port B 共有 vs port D 追加）+ DROP=0 再確認

---

関連: `docs/GOAL.md`（マイルストーン・資源予算）/ `docs/PC98_GDC_DESIGN.md`（第3期判断）
/ `docs/HANDOVER.md` §10（カーソル修正の経緯）

## 7. 追記 (2026-09-22, 実装後)

§3 の検証結果の修正と現状:

- **st マスタはゲスト実行中に動く**: `BUS_ARBITER.sv:59` は
  `hold_request = dma_hold_request | ext_access_request` — st_run は HOLD を上げ、
  HLDA (chipset_aen) を得て**サイクルスチール**する。「hold 中しか勝てない」は
  誤りで、postmon の ROM 読みが実証済み。よって softcore エンジンの GVRAM RMW
  経路は機能する (毎バイト hold 握手 ≒ 実機のメモリサイクル相当)
- **暫定サーバ実装済み**: `gdc_service.c` — np2kai の vectl/vectt/vectc/vectr/text
  を移植、除算は udiv32、ROM 32K 化 (BRAM 47% → 余裕) で収容。VECTE 捕捉・
  スナップショット 19B・FIFO-empty スロットル・done ベクトルリセットは RTL 側
  (tb_pc98_gdc で検証)
- **ウォッチドッグ搭載** (§6-1 のハング対策): サーバ無応答なら ~3 秒で強制
  完了。描画は失うが機械は固まらない
- §6-3 の最終形 (ピクセルループの RTL 化 = gvram_seq 拡張) は将来課題のまま。
  handshake/スナップショット設計はそのまま流用可能
