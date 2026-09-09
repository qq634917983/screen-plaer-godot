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

从之前已经正常运行的 Windows 项目保留/复制完整 `cef_artifacts/` Windows CEF 运行库。MPV 可从仓库内 `bin/win-bin.zip` 恢复。CEF 的 pak、locales、辅助程序等须整套保留，不能只复制 libcef.dll。
不要使用 Mac 目录覆盖 Windows 目录。其余 Windows 播放 DLL 已在 Git 中。

```powershell
powershell -File tools/run_windows.ps1 -Godot 'C:\Godot\Godot_v4.7.2-stable_win64.exe'
```

启动脚本缺少 MPV DLL 时自动从 `bin/win-bin.zip` 恢复，再检查主要运行库并导入启动。
若直接使用编辑器，先关闭 Godot，然后执行一次：

```powershell
powershell -ExecutionPolicy Bypass -File tools/restore_windows_mpv.ps1
```

恢复脚本只提取五个 Windows DLL，不覆盖双平台 `.gdextension` 或 Mac 库。
Error 126 也可能表示目标 DLL 的依赖缺失；本次旧运行包中的四个小 DLL 与 Git 版本
逐字节相同，补齐未入库的 `libmpv-2.dll` 是首要修复。若恢复后仍报错，需在 Windows
检查系统运行库与实际加载错误（EGL/GLES 还依赖 MSVCP140.dll、VCRUNTIME140.dll、VCRUNTIME140_1.dll），不能仅凭当前 Mac 上的文件检查断言已解决。
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
解压后的大型 libmpv、CEF 和 Mac 本地构建产物仍忽略；Windows MPV 压缩包随仓库提供。
**仅克隆 Git 仓库并不包含完整运行环境**，必须按上面步骤补齐对应平台依赖。

## 验证范围

ARM Mac 已实际验证视频进度、静音、暂停跳转、循环、封面、图片、网页触点、
PPT 转换/翻页及输出与投屏共享纹理。Windows 沿用此前正常运行的播放 DLL，
此次检查平台选择和启动/导出依赖；当前机器无法执行 Windows 真机测试，
不能据此承诺 Windows 本轮实测通过。

Windows 上更新后应验证：视频预览→快速切换→暂停跳转、卡片直接播放、
图片/网页/PPT 切换、投屏显隐、窗口拖动缩放，以及退出后重新打开项目。
