# ScreenPlayer 开发任务清单

## 业务逻辑（已确认）

```
单击媒体库条目
    └─> 视频加载到【预览播放器】（仅预览，可随意切换其他视频，不影响输出）

点击「快速切换」
    └─> 预览视频的 路径 + 播放状态 + 当前进度 推送到【输出播放器】
        ├─> 独立投屏窗口与输出播放器共享同一解码实例与纹理，画面声音完全一致
        └─> 预览播放器与输出端【不同步】，此后预览可自由切换别的视频
```

**核心原则（Phase 4 起）**：全程序只有两个 MPV 解码实例——预览一个、输出一个。
独立投屏窗口**不持有实例**，其 TextureRect 通过 `frame_updated` 信号共享输出端的
ImageTexture（同进程资源共享），因此两端显示的是同一块像素缓冲，
不存在同步问题（延迟为 0，不是毫秒级）。
**预览端始终静音**（仅作预览用，无开关无音量条）；输出/投屏的音频只有一路
（共享实例，音量/静音为实例级属性）。

## 架构约定

- **播放状态模型**：`{ media_path, playing, time_pos, loop, rate }`
  （音量/静音是本地配置，不随状态推送）
- **独立投屏窗口**：Godot `Window` 节点（单进程多窗口，无边框置顶），
  内部只有一个 TextureRect，显示输出端共享纹理
- **同步方向**：预览 →（快速切换，一次性推送 路径+进度+播放状态）→ 输出；
  投屏窗口无需任何状态同步（画面来自共享纹理，显隐跟随输出端状态）

---

## Phase 1 —— 输出播放器 + 独立窗口（已完成，Phase 4 重构）

- [x] 1.1 抽取播放器封装脚本 `scripts/player_slot.gd`：封装一个 MPVPlayer 实例 +
      TextureRect 显示 + 状态（load/play/pause/stop/seek/get_state），
      预览和输出两个播放器复用
- [x] 1.2 输出播放器接入第二个 MPVPlayer 实例，OutputScreen 下加
      TextureRect（`%OutputVideoView`）
- [x] 1.3 独立播放窗口：场景加 `Window` 节点（无边框、可置顶），
      内部全屏 TextureRect（`%CastVideoView`）
- [x] 1.4 「快速切换」按钮逻辑：读取预览播放器当前状态推送给输出播放器
      （自动显示独立窗口）
- [x] 1.5 ~~输出区状态广播到独立窗口~~（Phase 4 起不需要：共享实例）
- [x] 1.6 「隐藏投屏」按钮：控制独立窗口显隐
- [x] 1.7 验证：预览播 A → 快速切换 → 输出+独立窗口同步播 A；
      预览切 B → 输出端不受影响

## Phase 2 —— 完整业务闭环（已完成）

- [x] 2.1 媒体库条目增强：单击/双击均只加载到预览（不推输出端，只有「快速切换」
      才推送）；右键弹出菜单移除条目；当前输出条目绿色高亮标记
- [x] 2.2 播放/暂停按钮图标状态联动（▶/⏸），停止后复位
- [x] 2.3 进度条：预览/输出进度条换为 HSlider，显示真实进度（time_changed 驱动）
      + 拖动 seek；内核补了 get_duration（总时长），时间标签显示真实时长
- [x] 2.4 输出端音量控制：🔊 静音按钮（与设置窗口勾选框联动）+ 音量条，
      音量持久化到 settings.cfg
- [x] 2.5 状态栏真实数据：FPS / 帧耗时 / 内存 / PID / 版本号（0.5s 刷新）
- [x] 2.6 菜单栏功能：文件（添加文件/项目新建/打开/保存/另存为/退出）、
      窗口（投屏窗口显隐）、设置、帮助（关于对话框）
- [x] 2.7 「重启软件」按钮实现（OS.set_restart_on_exit + quit；
      编辑器内运行不生效，导出后生效——引擎限制）
- [x] 2.8 音频控制面板：输出端音量条（右侧「音频控制」面板），持久化到
      settings.cfg（预览端始终静音无条目；Phase 4 起投屏端共享输出实例，
      也不再单独成条目）

## Phase 3 —— 播放内核增强（已完成）

- [x] 3.1 从源码编译 godot_mpv：doc/godot_mpv-master 内的完整源码用 VS2026 +
      CMake 编译通过（godot-cpp master + 从 bin/ 三个 DLL 生成 MSVC 导入库 +
      pip glad2 生成 GLES2/EGL 绑定），已替换 bin/ 下 DLL（旧版备份为
      libgodot_mpv.alpha.bak）。完整 API 已运行时验证
