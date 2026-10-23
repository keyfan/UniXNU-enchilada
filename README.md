# UniXNU-enchilada — 一加 6（OnePlus 6, SDM845）设备仓库

把 UniXNU（XNU + iPadOS 用户态，UEFI 引导）移植到一加 6 的设备侧仓库，布局与
[UniXNU-sheng](https://github.com/UniXNU/UniXNU-sheng) 一致（BSD-2-Clause-Patent 衍生）。

```
UniXNU-enchilada/
  board.toml                        板级描述（[userdata] 两处 LBA 必须真机回填）
  configs/enchilada_defconfig       内核配置
  scripts/make-enchilada-adt.py     ADT 生成器（Apple 节点编码，SDM845 常量）
  scripts/check-enchilada.py        UEFI 构建前静态检查（内存图/FD/栈/vendor 输入）
  scripts/dump-device-facts.sh      真机数据采集（GPT LBA、boot 头、DTB 常量）
  package/                          设备 kit（对照 sheng 的 package/ 填充）
```

## 使用

与 `UniXNU` checkout 平级放置，UEFI 侧为 `../uefi-enchilada`（见其 README）：

```sh
cd UniXNU
./unixnu defconfig enchilada_defconfig -D ../UniXNU-enchilada
./unixnu fetch
./unixnu status                      # 模块解析自检
```

之后按《一加6-真机实施手册.md》推进（构建 → 引导 → 根 → 用户态）。

## 回填清单（真机实测后）

| 文件 | 字段 | 来源 |
|---|---|---|
| board.toml | `[userdata] first_lba/last_lba` | `scripts/dump-device-facts.sh` 的 GPT 输出 |
| board.toml | `[payload] dram_size` | 6 GiB=0x180000000 / 8 GiB=0x200000000 |
| board.toml | `[[bootimg.dtb_node]] splash reg` | stock dtb `/reserved-memory/cont_splash_region` |
| enchilada.toml | `[boot_image]` 头字段 | `unpack_bootimg` 解包 stock boot_a |
| make-enchilada-adt.py | GIC/UFS 常量 | stock dtb（不一致时） |

其余值（IPSW 成员哈希、kernelcache 哈希、slide、prelink roots、root 卷 UUID、
trust cache 哈希、text_fixups）与 sheng 相同——同一份 iPad7,1 21H461 镜像，已核对。
