# v0.1.2 — 新增 .18 / .22 / .40 / .57

自动识别七版原厂固件，选择各自 Telnet 密码种子；未知版本或显式版本不符仍会在 Telnet 登录前停止。内嵌六个启动文件与 v0.1.1 相同。

2026-10-21，新增四版均完成原厂升级、12 项 MTD 备份、派生密码 root 登录和完整单文件 RAM 启动验证。运行流程仅网线 / Telnet，无 TTL、Python、OpenSSL 或外部数据目录；RAM 启动不写闪存。

下载 `Start-BE6L-Ramboot.ps1` 即可直接运行，或下载仅包含相同脚本的 `BE6L-Pro-RAM-Boot.zip`。`SHA256SUMS` 提供附件校验值；`ramboot-payloads.zip`、`loader-inputs.zip` 和 `THIRD-PARTY-NOTICES.txt` 供复现与来源核对，普通使用不需要下载。

运行 `./Start-BE6L-Ramboot.ps1` 后按提示输入网页管理密码，无需选择版本。成功后管理地址为 http://192.168.15.1/，账号和密码均为 admin。无线仍暂时禁用，重启返回原厂固件。.16 / .51 / .62 的完整启动结果沿用历史记录。

实测 PS1 SHA-256：`a28c155fcb028d8094cc3a8bfe9edf208bc15cb42ea18bf553e75892bc2b82cf`。详细证据见 `docs/firmware-20261021.md` 和 `evidence/firmware-18.json` 等文件。
