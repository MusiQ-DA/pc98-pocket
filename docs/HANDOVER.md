# 引き継ぎドキュメント — PC-98 Pocket / ROM BASIC ブート(改訂第2版)

最終更新: 2026-09-13
前回からの変更: **根因が判明、UX BIOSでBASIC初期化まで到達**

---

## §1 現在位置

**UX BIOSでBASIC初期化に入った。残る障害は1つ: KF8253タイマーのスタック。**

```
✅ ITF メモリカウント画面出力("MEMORY 000KB OK")
✅ BIOS POST 完走
✅ int 1E → E800:0000 (EB 22 = クリーンエントリ)
✅ BASIC INIT (E800:0024): mov ss,0x60 ✓
✅ BASIC内部初期化(F353C-F3792、正しいレジスタ)
✅ SS=0060 DS=0060 ES=A000 SP=F7E0 (全て正常)
─────────── ここまで動く ───────────
❌ BASICの初期化ループがタイマー割込み待ちでブロック
   (タイマーが~2秒に1回しか発火せず、実機は~600Hz)
```

## §2 根本原因(全て解決済み)

### 2.1 bios.romは「Franken-ROM」だった(最重要発見)

旧bios.romはE800部分(file 0-0x7FFF)とFD80部分(file 0x8000-0x17FFF)が
**別世代のROMから混在**していた:

| | 旧bios.rom(壊) | UX BIOS(正) |
|---|---|---|
| E800:0000(IVT[1E]飛び先) | `06 66 18 77 D5…`(cmp命令の続き) | **`EB 22` → jmp E800:0024 → BASIC INIT直行** |
| file 0x7EBD | 別ルーチンのコードバイト | 実トークンテーブル |

**UX BIOS ROM**: `/tmp/uxroms/bios.rom` (md5: 3af0ae01)
ソース: `/Volumes/Backup 4TB/Downloads/NEC PC-9801UX [ROM].zip`

### 2.2 0x66「バグ」はバグではなかった

サブエージェントDが証明:
- E800:0000の`06 66 18`は**命令境界ではなく**`3B 06 66 18`(cmp ax,[1866])
  の opcode がE800:FFFFにあり、ModR/M+disp16が0000-0002にまたがっている
- `77 D5`(JA)は正しくtaken(CF=0, ZF=0)→ FFDAへ
- **nuV30コアは正常、修正不要**
- 0x66はV30の予約NOP(ModR/Mを消費する2バイトNOP)

### 2.3 SS=0xF202も全て説明済み

壊れたE800部分の偽ディスパッチ → int 1Eフレームを誤消費 →
`88 17`の2バイト目(0x17=POP SS)を命令として実行 → SS=フラグ値

## §3 残る課題: KF8253タイマー

BASIC初期化のループ(F353C-F3792)は`test byte [0x47E],4`等のフラグを
ポーリングしている。これらのフラグはタイマー割込み(INT 08)の
ハンドラーでセットされる。

**観測**: タイマーEDGE #9-11が約2秒間隔(実機は~600Hz)
**原因**: KF8253 Counter 0 mode-3出力が~5エッジ後に停止(初回セッション
から記録済み、未修正)

### 修正候補
1. **KF8253_Counter.sv のmode-3出力ロジック修正** — 出力が止まる理由を
   特定して修正
2. **タイマーを全ソフト生成に置換** — np2方式(スケジュールされた
   イベントから割込み生成)をRTLに移植
3. **ベンチのnp2方式タイマーをUX BIOSに対応させる** — 現在のベンチの
   タイマーは`+timer=1`でハードウェアKF8253に切り替え可能

## §4 セットアップ

### 4.1 ROMファイル

```bash
# UX BIOS(正しいROM)
/tmp/uxroms/bios.rom  (md5: 3af0ae01)

# シミュ用hexファイル
HEX=/var/folders/df/39xrvpn57gj_g103mfbqvy5c0000gp/T/v30sim
python3 -c "
rom = open('/tmp/uxroms/bios.rom','rb').read()
with open('$HEX/bios.hex','w') as f:
    for b in rom: f.write(f'{b:02x}\n')
"
```

### 4.2 ブート実行

```bash
docker run -d --name <name> \
  -v "$PWD":/work -v "$HEX":/hex -w /hex pc98-sim \
  bash -lc '<verilator build + /tmp/obj_v30b/v30boot>'
```
(~30分でBASIC初期化まで到達)

### 4.3 ハードウェアROM

デプロイ時に `/tmp/uxroms/bios.rom` を使用する。
`scripts/deploy_pc98.sh` のROMパスを更新。

## §5 コミット一覧(最終)

```
afc1e6d BREAKTHROUGH: UX BIOS boots into BASIC initialization
7f6487c sim: +golden=<file> work-area pre-seeder
c085cb3 sim: 0x66-prefix workaround (superseded — was a Franken-ROM artifact)
67d3e28 docs: final handover
a9cde63 sim: keyboard ACK delayed 80ms
d4dda77 sim: memory switch protected from POST clear
... (全履歴は git log 参照)
```

## §6 注意事項

- **FD80部分は互換**: UX BIOSのFD80部分は旧ROMとバイト同一(サブエージェントB
  が確認)。ポートモデルとの互換性は維持される
- **ITF**: UXのitf.romも使用(md5同一)。ITFのメモリカウントは000KBのまま
  進まないが、BIOSブートには影響しない
- **66→90パッチは不要**: UX BIOSには0x66が存在しない。ベンチの
  `if (bios[1] == 8'h66)` 条件付きパッチは自動的に無効化される
- **RTL移植済み**(サブエージェントC): キーボードACK遅延、メモリスイッチ
  プリシード+保護、DIP 0x31=0xE3
- **nuV30コアは未変更のまま**: 0x66問題はコアのバグではなかった

## §7 次のアクション

1. **KF8253タイマー修正**(唯一の残課題)
   - `pcxt-base/src/fpga/core/KFPC-XT/HDL/KF8253/HDL/KF8253_Counter.sv`
   - mode-3出力が止まる原因を特定して修正
   - またはnp2方式のソフトタイマーをRTLに移植
2. タイマー修正後、シミュでBASICバナー確認
3. RTLをビルドしてデプロイ
