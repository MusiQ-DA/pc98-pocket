# コア内蔵 SDRAM セルフテスト — 実装指示書

作成 2026-09-07。`docs/HANDOVER.md` §1.9 の「次の一手」の実装仕様。
**この文書だけで着手できるように書いてある。** 背景の詳細は HANDOVER §1 を参照。

## 0. なぜ作るのか

`sdram_mp` が実機で BIOS を通せない。実機ビルドを5本使って得られた情報は
「スプラッシュ→3回ビープ(= XT系 BIOS の **base 64KB RAM failure**)」の1点だけ。
論理側の仮説(DQサンプル点・読み出しパス・書き込み取り込み時刻・マルチバンク・
リフレッシュ)は**すべて潰れており**、シミュレーションは全部緑。

つまり **1ビルド15分 + 実機1往復あたり1ビットしか情報が得られない**のが律速。
これを「どのアドレスで、何を書いて、何が読めたか」に変えるのが本タスク。

**成功の定義**: 実機で OSD に最初の不一致が `ADDR=xxxxx GOT=xx WANT=xx` の形で出ること。

## 1. 全体構成

ゲスト 8088 を reset で止めたまま、**picorv32(softcore)から SDRAM を直接読み書きし、
結果を OSD に描く**。テストロジックは全部 C で書く(RTL に FSM を作らない)。
理由: 実機で挙動を変えたくなったとき、C なら firmware 再ビルドだけで済む。

```
firmware (C)  --MMIO-->  softcpu_subsystem  --->  core_top の ext ポート調停
                                                        |
                                                  CHIPSET.address_ext ほか
                                                        |
                                                     RAM.sv  --->  sdram_kf_shim -> sdram_mp
結果 --GPU_CHAR--> OSD
```

**既存資産をそのまま使う。新規に作るのは MMIO 4本と調停だけ。**

## 2. 判明している既存資産(調査済み・そのまま使える)

| 資産 | 場所 | 備考 |
|---|---|---|
| ゲストを reset に保持 | `SOFT_GUEST_HOLD` = `0x2000001C` bit0 | firmware から既に叩ける |
| OSD 文字描画 | `GPU_XY` / `GPU_CHAR` = `0x40000000` / `0x40000018` | `GPU_STATUS` bit0 で busy ポーリング |
| OSD 表示 ON | `VKB_CTRL` = `0x20000004` bit0 | |
| SDRAM への外部書き込み | `CHIPSET.address_ext` / `data_bus_ext` / `memory_write_n_ext` | BIOS ローダが実使用中(実績あり) |
| **SDRAM の外部読み出し** | `CHIPSET.memory_read_n_ext` | **ポートは存在するが `core_top.sv:1682` で `1'b1` に殺してある** |
| アクセス完了パルス | `RAM.sv` の `access_complete` (= `state == COMPLETE_RAM_RW`) | 既に core_top へ出ている |

**要点: 読み出し経路は「配線するだけ」。RAM.sv も CHIPSET も新規ロジックはほぼ不要。**

## 3. RTL 変更(3ファイル、いずれも小規模)

### 3.1 `KFPC-XT/HDL/CHIPSET.sv` — 読み出しデータを外に出す

現状 `internal_data_bus_ram`(RAM.sv の `data_bus_out`)は CHIPSET 内部で閉じている。
出力ポートを1本足す:

```systemverilog
output  logic   [7:0]   data_bus_ext_out,   // ext ポートで読んだ SDRAM の1バイト
```
`assign data_bus_ext_out = internal_data_bus_ram;`

※ 既存の `internal_data_bus_ext` は **入力側の mux**(l.453-470)。混同しないこと。

### 3.2 `core_top.sv` — ext ポートの調停

いま `address_ext` / `data_bus_ext` / `memory_write_n_ext` は BIOS ローダ専用。
セルフテストと**時分割**する。両者が同時に動くことはない
(BIOS ロードはダウンロード中のみ、セルフテストはロード完了後かつゲスト保持中のみ)が、
**明示的に排他にすること**:

```systemverilog
wire st_active = selftest_req & ~ioctl_download;   // BIOS ロード優先
assign address_ext_mux      = st_active ? st_addr        : bios_access_address;
assign data_bus_ext_mux     = st_active ? st_wdata       : bios_write_data[7:0];
assign memory_write_n_ext   = st_active ? st_write_n     : bios_write_n;
assign memory_read_n_ext    = st_active ? st_read_n      : 1'b1;   // ← 現状 1'b1 固定
assign ext_access_request   = st_active ? 1'b1           : bios_access_request;
```

`st_*` は softcpu_subsystem から来る。**`ext_access_request` を忘れないこと**
(BIOS ローダがこれで RAM.sv にアクセス権を主張している)。

### 3.3 `softcpu_subsystem.sv` — MMIO 4本

**`0x5` 領域を新設する(実装時に変更)。** `0x2` の空きを使う案だったが、既存デコードが
すべて `cpu_mem_addr[4:2]`(bit5を無視)なので `0x20000030` が `0x20000010`(OSD_ACTION)、
`0x34` が OSD_ORIGIN に**エイリアスする**。独立領域なら衝突しない:

