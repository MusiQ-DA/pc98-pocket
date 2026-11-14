# GDC 描画エンジン (`pc98_gdc_draw`) — VECTE/TEXTE の回路化

スレーブ GDC の EXECUTE 図形描画を、picorv32 の横にある小さなハード
エンジンが担う。ファームウェアはコマンドの解釈とエンジンの起動だけを
し、ドットの列挙は RTL が行う。参照実装は np21w (`io/gdc.c` の
vectdraw/textdraw、`io/gdc_sub.c` の gdcsub_vectl/vectt/text、
`io/gdc_pset.c` の gdcpset) で、**ドット単位で一致**を目指す。

## 対応図形

| 図形 | ope ビット | np21w | 備考 |
|---|---|---|---|
| DOT | なし | vectdraw | CSRW の 1 ドット |
| LINE | 0x08 | gdcsub_vectl | D/D2 のブレゼンハム、DC が長さ |
| RECT | 0x40 | vectdraw+r | 4 辺 (D, D2, −D, −D2) |
| VECTT | 0x10 (VECTE) | gdcsub_vectt | TEXTW[0..1] をパターンに。SL は 16bit 完全逆順 (GDCPATREVERSE)。ZOOM が行複製、パターンは行をまたいで連続回転 |
| TEXT | 0x10 (TEXTE) | gdcsub_text | TEXTW 8 バイト全体。行は pat[7] から pat[0] へ (patnum-- )。vectp/vectl/vectr は TEXTW[7]=para[27] の倍加 |

VECTE に vectc (円弧、ope&0x20) が乗るものと円弧 (FIG_CIRC) は
ソフト描画のまま — ファームウェアの slow path が出す。これは意図的:
円弧は per-dot の除算を免れた独自曲線 (d161c81) で既に np21w 一致
しており、面積に見合わない。

## データ経路

```
guest port 0xA0/0xA2                  (Peripherals が cs/a1 を敲く)
      │
┌─────▼──────────────────────────────────────────────────────┐
│ pc98_gdc (slave, MASTER=0)                                  │
│  EXECUTE 0x6C / 0x68 の書込み、または WDAT のパラメータ完了で │
│  PRAM から 32 バイトのスナップショット draw_snap[0:7] をラッチ│
│  (byte→para 写像は snap_src 関数)。draw_req / draw_op を立てる│
└─────┬──────────────────────────────────────────────────────┘
      │ 512 bit (master + slave)
┌─────▼──────────────────────────────────────────────────────┐
│ softcpu_subsystem                                            │
│  picorv32 が 0x5000_0140..0x164 (master)                     │
│              0x5000_0180..0x1A4 (slave) で 8 ワードずつ読む   │
│  エンジン pc98_gdc_draw は slave 側 256 bit を直接見る        │
└─────┬──────────────────────────────────────────────────────┘
      │
┌─────▼──────────────────────────────────────────────────────┐
│ firmware gdc_service.c                                        │
│  fast path: VECTE/TEXTE かつ vectc 無し (ope&0x20==0)。      │
│    CSRW から np21w の x/y を割り出し (乗算のみ、除算なし)、   │
│    チャージャー状態から書きモード (PLAIN/RMW/WORD) を選び、   │
│    LN_XY={y,x} と LN_GO (モード|図形種|TEXTEフラグ) を書く。  │
│    busy を 1<<22 サイクル poll したら abort (watchdog もあり) │
│  slow path: それ以外は従来のソフト描画 (pset_prepare 経由)    │
└─────┬──────────────────────────────────────────────────────┘
      │
┌─────▼──────────────────────────────────────────────────────┐
│ pc98_gdc_draw (clk_pico)                                     │
│  状態機械 S_DOT→S_RD→S_FL→S_W2A/B/C。ドットを列挙し、       │
│  サービスチャネル (SVC) の vr_read8 / vr_write8 相当のバイト  │
│  操作を発行 → GVRAM シーケンサの charger / line buffer /     │
│  write-back はソフト描画と同じトラフィックを見る。            │
│  PLAIN はプレーン バイトの RMW、GRCG RMW はドットマスク書き、 │
│  TDW/EGC はワードを 2 バイト。連続ドットは 1 バイトに畳む     │
│  (per-bit 演算なので np21w のドット毎ストアと同じ VRAM 结果)  │
└──────────────────────────────────────────────────────────────┘
```

## スナップショットの byte マップ

