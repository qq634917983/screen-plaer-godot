# 日志与问题追踪

打开方式：主菜单「帮助 → 打开日志文件夹」，或「设置 → 日志诊断」。
日志诊断页可选择 DEBUG / INFO / WARN / ERROR，并显示已写入、排队、丢弃数量与写入故障。
默认 INFO，设置持久保存，切换级别立即生效。复现偶发问题前可打开 DEBUG。

日志目录为 `user://logs`，界面显示实际绝对路径，支持复制。macOS 默认在
`~/Library/Application Support/Godot/app_userdata/screen-plaer-godot/logs`，
Windows 默认在 `%APPDATA%/Godot/app_userdata/screen-plaer-godot/logs`。
每次运行使用单独的 `screenplayer_<UTC毫秒>_<PID>_<单调时钟>/` 目录，支持同时运行多个实例。

## 可以追踪的内容

- 启动/正常退出、程序/Godot 版本、系统、架构、显示器位置/尺寸/缩放，以及每 30 秒的 FPS、内存和日志队列健康数据。
- 投屏位置：`geometry_requested` / `geometry_applied` / `geometry_failed` 使用同一个 `request_id`。
  请求记录目标坐标/尺寸与修改前坐标；完成记录最终值、耗时、尝试次数。
  DEBUG 补充重试、旧请求被新请求替代和焦点变化，不记录逐帧进度。
- 快捷键触发、快捷键配置更改、设置页窗口参数提交、投屏显示/隐藏/关闭及实际可见性变化。
- 预览/输出切换、媒体加载、首帧耗时、播放/暂停/停止、seek 与有限重试、播放列表、PPT 转换开始/结束、项目打开/保存。
- Godot 警告、脚本错误及原生扩展通过 Godot 错误流报告的问题，包含源码文件、行号、函数和错误类型。
  现有 `push_warning` / `push_error` 也会自动进入结构化日志。
- 设置写盘失败会报告到错误流，避免把“本次已应用”误认为“下次启动一定能恢复”。

JSONL 一行一个 JSON 对象，可用文本编辑器、`jq` 或日志分析工具读取。
每行包含 UTC 毫秒时间 `timestamp`、单调时间 `elapsed_us`、会话 `session`、PID、
递增 `seq`、级别 `level`、模块 `component`、事件 `event` 及上下文 `fields`。
队列过载生成的汇总事件不占业务 `seq`，使用 `dropped_total` / `dropped_since_last`。
例如按 `component=cast` 过滤后，再用 `fields.request_id` 对照一次位置修改的结果。

## 性能与容量

采用官方 Godot `Logger` 接收错误，再通过有界生产者/消费者队列交给一个专用线程。
此方案使用常见的异步日志模式，无需第三方二进制库，ARM64 macOS / x86_64 Windows 共用实现。

- 调用端只做级别过滤、上下文快照和短时间互斥入队；JSON 编码、脱敏、文件操作、轮转与清理均在后台。
- 队列最多 4096 条，最后 128 个位置为 WARN/ERROR 预留。满载时丢弃新日志并累计统计，不阻塞播放等待磁盘。
  错误风暴超过全部容量仍可能丢弃错误；`queue_overflow` 明确报告损失，不能保证无限日志完整保存。
- 上下文限制深度、节点数、字符串长度和总字符数；单行最多 64 KiB，超限以截断标记代替上下文。
  不将 Node、Texture、图片、音视频或任意 Object 送入日志线程。
- 正常日志每 0.5 秒唤醒一次；积累 64 条或收到警告/错误时提前唤醒。每批 flush，避免逐条同步刷盘。
- 每个结构化文件最多 5 MiB，保留当前文件 + 4 个备份，单会话最多约 25 MiB。
- 启动时需要清理的情况下，在后台清理旧会话，目标保留最近 10 个；活动进程的目录始终保留，因此多实例运行可暂时超出 10 个。
  后台只枚举一次系统 PID；进程枚举失败时跳过清理，避免误删正在写入的目录。
- 磁盘写入、轮转或目录创建失败时停用该写入器，诊断页显示原因；不会递归记录日志系统自己的写盘错误。
  解决磁盘问题后重启程序恢复日志。
- 正常退出排空队列并关闭文件；退出过程会等待未完成的文件操作。
  强制杀进程、断电、原生崩溃或主循环卡死时，尚未刷出的尾部日志可能丢失。
  `FileAccess.flush()` 不是断电持久性的 fsync 保证。

另外启用 Godot 原生 `godot.log`（最多保留 5 次运行），作为启动输出与完整原生错误栈的补充。
它使用 Godot 自身的日志机制，仅按运行轮转，没有结构化文件的单文件大小限制。
CEF 的 `cef.log` 仍由浏览器组件管理；这两个原生日志不受本日志线程的大小限制与脱敏处理。
应用事件不重复 `print` 到控制台，也不额外启用 release 的持续调用栈跟踪。

结构化上下文中的常见凭据字段会替换为 `[redacted]`；URL 查询参数/fragment 会移除，
媒体使用文件名 + 哈希标识而非完整路径。日志仅保存在本机，未配置自动上传。

## 验证

- `Godot --headless --path . --script tests/logging_smoke.gd`：级别过滤、并发顺序、调用端快照、
  JSON 转义/脱敏、退出排空、队列预留/过载汇总、大小轮转、旧会话保留、不可写目录及官方引擎错误接入。
  测试会主动产生一条目录错误和一条警告，这是故障注入的预期输出，以 `LOGGING SMOKE failures=0` 为通过标志。
- 测试输出 `BENCH` 的单线程调用耗时中位数/p95/p99、过滤耗时与四线程入队数据；
  这些是当前机器、当前构建、当前字段规模的观测值，不是所有机器的性能保证。
- 使用独立测试项目运行 `tests/cast_window_smoke.gd`，验证日志接入后窗口与快捷键行为。
- `tests/macos_smoke.gd` 验证原生 MPV、暂停 seek、共享纹理、循环播放、缩略图和图片输出。
- Windows 的线程/文件/API 共用实现已经接入，仍需 Windows 真机回归与低速磁盘压测。

参考：[Godot 官方 Logger 接口](https://docs.godotengine.org/en/stable/classes/class_logger.html)、
[Godot 日志说明](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/logging.html)。

本轮 Apple M4 / Godot 4.7.2 debug 构建的本地记录：4000 次单线程 INFO 调用，
仅包含一个整数字段，两次运行的调用耗时中位数 2–4 µs、p95 3–6 µs、p99 4–9 µs，
过滤 DEBUG 的平均耗时约 0.24–0.44 µs；四生产者共 4000 条无丢弃。
这个小负载入队测试不包含真实播放时的帧率对比，也不能推导机械盘/满盘下的性能。
完整原生播放冒烟测试与 15 项投屏回归在日志启用时通过。
