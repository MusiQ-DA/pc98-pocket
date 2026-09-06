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

#### 2026-09-07 に修正した不備(投入時に抜けていた点)

1. **必須アセット boot.bin が未配置だった。**
   data.json のスロット1「PCXT BIOS」は `required: true` / `parameters: 0x203`
   (bit1 = core specific)で、**コア固有アセットディレクトリ**を参照する。
   純正は `Assets/pcxt/desaster.PCXT/boot.bin` にあるが、我々のコア用は皆無だった。
   → `Assets/pcxt/hiroya.PCXTDEV/boot.bin` と
     `Assets/pcxt/hiroya.PCXT-dev/boot.bin` の**両方**に配置した
     (author.shortname 派生かフォルダ名派生かが未確定のため両建て)。
   **これ自体がロードエラーの原因になり得るので、以前の実機テスト結果は
   このアセット欠落込みの結果である可能性がある。**
2. **SD上の core.json が手編集され、LF・末尾改行なしになっていた。**
   → `dist/testB0/.../core.json` を正規化して再生成し、SDへ再コピー。
   なお **純正 desaster.PCXT の JSON も LF**(CRLFではない)。
   `scripts/package.sh` は CRLF で出力するが TestA で実証済みなのでどちらでも可。

### B0 実機テストの判定基準

- ✅ BIOS POST 表示 → **我々のビルドパイプラインは健全** → 自作機械層のRTLを
  疑って部分ビセクト → P1へ
- ❌ 同じエラー(Load error / RS: Host commands ignored)
  → raetroイメージのQuartus設定・ビルド環境の問題
  → MacLCソースを raetro でビルドして実機テストする A/B が最短

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

1. **B0の実機テスト**(ビルド・パッケージ・SD投入は完了済み。§1参照)
   - Pocket で `PCXTDEV` を起動し、BIOS POST が出るか確認
   - 判定基準は §1「B0 実機テストの判定基準」を参照
   - **注意**: 2026-09-07 に boot.bin 配置漏れを修正した。それ以前に
     テスト済みなら、修正後に**再テスト**すること
2. **P1: PC-98メモリマップ**(CPU+SDRAM+BIOSフェッチ)
3. **P2: TVRAM+テキスト表示**(Phase 3資産: tvram.sv/text_render.sv 移植)
4. **P3: GDC** / **P4: FDD→DOS** / **P5: BEEP→OPNA** / **P6: EGC**

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