- [x] 3.2 GDScript 侧适配：load_file 改 3 参；set_volume/set_repeat_file/
      set_playback_speed 均传 String；elapsed 改由 time_changed 信号驱动
      （真实进度）；新增 seek/set_volume/set_rate

### 新内核注意事项

- `set_time_pos` 会强制解除暂停——暂停状态下 seek 后需重新 pause
  （PlayerSlot.seek 已处理）
- 首帧到达时 demuxer 可能未就绪导致 seek 丢失——PlayerSlot 用 time_changed
  校验重试（容差 0.15s，最多 5 次）
- `restart` 方法在上游源码里被错误绑定到 pause（mpv_player.cpp:38），未使用
- 编辑器进程仍持有旧 alpha 类注册，编辑器内直接调新 API 需重启编辑器；
  游戏进程每次启动都加载新 DLL，不受影响

## Phase 4 —— 共享纹理架构（已完成）

- [x] 4.1 投屏窗口移除独立 PlayerSlot/CastSlot，`%CastVideoView` 改通过
      PlayerSlot 新增的 `frame_updated(texture)` 信号共享输出端纹理
      （实测两端 texture 为同一对象）
- [x] 4.2 删除两阶段起播对齐与状态广播代码（_sync_pending/_finish_sync/
      apply_state 等）；快速切换简化为一次 load_media(路径, 播放态, 预览进度)
- [x] 4.3 音频模型合并：输出/投屏只剩一路声音（默认开），设置窗口去掉
      「投屏窗口声音」勾选框，音频控制面板去掉投屏音量条；
      随后应业务要求预览端改为始终静音（无开关无音量条）
- [x] 4.4 验证：快速切换后输出/投屏同一纹理、起播 seek 误差 ≤0.3s、
      暂停态推送保持暂停、输出停止后投屏画面隐藏、预览静音且正常播放

## Phase 5 —— UI 精细化（已完成）

- [x] 5.1 控制按钮图标统一：全部改用 Segoe UI Symbol 文字字形
      （▶/⏸/■/⟳/🔊/🔇，字号 14、最小宽 34），不再混用 emoji 字体导致大小参差；
      循环图标 🔄 → ⟳。注意：微软雅黑不含 ▶⏸↻✕ 等符号字形
- [x] 5.2 预览播放器控制区简化：只保留 播放/暂停、停止、进度条 + 时间
      （移除循环按钮和「详情」占位按钮）
- [x] 5.3 媒体库卡片化（scripts/media_item_card.gd，样式参照 doc/item.png）：
      ItemList → ScrollContainer+HFlowContainer（%MediaGrid）；
      卡片 = 文件名 + 缩略图 + ▶预览 / →推送输出 / ✕移除 三个小图标按钮；
      点击卡片任意处 = 加载预览；当前输出条目文件名绿色高亮；
      右键删除菜单随之移除（卡片自带删除按钮）
- [x] 5.4 卡片封面：scripts/thumbnailer.gd 后台截取器（第三个独立 MPVPlayer
      实例，静音不上屏），添加文件/打开项目时对无封面条目排队截取——
      起播后 seek 到设定秒数抓帧，等比缩放到 320x180 以内（保持原视频比例，
      卡片内居中显示），PNG 持久化到 user://thumbnails/<md5>.png，
      重启后直接加载不重截；截取位置在设置窗口可调（默认 1 秒）。
      注意：load 后 mpv 会补发上一文件的残留纹理和时间信号，必须等
      time_changed 落到目标位置附近再取最新纹理，否则会串图

## Phase 6 —— 多媒体媒体库 + 条目设置（已完成）

- [x] 6.1 媒体对象模型 scripts/media_object.gd（MediaObject）：媒体库条目从
      纯路径升级为对象——类型按扩展名推断（视频/音频/图片/网页/PPT/其他），
      基础属性含缩放比例 scale、水平偏移 offset_x、垂直偏移 offset_y；
      to_dict/from_dict 序列化。项目文件 *.splproj 改存 media/items 字典数组
      （保留 media/paths 兼容旧项目），属性改动自动保存
