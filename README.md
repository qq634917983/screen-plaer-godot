# ScreenPlayer — 跨窗口同步播放器

基于 **Godot 4.7.2** 的 Windows x86_64 / macOS ARM64 桌面媒体播放器：单进程多窗口，预览端与输出端独立播放，
独立投屏窗口共享输出端纹理实现零延迟画面同步。支持视频 / 音频 / 图片 / 网页 / PPT 混排播放。

主程序是 Godot 原生桌面应用。内嵌 CEF 用于网页/PPT 媒体播放；未来可另加简单网页后台遥控器，当前尚未实现。

双平台依赖、启动方法与验证范围见 [doc/PLATFORMS.md](doc/PLATFORMS.md)。

## macOS 运行

`master` 已合并 ARM64 macOS 与 x86_64 Windows 的双平台适配，共用业务逻辑，按平台加载原生依赖。
macOS 适配由 GPT 在 `codex/macos-support` 分支从 Windows 稳定基线开始，保留完整提交历史。
本机已构建依赖，可执行 `./tools/run_macos.sh`；新克隆先执行
`brew install mpv cmake`、`./tools/build_macos.sh --with-cef`（需要完整 Xcode）。
已验证 Apple M4 / Godot 4.7.2 的视频、图片、网页、PPT 与独立窗口投屏。
构建、测试及分发限制见 [doc/MACOS.md](doc/MACOS.md)。

## 功能特性

- **双端播放架构**：预览端（始终静音，随意切换不影响输出）+ 输出端，两路独立 MPVPlayer 实例；
  「快速切换」一键把预览的路径 / 播放状态 / 当前进度推送到输出端
- **独立投屏窗口**：无边框置顶的原生窗口，通过 `frame_updated` 信号共享输出端纹理——
  两端显示同一块像素缓冲，画面零延迟完全一致，无任何状态同步代码
- **多媒体混排**：
  - 视频 / 音频 — mpv 解码（自编译 godot_mpv 完整版扩展）
  - 图片 — 静态纹理通路
  - 网页 — CEF 内嵌浏览器（gdcef），鼠标事件转发，可编辑「触点」逐步模拟点击
  - PPT — PPTX 后台转自包含 HTML（PPTX2HTML）缓存播放，按页跳转，画面内 < > 翻页
- **媒体库卡片**：缩略图后台截取、条目级静音 / 循环偏好、缩放与偏移设置、
  丢失文件自动置灰标记、三档卡片尺寸
- **播放列表**：条目连播次数、距下一项间隔，列表总时长循环，定时自动播放（HH:MM 跨午夜）
- **无边框主窗口**：自绘标题栏 + 八向边缘缩放，逐帧移动窗口避开 Windows 模态消息循环，
  拖动 / 缩放全程播放与投屏画面不冻结
- **内容区十字四分区**：预览 / 实用功能 / 媒体 / 音频四象限可拖拽布局，比例持久化

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
