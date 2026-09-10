# ScreenPlayer — 跨窗口同步播放器（Godot 4.7.2）

## 自动续作指令

每次会话开始时：先读 `doc/TODO.md`，从第一个未勾选的 Phase 条目继续执行，
完成后勾选对应条目并更新本文件的"当前进度"。用户说"继续"即指此流程。
不要重复已完成的工作。

## 会话结束自动提交

每次对话结束时（完成一轮工作后收尾前）：若工作区有改动，执行一次
`git add -A && git commit`，提交信息概括本次改动，方便管理和回档。

## 业务逻辑（已确认，详见 doc/TODO.md）

- 支持平台仅 ARM64 macOS 和 x86_64 Windows。共用业务逻辑，按平台加载 MPV/CEF 原生依赖；不扩展 Intel Mac、Windows ARM 或 Linux 支持。
- 产品定位：Godot 原生跨平台桌面媒体播放与投屏系统；CEF 仅用于播放网页/PPT 媒体。未来可能增加简单的网页后台遥控器，作为桌面播放器的独立控制入口，当前不开发。

- 单击媒体库条目 → 加载到预览播放器（预览可随意切换，不影响输出）
- 卡片「播放」按钮 → 直接送输出端 + 投屏窗口从头播放，不经过预览端
  （main.gd _on_card_push → _load_output；PPT 无缓存时后台转换完成自动起播）
- 点击「快速切换」→ 预览的视频路径+播放状态+当前进度推送给输出播放器
- **共享纹理架构（Phase 4 起）**：全程序只有两个 MPVPlayer 实例（预览/输出）。
  独立投屏窗口不持有实例，其 TextureRect 通过 PlayerSlot 的 `frame_updated`
  信号共享输出端纹理——两端显示同一块像素缓冲，画面零延迟完全一致，
  没有任何状态同步代码。代价：输出/投屏的音频只有一路（实例级属性）
- 预览端始终静音（仅作预览用，无开关无音量条）
- 预览与输出端互不同步；独立播放窗口用 Godot `Window` 节点实现
  （单进程多窗口，无边框置顶）

## 当前进度

- Windows x86_64 Release 发行构建（2026-09-10）：export_presets 使用 Godot 4.7.2
  `windows_release_x86_64` 正式模板，脚本编译为 GDScript bytecode，嵌入 PCK；导出时
  排除 tests/doc/tools/Godot AI 调试组件和 CEF 缓存。CEF 运行文件从锁定清单复制到
  exe 同目录，仅保留 zh-CN/en-US 两个 locale。MPV 与 CEF 的 ANGLE DLL 原名冲突，
  打包时将 MPV 一侧隔离为 mpvEGL.dll/mpvGLES2.dll，并部署官方 VC++ x64 Redist。
  tools/build_windows_release.ps1 自动校验运行库、提取模板、导出、检查文件、从发行目录
  实际加载 MPV/CEF 扩展并生成 ZIP。当前产物 35 文件/约 574MB，ZIP 约 244MB；
  Release 隐藏启动验证退出码 0。产物在 dist/，不入 Git。

- 关闭交互优化（2026-09-10）：自绘标题栏关闭按钮点击后立即禁用并显示“…”、
  执行 0.14s 缩放回弹，标题变为“正在关闭”；随后主窗口立即最小化，预先停止
  预览/输出/封面 MPV、播放列表和 PPT/网页浏览器，再进入全局 CEF shutdown。
  菜单「退出」和重启走同一清理入口。关闭动画测试 6 项通过；完整 CEF 主场景
  从发起清理到进程退出约 1.15s（Windows D3D12 本机，无活动媒体）。

- 独立投屏窗口空闲时固定显示纯黑背景；无视频、停止视频或仅播放音频时不会露出
  透明/系统底色。设置窗口采用草稿式编辑：顶部「设置」仍直接弹窗，「应用」统一
  保存并立即生效但不关闭，「确定」保存、生效并关闭；关闭窗口放弃尚未应用的改动。
  tests/settings_button_smoke.gd 已验证黑屏、未应用不落盘、应用不关闭及确定关闭。

