# 第三方组件说明

一键脚本内嵌了 XWRT/Linux initramfs、kexec-tools、musl 和 zlib 的二进制。它们保留各自版权及许可证，见 [来源清单](docs/provenance.md) 与 [LICENSES/](LICENSES/)。

单文件封装不表示这些组件由本项目原创，也不改变其原有授权。仓库没有上传 Tenda 原厂固件、设备备份、个人配置或原厂管理密码。

Release 的 `THIRD-PARTY-NOTICES.txt` 汇总所保存的上游许可证文本。Linux 内核中的 syscall note 与 initramfs 中其他包的许可证仍按其各自上游声明适用。

本次发布没有为仓库中新写的研究说明和封装源码选择额外的统一开源许可证；第三方许可证只适用于相应第三方组件。
