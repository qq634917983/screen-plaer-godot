# ScreenPlayer — 跨窗口同步播放器（Godot 4.7.2）

## 自动续作指令

每次会话开始时：先读 `doc/TODO.md`，从第一个未勾选的 Phase 条目继续执行，
完成后勾选对应条目并更新本文件的"当前进度"。用户说"继续"即指此流程。
不要重复已完成的工作。

## 业务逻辑（已确认，详见 doc/TODO.md）

- 单击媒体库条目 → 加载到预览播放器（预览可随意切换，不影响输出）
- 点击「快速切换」→ 预览的视频路径+播放状态+当前进度推送给输出播放器
- **共享纹理架构（Phase 4 起）**：全程序只有两个 MPVPlayer 实例（预览/输出）。
  独立投屏窗口不持有实例，其 TextureRect 通过 PlayerSlot 的 `frame_updated`
  信号共享输出端纹理——两端显示同一块像素缓冲，画面零延迟完全一致，
  没有任何状态同步代码。代价：输出/投屏的音频只有一路（实例级属性）
- 预览端始终静音（仅作预览用，无开关无音量条）
- 预览与输出端互不同步；独立播放窗口用 Godot `Window` 节点实现
  （单进程多窗口，无边框置顶）

## 当前进度

- Phase 0-9、11-12 全部完成（doc/TODO.md）；Phase 10（播放体验增强：顺序播放 /
  网页缩放 / PPT 翻页快捷键）已立项待做
- Phase 12（卡片重构，参照 doc/item.html）：标题栏（蓝色序号+文件名+类型徽标）
  + 16:9 画面区 + 无缝 3×2 按钮网格（播放/静音/循环/预览/设置/删除）；
  静音/循环为条目级偏好（MediaObject.loop/muted，持久化），推送输出时应用，
  静音与全局开关为或关系（main.gd _output_muted_state）
- Phase 11（丢失标记 + 复制入库）：丢失文件的卡片置灰 + 红色「已丢失」徽标 +
  禁用播放按钮（窗口重获焦点时自动复查/恢复）；设置窗口「添加文件时复制到
  项目目录」开关（默认关）——开启后媒体真实复制进 X_cache/media/，
  MediaObject.origin_path 记录来源。注意：mpv 只认操作系统路径，
  凡把路径交给 mpv/CEF 前必须 ProjectSettings.globalize_path
  （user:// 项目缓存的副本依赖此修复）
- Phase 9（PPT 播放，PPTX2HTML + CEF）：pptx 经 PptxConverter
  （scripts/pptx_converter.gd，隐藏浏览器 + base64 注入 + 标题轮询）预转成
  自包含 HTML 缓存（全局 user://pptx/<md5>.html，保存项目时同步进
  X_cache/pptx/；封面副本进 X_cache/thumbs/，项目缓存优先于全局查找）；
  播放器壳 pptx_renderer/player.html（双模式：转换 / 缓存加载，导航
  gotoSlide(n)/getSlideCount()，标题 pptx:{页数}）；CEF file:// 下 Worker
  不可用，自动降级主线程 shim（js/worker.inline.js）；PlayerSlot 新增
  SourceKind.SLIDE + load_slides（复用 WEB 通路，seek=跳页，
  next_page/prev_page，get_state 带 page）；进度条对 PPT 按页走
  （"3 / 12"）；PPT 封面 = 首次预览时抓第一页帧；MediaObject 新增
  page_count 持久化。注意 gdcef 的 on_page_loaded 信号参数是
  (http_code, browser) 不带 URL。实测 test.pptx 19 页、doc/test.pptx
  26 页，转换/翻页/推送/缓存重开全部通过
- Phase 8（浏览器内核，CEF + gdcef）：gdcef v0.20.0 源码在 doc/gdcef/
  （godot-4.x 分支，经 ghproxy 镜像克隆；build.py 已适配 CEF 151.3.24 +
  去管理员权限 + 跳过 demo 步骤，重建用 doc/gdcef/run_build.bat）；
  CEF 151.3.24 标准包在 doc/gdcef/thirdparty/cef_binary；
  产物部署在项目根 cef_artifacts/（397MB，含 gdcef.gdextension +
  libgdcef.dll + libcef.dll + gdCefRenderProcess.exe + pak/locales）。
  注意：.godot/extension_list.cfg 由编辑器启动时生成，编辑器运行中新增
  gdextension 需手动加行或重启编辑器（已加 res://cef_artifacts/gdcef.gdextension）；
  扩展注册的类名是 GdCEF/GdBrowserView（大小写敏感）。
  PlayerSlot 新增 SourceKind.WEB + load_web：CEF 离屏渲染直接写各端
  TextureRect（预览/输出各一浏览器实例，共用 main.gd 注入的全局 GdCEF），
  on_browser_paint 转发 frame_updated 投屏无感知共享；浏览器视口固定
  1280×720（WEB_VIEWPORT_SIZE），窗口缩放由 TextureRect 等比完成
  （Phase 8.5：小窗口页面完整可见）；显示区 gui_input 鼠标事件经
  _web_to_browser_pos 反算回固定视口坐标转发浏览器；预览端 set_muted 静音；
  冒烟场景 cef_smoke.tscn 保留可复用。音频结论：CEF 原生出声（无需接管，
  set_audio_stream 仅用于路由进 Godot 加音效，不使用）；音量面板不控制
  网页/PPT 声音，静音经 _apply_volume → browser.set_muted 生效
