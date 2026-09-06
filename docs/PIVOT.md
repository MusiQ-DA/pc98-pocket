# ピボット決定(2026-09-06): ベースを desaster/openfpga-PCXT に変更

## 経緯

MacLCテンプレートベースのスクラッチchassisで「RS: Host commands ignored」
(ブリッジホストコマンドが全く応答しない)を解決できず。一方、
desaster/openfpga-PCXT は同一Pocket実機でDOSブートに成功している
(ユーザー実機確認済み: BIOS POST起動まで確認)。

## 決定

- ベースを openfgba-PCXT(pcxt-base/)に変更
- PC/AT機械層(KFPC-XT)をPC-98機械層に置換していく
- 詳細は PC98_MACHINE_SPEC.md

## 旧ビルド(MacLCテンプレートベース)の扱い

- src/(旧), ap_core.qsf(旧) は legacy 参考として残置
- 得られた知見:
  - bridge_endian_little はフレームワーク語順規約(常時0)
  - ステータス遷移(1→2→3→4)はOSが観測する
  - rbf_r はバイトごとビット反転必須
  - /Cores/ ルートへのファイル散落はフレームワークエラーの原因になりうる

## ローカルビルド

- Docker Desktop 再インストール済み、raetro/quartus:pocket イメージpull済み
- `bash pcxt-base/scripts/build.sh 相当` または直接 quartus_sh --flow compile
- 注意: Docker Desktopのアンマウント/ejectはSSHセッションから不可(GUIで実施)
