# 构建与验证

## 复现发布的单文件脚本

**运行发布脚本不需要 Python；只有维护和重新封装才需要 Python 3。**

从相同版本的 Release 下载 `ramboot-payloads.zip`，保存为 `dist/ramboot-payloads.zip`。该 ZIP 保存原样内嵌包，保留其原始元数据，因此可复现已实测 PS1 的字节：

```text
python tools/build_release.py --payload dist/ramboot-payloads.zip --verify-release
```

输出到 `dist/`：单文件 PS1、只含 PS1 的压缩下载、内嵌输入包及 SHA256SUMS。构建会核对输入包、manifest 和全部六个文件的校验值；`--verify-release` 进一步要求最终 PS1 与 [lock.json](../payloads/lock.json) 记录的实测文件 SHA256 一致。

也可从已下载的单文件 PS1 取回相同 ZIP，无需访问路由器：

```text
python tools/extract_payload.py Start-BE6L-Ramboot.ps1 --output dist/ramboot-payloads.zip
```

这复现的是**单文件封装**，并不从源码重编完整 XWRT 固件。内核和运行库的来源、版本、校验值见 [provenance.md](provenance.md)。

## 重建分段装载器

从 `ramboot-payloads.zip` 取出 `data/openwrt-kernel`，从 Release 的 `loader-inputs.zip` 取出原始 `openwrt.dtb`，放入 `.payloads/` 后运行：

```text
python tools/build_split_loader.py --disable-wifi
```

程序输出静态 ARM EABI 装载器、调整后的 DTB 和参数清单。无需 ARM 交叉编译工具；ARM 指令由源码明确编码。最初研究时已对生成指令逐条反汇编核对。发布二进制的 SHA256 位于 `payloads/manifest.json`。

## 离线回归检查

不访问路由器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Test-Standalone.ps1
pwsh -NoProfile -File tests/Test-Standalone.ps1
```

检查自动识别 .16/.18/.22/.40/.51/.57/.62、七套密码夹具、七版显式选择、提前拒绝版本不符/未知版本、内存范围及内置 C# 传输代码编译。`.62` 使用固定 Base64 密码夹具；测试使用脱敏数据，不依赖私有日志。

发布文件自身的离线校验：

```powershell
.\dist\Start-BE6L-Ramboot.ps1 -CheckFiles
```

真实设备完整测试会切换系统，应在需要执行 RAM 启动时运行；普通 CI 不访问实体路由器。