- Phase 7（帧源抽象 + 图片播放）：PlayerSlot 增加 SourceKind
  { NONE, MPV, STATIC } 帧源标识，新增 load_static(path) 静态纹理通路
  （图片 Image.load_from_file → ImageTexture，发一次 frame_updated，
  投屏窗口无感知共享）；STATIC 期间屏蔽 mpv 残留帧/时间信号；
  toggle_play/seek 对静态媒体为空操作；静态媒体进度条禁用、时间显示 "—"；
  MediaObject.is_playable() 纳入图片
- Phase 6（多媒体媒体库 + 条目设置）：媒体库条目升级为 MediaObject
  （scripts/media_object.gd：类型按扩展名推断 视频/音频/图片/网页/PPT，
  属性含缩放比例/水平/垂直偏移，随 *.splproj 持久化，兼容旧格式）；
  卡片新增 ⚙ 按钮，点击创建独立条目设置窗口（scripts/item_settings_window.gd），
  改动即时应用到画面（PlayerSlot.set_view_transform）并自动保存项目；
  音频走 mpv 播放但画面显示 ♪ 播放符号；图片直接读图做封面；
  图片/网页/PPT 播放分别在 Phase 7/8/9 实现；
  输出播放器控制区为 播放/停止/进度条/静音按钮/时间（音量条移除，
  音量统一由右侧「音频控制」面板调节；%OutputMute 静音按钮切换
  PlayerSlot.muted 并持久化 audio.output，设置窗口勾选也可静音）
- Phase 5（UI 精细化）：控制按钮图标统一为 Segoe UI Symbol 文字字形
  （▶/⏸/■/⟳/🔊/🔇，emoji 字体不再混用）；预览控制区只剩 播放/停止/进度条；
  媒体库改为卡片式（scripts/media_item_card.gd：文件名+缩略图+▶预览/→推送/✕移除，
  点击卡片=预览）；封面由 scripts/thumbnailer.gd 后台截取（第三个 MPVPlayer
  实例，静音不上屏，seek 到设定秒数抓帧，PNG 持久化 user://thumbnails/，
  截取位置在设置窗口可调，默认 1 秒）
- Phase 4（共享纹理重构）：投屏窗口的 CastSlot 已删除，`%CastVideoView`
  共享输出端纹理（运行验证两端 texture 为同一对象）；两阶段起播对齐、
  状态广播、apply_state 等同步代码已全部删除；音频：预览端始终静音
  （无开关），输出/投屏一路（默认开），设置窗口和音频面板只保留输出音频条目
- 项目/设置持久化：项目 = 媒体库列表（*.splproj），启动自动打开上次项目、
  增删自动保存、文件菜单新建/打开/保存/另存为、窗口标题显示项目名。
  投屏窗口首次弹出居中于主窗口（手动计算，initial_position 有偏移 bug）
- 投屏窗口是真正的独立原生窗口：项目设置已关闭
  `display/window/subwindows/embed_subwindows`
- Phase 3：doc/godot_mpv-master 源码用 VS2026+CMake 编译出完整版 DLL
  （已替换 bin/ 下 DLL，旧版备份 libgodot_mpv.alpha.bak；重建命令见 TODO.md）。
  解锁 seek/音量/循环/倍速/time_changed，GDScript 已适配

## 关键文件

- `main.tscn` — 主场景（MainWindow/PanelContainer，UI 树，关键节点均设了
  unique_name，脚本里用 `%Name` 引用；`%CastWindow` 为独立投屏窗口，
  内含 `%CastVideoView` TextureRect 共享输出纹理）
- `scripts/main.gd` — 主逻辑（媒体库卡片 + 预览/输出两端调度 + 快速切换 + 项目管理）
- `scripts/media_object.gd` — MediaObject 媒体对象模型（类型推断 + 缩放/偏移
  属性 + 序列化；媒体库条目、项目持久化的数据单元）