- 菜单栏「设置」直接弹窗（2026-09-09）：MenuSettings 由 MenuButton 改为
  普通 Button（theme_type_variation=MenuButton 保持与相邻菜单一致的外观），
  点击直接居中弹出 SettingsWindow，不再经过「打开设置」二级菜单；
  tests/settings_button_smoke.gd 无头冒烟 7 项通过（headless 下 CEF 初始化失败为预期降级）。

- 窗口缩放保持卡片尺寸（2026-09-09）：关闭 project.godot 的 canvas_items 全局拉伸；
  MediaItemCard / PlaylistCard 两轴使用 SIZE_SHRINK_BEGIN，分区变化只重排卡片，
  不拉伸 item。Windows 实窗测试 3 档尺寸 × 3 种窗口 × 2 种分区比例通过，
  tests/card_layout_smoke.gd 可复用；三档实测 160×174 / 210×202 / 280×241。

- Windows 克隆后 Error 126 已修复（2026-09-09）：从旧项目恢复 Git 忽略的 libmpv 与 CEF；
  tools/windows-runtime.lock.json 固定逐文件哈希，install/check/pack_windows_runtime.ps1
  实现安装、原生加载检查与运行库打包，run_windows.ps1 启动前检查。Windows D3D12 实测
  视频、暂停 seek、共享纹理投屏、循环、封面和图片切换通过；运行包在 dist/（不入库），
  新机器需同时获得运行包，流程见 doc/PLATFORMS.md。未重测 Mac 和网页/PPT 完整交互。

- 双平台适配已合并到 `master`：共用桌面业务逻辑，按平台加载 ARM64 macOS /
  x86_64 Windows 原生依赖；历史保留在 master 提交图中，仓库只维护 master 分支。

- 双平台运行入口整理：tools/run_windows.ps1 检查 x86_64 与 Windows 运行库后导入启动；
  tools/run_macos.sh 检查 ARM64 与 Mac CEF。Windows MPV 导出依赖显式包含
  libmpv/EGL/GLES/zlib；大型运行包仍不入库，克隆后补齐方式见 doc/PLATFORMS.md。
  Windows 本轮只做配置/二进制架构检查，未做真机回归。

- 编辑器布局统一：QuadSplitContainer 为 @tool，导出属性 setter 自动重新布局；
  TitleBar 为 @tool 并直接挂在 main.tscn 的 RootVBox/TitleBar，main.gd 只引用现有节点。
  编辑器中标题栏只绘制，不移动/关闭窗口。播放/停止按钮静态样式放场景资源。
  主业务脚本不能改为 @tool（避免编辑场景启动解码器/浏览器或读写项目）；
  编辑器使用默认分区比例，运行时仍恢复用户设置。

- Phase 16 macOS 开发运行适配已落地（用户指定优先于 Phase 10）：GPT 起点提交
  `2d6ab86` 已合入 master；Apple M4 / Godot 4.7.2
  Metal 实测视频、图片、网页触点、26 页 PPT 转换/翻页及共享纹理投屏。
  `native/mpv/` 为 Mac libmpv 软件渲染后端；`tools/build_macos.sh --with-cef`
  固定版本构建 MPV 与 gdcef，`tools/run_macos.sh` 导入后启动。
  CEF 的 Mac 适配必须包含 external_message_pump 与
  `native/cef_application_mac.mm` 的 NSApplication 协议桥，否则原生事件循环崩溃；
  framework 拷贝保留符号链接，替换 Helper 后重新 ad-hoc 签名。
  Mac CEF 缓存/日志在 user://；浏览器路径统一走 PlatformPaths.browser_url。
  QuadSplitContainer 最小尺寸需计入子控件实际尺寸（Mac 字体高度不同）。
  Mac libmpv 的目标时间信号可能早于纹理，Thumbnailer 必须等两者到位再截取。
  详情/测试命令见 doc/MACOS.md；尚未完成本轮 Windows 真机回归、外接多屏/4K，
  尚未制作独立签名公证 .app，Mac dylib 依赖本机 Homebrew，原生运行包不入库。