スナップショットは描画パラメータの静止したコピーで、エンジンが走って
いる間は変わらない (リタイアまで false-path 済み)。どの byte がどの
PRAM 場所かは `sim/tb_pc98_gdc_snap.sv` がゲストポート経由で検証する
— エンジン系ベンチは draw_snap を直接書くので、写像のバグは全ベンチ
緑のまま漏れる (実際 TEXTW[2..7] が para[26..31] を運ぶバグがそう
だった)。

| byte | para | 名前 | 読むのは誰 |
|---|---|---|---|
| 0 | 32 | ope (VECTW 先頭) | vectdraw のディスパッチ |
| 1..2 | 33..34 | DC | gdcsub_vectl/text の長さ |
| 3..6 | 35..38 | D, D2 | vectl/text の方向 |
| 7..10 | 39..42 | D1, DM | vectl のエラー項 |
| 11..13 | 43..45 | CSRW 下位 3 | EAD から gdcsub_x/y |
| 14 | 46 | MASK 下位 | np21w は CSRW dword の 4 バイト目を読む |
| 15..16 | 20..21 | TEXTW[0..1] | VECTT のパターン (vectdraw の vectt) |
| 17 | 8 | ZOOM | multiple = (ZOOM&15)+1 |
| 18 | 53 | WRITE | 描画族コマンドバイト |
| 19..20 | 46..47 | MASK | gdcsub_write |
| 21..22 | 54..55 | CODE | gdcsub_write |
| 23 | 0 | (pad) | 誰も読まない (SLAVE の SYNC[0] シード 06 が乗る) |
| 24..29 | 22..27 | TEXTW[2..7] | TEXT の pat[2..7] |
| 30..31 | -- | (pad) | 0 |

WDAT (0x20) のパラメータ完了もスナップショットをラッチする
(np21w の gdc_write_psetl に相当)。これはソフトパスがバイトを
書き戻す間のパラメータ一貫性のため。

## リタイアと vectreset

エンジンの完了 (`srv_done_stb`) で pc98_gdc は draw_req を下ろし、
EXECUTE 系 (0x6C/0x68) なら np21w `gdc.c` vectdraw のエピローグ
gdc_vectreset を生 PRAM に走らせる: VECTW+1..10 が DC=0, D=8,
D2=8, D1=DM=FFFF に戻り、TEXTW/CSRW/ZOOM/MASK/CODE はそのまま。
WDAT は対象外 (連続書き込みのソフトは再プログラムしない)。

## Verilator 5.020 の罠 (CI sim のピン)

CI の sim ジョブがピンしている Verilator 5.020 には、**モジュール入力
が変化した後に派生した組合せ論理を再評価しない**場合がある
(tb_softcpu_gdcdraw で snap 変化後の sx/pat8 が時刻 0 の値のまま
だった)。単一 part-select の assign と always_ff 内の直接参照は無事。
そこで `pc98_gdc_draw.sv` は:

- snap からの派生値 (dc/cnt/r) は **GO 書込みの always_ff 内**で
  三項を直接 snap から計算する (組合せ仲介レジスタを置かない)
- pat8 も GO 時にバイト毎の個別代入でロードする reg

同じ理由で `// Verilator 5.020.` で始まる行コメントはメタコメントと
誤解されて BADVLTPRAGMA になる — コメントは「the CI sim's pinned
verilator 5.020」等の言い回しにすること。

## 検証

| ベンチ | 何を見るか |
|---|---|
| `scripts/sim_gdc_draw.sh [n] [seed] [kinds]` | host C++ リファレンス (np21w 直訳) vs RTL。kinds `l/p/r/t/x` = LINE/DOT/RECT/VECTT/TEXT。既定 lprtx |
| `sim/tb_softcpu_gdcdraw.sv` | softcpu + エンジンの全体。SV で書いた np21w リファレンス (r_vectr/r_vectt/r_text) と VRAM 全面比較。`+n=200` |
| `sim/tb_pc98_gdc_snap.sv` | スナップショット byte マップ (ゲストポート経由、WDAT リタイア、vectreset 後の再ラッチ) |

## 面積の歩み

- LINE 導入 (1300477): エンジン初代
- 矩形 VECTE+R (8330892): +285 ALM、`pc98_gdc_line` → `pc98_gdc_draw` に改名
- VECTT/TEXTE (6133f53): スナップショット 24→32 バイト (384→512 bit)
- 実測は CI の fit ログで (Logic utilization)。SEED は fitter が選ぶ
  ので、違反ゼロが続く限り触らない