- [x] 6.2 条目设置窗口 scripts/item_settings_window.gd（ItemSettingsWindow）：
      点击卡片 ⚙ 时创建独立原生窗口（每个条目一个，重复点击聚焦已有窗口），
      编辑缩放比例/水平/垂直偏移 + 重置；改动即时写回 MediaObject 并应用到
      正在播放该条目的预览/输出画面（PlayerSlot.set_view_transform，以画面
      中心为 pivot，随控件 resize 自动校正）；投屏画面变换 =
      全局窗口缩放/平移 × 条目缩放/偏移
- [x] 6.3 多媒体类型支持：添加文件对话框过滤器扩展为视频/音频/图片/网页/PPT；
      卡片显示类型徽标（文件名右侧小字）+ 无封面类型显示占位字形
      （视频▶/音频♪/图片"图"/网页</>/PPT"P"）；图片直接读文件缩略做封面
      （等比缩放到 320x180 以内）；音频走 mpv 正常播放，预览/输出画面
      显示 ♪ 播放符号代替视频纹理（投屏隐藏画面）；图片/网页/PPT 点击预览
      只显示类型占位提示，真实播放暂未实现（后续阶段）；媒体库条目去重
      （同路径不重复入库）
- [x] 6.4 输出播放器控制区精简：只保留 播放/停止/进度条/时间；移除循环按钮
      与音量条/静音按钮——音量统一由右侧「音频控制」面板的输出滑动条负责
      （持久化到 settings.cfg），静音由设置窗口的「输出/投屏声音」勾选框控制

## Phase 7 —— 帧源抽象 + 图片播放（已完成）

> 目标：把 PlayerSlot 从"强绑 mpv"改为"帧源可插拔"，图片走静态纹理通路。
> 同步问题不需要新代码：投屏窗口只是持有输出端纹理引用，
> 任何帧源把纹理发进 `frame_updated`，投屏即自动一致。

- [x] 7.1 PlayerSlot 帧源抽象：`SourceKind { NONE, MPV, STATIC }` 帧源标识 +
      统一对外接口（纹理显示 + frame_updated 信号 + 状态模型
      playing/elapsed/duration）；mpv 通路为 MPV 帧源，新增
      `load_static(path)` 静态纹理帧源（Image.load_from_file →
      ImageTexture，加载时发一次 frame_updated）；STATIC 期间忽略 mpv
      残留帧/时间信号（_on_texture_updated/_on_time_changed 入口校验）
- [x] 7.2 图片真实播放：预览/输出两端同通路（main.gd `_load_preview` /
      快速切换按类型分支）；toggle_play/seek 对静态媒体为空操作
      （播放/停止退化为 显示/撤下）；进度条禁用、时间标签显示 "—"；
      缩放/偏移（set_view_transform）保持兼容
- [x] 7.3 快速切换适配：按媒体类型分支——图片推送到输出端走同一
      load_static 静态通路（无视进度），视频/音频维持 mpv 通路；
      MediaObject.is_playable() 纳入图片
- [x] 7.4 验证（game_eval 实测）：预览图片（kind=STATIC）→ 快速切换 →
      输出 STATIC 且输出/投屏 texture 为同一对象、时间显示 "—"、
      进度条禁用；图片→视频→停止→图片来回切换不串画面，停止后投屏隐藏

## Phase 8 —— 浏览器内核（真实网页播放）

> 需求确认：网页 = 真实网页，需要真浏览器内核（非截图降级）。
> 这是后续 PPT 的共同底座（见 Phase 9），选型一次到位。
> 注：若只是视频网页/直播流地址，mpv 的 load_file(path, headers, yt_dlp)
> 第三参已能播，不属于本 Phase。

- [x] 8.1 内核选型（已落地：CEF + gdcef）：
      - 选择 CEF（gdcef v0.20.0 godot-4.x 分支，源码在 doc/gdcef/）：
        离屏渲染直接写 TextureRect，最贴合帧源模型；CEF 151.3.24
        （上游锁 151.3.18，同分支小版本差，编译零适配一次通过）
      - 构建：VS2026 + CMake/SCons（doc/gdcef/run_build.bat，日志 build_log.txt）；
        godot-cpp 4.5 分支；产物输出 doc/gdcef/cef_artifacts/（重建时重新生成，
        已部署后清理）；CEF 压缩包与 Debug/ 目录已清理（重下地址见 build.py
        的 CEF_VERSION + cef-builds.spotifycdn.com）
      - 部署：cef_artifacts/ 拷贝到项目根（.gdextension 引用
        res://cef_artifacts/windows/libgdcef.dll）；注意扩展清单
        .godot/extension_list.cfg 由编辑器启动时生成——编辑器运行中新增
        gdextension 需手动加入该行或重启编辑器
      - 冒烟测试通过（cef_smoke.tscn）：CEF 初始化成功、
        create_browser(url, TextureRect, config) 离屏渲染 doc/test.html 正常显示
      - gdcef API 要点：场景放 GdCEF 节点 → initialize({incognito,...}) →
        create_browser(url, TextureRect, {javascript, webgl, frame_rate}) →
        返回 GdBrowserView 节点（load_url/reload/previous_page/next_page/
        set_muted/execute_javascript/set_mouse_*/set_key_pressed/resize），
        信号 on_page_loaded/on_browser_paint/on_page_failed_loading 等
