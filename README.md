# Tenda BE6L Pro：仅网线 + Telnet 启动 RAM initramfs

从正常运行的原厂固件，通过网线和 Telnet 将 XWRT initramfs 装入内存并执行 kexec。**无需拆机、TTL 或进入 U-Boot，不刷写固件；重启后回到原厂系统。**

> 当前镜像暂时禁用无线设备，以避开 kexec 后 mt7996e 初始化崩溃。有线网络和管理页已验证。本项目是研究成果，不等同于完整无线固件适配。

## 下载与运行

从 **[Releases](https://github.com/YangZJ781/Tenda-BE6L-Pro-Telnet-only-ramboot/releases/tag/v0.1.0)** 下载 `Start-BE6L-Ramboot.ps1`，或者下载只含该文件的 `BE6L-Pro-RAM-Boot.zip`。

**只需要这一个 PS1**，约 20 MB，已内嵌全部启动文件。Windows PowerShell 5.1 / PowerShell 7 均可运行，无需 Python、OpenSSL、额外数据目录或 TTL。

电脑用网线接路由器 LAN，在脚本所在目录运行：

```powershell
.\Start-BE6L-Ramboot.ps1
```

按提示输入原厂网页管理密码。默认访问 `192.168.0.1`，**自动识别 .16 / .51 并选择对应的 Telnet 密码算法，无需传版本参数**。

如果执行策略阻止运行，可仅为当前进程设置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-BE6L-Ramboot.ps1
```

启动后电脑会通过 DHCP 获得 `192.168.15.x`，管理页为 **<http://192.168.15.1/>**，账号 / 密码为 **`admin` / `admin`**。脚本会从网络读取 `rootfs_type=initramfs` 确认启动结果；不只检查 ping。

## 验证范围

| 原厂固件 | Telnet root | 经 Telnet 启动 initramfs | 备注 |
| --- | --- | --- | --- |
| `V16.03.60.16_cn` | 已验证 | 已验证 | 单文件版的版本选择与密码分支另有回归检查 |
| `V16.03.60.51_cn` | 已验证 | 已验证 | 单文件 PS1 在仅有一个输入文件的目录中完整实测，无 TTL |
| `V16.03.60.62XD` | 未完成验证 | 未测试 | 不能据此判定固件不支持；当前脚本会提前停止 |

测试日期：2026-10-19；设备为 BE6L Pro V1.0。原厂内核 Linux 5.4.55，RAM 镜像 X-WRT `26.04_b202609230606` / Linux 6.18.52。测试结果保存在 [evidence/](evidence/)。

## 其他选项

```powershell
# 只核验内嵌文件，不连接路由器
.\Start-BE6L-Ramboot.ps1 -CheckFiles

# 自动识别、登录并检查条件，不上传或切换系统
.\Start-BE6L-Ramboot.ps1 -CheckOnly

# 上传并预装载，暂不切换系统
.\Start-BE6L-Ramboot.ps1 -LoadOnly

# 可选：限定必须是 .51；不符时在 Telnet 登录前停止
.\Start-BE6L-Ramboot.ps1 -Firmware 51

# 指定原厂地址
.\Start-BE6L-Ramboot.ps1 -RouterIP 192.168.0.1
```

日志生成在脚本旁的 `ramboot-logs/`。脚本不会更改电脑网卡、防火墙或原厂 `/tmp` 容量，也不会自动下载启动文件。`-LoadOnly` 后重新运行前，可先正常重启原厂系统以清除上次的 RAM 文件。

## 研究与源码

- [研究过程与技术结论](docs/research.md)：密码派生、kexec 分段、内存容量、无线崩溃。
- [构建与复现](docs/build.md)：从 Release 输入包构建出与实测文件逐字节相同的单文件 PS1。
- [第三方组件与来源](docs/provenance.md)、[许可证说明](NOTICE.md)。
- [源码模板](src/Start-BE6L-Ramboot.template.ps1)：网页鉴权、AES、Telnet 协议协商、TFTP、装载和网络验证。
- [分段装载器生成源码](tools/build_split_loader.py)。

仓库只保存源码、说明、校验清单和脱敏证据；完整的一键脚本和二进制输入放在 Release。没有上传设备备份、个人配置、完整原始串口日志、设备序列号或原厂管理密码。
