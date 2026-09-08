# macOS 开发运行说明

ScreenPlayer 是支持独立窗口投屏的媒体播放系统。Windows 版本已基本正常；
`codex/macos-support` 从 `2d6ab86` 开始由 GPT 进行多系统适配。

## 本机运行

已在 Apple M4 / macOS / Godot 4.7.2（Metal）验证。
当前机器的依赖与原生扩展已经构建好，在项目目录执行：

```sh
./tools/run_macos.sh
```

也可以用 Godot 打开 `project.godot` 后运行主场景。
首次打开须等待导入完成；启动脚本会自动完成这一步。

## 从新克隆构建

需要 Godot 4.7.2、完整 Xcode（CEF 的 `ibtool` 必需）、Homebrew。
构建脚本按本机架构选择 arm64 / x86_64，不生成 universal 包。

```sh
brew install mpv cmake
./tools/build_macos.sh --with-cef
./tools/run_macos.sh
```

仅重建视频内核：`./tools/build_macos.sh`。
`GODOT_BIN` 可指定 Godot 可执行文件；`SCREENPLAYER_BUILD_DIR` 可指定构建目录
（默认 `.build/`）。CEF 源码与下载缓存放 `doc/gdcef/`。
脚本固定 godot-cpp、gdcef 提交以及 Python 构建工具版本，下载 CEF 后校验上游摘要。
第三方源码、CEF 的约 324MB 运行包、Mac dylib、构建缓存均不进入 Git。

## 实现

- Windows 继续使用原来的 `bin/*.dll`，D3D12 设置不变。
- Mac 使用 `native/mpv/` 的 MPVPlayer 扩展，经 Homebrew libmpv 解码，
  使用软件 render API 生成 ImageTexture，可用于 Metal 与 Compatibility 渲染。
  保留源画面显示尺寸；预览/输出各一实例，封面截取另有一个后台实例。
  投屏仍直接共享输出纹理，无额外解码或状态同步。
- CEF 使用同一 gdcef API 与 PPTX2HTML 管线。`tools/build_cef_macos.py`
  修复上游 Mac framework 拷贝、Helper 重签名、外部消息循环，并安装
  `native/cef_application_mac.mm` 来补接 CEF 要求的 NSApplication 事件协议。
  源码改动仅在 Mac 构建脚本中应用，不修改 Windows 二进制。
- Mac 浏览器缓存/日志放 `user://cef_cache`、`user://cef.log`，不写应用安装目录。
- 本地网页统一生成编码后的 file URL，支持中文、空格、`#`、Windows 盘符与 UNC。
- 字体增加 Apple Symbols / PingFang SC 回退；四分区按实际控件最小尺寸钳制，
  防止不同平台字体高度导致控制条被覆盖。

## 回归验证

先运行启动脚本或编辑器导入，再运行下列测试（测试输出始终静音）：

```sh
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 -t 8 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac '/tmp/screenplayer 测试 #1.mp4'
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --script tests/macos_smoke.gd -- '/tmp/screenplayer 测试 #1.mp4'
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --script tests/macos_web_smoke.gd
```

测试覆盖实际视频帧/进度/静音、暂停 seek、循环、后台封面、图片投屏、
输出与投屏纹理同一性、预览独立性、Mac 字体布局，以及本地 HTML 触点、
26 页 PPT 转换、缓存加载与翻页投屏。网页点击测试等待首幅内容绘制完成。

## 验证边界

这是可在当前 Mac 开发运行的版本，尚未制作可脱离 Homebrew 分发的签名/公证 `.app`。
视频 dylib 动态依赖本机 Homebrew 库；复制整个目录到另一台 Mac 后需要安装依赖并重建。
Intel Mac 和 Windows 真机回归尚未执行，外接多显示器及 4K 性能也尚未实测。
软件渲染会产生 CPU 像素拷贝，高分辨率性能需按实际片源验证。

已有 Windows 项目中的 `D:/...` 绝对路径在 Mac 上不会自动映射，需要重新添加本机文件。
网页/PPT 播放仍沿用原有 CEF 静音规则；音量滑条只控制 mpv 音频。

构建依据：
[libmpv render API](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h)、
[gdcef](https://github.com/Lecrapouille/gdcef)、
[CEF macOS 应用协议](https://github.com/chromiumembedded/cef/blob/master/include/cef_application_mac.h)。
第三方库许可证保留在下载的源码/运行包中，分发产品时需一并处理这些依赖的许可证。