- [x] 8.2 WebSource 帧源：PlayerSlot 新增 SourceKind.WEB + load_web(path)，
      CEF 离屏渲染直接写入各端 TextureRect（预览/输出各一个浏览器实例，
      共用全局唯一 GdCEF 节点，main.gd _ready 注入 web_cef）；
      on_browser_paint 时把浏览器纹理转发进 frame_updated，投屏零感知共享；
      网页无播放/暂停语义（toggle_play/seek 空操作），进度条禁用、时间 "—"；
      修复遗留 bug：类名是 GdCEF 而非 GDCEF（大小写敏感，此前从未真正初始化）
- [x] 8.3 交互路径：显示区 gui_input 转发浏览器（鼠标移动/左右中键/滚轮，
      浏览器视口与显示区等尺寸 1:1 映射，resize 时 _browser.resize 跟随）；
      投屏端只读（共享纹理天然一致）；预览端浏览器 set_muted(true) 静音。
      音频结论（已评估）：CEF 原生出声（gdcef 默认 CEF native audio，无需接管），
      set_audio_stream 仅用于把音频路由进 Godot 加音效，不使用；音量面板不控制
      网页/PPT 声音，静音经 PlayerSlot._apply_volume → browser.set_muted 生效
- [x] 8.4 验证（game_eval 实测）：test.html 入库（Type.HTML）→ 预览 WEB 渲染
      正常 → 快速切换 → 输出 WEB 且输出/投屏 texture 为同一对象、投屏窗口
      自动弹出；网页→视频→网页互切无残留；预览区鼠标点击注入无异常
- [x] 8.5 HTML 随窗口缩放：浏览器视口固定参考分辨率 1280×720
      （PlayerSlot.WEB_VIEWPORT_SIZE），不再跟随显示区 resize——窗口缩放由
      TextureRect（KEEP_ASPECT_CENTERED）完成，小窗口下页面等比缩小完整可见，
      与视频同一模型；鼠标事件经 _web_to_browser_pos 按居中缩放矩形反算回
      固定视口坐标，缩放后命中精度不变（game_eval 缩窗实测通过）

## Phase 9 —— PPT 播放（pptx2html 转 HTML，经浏览器内核渲染）

> 需求变更（用户确认）：放弃 PDF 路线，改用 PPTX2HTML（g21549/PPTX2HTML，
> 纯 JS：JSZip 解压 + XML 解析 + DOM 重建）把 PPTX 转成 HTML 再播放；
> 转换结果保存在项目中，项目保存要包含这些缓存文件、条目封面、条目设置等。
> 链路：PPTX →（导入时一次性转换）→ 静态 HTML（缓存）→ CEF 渲染播放，
> 翻页 = 注入 JS 切换幻灯片 div。

- [x] 9.1 转换管线：vendor PPTX2HTML 到 res://pptx_renderer/（库 + 自建
      播放器壳 player.html：接收 pptx 路径→渲染全部幻灯片为堆叠 div→
      暴露 window.gotoSlide(n)/getSlideCount()）；导入时隐藏浏览器实例
      执行转换，产出静态 HTML 存入项目缓存目录（见 9.2）
- [x] 9.2 项目缓存捆绑：保存项目（*.splproj）时写同级缓存目录
      <项目名>_cache/（pptx 转换结果 + 各条目封面缩略图）；打开项目时
      优先从缓存目录恢复（回退 user://thumbnails）；条目设置本就在
      splproj 内（Phase 6 已实现）
- [x] 9.3 SlideSource = WEB 帧源特化：加载缓存 HTML，进度条复用为页码
      "3 / 12"（execute_javascript 调 gotoSlide），播放/停止语义同图片；
      get_state 增加 current_page，快速切换推送页码；缩放/偏移兼容
