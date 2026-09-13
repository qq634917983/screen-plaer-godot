# ScreenPlayer — 跨窗口同步播放器

基于 **Godot 4.7.2** 的 Windows x86_64 / macOS ARM64 桌面媒体播放器：单进程多窗口，预览端与输出端独立播放，
独立投屏窗口共享输出端纹理实现零延迟画面同步。支持视频 / 音频 / 图片 / 网页 / PPT 混排播放。

主程序是 Godot 原生桌面应用。内嵌 CEF 用于网页/PPT 媒体播放；未来可另加简单网页后台遥控器，当前尚未实现。

双平台依赖、启动方法与验证范围见 [doc/PLATFORMS.md](doc/PLATFORMS.md)。

## macOS 运行

`master` 已合并 ARM64 macOS 与 x86_64 Windows 的双平台适配，共用业务逻辑，按平台加载原生依赖。
macOS 适配由 GPT 从 Windows 稳定基线开始，完整提交历史已合入 `master`；仓库只维护主分支。
本机已构建依赖，可执行 `./tools/run_macos.sh`；新克隆先执行
`brew install mpv cmake`、`./tools/build_macos.sh --with-cef`（需要完整 Xcode）。
已验证 Apple M4 / Godot 4.7.2 的视频、图片、网页、PPT 与独立窗口投屏。
构建、测试及分发限制见 [doc/MACOS.md](doc/MACOS.md)。

## 功能特性

- **品牌化启动**：使用蓝青播放器图标作为项目和 Windows 程序图标；Godot 原生启动画面
  与主场景初始化层保持统一深蓝外观，并显示初始化阶段和加载进度条
- **快速启动**：CEF 浏览器进程改为首次打开网页、PPT 或网页条目设置时才初始化；
  普通视频、音频和图片启动不再等待网页组件。首次使用时会显示初始化进度，完成后
  自动继续原来的预览或输出操作。同一台 Windows 测试机的 Release 主窗口就绪时间
  从约 19.7 秒降至约 7.5 秒
- **双端播放架构**：预览端（始终静音，随意切换不影响输出）+ 输出端，两路独立 MPVPlayer 实例；
  「快速切换」一键把预览的路径 / 播放状态 / 当前进度推送到输出端；两个播放器采用
  标题栏 / 黑色视频内容 / 控制栏三段式卡片布局；标题栏和控制栏高度固定，黑色内容区
  吸收窗口高度变化，实际画面在其中保持 16:9 完整显示
- **独立投屏窗口**：无边框置顶的原生窗口，通过 `frame_updated` 信号共享输出端纹理——
  两端显示同一块像素缓冲，画面零延迟完全一致，无任何状态同步代码
- **多媒体混排**：
  - 视频 / 音频 — mpv 解码（自编译 godot_mpv 完整版扩展）
  - 图片 — 静态纹理通路
  - 网页 — CEF 内嵌浏览器（gdcef），鼠标事件转发，可编辑「触点」逐步模拟点击
  - PPT — PPTX 后台转自包含 HTML（PPTX2HTML）缓存播放，按页跳转，画面内 < > 翻页
- **媒体库卡片**：媒体与播放列表统一为无边框、无圆角的标题 / 预览 / 3×2 按钮结构；
  媒体库外框与滚动内容区同样使用直角边框；标题栏“编辑顺序”可调整所有卡片的
  混排位置并随项目保存；支持缩略图后台截取、
  条目级静音 / 循环偏好、缩放与偏移设置、丢失文件标记、三档尺寸和拖入媒体快速添加
- **播放列表**：条目连播次数、距下一项间隔，列表总时长循环，定时自动播放（HH:MM 跨午夜）
- **无边框主窗口**：自绘标题栏 + 八向边缘缩放，逐帧移动窗口避开 Windows 模态消息循环，
  拖动 / 缩放全程播放与投屏画面不冻结；主窗口宽高自动保存并在下次启动恢复
- **六区域自由布局**：预览播放器 / 转场 / 输出播放器可分别横向拖动，外层分割线可调整
  播放区 / 常用功能 / 媒体库 / 音频控制的宽高；所有位置按窗口比例持久化，不再使用
  人工最大/最小百分比。设置窗口支持保存、恢复、设为默认、导入和导出 `.spllayout` 布局文件
- **统一工作区外观**：媒体库、常用功能和音频控制与播放器共用标题栏、内容区色板；
  预览与输出播放器外壳无边框，转场、媒体库、常用功能和音控台使用 2px 窄边框；
  六个组件的顶部标题栏统一为 40px 高度；窗口标题栏使用独立蓝灰色，播放器控制按钮无矩形描边，
  快速切换使用靠上的宽短单行按钮
- **纵向音频调音台**：主音量及每个视频/音频 item 各有一列纵向音量条和静音按钮；
  每列均有独立标题栏，item 音量、静音随项目保存，通道较多时可横向滚动；上下分割线
  拖到极限时仍会保留组件标题栏
- **集中帮助**：主界面工作区不显示提示段落；播放器、媒体库、音频、常用功能和
  投屏操作说明集中在设置窗口的“帮助”页

## 技术栈

