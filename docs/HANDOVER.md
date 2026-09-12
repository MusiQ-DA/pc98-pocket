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

## §3 残る課題: KF8253タイマー — **解決済み(2026-09-13)**

### 3.1 診断の訂正: mode-3は壊れていなかった

「mode 3出力が~5エッジで停止」の正体は **mode 0 の正常動作**:
- ITF(F854E)はカウンタ0に ctrl 0x30(**mode 0**)を書き込み、
  カウンタテスト(FD873相当)とINT 08テスト(F8A3C)に使う
- ROMセット全体で ctr0 を mode 3 にする書き込みは **FD80 POSTのFDE20の一箇所のみ**
  (ctrl 0x36 + LSB 0x00 + MSB 0x60 → 0x6000 = 2.4576MHzで100Hz、続けてIRQ0アンマスク)
- ゴールデンステートのストラップはPOSTをスキップするためFDE20が走らず、
  タイマーはITFが残したmode 0(1回のTCで1割込み、以後沈黙)のまま → BASICの
  初期化待ちループが永遠に回る
- なおログの時刻表示 `%t` は **ps単位**(timescale 1ns/1ps)。旧ログの
  「~2秒間隔」は実は 2.1s、「#9→#10の0.05s」は50ms(mode 0のTCそのもの)

検証: `sim/tb_kf8253_mode3.sv` — KF8253単体で0x8000/0x6000/奇数/再プログラム
の全ケースが正確にN/2カウント毎に永遠にトグルすることを直接測定。
**KF8253_Counter.svのmode-3ロジックは無修正。**

### 3.2 本当にあった3つのバグ(全て修正済み)

1. **KF8259エッジ検出がレベル追従だった**(`KF8259_Interrupt_Request.sv`)
   - `low_input_latch`がピンLOWでセットされた後、**HIGHの間ずっと武装解除されず**、
     IRRが毎クロック再アサート(mode 3の矩形波High半周期中は実質レベルトリガ)
   - 8259A本来の「立上がりエッジ1回でラッチ、次のエッジまで再武装しない」に修正
   - これがないと割込み確認直後に同一割込みが再燃し続ける
2. **PIT入力クロックが1.193MHz(PC/XT)だった**(`Peripherals.sv` / ベンチ)
   - PC-98は **2.4576MHz**(VM=5MHz機、np2のclk_baseと同じ)
   - 42.954545MHzは非整数倍(17.48)なので位相アキュームレータで正確に2.4576MHzを生成
3. **np2のIRR0クリア特性が未実装**(`KF8259.sv`に`external_irr_clear`ポート追加)
   - np2 io/pit.c: ch0への書き込み(カウント値、またはRL≠ラッチのコントロール
     ワード)でマスタPICのIRR bit0をクリア
   - 再プログラム前にラッチされた古い割込みが、新しいハンドラに届くのを防ぐ
     実機由来の挙動。Peripherals.svとベンチ両方に配線

### 3.3 ベンチ(tb_pc98_v30.sv)の変更

- IRQ0を **ハードウェアPIT出力(timer_out0)から直接** 駆動。
  固定レートのソフトウェアトグラー(pit_timer_irq, 16384ce毎)は削除
  — mode 3矩形波+エッジトリガPICで「周期ごとに1回の割込み」= np2の
  NEVENT_ITIMERと同一のケイデンス
- **PITシード**: ブート判断(FE1FD)の瞬間 — +goldenのRAM事前投入と同じ境界 —
  にFDE20の書き込み列(ctrl 0x36, LSB 0x00, MSB 0x60)を実際のバス経路で注入。
  ツーパスブートの2回目の判断でも再注入(ITFパスがmode 0に書き戻すため)。
  `+nopitseed`で無効化
- タイマークロックを2.4576MHzに(位相アキュームレータ、RTLと同一方式)

検証: `sim/tb_pit_boot_seq.sv` — クロック較正(2,457,432Hz実測)、
ITF列(mode 0ワンショット=エッジ2本)、FDE20列(mode 3連続、半周期5.000ms)、
IRR0クリア両経路。**全フェーズPASS。** `tb_pic_cascade`も変わらずPASS。

### 3.4 RTL(FPGA実機)への影響

実機のフルブートはITF→FD80 POST全体を実行するのでFDE20が走り、
シードは不要。実機に必要なのは上記3修正(クロック・エッジ検出・IRR0クリア)
のみ。`Peripherals.sv`のPITクロックとIRR0クリア配線はMACHINE_PC98側で対応済み。

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

1. ~~KF8253タイマー修正~~ — **完了(§3参照)**。mode-3は元から正常、
   本当のバグはKF8259のエッジ検出・PITクロック1.193MHz・IRR0クリア未実装の3点
2. 修正後のシミュでBASICバナー確認(docker `pitfix` コンテナで実行中)