- [x] 9.4 已知取舍：动画/切换特效/嵌入视频在转换中丢失（会议放片场景可接受）
- [x] 9.5 验证：doc/test.pptx 预览翻页 → 快速切换 → 输出+投屏同页；
      重开项目缓存与页码恢复

> 9.x 实施备注（2026-09，全部实测通过）：
> - gdcef 信号签名与直觉不同：on_page_loaded(http_code, browser)、
>   on_page_failed_loading(err_code, err_msg, browser)——均不带 URL，
>   用 browser 参数比对身份
> - CEF file:// 页面创建 Worker 抛 SecurityError，player.html 自动降级
>   到主线程 shim（pptx_renderer/js/worker.inline.js = worker.js 包一层
>   fake self/postMessage；shim 跑在 CEF 渲染进程，不卡 Godot 主线程）
> - 转换产出为自包含 HTML：CSS 在 player.html 构建期内联，图表 SVG 与
>   全部 .slide-page 都在 DOM 里，内联导航脚本重载自洽
> - 实测：test.pptx(240KB)→19 页/413KB 缓存；doc/test.pptx(6.9MB)→
>   26 页，转换 <6s；page_count 持久化在 MediaObject（splproj）里

## Phase 12 —— 卡片重构（参照 doc/item.html）（已完成）

- [x] 12.1 卡片改版：标题栏（蓝色序号 + 文件名 + 类型徽标，#333 底）+
      16:9 黑色画面区（AspectRatioContainer，下边框 2px #ccc）+
      无缝 3×2 按钮网格（播放/静音/循环/预览/设置/删除，#5a5a5a 底 +
      1px #ccc 边线，GridContainer 负间距拼无缝）；序号增删后自动重排
- [x] 12.2 条目级偏好：MediaObject 新增 loop/muted（随项目持久化，
      卡片按钮蓝色高亮表示开启）；「播放」= 推送到输出端并应用条目的
      循环/静音（静音与全局「输出/投屏声音」为或关系，
      _output_muted_state() 统一计算）；正在输出该条目时开关立即生效

## Phase 11 —— 文件丢失标记 + 媒体复制入库（已完成）

- [x] 11.1 丢失条目特殊显示：MediaObject 新增 exists()/is_remote()；
      卡片 set_missing(true) = 缩略图置灰 + 红色「已丢失」徽标 + 禁用 ▶/→
      + tooltip 说明；入库/打开项目时检测，主窗口重获焦点时全量复查
      （文件恢复自动取消标记并补封面）；_first_playable 跳过丢失条目
- [x] 11.2 「复制到项目目录」开关：设置窗口基础设置新增（media/copy_to_project，
      默认关）；开启后添加文件时真实复制进 X_cache/media/<md5前缀>_<文件名>
      （同源重复导入复用副本），MediaObject 新增 origin_path 记录原始路径；
      仅对已保存项目生效（未保存时回退原路径并告警）
- [x] 11.3 配套修复：mpv 只认操作系统路径——PlayerSlot.load_media /
      Thumbnailer 抓帧统一 globalize_path（user:// 项目缓存的副本可正常
      播放/截封面）；load_web/load_slides 的 file:// 拼接同步 globalize；
      load_media 对本地文件先验存在性，丢失文件显示「文件不存在」提示
      而不是 mpv 的 error -13

## Phase 14 —— 播放列表（已完成）

> 媒体库「添加文件」左侧新增「添加列表」按钮；列表与媒体卡片混排在媒体库
> （≡ 标记卡片），条目取自媒体库，逐项可设播放时长，列表可设整体播放
> 时间与每日定时自动播放（开启/关闭时间）。

- [x] 14.1 数据模型 scripts/playlist_object.gd（PlaylistObject）：
      items = { path, duration, count }（duration 秒 = 距下一项的间隔，
      0 = 视频/音频播到自然结束，图片/网页/PPT 默认 10 秒；count = 该项
      连续播放次数，默认 1，播够次数才切下一项）+ duration（列表播放时间，
      0=播完一轮，>0=循环直到播满）+ auto_enabled/auto_start/auto_stop
      （"HH:MM" 支持跨午夜，开启==关闭=全天）；随项目 playlist/lists 段持久化
- [x] 14.2 执行器 scripts/playlist_runner.gd（PlaylistRunner）：墙钟计时
      把条目依次推输出端（复用卡片「播放」通路 _load_output，投屏自动弹出，
      列表模式强制关闭单条循环）；视频自然结束判定 = 进度到尾 0.3s 或
      墙钟超时长+2s 兜底；外部干预（手动推送/快速切换/输出停止）检测
      输出端路径不一致即静默让出；条目丢失自动跳过
