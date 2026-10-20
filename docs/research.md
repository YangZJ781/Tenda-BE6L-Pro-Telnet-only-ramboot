# 研究记录：Telnet 到 RAM initramfs

## 已验证结论

BE6L Pro 的原厂 .16、.51 和 .62 都能在正常系统中，经网线开启 Telnet、取得 root、调用 kexec，并启动提供的 XWRT initramfs。TTL 在最初研究中用于观察日志和排查问题；最终单文件脚本没有任何串口访问功能。

成功结果需区分两点：内存启动机制已验证；无线设备在热切换后的初始化问题尚未解决。成功测试使用临时 DTB 禁用无线 PCIe 控制器，保留有线网络。

## 设备与镜像

- Airoha AN7563PT，Cortex-A53，当前系统为 ARM 32 位软浮点 ABI，512 MiB DRAM。
- 原厂内核 5.4.55；`.16` 构建于 2024-10-21，`.51` 构建于 2025-09-24。
- XWRT initramfs：`26.04_b202609230606`，`r36651-d58eb38f55e`，Linux 6.18.52。
- 用户提供的 `tenda_be6l-pro-initramfs-god1.bin` 与不含 God1 头的 `tenda_be6l-pro-initramfs-kernel.bin`，FIT 内容相同。God1 外层有头部与填充，不能直接作为通用 kexec 的原始内核输入。
- FIT 中 LZMA 内核解压为 23072608 字节的原始 ARM Image，内嵌 initramfs，无需额外 ramdisk。

内核 SHA256：`4112560412c7a1fb12d13b5e83d4365bb8b1e45cad2ce2e79701fb956c3dea1b`。

原始 DTB SHA256：`43b4d26c85291e7299c0f5ed085982b5f49032e1a410bb71fe0c642222842e53`。

## Telnet 密码

网页接口使用管理员密码的 MD5 大写十六进制值进行鉴权。登录后调用 `/goform/telnet`，成功返回 `load telnetd success.`。

静态 `/etc_ro/passwd` 对应的 `Fireitup` 并非正常启动后的可用密码：启动程序会重新生成 root 密码。三版固件使用不同种子：

| 固件 | 种子 |
| --- | --- |
| .16 | `4rKSbd1m_5756` |
| .51 | `TxVqqk5_7730` |
| .62 | `HZJb9q_8765` |

取 LAN MAC 最后两个字节，各转为两位小写十六进制，拼接为 `倒数第二字节 + 种子 + 最后字节`，再对 ASCII 做 Base64。例如虚构 MAC `02:00:00:00:15:e0`，`.51` 的待编码字符串为 `15TxVqqk5_7730e0`。种子与算法都已通过实际 root 登录核验。

原厂 BusyBox 缺少 `id` applet，权限检查使用 `/proc/self/status` 的 `Uid: 0 0 0 0`。

2026-10-20 从 `.62` 的 `/bin/cnsl_safe` 提取新种子，并核对其生成的实际 MD5-crypt 哈希和正常系统 Telnet root 登录。该程序 SHA256 为 `0ba0492e84b784de5ee7065a103f2e827e8f77a9e8f095ced5bf94219cf6be0e`。未登录访问 `/goform/telnet` 会跳转登录页；管理员鉴权后，同一会话访问不带 stok 前缀的该路径返回 `load telnetd success.`。不能把它描述为已验证的匿名鉴权绕过。

旧脚本默认选择 .16 算法，直到 Telnet 登录后才检查版本，导致不带参数运行于 .51 时误报登录失败。当前单文件版在任何 Telnet 登录前先识别型号与版本。

`.51` 的 `systemCfg.productName` 返回空字符串；脚本会读取同次鉴权响应中 `deviceVersionList` 的本机 `devModel=BE6LProV1.0` 来核对型号。

## kexec 与分段装载

两版原厂均有 `kexec_load_disabled=0`。CPU / 内核使用软浮点环境，通用硬浮点工具不适用；OpenWrt 的软浮点 kexec 又需要原厂 libc 缺失的 time64 接口。因此将独立 musl loader、zlib 与 kexec 全部放在 `/tmp`，不替换原厂 `/lib`。

实际 RAM 范围包括：

```text
80040000-801fffff : System RAM
80200000-83ffffff : System RAM
84100000-9fffffff : System RAM
```

普通 kexec 因分段选择了 `0x80208000`，与已验证的入口 `0x80088000` 不符；将相邻范围仅在工具中合并后，单个内核段又被原厂内核返回 EINVAL 拒绝。ARM `machine_kexec_prepare()` 会检查每个段是否完整落在一个 memblock 范围内。

最终使用 680 字节静态 ARM EABI 装载器，把物理上连续的内核按 `0x80200000` 边界拆成两段，入口和内核字节不变：

| 段 | 目标地址 | 文件数据字节 | 页对齐内存字节 |
| --- | --- | ---: | ---: |
| 内核第一段 | `0x80088000` | 1540096 | 1540096 |
| 内核第二段 | `0x80200000` | 21532512 | 21532672 |
| DTB | `0x86ee3000` | 10618 | 12288 |

装载器仅调用 open、mmap2、kexec_load、exit。`kexec_load` 返回 0 后，`/sys/kernel/kexec_loaded` 为 1，再从原 Telnet 会话执行 `kexec -e`。详细参数见 [split-loader-manifest.json](split-loader-manifest.json)。

## 临时 DTB 与无线限制

测试仅调整内存中的 DTB：

1. `bootargs-override` 从 `console=ttyS0,115200n8 earlycon ubi.mtd=ubi` 改为 `console=ttyS0,115200 earlycon`。
2. `/soc/pcie@1fa91000` 的 `status` 从 `okay` 改为 `disabled`。

保留无线时，XWRT 内核、两个 CPU 和 initramfs 用户空间均已启动，但约 17 秒后出现：

```text
mt7996e ... Timeout for driver own
probe with driver mt7996e failed with error -5
LR is at mt7996_irq_tasklet...
Kernel panic - not syncing: Fatal exception in interrupt
```

随后自动重启回原厂系统。禁用该 PCIe 控制器后，进入 root 命令行和有线网页，根目录为 tmpfs，`ubus call system board` 返回 `rootfs_type=initramfs`。这定位了热切换后的无线初始化问题，但没有证明具体复位或驱动修复方案。

## 内存盘容量

原厂 `/tmp` 默认 30 MiB，`df` 为 30720 KiB。完整启动文件约 23 MiB，可在默认容量内存放。

`.16` 中临时 `remount,size=256M` 被接受，随后恢复 30 MiB。**30 MiB 是配置值；256 MiB 是已接受的容量设置，未做写满测试，不是已测得的绝对上限。** tmpfs 与系统共享物理内存。

## 验证边界

- 原厂 .16 / .51 / .62 到同一 initramfs 均已完成实际启动。
- 最终单文件 PS1 在 .51 上从仅有一个输入文件的目录完整运行，不访问 TTL，也不调用 Python 或 OpenSSL。
- 最终 PS1 的 .16 选择与密码分支做了回归检查；没有为最后封装版本再次降级完整重测 .16。
- v0.1.1 单文件 PS1 在 `.62_cn` 完成完整启动测试，从网络确认 `rootfs_type=initramfs`；没有访问 TTL 或调用 Python/OpenSSL。`.62XD` 等未验证版本字符串仍会在 Telnet 登录前停止。
- 发布脚本没有升级或还原闪存的功能；研究中为切换原厂版本使用的升级辅助程序不属于本项目启动流程。
