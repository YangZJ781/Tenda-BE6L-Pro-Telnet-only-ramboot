# 二进制输入与来源

完整输入清单：[manifest.json](../payloads/manifest.json)；发布脚本和内嵌 ZIP 的固定 SHA256：[lock.json](../payloads/lock.json)。研究仓库不分发 Tenda 原厂固件、设备备份或配置。

| 组件 | 来源 / 版本 | 原始包 SHA256 |
| --- | --- | --- |
| kexec | [OpenWrt 23.05.6，arm_arm926ej-s，2.0.26-1](https://downloads.openwrt.org/releases/23.05.6/packages/arm_arm926ej-s/base/) | `1508e0b94df80c9612417f9ec543836c8f607b05b1ac0212c9b95c7c63511117` |
| zlib | 同一目录，1.2.13-1 | `43047828117bd3389e98b2b539876158230e6ab43a945f3bbda5f24725f3bcd5` |
| musl | [OpenWrt 23.05.6，at91/sam9x，libc 1.2.4-4](https://downloads.openwrt.org/releases/23.05.6/targets/at91/sam9x/packages/) | `c748f2fd6552a516a51e37f496676e817e7a380087942190a6c7d4cf2a5e84a9` |
| 内核与原始 DTB | 用户提供的 BE6L Pro XWRT initramfs FIT；内嵌信息报告 X-WRT `26.04_b202609230606`、`r36651-d58eb38f55e`、Linux `6.18.52` | 见下文 |
| 分段装载器 | 本仓库 [生成源码](../tools/build_split_loader.py) | 二进制见 manifest |

God1 输入 SHA256：`02b099eca11115d29d243af1938d6db64e13b38618f0e0caf72956b7429f3c4d`。已核对外层 CRC32 `41d3465a`，内部 FIT 与无 God1 头版本一致。

解压内核 SHA256：`4112560412c7a1fb12d13b5e83d4365bb8b1e45cad2ce2e79701fb956c3dea1b`。

原始 DTB SHA256：`43b4d26c85291e7299c0f5ed085982b5f49032e1a410bb71fe0c642222842e53`。原始 DTB 放在 Release 的 `loader-inputs.zip`；调整后的 DTB 与内核保存在 `ramboot-payloads.zip`。

## 上游源码与许可证

- [kexec-tools v2.0.26](https://github.com/horms/kexec-tools/tree/v2.0.26)，GPL-2.0；许可证文本位于 `LICENSES/kexec-tools-COPYING.txt`。
- [zlib v1.2.13](https://github.com/madler/zlib/tree/v1.2.13)，zlib license。
- [musl v1.2.4](https://git.musl-libc.org/cgit/musl/tree/?h=v1.2.4)，MIT 等上游版权条款，见 COPYRIGHT。
- [OpenWrt v23.05.6](https://github.com/openwrt/openwrt/tree/v23.05.6)，包含对应包的构建配方与补丁。
- [本次镜像报告的 X-WRT 提交](https://github.com/x-wrt/x-wrt/commit/d58eb38f55e1d6552025dd5817f525712420d672)，已核对该提交存在，上游提交时间为 2026-09-25。
- [Linux stable 源码](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/)；镜像报告内核版本为 `6.18.52`。

内核镜像由既有固件提取，本项目没有重新编译完整 XWRT，也没有将普通上游 Linux 标签冒充为带全部 XWRT 补丁及配置的对应构建源码。源码模板和封装工具用于审阅及复现本项目的装载流程。

第三方组件保留各自许可证。Release 提供第三方许可证汇总，仓库保存上游许可文本；源码归属与许可不因本项目重新打包而改变。