- [x] 14.3 列表卡片 scripts/playlist_card.gd（与媒体卡片同板）：标题行
      ≡+名称+列表徽标 + 信息区（条目数/播放时间/定时时段）+
      播放/设置/删除按钮；播放中名称绿色高亮、播放键变 ■ 停止
- [x] 14.4 列表设置窗口 scripts/playlist_settings_window.gd（独立窗口）：
      名称/列表播放时间/定时自动播放（HH:MM 校验，非法标红不写回）+
      条目管理（OptionButton 从媒体库选媒体添加、↑↓ 调序、✕ 删除、
      逐项时长 SpinBox），改动即时生效并自动保存项目
- [x] 14.5 定时自动播放：主窗口 0.5s tick 检查各列表时段，到开启时间
      且执行器空闲自动起播，出时段自动停止（_check_playlist_schedules）
- [x] 14.6 验证（game_eval 实测）：3 条目（视频3s/图片2s/网页2s）按时长
      依次切换并播完自动停止清屏；列表时长 7s 时 2s 条目循环 4 轮后准点
      收尾；定时起播/停止按 HH:MM 生效；保存/重开项目列表完整恢复

## Phase 15 —— 内容区十字四分区布局（已完成）

> 内容区由「左列（播放器+媒体库）| 右列（实用功能+音频控制）」改为十字
> 四分区：左上=预览/快速切换/输出播放器，右上=实用功能，左下=媒体，
> 右下=音频控制；竖横分割条中心交叉，拖拽调整布局。

- [x] 15.1 scripts/quad_split_container.gd（QuadSplitContainer extends Container）：
      按子节点名对位四象限（PlayersSection/UtilityPanel/MediaPanel/AudioPanel），
      分割位置以比例（split_x_ratio/split_y_ratio）存储，窗口缩放时按比例伸缩
      （窗口放大各分区按历史比例放大）；拖拽竖条/横条/交叉点（两轴同调），
      悬停显示 ↔/↕/✥ 光标，各向最小尺寸钳制（min_left/right/top/bottom），
      拖拽结束发 ratios_changed
- [x] 15.2 main.tscn 重构：MainHBox/MainLeft/SidePanels 三层包装删除，
      四个分区面板直接挂 %QuadSplit
- [x] 15.3 比例持久化：拖拽结束写 settings.cfg（ui/split_x、ui/split_y，
      默认 0.72/0.5），启动恢复（main.gd _ready）
- [x] 15.4 验证（game_eval 实测）：模拟拖拽（含最小尺寸钳制）比例与
      settings.cfg 同步更新；窗口 1152×648 → 1600×900 分割条按比例跟随
- [x] 15.5 播放器画面区锁 16:9：预览/输出的黑色画面面板（PreviewScreen/
      OutputScreen）外套 AspectRatioContainer（FIT、居中），分区拉伸时
      画面区固定 16:9 不变形、多余空间留边；面板内 TextureRect 仍按视频
      实际比例居中（非 16:9 片源面板内留黑边）
- [x] 15.6 媒体库卡片三档尺寸：标题栏「尺寸」MenuButton（小 160×174 /
      中 210×202 / 大 280×241，高按 16:9 画面区推导），媒体卡片与列表
      卡片一起调（MediaItemCard.apply_size / PlaylistCard.apply_size），
      宽高写死为最小尺寸、不随窗口拉伸；选择持久化 settings.cfg
      （ui/card_size，默认中）

## Phase 16 —— macOS 多系统适配（开发运行版）

> 用户指定优先于 Phase 10。Windows 已基本正常；2026-09-08 由 GPT 在
> 从提交 `2d6ab86` 开始适配，现已完整合入 `master`。

- [x] 16.1 创建适配分支并提交 Windows 基线说明
- [x] 16.2 macOS MPVPlayer 原生扩展：libmpv 软件 render API → ImageTexture，
      支持 Metal，保留输出/投屏共享纹理、预览独立静音与后台封面；
      封面截取等待目标时间与对应纹理都到位，兼容 Mac 先时间后纹理的信号顺序
- [x] 16.3 CEF Mac 构建：固定上游版本、framework 符号链接拷贝、Helper 签名，
      补接 NSApplication 的 CEF 协议与 external_message_pump，解决运行崩溃