| 组件 | 说明 |
|---|---|
| Godot 4.7.2 | 主程序框架，Windows D3D12 / macOS Metal |
| godot_mpv（自编译） | 视频解码扩展，源码在 doc/godot_mpv-master/（不入库） |
| gdcef v0.20.0 + CEF 151 | 内嵌浏览器，产物在 cef_artifacts/（不入库） |
| PPTX2HTML | PPT 转换，vendor 依赖在 pptx_renderer/js/ |

## Windows 运行前准备

Windows MPV 运行包已压缩放入 `bin/win-bin.zip`，关闭编辑器后执行
`powershell -ExecutionPolicy Bypass -File tools/restore_windows_mpv.ps1` 恢复。
CEF 仍需自行补齐：

| 路径 | 说明 |
|---|---|
| `cef_artifacts/`（约 397MB） | gdcef.gdextension + libcef.dll 等 CEF 产物，重建方法见 `doc/TODO.md` |
| `bin/libmpv-2.dll`（约 117MB） | mpv 主库，从仓库内 win-bin.zip 恢复 |
| `doc/godot_mpv-master/`、`doc/gdcef/` | 扩展完整源码与构建环境（VS2026 + CMake） |

其余 `bin/` 下已提交的 DLL（godot_mpv 扩展、GLES 等）可直接使用。

用 Godot 4.7.2 打开 `project.godot` 运行主场景即可；`*.splproj` 为项目媒体库存档。

## 手动编译 Windows Release 发行版

以下流程生成正式 Release，不是 Debug。需要准备：

- Windows x86_64 与 Godot 4.7.2 x86_64 console 版；
- Godot 4.7.2 Export Templates 压缩包 `Godot_v4.7.2-stable_export_templates.tpz`；
- Visual Studio 的“使用 C++ 的桌面开发”组件，用于取得官方 VC++ x64 Redist；
- 完整的 `bin/` MPV 依赖和 `cef_artifacts/windows/` CEF 运行文件。

打开 PowerShell，进入项目根目录：

```powershell
cd D:\code\godot\screen-plaer-godot
```

首次克隆项目时，先恢复仓库内压缩保存的 MPV 文件并检查全部 Windows 依赖：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\restore_windows_mpv.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check_windows_runtime.ps1
```

执行正式发行构建，路径按本机实际安装位置修改：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_windows_release.ps1 `
  -Godot "D:\app\godot\Godot_v4.7.2-stable_win64_console.exe" `
  -TemplateArchive "D:\Download\Godot_v4.7.2-stable_export_templates.tpz"
```

模板第一次使用后会缓存在 `.build/export_templates/`，以后可以省略
`-TemplateArchive`：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_windows_release.ps1 `
  -Godot "D:\app\godot\Godot_v4.7.2-stable_win64_console.exe"
```

脚本使用 `windows_release_x86_64.exe` 模板和 Godot 的 `--export-release` 参数，
GDScript 会编译为字节码并嵌入 PCK；Godot AI 调试助手、测试、文档、工具和 CEF
缓存不会进入发行包。构建日志出现下面两行，说明发行目录中的 MPV 与 CEF 已经实际
通过 Windows 加载检查：

```text
PASS release native load: libgodot_mpv.windows.template_release.x86_64.dll
PASS release native load: libgdcef.dll
```

构建产物：

| 位置 | 用途 |
|---|---|
| `dist/ScreenPlayer-Windows-x86_64/` | 解压后的完整运行目录，可在本机测试 |
| `dist/ScreenPlayer-Windows-x86_64.zip` | 发给其他 Windows x86_64 机器的发行包 |

必须分发完整 ZIP，不能只复制 `ScreenPlayer.exe`。脚本会把 MPV、CEF 和官方 VC++
x64 运行库部署到 exe 旁，并将 MPV 的 ANGLE 库隔离为 `mpvEGL.dll`、
`mpvGLES2.dll`，避免被 CEF 的同名 DLL 覆盖。

也可以在 Godot 中打开“项目 → 导出 → Windows Desktop”，取消 **Export With
Debug** 后导出，但编辑器只完成 Godot 导出，不执行本项目的 ANGLE 隔离、VC++
运行库部署和 DLL 加载检查。因此对外发布必须使用上述 PowerShell 构建脚本生成的 ZIP。

## 目录结构

```
main.tscn / scripts/main.gd   主场景与主逻辑（媒体库 + 双端调度 + 项目管理）
scripts/player_slot.gd        播放端封装（MPV / 静态 / CEF 网页 / PPT 四类帧源）
scripts/title_bar.gd          无边框自绘标题栏
scripts/window_resizer.gd     边缘缩放
scripts/media_object.gd       媒体条目数据模型
scripts/media_item_card.gd    媒体库卡片
scripts/playlist_*.gd         播放列表（数据 / 执行器 / 卡片 / 设置窗口）
scripts/pptx_converter.gd     PPTX→HTML 后台转换器
scripts/project_store.gd      项目持久化（*.splproj + settings.cfg）
pptx_renderer/                PPT 播放器壳 + vendor 依赖
doc/                          设计稿、任务清单（TODO.md）、测试文件
```

进度与细节真相来源：`doc/TODO.md` 与 `AGENTS.md`。

Windows 克隆后遇到 Error 126：使用 tools/install_windows_runtime.ps1 从匹配运行包安装依赖，
再运行 tools/check_windows_runtime.ps1；详细安装与分发步骤见 [双平台文档](doc/PLATFORMS.md#windows-error-126-修复与可重复安装2026-09-09)。