| アドレス | 方向 | 内容 |
|---|---|---|
| `0x50000000` | W | `st_addr[19:0]` — ゲスト物理アドレス |
| `0x50000004` | W | `st_wdata[7:0]` |
| `0x50000008` | W | bit0 = write 起動、bit1 = read 起動 |
| `0x5000000C` | R | `{busy, rdata[7:0]}` — bit8 busy、bit[7:0] が読めた値 |

起動から `access_complete` までを `busy` で覆う。**`access_complete` は
`clk_chipset` ドメイン、`clk_pico` は `clk_chipset` の 1/6 ゲートクロックなので
CDC は不要**(SDC で同一グループ、`set_multicycle_path` 済み。`core_constraints.sdc` 参照)。
ただし起動パルスは clk_pico の1発が clk_chipset の6サイクル分続くので、
**`st_*_n` は「立ち下がりを1回だけ拾う」形にすること**(6回アクセスが走らないように)。

## 4. firmware 変更

### 4.1 新規 `pcxt-base/src/firmware/sdramtest.c` / `.h`

```c
void sdram_selftest_run(void);   // main.c から、BIOS ロード完了後・ゲスト解放前に呼ぶ
```

アクセスプリミティブ:
```c
static void  sd_poke(uint32_t addr, uint8_t v);
static uint8_t sd_peek(uint32_t addr);   // busy をポーリング
```

### 4.2 テスト内容(この順で、最初に落ちた所で止めて表示)

1. **base 64KB スイープ** `0x00000-0x0FFFF`
   — **3回ビープが指している領域。ここが本命。**
   全書き→全読みの2パス(書きながら読むと隣接アドレスの破壊を見逃す)。
   パターンは `addr` から導出(`(addr*0x9D)^0x5A` 等)。アドレス依存にすること
   — 定数パターンだとアドレス化けを検出できない。
2. **バンク境界** `bank = addr[10:9]` なので 512 バイトごとにバンクが変わる。
   `0x00000,0x00200,0x00400,0x00600` を巡回するストライドアクセス。
   ※ KFSDRAM は `bank = addr[23:22]` で**常にバンク0**。ここが両者の最大の差。
3. **リフレッシュ放置** 書き込み後に約 100ms 何もせず待ってから読み戻す。
   リフレッシュ不良ならここだけ落ちる。

### 4.3 表示(OSD)

```
SDRAM SELFTEST
PASS: 65536 bytes           ← 全部通った場合
```
または
```
SDRAM SELFTEST
FAIL @ 0A3F4  GOT 7C WANT 5A
BANK 1 ROW 20 COL 1F4
ERRORS 1832 / 65536
```
`BANK/ROW/COL` は `addr[10:9] / addr[23:11] / addr[8:0]` から計算して出す。
**これが無いと「どのバンクか」が分からず、今回の切り分けに使えない。**

エラー総数も出すこと。1個だけ壊れるのか全滅なのかで原因が全く違う。

## 5. 検証手順(実機に持って行く前に必ず)

1. **シミュレーションで先に通す。**
   `sim/tb_ram_ab_ph.sv` に、ext ポート経由の read/write を叩くケースを追加する。
   **鉄則: KFSDRAM 参照(`mode=ref`)も同じテストを通ること。**
   参照が落ちたら疑うのは TB 側(これで既に2回助かっている。HANDOVER §1.9)。
2. `bash sim/run_ph.sh` が ref / mp / mp_kfref の3モードとも PASS。
3. CI(`.github/workflows/build.yml`)でビルド。
   ゲート "SDRAM interface is actually timed" が緑であること。
4. パッケージ: `dist/testB1` を複製 → `bitstream.rbf_r` だけ差し替え。
   **変換はバイト内ビット順リバース**(XOR 0xFF ではない。HANDOVER §2-1)。
   先頭が `FF×128 + 56 56 56 56 6c 2f` になることを `xxd` で確認。

## 6. 落とし穴(既知)

- Verilator 5.020: `fork/join` は SIGSEGV。コメント内の "verilator" の語もエラーになる。
- `$display` で文字列リテラルの隣接連結は Verilator が受け付けない。1行にすること。
- `getartifact.py` は失敗した run を拒否する。コンパイルが通っていて後段ステップだけ
  赤い場合は `--allow-failed` を付ける。
- ローカル Docker ビルドは45分かかる。**ビルドは CI 一択**(13〜15分)。
- システムDNSが壊れている。ネットワークは `scripts/tools/ghlib.py` 経由(dig ピン留め)。

## 7. やってはいけないこと

- **DQ サンプル点をまた動かさない。** P+2.5 / P+3 / P+4 の3点とも実機で failed 済み。
- **読み出しパスの -2.4ns を追わない。** 実機で動く KFSDRAM が同値(HANDOVER §1.8)。
- **入力遅延 `-max` を根拠なく変えない。** 5.9→3.5 は悪化した(§1.10 / run#60)。
- np2 のコードは移植しない(挙動リファレンスとしてのみ)。