- [x] 16.4 跨平台 file URL 编码、Mac 字体回退、真实控件最小尺寸钳制，
      入口改为资源路径；Mac CEF 数据与日志写 user://
- [x] 16.5 提供构建/启动脚本及 doc/MACOS.md（依赖与运行限制）
- [x] 16.6 Mac 实际图形运行验证：视频解码、暂停 seek、输出/投屏纹理一致、
      预览独立、循环、后台封面、字体布局、图片、网页触点、
      26 页 PPT 转换/缓存/翻页投屏；空构建目录重建脚本与启动脚本验证通过

支持范围：仅 ARM64 macOS + x86_64 Windows，共用播放/投屏逻辑，按平台加载原生依赖。
验证范围：Apple M4 + Godot 4.7.2 / Metal 开发运行；本轮 Windows 真机回归、
外接多屏/4K 性能及独立签名公证安装包尚未验证。Mac 扩展依赖本机 Homebrew libmpv，
运行包不入库；新机器按 doc/MACOS.md 重建。Windows 绝对媒体路径需在 Mac 重新添加。

## 双平台上传前整理（2026-09-09）

- [x] 确认 ARM64 Mac / x86_64 Windows 扩展路由与现有二进制架构
- [x] 补齐 Windows 导出依赖 EGL/GLES/zlib；新增 Windows 启动脚本检查主要运行库
- [x] Mac 启动脚本检查架构与 CEF；新增 doc/PLATFORMS.md 说明克隆后依赖补齐方式
- [x] 当前版本 ARM Mac 视频与网页/PPT 集成回归：两组 failures=0；测试使用独立 CEF 配置目录，不占用运行中的桌面实例
- [x] 将双平台适配提交历史完整合并到 master

Windows 真机不在当前环境，保留既有正常 DLL，不能将配置检查写成真机验证通过。

## 编辑器布局与运行布局统一

- [x] 四分区容器启用 @tool，编辑器使用同一套尺寸/比例钳制；检查器修改比例与最小尺寸时立即重新布局
- [x] 自绘标题栏放进 main.tscn，编辑器与运行时共用；编辑器禁用窗口移动、模式切换与关闭操作
- [x] 四个播放/停止按钮的字体、字号与最小尺寸从运行时代码移入场景资源
- [x] 编辑器/运行模式使用同尺寸视口验证四象限与标题栏布局，以及修改比例后重新排版

编辑器展示场景默认布局；运行时媒体条目、播放状态与用户保存的分区比例仍按原逻辑恢复。
主业务脚本保持非 @tool，编辑场景不会启动 MPV/CEF 或读写用户项目。

## Phase 10 —— 播放体验增强（待做）

- [ ] 10.1 播放列表/顺序播放：输出端当前条目播完后自动切换下一条
      （媒体库顺序或自定义列表，UI 上加顺序/单条模式开关）。
      前提：确认自编译内核能否拿到 mpv 的 end-file 播放结束事件
      （现只有 time_changed，可靠判定"播完"是前置条件；若内核没有，
      需在 doc/godot_mpv-master 侧补绑定后重编译）
- [ ] 10.2 网页缩放控制：WEB 帧源页面缩放（CEF 侧 zoom 等级或注入 CSS zoom），
      预览/输出两端可用；注意与固定视口 1280×720 + TextureRect 等比缩放
      的关系（缩放的是页面内容，不是显示区），鼠标反算 _web_to_browser_pos
      需同步适配
- [ ] 10.3 PPT 翻页快捷键：输出端 SLIDE 帧源的 上一页/下一页 键盘快捷键
      （复用设置窗口的快捷键改键体系，默认如 ←/→ 或 PageUp/PageDown），
      翻页走已有的 goto_page/next_page/prev_page

## 历史限制（alpha 版扩展，已由内核自编译解决）

- ~~无 `set_time_pos`、`set_volume`、`set_repeat_file`、`time_changed`~~ 已全部可用
- 画面经 glReadPixels → ImageTexture 走 CPU 回读，性能一般，4K 高码率需观察
  （2026-09 实测：1080p ~20Mbps 单/双实例播放时主循环 ~25fps、帧 CPU 45-60ms，
  回读为瓶颈；播放进度跟得上实时（elapsed 与墙钟同步），投屏共享纹理零额外
  开销；空载 60fps 满帧。结论：1080p 高码率可用但 UI 帧率被拉低，4K 预计
  无法实时，需内核侧零拷贝（纹理共享）才能解决）

