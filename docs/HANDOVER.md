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

### B0(ベースライン)ビルド: 進行中または完了

- `pcxt-base/` ツリーをローカルDocker(raetro/quartus:pocket)でコンパイル中だった。
- **再開時の最初の作業**: ビルド状態の確認
  ```bash
  tail -5 /tmp/pcxtbase_build.log   # または再実行
  cd ~/repo/pc98-pocket/pcxt-base && bash scripts/build-docker.sh
  ```
- 完了していれば `pcxt-base/src/fpga/output_files/ap_core.rbf` が生成されている。

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
6. **openfpga-PCXTの picorv32 ファームウェア(firmware.vh)はリポジトリ未同梱**。
   RISC-Vツールチェーンで src/firmware/*.c をコンパイルして生成する。
   ベースライン検証用のNOPスタブ(6144×0x00000013)は作成済み
   (`pcxt-base/src/firmware/firmware.vh`)。
7. **np2のI/Oマップは np2ソースの `iocore_attach*` 呼び出しから機械抽出可能**
   (低域0x00-0xF0は抽出済み: PC98_MACHINE_SPEC.md 参照)。

---

## 5. 次のセッションの作業リスト(優先順)

1. **B0ビルド完了確認** → rbfをパッケージ(`scripts/package.sh` 相当で
   バイト反転+CRLF JSON+zip)→ SDへ → 実機テスト
   - ✅ BIOS POST表示 → パイプライン確定 → P1へ
   - ❌ 同エラー → raetroイメージのQuartus検証(MacLCソースをraetroで
     ビルドして実機テストするA/Bテストが最短)
2. **P1: PC-98メモリマップ**(CPU+SDRAM+BIOSフェッチ)
3. **P2: TVRAM+テキスト表示**(Phase 3資産: tvram.sv/text_render.sv 移植)
4. **P3: GDC** / **P4: FDD→DOS** / **P5: BEEP→OPNA** / **P6: EGC**

## 6. ユーザー環境メモ

- Pocketファームウェア 2.7(pocket_firmware_2_7.bin)
- SDカード: 15GB、多数のコア導入済み(pupdate管理)
- desaster.PCXT がインストール済みでDOSブート実績あり
  (Assets/pcxt/common/boot.bin 配置済み)
- **PC-98用ROM資産あり**: `~/Documents/lodemnc/np2rom/`
  (bios.rom 96KB ✓ / font.rom 288KB ✓ / sound.rom 16KB / ITF.ROM)
  → PC-98コアのAssetsは `Assets/pc98/common/` に置く想定

## 7. 大事な約束事

- **np2のコードは移植しない**(挙動リファレンスとしてのみ使用)
- MCL86はMIT、TVRAM/GDC/OPNA周りは新規設計+既存OSS参考
- 実機テストはユーザーが実施、私側はビルド/解析/SD準備を担当
- ネットワークが不安定な場合は、必ず dig ピン留め curl で回避する
