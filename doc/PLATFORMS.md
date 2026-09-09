# 双平台运行与验证

只支持 **Windows x86_64** 和 **macOS ARM64**，使用同一主场景和播放/投屏逻辑。
Godot 按 `.gdextension` 平台条目选择对应原生库，不使用另一平台的库。

| 项目 | Windows x86_64 | macOS ARM64 |
| --- | --- | --- |
| Godot | 4.7.2 x86_64 | 4.7.2 arm64 |
| 播放扩展 | `bin/libgodot_mpv.windows.template_release.x86_64.dll` | `bin/libgodot_mpv.macos.arm64.dylib` |
| mpv | `bin/libmpv-2.dll` 与 EGL/GLES/zlib DLL | 本机 Homebrew libmpv |
| 浏览器 | 完整 `cef_artifacts/windows/` | 完整 `cef_artifacts/macos/` |
| 启动入口 | `tools/run_windows.ps1` | `tools/run_macos.sh` |

## Windows

从之前已经正常运行的 Windows 项目保留/复制完整 `cef_artifacts/` 和
`bin/libmpv-2.dll`。CEF 的 pak、locales、辅助程序等须整套保留，不能只复制 libcef.dll。
不要使用 Mac 目录覆盖 Windows 目录。其余 Windows 播放 DLL 已在 Git 中。

```powershell
powershell -File tools/run_windows.ps1 -Godot 'C:\Godot\Godot_v4.7.2-stable_win64.exe'
```

启动脚本检查目标架构和主要运行库，完成 Godot 导入后启动主场景。
Windows 导出依赖已列入 mpv、EGL、GLES 和 zlib；CEF 仍须按完整运行包部署。

## Mac

```sh
brew install mpv cmake
./tools/build_macos.sh --with-cef
./tools/run_macos.sh
```

需要完整 Xcode；本机已经构建好时只执行最后一行。
详见 [MACOS.md](MACOS.md)。

## Gitee 中包含什么

上传的是源代码、构建/启动脚本及已入库的 Windows 小型 DLL。
大型 libmpv/CEF 和 Mac 本地构建产物仍按既有规则忽略。
**仅克隆 Git 仓库并不包含完整运行环境**，必须按上面步骤补齐对应平台依赖。

## 验证范围

ARM Mac 已实际验证视频进度、静音、暂停跳转、循环、封面、图片、网页触点、
PPT 转换/翻页及输出与投屏共享纹理。Windows 沿用此前正常运行的播放 DLL，
此次检查平台选择和启动/导出依赖；当前机器无法执行 Windows 真机测试，
不能据此承诺 Windows 本轮实测通过。

Windows 上更新后应验证：视频预览→快速切换→暂停跳转、卡片直接播放、
图片/网页/PPT 切换、投屏显隐、窗口拖动缩放，以及退出后重新打开项目。

## Windows Error 126 修复与可重复安装（2026-09-09）

本次定位：扩展 DLL 存在，但其依赖 `bin/libmpv-2.dll` 被 Git 忽略，克隆后缺失；
`cef_artifacts/` 也缺失。已从本机旧 Windows 项目恢复匹配的原生库。
Windows LoadLibrary 会继续加载依赖 DLL，因此报错中的扩展路径存在也可能返回 126。

仓库现在提供 Windows 运行库锁定清单（逐文件 SHA-256，包含 CEF locales/pak/helper，
排除浏览器缓存与构建中间文件），安装前校验源文件，启动前校验文件及真实 DLL 加载：

```powershell
# SourceRoot 是旧正常项目或运行库 ZIP 解压目录，内含 bin/ 和 cef_artifacts/
powershell -File tools/install_windows_runtime.ps1 -SourceRoot 'D:\runtime\screenplayer-windows'
powershell -File tools/check_windows_runtime.ps1
powershell -File tools/run_windows.ps1 -Godot 'D:\app\godot\Godot_v4.7.2-stable_win64_console.exe'

# 在已补齐依赖的机器生成可传递运行包（不入 Git）
powershell -File tools/pack_windows_runtime.ps1
```

默认运行包：`dist/screenplayer-runtime-windows-x86_64-2026-09-09.zip`。
新机器先解压，再执行安装脚本。脚本只安装清单内的文件，不覆盖已有不同版本文件，
不改系统 PATH，不复制 CEF 浏览数据，不触碰 Mac 原生库。升级原生库时需重新验证、
更新锁定清单并生成新的版本包。当前没有公开托管下载地址，不能只拉 Git 就自动补齐。

推荐的发布流程：业务源代码共用；按操作系统/CPU 分别构建原生依赖；固定版本与哈希；
把完整运行库作为 Release 附件或制品仓库内容；CI 在 Windows x64 / Mac ARM64
分别做实际加载与播放测试；最终面向用户发布自包含安装包。
本轮已落实 Windows 清单、安装、校验和本地打包，尚未搭建远程制品托管或 CI。
Mac 当前 Homebrew 依赖仅适合开发；正式 .app 应捆绑 dylib、修正加载路径并签名公证。

官方依据：
- [Microsoft DLL 搜索与依赖加载规则](https://learn.microsoft.com/zh-cn/windows/win32/dlls/dynamic-link-library-search-order)
- [Godot 平台库选择与导出依赖声明](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html)

本机 Windows 4.7.2 / D3D12 / GTX 1050 已验证原生库加载、视频进度/纹理、预览静音状态、
暂停 seek、输出接收暂停进度、输出与投屏共享纹理、预览独立、循环、封面和图片切换。
运行测试：`godot --path . --script tests/windows_smoke.gd -- <视频绝对路径>`。
本次没有重测 Mac、外接屏/4K，以及网页/PPT 完整交互流程（CEF 原生加载与初始化已通过）。

远程同步补充：仓库已包含 bin/win-bin.zip，可用 tools/restore_windows_mpv.ps1 恢复 MPV；run_windows.ps1 缺少 MPV 时自动恢复，随后执行完整哈希与加载检查。CEF 仍需独立补齐。
