# v0.1.0 — BE6L Pro 单文件 Telnet RAM 启动

从正常原厂系统，仅经网线和 Telnet 启动 XWRT initramfs；无需 TTL、Python、OpenSSL 或外部数据目录，不刷写固件。

## 下载

- **普通使用：`Start-BE6L-Ramboot.ps1`**，或者只包含同一脚本的 `BE6L-Pro-RAM-Boot.zip`。
- `SHA256SUMS`：发布附件校验值。
- `ramboot-payloads.zip`、`loader-inputs.zip`：供源码复现使用，普通运行不需要下载。
- `THIRD-PARTY-NOTICES.txt`：第三方组件的来源和许可证说明。

```powershell
.\Start-BE6L-Ramboot.ps1
```

按提示输入原厂网页管理密码。脚本默认自动识别 .16/.51，再选择对应的 Telnet 密码算法，不需要传版本参数。

## 验证与限制

- 原厂 `V16.03.60.16_cn`、`V16.03.60.51_cn` 均已完成 Telnet root 和 RAM 启动验证。
- 最终单文件 PS1 在 .51 上完成完整实测：仅有一个输入文件、未访问 TTL，并从网络确认 `rootfs_type=initramfs`、Linux 6.18.52。
- 最终 PS1 的 .16 自动选择及密码分支已做回归检查；该封装版没有再次降级完整重测 .16。
- 修复旧分文件脚本默认按 .16 密码算法登录 .51、随后才检查版本的问题。当前版本不符或未知固件会在 Telnet 登录前停止。
- **实验版：无线暂时禁用。** 原始设备树在 kexec 后会触发 mt7996e 初始化超时及崩溃，目前验证的是有线 RAM 系统。
- `.62XD` 尚未完成验证，当前脚本不支持直接运行；不能据此判定该固件无法内存启动。

成功后的管理页：`http://192.168.15.1/`，账号 / 密码 `admin` / `admin`。重启返回闪存中的原厂固件。

完整研究、源码、脱敏证据与构建方法见仓库 README。
