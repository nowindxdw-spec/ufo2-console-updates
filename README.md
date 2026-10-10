# UFO2 Console 发行资产

本仓库只放各版本 Windows 安装包与 latest.json（下载通道入口）。源码是 Microsoft UFO2（MIT）的本机包装层。

- 最新版：<https://github.com/nowindxdw-spec/ufo2-console-updates/releases/latest>
- 机器可读清单：<https://raw.githubusercontent.com/nowindxdw-spec/ufo2-console-updates/main/latest.json>

目标机一键安装 / 升级：

```powershell
powershell -ExecutionPolicy Bypass -File install-latest.ps1 -Repo nowindxdw-spec/ufo2-console-updates
```powershell

每个资产旁都有同名 .sha256；安装脚本校验通过才落盘安装。