- `scripts/item_settings_window.gd` — ItemSettingsWindow 条目设置独立窗口
  （点卡片 ⚙ 创建，编辑缩放比例/水平/垂直偏移，改动即时生效并存项目）
- `scripts/media_item_card.gd` — MediaItemCard 媒体库卡片（参照 doc/item.html：
  标题栏蓝色序号+文件名+类型徽标，16:9 画面区，无缝 3×2 按钮网格
  播放/静音/循环/预览/设置/删除；信号 preview_requested/push_requested/
  settings_requested/delete_requested/loop_toggled/mute_toggled）
- `scripts/thumbnailer.gd` — Thumbnailer 封面截取器（独立 MPVPlayer 后台抓帧，
  信号 thumbnail_ready/thumbnail_failed；注意 mpv 会补发残留帧，需等
  time_changed 落到目标位置再取最新纹理）
- `scripts/player_slot.gd` — PlayerSlot 播放端封装（帧源 SourceKind
  { NONE, MPV, STATIC, WEB, SLIDE }：mpv 解码 / load_static 静态纹理 /
  load_web CEF 网页 / load_slides PPT 幻灯片（CEF + gotoSlide 跳页）
  + TextureRect
  + 状态模型 get_state；信号 state_changed / frame_updated，后者供投屏窗口
  共享纹理，帧源类型对投屏透明；MPV 用 `mpv.call("方法名")` 调用）
- `scripts/pptx_converter.gd` — PptxConverter PPTX→自包含 HTML 转换器
  （隐藏浏览器跑 pptx_renderer/player.html，base64 注入 pptx，轮询标题
  "pptx:{页数}" 判完成，request_html_content 序列化写盘；队列化一次一个，
  信号 convert_done(ok, out_path, page_count)）
- `pptx_renderer/player.html` — PPT 播放器壳（双模式：转换 / 缓存加载；
  内联 CSS 与导航脚本使序列化产物自包含可播放；js/ 为 vendor 的
  PPTX2HTML 依赖，worker.inline.js 是 file:// 降级 shim）
- `scripts/project_store.gd` — ProjectStore 持久化（项目 *.splproj 读写 +
  user://settings.cfg 记录上次项目；项目缓存捆绑 X_cache/：
  pptx 转换结果 + 封面副本，保存时同步、打开时优先查找；ConfigFile.save
  需先建目录）
- `scripts/settings_window.gd` — SettingsWindow 设置窗口（声音开关/快捷键/
  投屏窗口几何，代码建 UI）
- `ui/theme.tres` — 全局深色主题（SystemFont: 微软雅黑 + Segoe UI Emoji 回退）
- `bin/godot_mpv.gdextension` — MPV 扩展入口（debug 条目指向 release 库）
- `doc/godot_mpv-master/` — 扩展完整源码 + 构建环境（godot-cpp/导入库/glad，
  已放 .gdignore；VS2026 + CMake 重建）
- `doc/index.html` — UI 设计稿参考
- `doc/TODO.md` — 任务清单（进度真相来源）

## 环境与技术要点

- Godot 编辑器通过 godot-ai MCP 插件连接；场景编辑用 MCP 工具，
  验证流程：`project_run` → `editor_manage(game_eval)` → `editor_screenshot(game)`
- MPVPlayer（自编译完整版）API：initialize / load_file(path,headers,yt_dlp)
  【3 参】/ play / pause / stop / seek_content_pos(String 绝对秒) /
  set_time_pos(double)【会强制解除暂停，暂停态 seek 后要重新 pause】/
  set_volume(String "0"-"100+") / set_repeat_file(String "inf"/"no") /
  set_playback_speed(String) / set_audio_track / set_subtitle_track /
  get_texture / get_width / get_height / get_duration；信号 texture_updated +
  time_changed（真实进度，PlayerSlot.elapsed 由它驱动）
- 内核已知问题：`restart` 绑定错到 pause（上游 bug，未使用）；首帧时 seek
  可能丢失（PlayerSlot 已用 time_changed 校验重试，容差 0.15s 最多 5 次）
- 编辑器进程持有旧 alpha 类注册：游戏进程每次启动加载新 DLL 不受影响，
  编辑器内要用新 API 需重启编辑器
- 扩展经 glReadPixels→ImageTexture 上屏，d3d12 渲染驱动下可用
- 测试视频：`D:/Download/godot_mpv-master_extract/godot_mpv-master/assets/video/AV1_Big_Buck_Bunny_720_10s.mp4`
- 测试网页/PPT：`doc/test.html`、`doc/test.pptx`（Phase 8/9 验证用）
- 运行时报"main loop not advancing"是游戏窗口失焦，聚焦后重试即可