- Phase 0-9、11-12、14-15 全部完成（doc/TODO.md）；Phase 10（播放体验增强：
  网页缩放 / PPT 翻页快捷键）已立项待做
- Phase 15（内容区十字四分区）：左上=预览/快速切换/输出、右上=实用功能、
  左下=媒体、右下=音频控制；scripts/quad_split_container.gd（QuadSplitContainer，
  按子节点名对位四象限，分割条比例存储、窗口缩放按比例伸缩，竖条/横条/交叉点
  可拖，各向最小尺寸钳制）；比例持久化 settings.cfg（ui/split_x、ui/split_y，
  默认 0.72/0.5），main.gd 启动恢复；预览/输出画面区外套 AspectRatioContainer
  锁 16:9（FIT 居中），分区拉伸画面不变形；媒体库标题栏「尺寸」按钮三档
  卡片规格（小/中/大，宽高写死不随窗口拉伸，ui/card_size 持久化）
- Phase 14（播放列表）：媒体库「添加文件」左侧「添加列表」按钮；PlaylistObject
  （scripts/playlist_object.gd：条目{path,duration,count}——duration=距下一项
  间隔秒数、count=连播次数默认 1——+ 列表总时长 + 定时
  自动播放 HH:MM 跨午夜，随项目 playlist/lists 段持久化）；PlaylistRunner
  （scripts/playlist_runner.gd：墙钟计时依次推输出端，条目时长 0=视频/音频
  自然结束（进度到尾 0.3s 或墙钟超时长+2s 兜底）、图片/网页/PPT 默认 10s；
  列表时长>0 时循环播满；外部干预检测输出路径不一致即让出；列表模式强制
  关单条循环）；PlaylistCard（scripts/playlist_card.gd，≡ 标记与媒体卡片
  混排）；PlaylistSettingsWindow（scripts/playlist_settings_window.gd：
  名称/列表时长/定时开关/条目增删调序与逐项时长）。定时起播/停止由主窗口
  0.5s tick 检查（main.gd _check_playlist_schedules）。注意：媒体网格混排
  后凡遍历 %MediaGrid 的循环都必须 is MediaItemCard 判断（列表卡片是
  PlaylistCard），序号只编媒体卡片
- 无边框主窗口（解决拖动冻结）：Windows 拖动/缩放原生窗口会进入模态消息循环，
  冻结整个进程主循环（mpv 音频在自己线程所以声音不停）。现主窗口
  borderless + 自绘标题栏（scripts/title_bar.gd：代码逐帧移动窗口，拖动时
  播放/投屏画面不中断；最小化/最大化/关闭按钮；双击标题栏最大化）+
  手动边缘缩放（scripts/window_resizer.gd：边缘 6px 八向缩放，最小 1024×600）。
  注意：无边框窗口的 mode 切换请求偶发被系统丢弃（TitleBar 有逐帧校验重试），
  最大化还原后系统不恢复旧几何（靠持续记录的 _windowed_rect 手动写回）
- Phase 13（网页触点）：HTML 媒体的播放/停止键在网页模式下变成 ← →，
  按 MediaObject.touch_points（归一化坐标，随项目持久化）逐步模拟点击
  （PlayerSlot.step_web：移光标 + 左键按下/抬起）；预览端「触点」开关进入
  编辑模式：左键画面加点、右键删最近点（PlayerSlot.touch_edit_mode +
  touch_edit_clicked 信号，编辑期点击不转发浏览器）；触点白点+序号由
  scripts/touch_points_layer.gd 绘制，只叠加在预览/输出画面（投屏窗口
  不显示触点标记，只执行点击），当前步红色高亮。
  注意：网页点击转发两端均已验证有效（WEB_VIEWPORT_SIZE 1280×720 反算），
  点击无反应先查是否有弹窗/投屏窗口遮挡主窗口
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
  26 页，转换/翻页/推送/缓存重开全部通过；预览/输出画面**内部**底部有
  水平 < > 翻页按钮（%PreviewPageButtons/%OutputPageButtons，
  叠加在画面上、mouse_filter IGNORE 不挡点击，仅 SLIDE 帧源可见，
  首页禁 < 末页禁 >，main.gd _update_page_buttons）
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
- `scripts/title_bar.gd` — 无边框主窗口自绘标题栏（逐帧拖动避开 Windows 模态
  循环，最小化/最大化/关闭；关闭按钮先播放反馈动画再发清理信号；
  mode 切换重试 + 窗口态几何记录）
