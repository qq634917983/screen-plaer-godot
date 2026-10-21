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
Windows 发行脚本部署 mpv、CEF、EGL/GLES、zlib 及官方 VC++ x64 Redist。
MPV 和 CEF 使用不同版本但原名相同的 ANGLE DLL；发行包把 MPV 一侧改为
`mpvEGL.dll` / `mpvGLES2.dll`，CEF 保留原名，不能再直接覆盖合并这两套文件。

### 编译并生成 Windows 安装包

在 **Windows x64** 构建机上操作（推荐 Windows 10/11）。当前发行流程使用
PowerShell、Godot 4.7.2 x86_64、Godot 4.7.2 导出模板、项目锁定的 Windows
MPV/CEF 运行库、Visual Studio 的 VC++ x64 Redist，以及 Inno Setup 6 或 7。
CEF 和 MPV 的版本及每个运行文件的 SHA-256 记录在
`tools/windows-runtime.lock.json`；不要从其他版本拼接 DLL，也不要用 macOS 文件替换。

1. 克隆仓库并进入项目目录：

   ```powershell
   git clone https://github.com/qq634917983/screen-plaer-godot.git
   cd screen-plaer-godot
   ```

2. 安装并准备 Godot 4.7.2 x86_64 与匹配的导出模板。可在 Godot 编辑器中安装
   `4.7.2.stable` 导出模板；或下载与 Godot 版本一致的
   `Godot_v4.7.2-stable_export_templates.tpz`。如 Godot 不在 PATH，后续命令通过
   `-Godot` 指定 exe 路径；如模板未安装，通过 `-TemplateArchive` 指定 tpz 文件。

3. 准备项目 Windows 原生运行库。大型 CEF 文件不保存在 Git 中，需从已有的、与
   清单版本一致的 Windows 开发环境复制**完整** `cef_artifacts/windows/` 目录，连同
   `bin/libmpv-2.dll`，放回仓库对应路径。仓库已跟踪的 MPV 支持 DLL 也需保留。
   如果拿到的是包含 `cef_artifacts/windows/...` 和 `bin/libmpv-2.dll` 的完整运行包，
   先解压到临时目录，再让安装脚本按清单校验并复制缺失文件：

   ```powershell
   Expand-Archive C:\downloads\screenplayer-runtime-windows-x86_64.zip C:\screenplayer-runtime
   .\tools\install_windows_runtime.ps1 -SourceRoot C:\screenplayer-runtime
   ```

   `install_windows_runtime.ps1` 会先校验整个来源包的 SHA-256，再复制文件；如已存在
   目标中已存在同名但哈希不匹配的文件，会停止而不会覆盖；哈希匹配的文件会跳过，缺失文件才会复制。运行 `check_windows_runtime.ps1` 可单独
   检查文件哈希及原生 DLL 加载。CEF 不齐或哈希不符时不能继续打包。

4. 安装 Visual Studio 2022 的 C++ x64 工具/运行库（或 Build Tools 中相应组件），确保
   安装目录含 `VC/Redist/MSVC/<版本>/x64/Microsoft.VC*.CRT/`，其中包括
   `msvcp140.dll`、`vcruntime140.dll` 和 `vcruntime140_1.dll`。脚本会自动选择本机
   最新的 x64 CRT 目录；若自动查找不到，可在构建命令中传 `-VCRuntimeDirectory`。
   安装 Inno Setup 6/7，使 `ISCC.exe` 位于默认检测路径，或使用 `-InnoCompiler`
   显式传入其路径。

5. 在项目根目录运行完整发行构建和安装包编译：

   ```powershell
   .\tools\build_windows_installer.ps1 `
     -Godot 'C:\Godot\Godot_v4.7.2-stable_win64.exe' `
     -TemplateArchive 'C:\downloads\Godot_v4.7.2-stable_export_templates.tpz' `
     -VCRuntimeDirectory 'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.xx.xxxxx\x64\Microsoft.VC143.CRT' `
     -InnoCompiler 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
   ```

   参数可省略：Godot 在 PATH、导出模板已安装、VC++ CRT 位于 Visual Studio 默认目录、
   Inno Setup 位于脚本默认路径时，执行 `./tools/build_windows_installer.ps1` 即可。
   该流程先校验运行库，再导入资源并导出 Windows Release，部署 CEF/MPV/VC++ 文件，
   检查关键文件并从发行目录实际加载 MPV 与 CEF 扩展，生成 ZIP，最后调用 Inno Setup
   生成安装器。版本号从 `project.godot` 的 `config/version` 读取。

6. 产物位于 `dist/`：

   - 可直接解压运行目录：`dist/ScreenPlayer-Windows-x86_64/`
   - 绿色压缩包：`dist/ScreenPlayer-Windows-x86_64.zip`
   - 安装程序：`dist/ScreenPlayer-Setup-<版本号>.exe`

   构建脚本会输出安装程序的大小和 SHA-256。交付前在 Windows x64 上安装测试：启动
   程序并检查 MP4 播放、投屏窗口与快捷键、网页/PPT 页面、设置保存；退出后再从开始菜单
   重启，并通过“应用和功能”卸载。构建产物位于 `dist/`，不提交到 Git。

若只需生成绿色发行目录和 ZIP（不编译安装器），运行
`tools/build_windows_release.ps1`，参数与上例相同。不要使用
`-SkipReleaseBuild`，除非 `dist/ScreenPlayer-Windows-x86_64/` 已由同一提交的
发行构建生成且文件齐全。

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
PPT 转换/翻页及输出与投屏共享纹理。Windows 已在 x86_64 真机完成 MPV 初始化、
视频解码与纹理、暂停跳转、循环、缩略图以及输出/投屏共享纹理测试；发行目录的
MPV/CEF 扩展均通过 LoadLibraryEx 加载，发行程序隐藏启动后正常退出。新机器仍需做
一次完整界面回归。

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

### 发行包同名依赖修复（2026-09-10）

旧发行脚本先复制 MPV 依赖、再把 CEF 文件复制到 exe 目录。两边都有不同版本的
`libEGL.dll` 和 `libGLESv2.dll`，所以 CEF 文件覆盖了 MPV 文件；主程序能启动，
首次创建 MPV 播放器时才会加载失败。修复后构建脚本隔离 MPV 的导入名，并在包内
附带 Visual Studio 官方 x64 CRT DLL。生成 ZIP 前会实际加载 `libgodot_mpv` 与
`libgdcef`，因此间接依赖缺失或再次发生 DLL 冲突会让构建直接失败。
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