---

## 已完成（Phase 0 及其他）

- [x] 主界面 UI（参照 doc/index.html 深色布局，ui/theme.tres）
- [x] 媒体库：添加文件（原生文件对话框、多选）→ ItemList 生成条目
- [x] 预览播放器：MPV GDExtension 播放（bin/godot_mpv），单击条目播放
- [x] 预览播放控制：播放/暂停/停止、时间显示
- [x] 项目/设置持久化（scripts/project_store.gd）：项目 = 媒体库列表（*.splproj，
      ConfigFile）；启动自动打开上次项目（user://settings.cfg 记录），首次运行建
      默认项目（user://projects/default.splproj）；媒体库增删自动保存；
      文件菜单支持新建/打开/保存/另存为；窗口标题显示当前项目名
- [x] 起播一次性校正：快速切换时输出端装载后 seek 到预览当前进度
      （首帧到达后执行 + time_changed 校验重试），不做实时校正
- [x] 设置窗口（scripts/settings_window.gd，设置菜单打开）：
      基础设置 = 输出/投屏声音开关（默认开；预览端始终静音）+ 快捷键改键
      （快速切换 Q、切换条目 1/2/3，点击按钮捕获按键）；
      窗口设置 = 投屏窗口大小/位置/画面缩放/平移，
      点击「应用」或「确定」后持久化到 settings.cfg 并生效

## Windows 克隆后原生依赖修复（2026-09-09，用户指定优先）

- [x] 定位 Error 126：缺失被忽略的 libmpv-2.dll，同时恢复 CEF 运行目录
- [x] 增加 Windows 逐文件 SHA-256 清单、安装/原生加载检查/运行库打包脚本，启动接入检查
- [x] Windows 图形回归：视频/暂停 seek/共享纹理投屏/循环/封面/图片切换；详见 doc/PLATFORMS.md

- [x] 合并远程 bin/win-bin.zip 和缺库自动恢复流程，保留 Windows 实测结果及 Mac 脚本可执行位

## 窗口缩放时固定内部卡片（2026-09-09）

- [x] 关闭整套 UI 画布缩放，窗口大小交给容器重新布局
- [x] 媒体与播放列表卡片取消双轴填充，保持当前尺寸档位，宽度变化只换行
- [x] Windows D3D12 实窗验证 18 组尺寸/分区组合：卡片尺寸不变且画布比例为 1，LAYOUT failures=0

## 投屏空闲黑屏与设置确认流程（2026-09-09）

- [x] CastWindow 增加不透明纯黑底层，无视频/停止/音频状态保持黑屏
- [x] 设置控件改为草稿编辑，改值时不直接写 settings.cfg
- [x] 「应用」保存并应用但不关闭；「确定」保存、应用并关闭
- [x] 扩展设置按钮冒烟测试，覆盖黑屏、未应用不落盘、应用及确定语义

## 关闭反馈与退出优化（2026-09-10）

- [x] 标题栏关闭按钮增加按压回弹和“正在关闭”状态，防止关闭期间看起来无响应
- [x] 统一标题栏、菜单退出和软件重启的清理入口，并防止重复触发
- [x] 退出前主动停止 MPV/封面任务/播放列表并关闭 CEF 页面，减少 shutdown 等待
- [x] 动画后立即最小化主窗口；完整主场景实测清理到退出约 1.15s
- [x] `tests/close_feedback_smoke.gd` 6 项通过，`tests/shutdown_smoke.gd` 正常退出

## 仓库整理（2026-09-10）

- [ ] 删除无引用的多窗口教程副本、旧 Windows 项目副本和下载模板脚本（大范围删除待明确确认）
- [x] 忽略 Godot 热重载产生的 `bin/~*.dll*` 临时文件
- [x] 将功能提交快进合并到 master，删除本地及 Gitee 的其他分支，只维护 master

## Windows Release 发行构建（2026-09-10）

- [x] 使用 Godot 4.7.2 Windows x86_64 Release 模板和 `--export-release`
- [x] Release 排除测试、文档、工具、Godot AI 调试组件及 CEF 浏览缓存
- [x] 从锁定清单部署完整 CEF 运行文件，仅保留 zh-CN/en-US 语言包
- [x] 新增可重复构建脚本，自动校验依赖、提取模板、导出、检查和压缩
- [x] 发行目录 23 文件约 566MB，ZIP 约 242MB；隐藏启动验证退出码 0