- `scripts/window_resizer.gd` — 无边框主窗口手动边缘缩放（边缘 6px 八向，
  边缘点击 accept 事件避免与标题栏拖动冲突）。光标提示：每帧按真实鼠标
  位置改「当前悬停控件」的 mouse_default_cursor_shape、离开还原——不能用
  Input.set_default_cursor_shape（根面板铺满全窗口时永不生效，悬停控件的
  形状优先且 CURSOR_ARROW 是显式箭头非回落默认）；也不能在 _input 的
  motion 里做（_input 先于视口悬停更新，目标控件落后一拍）
- `scripts/media_object.gd` — MediaObject 媒体对象模型（类型推断 + 缩放/偏移
  属性 + 序列化；媒体库条目、项目持久化的数据单元）
- `scripts/item_settings_window.gd` — ItemSettingsWindow 条目设置独立窗口
  （点卡片 ⚙ 创建，水平三分区无页签：左=分区名列表「属性/触点」，中=对应
  属性列表（缩放/偏移即时生效，触点分区为触点管理按钮），右=实时预览画面
  ——仅网页媒体，内嵌 CEF 浏览器一直显示、相当于本窗口独享的独立播放器、
  不与预览/输出端同步、关窗即销毁（静音、frame_rate 15）；选中「触点」
  分区时左键点画面加点/右键删点，撤销/清空，与播放端触点层共享引用
  即时同步；非网页媒体无预览区、窗口更窄）
- `scripts/media_item_card.gd` — MediaItemCard 媒体库卡片（参照 doc/item.html：
  标题栏蓝色序号+文件名+类型徽标，16:9 画面区，无缝 3×2 按钮网格
  播放/静音/循环/预览/设置/删除；信号 preview_requested/push_requested/
  settings_requested/delete_requested/loop_toggled/mute_toggled）
- `scripts/playlist_object.gd` — PlaylistObject 播放列表数据模型（条目
  {path,duration,count}：duration=距下一项间隔秒数、count=连播次数默认 1；
  列表总时长、定时自动播放 HH:MM 跨午夜，随项目持久化）
- `scripts/playlist_runner.gd` — PlaylistRunner 播放列表执行器（墙钟计时
  依次推输出端；条目时长 0=视频/音频自然结束、其他默认 10s；count>1 重新
  加载同一条目连播，播够次数才切下一条；列表时长>0 循环播满；外部干预
  自动让出；信号 started/item_started/stopped）
- `scripts/playlist_card.gd` — PlaylistCard 播放列表卡片（与媒体卡片同板
  混排：≡+名称+列表徽标、信息区、播放/设置/删除）
- `scripts/playlist_settings_window.gd` — PlaylistSettingsWindow 列表设置
  独立窗口（名称/列表播放时间/定时开关 HH:MM 校验 + 条目从媒体库添加/
  调序/删除/逐项时长）
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
  投屏窗口几何，代码建 UI；修改先作为窗口草稿，「应用」保存生效不关闭，
  「确定」保存生效并关闭）
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

- 已合并远程 Windows MPV 压缩运行包 bin/win-bin.zip 与 restore_windows_mpv.ps1；启动时先恢复缺失 MPV，再做完整运行库哈希/加载检查。Mac 启动和构建脚本保留可执行位。
