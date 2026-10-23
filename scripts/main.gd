extends PanelContainer
## ScreenPlayer 主窗口
## 媒体库（卡片式，参照 doc/item.png）+ 两个播放端（预览 / 输出）；
## 独立投屏窗口共享输出端纹理（同一解码实例，画面零延迟一致）。
## 预览端始终静音（仅作预览用）。项目持久化：启动打开上次项目，媒体库增删自动保存。
## 封面：Thumbnailer 后台实例在设定秒数抓帧，PNG 持久化到 user://thumbnails/；
## 图片直接读文件缩略，音频/网页显示类型占位字形；PPT 封面在首次预览时
## 从幻灯片第一页抓帧生成。
## 媒体库条目 = MediaObject（scripts/media_object.gd）：类型按扩展名推断，
## 属性含缩放比例/水平/垂直偏移，卡片 ⚙ 打开独立条目设置窗口编辑；
## 视频/音频由 mpv 播放，图片走静态纹理通路，网页走 CEF 内核，
## PPT 由 PptxConverter 预转成自包含 HTML 后经 CEF 播放（翻页 = 页码导航）。
## 项目缓存捆绑：X.splproj 同级 X_cache/ 存 pptx 转换结果与封面副本（保存时同步）。
## 播放列表：媒体库「添加列表」创建 PlaylistObject（条目+逐项时长/列表总时长/
## 定时自动播放，随项目持久化），卡片 ≡ 标记与媒体卡片混排；PlaylistRunner
## 用墙钟把条目依次推输出端（复用卡片「播放」通路，投屏自动弹出）。

const MediaItemCardScene := preload("res://scripts/media_item_card.gd")
const PlaylistCardScene := preload("res://scripts/playlist_card.gd")
const ThumbnailerScene := preload("res://scripts/thumbnailer.gd")
const WebThumbnailerScene := preload("res://scripts/web_thumbnailer.gd")
const PptxConverterScene := preload("res://scripts/pptx_converter.gd")
const WindowResizerScript := preload("res://scripts/window_resizer.gd")
const TouchPointsLayerScript := preload("res://scripts/touch_points_layer.gd")
const BUILTIN_LAYOUT := {
	"version": 1,
	"split_x": 0.72,
	"split_y": 0.5,
	"player_left": 0.43,
	"player_right": 0.57,
}

var _preview: PlayerSlot
var _output: PlayerSlot
var _cast_geometry_request := 0

var cef_cache_path := "user://cef_cache"  # 测试可在入树前设置独立目录，避免占用正在运行的浏览器配置
var cef_enabled := true  # 非网页冒烟测试可关闭，避免与已运行编辑器的 CEF 单例互相占用
var _cef: Node  # GDCEF 浏览器内核管理节点（gdcef 未安装时为 null）
var _cef_initializing := false
var _pending_cef_preview := ""  # 首次初始化 CEF 后继续加载的网页/PPT
var _pending_cef_output := ""
var _thumbnailer  # Thumbnailer（preload 实例化，不依赖全局类注册）
var _web_thumbnailer  # WebThumbnailer（复用延迟初始化的 CEF，独立离屏抓取 HTML 封面）
var _web_cover_backlog: Array[String] = []
var _web_cover_init_requested := false
var _pptx_converter  # PptxConverter（同上）
var _media_items: Array[MediaObject] = []  # 与媒体卡片一一对应
var _playlists: Array[PlaylistObject] = []  # 播放列表（与列表卡片一一对应）
var _item_windows := {}  # 媒体路径 -> ItemSettingsWindow（点击 ⚙ 时创建）
var _playlist_windows := {}  # PlaylistObject -> PlaylistSettingsWindow
var _runner: PlaylistRunner  # 播放列表执行器（推输出端顺序播放 + 定时自动播放）
var _output_media: MediaObject  # 当前输出端播放的媒体对象（null = 空）
var _thumb_cache := {}  # 媒体路径 -> ImageTexture
var _project_cache_dir := ""  # 当前项目的 X_cache/ 目录（无项目时为空）
var _pending_ppt_preview := ""  # 等待转换完成后自动预览的 pptx 路径
var _pending_ppt_output := ""  # 等待转换完成后直接在输出端起播的 pptx 路径（卡片「播放」）
var _status_timer := 0.0
var _project_name := ProjectStore.DEFAULT_PROJECT_NAME
var _project_path := ""
var _preview_dragging := false
var _output_dragging := false
var _card_size_idx := 1  # 媒体库卡片规格索引（小/中/大）
var _order_editing := false
var _title_bar  # TitleBar（自绘标题栏，无边框主窗口用）
var _preview_dots  # 预览画面触点可视化层（TouchPointsLayer）
var _output_dots  # 输出画面触点可视化层（投屏窗口不叠加触点标记）
var _is_quitting := false
var _main_window_save_timer: Timer
var _pending_main_window_size := Vector2i.ZERO
var _restoring_main_window_size := false
var _audio_item_controls := {}  # MediaObject -> {slider, value, mute}，媒体库音频调音台
var _startup_initializing := true
var _loading_tween: Tween

@onready var _menu_file: MenuButton = %MenuFile
@onready var _menu_window: MenuButton = %MenuWindow
@onready var _menu_settings: Button = %MenuSettings  # 普通按钮：点击直接弹设置窗口
@onready var _menu_help: MenuButton = %MenuHelp
@onready var _add_file_button: Button = %AddFileButton
@onready var _add_list_button: Button = %AddListButton
@onready var _card_size_button: MenuButton = %CardSizeButton
@onready var _order_edit_button: Button = %OrderEditButton
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _project_open_dialog: FileDialog = %ProjectOpenDialog
@onready var _project_save_dialog: FileDialog = %ProjectSaveDialog
@onready var _media_grid: HFlowContainer = %MediaGrid
@onready var _about_dialog: AcceptDialog = %AboutDialog
@onready var _settings_window: SettingsWindow = %SettingsWindow
@onready var _preview_label: Label = %PreviewScreenLabel
@onready var _preview_play_button: Button = %PreviewPlay
@onready var _preview_stop_button: Button = %PreviewStop
@onready var _preview_time_label: Label = %PreviewTime
@onready var _output_play_button: Button = %OutputPlay
@onready var _output_stop_button: Button = %OutputStop
@onready var _output_time_label: Label = %OutputTime
@onready var _quick_switch_button: Button = %QuickSwitch
@onready var _hide_cast_button: Button = %HideCastButton
@onready var _restart_button: Button = %RestartButton
@onready var _cast_window: Window = %CastWindow
@onready var _cast_video_view: TextureRect = %CastVideoView
@onready var _preview_progress: HSlider = %PreviewProgress
@onready var _output_progress: HSlider = %OutputProgress
@onready var _preview_page_buttons: HBoxContainer = %PreviewPageButtons
@onready var _output_page_buttons: HBoxContainer = %OutputPageButtons
@onready var _output_mute_button: Button = %OutputMute
@onready var _audio_channels: HBoxContainer = %AudioChannels
@onready var _audio_master_item: PanelContainer = %AudioMasterItem
@onready var _audio_master_header: PanelContainer = %AudioMasterHeader
@onready var _audio_master_slider: VSlider = %AudioMasterSlider
@onready var _audio_master_value: Label = %AudioMasterValue
@onready var _audio_master_mute_button: Button = %AudioMasterMute
@onready var _status_cpu: Label = %StatusCpu
@onready var _status_gpu: Label = %StatusGpu
@onready var _status_mem: Label = %StatusMem
@onready var _status_pid: Label = %StatusPid
@onready var _status_version: Label = %StatusVersion
@onready var _quad_split: QuadSplitContainer = %QuadSplit
@onready var _players_split: TripleSplitContainer = %PlayersSection
@onready var _startup_overlay: ColorRect = %StartupOverlay
@onready var _startup_progress: ProgressBar = %StartupProgress
@onready var _startup_stage: Label = %StartupStage


func _ready() -> void:
	AppLog.info("app", "main_initializing")
	_startup_overlay.visible = true
	_startup_overlay.modulate = Color.WHITE
	_set_startup_progress(6.0, "正在准备界面…")
	await get_tree().process_frame
	# 无边框主窗口 + 自绘标题栏 + 手动边缘缩放：窗口拖动/缩放由代码逐帧完成，
	# 不进入 Windows 的模态移动/缩放消息循环（该循环会冻结整个进程主循环），
	# 因此拖动主窗口时播放与投屏画面不再中断
	var main_window := get_window()
	main_window.borderless = true
	_title_bar = $RootVBox/TitleBar
	_title_bar.close_requested.connect(_request_app_quit)
	add_child(WindowResizerScript.new())
	_restore_main_window_size()
	_main_window_save_timer = Timer.new()
	_main_window_save_timer.one_shot = true
	_main_window_save_timer.wait_time = 0.35
	add_child(_main_window_save_timer)
	_main_window_save_timer.timeout.connect(_save_main_window_size)
	main_window.size_changed.connect(_queue_main_window_size_save)
	main_window.files_dropped.connect(_on_files_dropped)
	_set_startup_progress(20.0, "正在创建播放窗口…")
	await get_tree().process_frame

	_preview = PlayerSlot.new()
	_preview.name = "PreviewSlot"
	add_child(_preview)
	_preview.setup(%VideoView, _preview_label)
	_preview.set_muted(true)  # 预览端始终静音（仅作预览用，业务上不需要声音）
	_preview.state_changed.connect(_refresh_preview_ui)

	_output = PlayerSlot.new()
	_output.name = "OutputSlot"
	add_child(_output)
	_output.setup(%OutputVideoView, %OutputScreenLabel)
	_output.state_changed.connect(_on_output_state_changed)
	# 投屏窗口与输出播放器共享同一纹理：同一解码实例，物理上不可能不同步
	_output.frame_updated.connect(func(tex: Texture2D) -> void: _cast_video_view.texture = tex)
	_set_startup_progress(38.0, "正在初始化播放器…")
	await get_tree().process_frame

	_thumbnailer = ThumbnailerScene.new()
	_thumbnailer.name = "Thumbnailer"
	add_child(_thumbnailer)
	_thumbnailer.thumbnail_ready.connect(_on_thumbnail_ready)
	_web_thumbnailer = WebThumbnailerScene.new()
	_web_thumbnailer.name = "WebThumbnailer"
	add_child(_web_thumbnailer)
	_web_thumbnailer.thumbnail_ready.connect(_on_thumbnail_ready)

	# CEF 是启动阶段最重的组件。普通视频/音频/图片不需要浏览器，因此这里只
	# 准备引用；首次打开网页或 PPT 时再由 _ensure_cef 初始化并显示进度。
	_preview.web_cef = null
	_output.web_cef = null
	_set_startup_progress(50.0, "正在准备媒体组件…")
	await get_tree().process_frame

	# PPT 转换管理器：复用全局 GDCEF，隐藏浏览器后台把 pptx 转成自包含 HTML
	_pptx_converter = PptxConverterScene.new()
	_pptx_converter.name = "PptxConverter"
	add_child(_pptx_converter)
	_pptx_converter.setup(_cef)
	_pptx_converter.convert_done.connect(_on_pptx_convert_done)

	# 播放列表执行器：条目经 _runner_load_item 推输出端（复用卡片「播放」通路）
	_runner = PlaylistRunner.new()
	_runner.name = "PlaylistRunner"
	add_child(_runner)
	_runner.setup(_output, _runner_load_item, _runner_is_pending)
	_runner.started.connect(func(_pl: PlaylistObject) -> void: _refresh_playlist_cards())
	_runner.item_started.connect(func(_pl: PlaylistObject, _i: int) -> void: _refresh_playlist_cards())
	_runner.stopped.connect(_on_playlist_stopped)
	_set_startup_progress(78.0, "正在连接界面控件…")
	await get_tree().process_frame

	_add_file_button.pressed.connect(_on_add_file_pressed)
	_add_list_button.pressed.connect(_on_add_list_pressed)
	_order_edit_button.toggled.connect(_on_order_edit_toggled)
	# 媒体库卡片规格：三档固定尺寸（小/中/大，不随窗口拉伸），选择持久化
	var size_popup := _card_size_button.get_popup()
	for i in MediaItemCard.CARD_WIDTHS.size():
		size_popup.add_radio_check_item(MediaItemCard.CARD_SIZE_LABELS[i], i)
	size_popup.id_pressed.connect(_on_card_size_selected)
	_apply_card_size(int(ProjectStore.get_setting("ui", "card_size", 1)))
	_file_dialog.files_selected.connect(_on_files_selected)
	_project_open_dialog.file_selected.connect(_on_project_open_file_selected)
	_project_save_dialog.file_selected.connect(_on_project_save_file_selected)
	_preview_play_button.pressed.connect(_on_preview_play_pressed)
	_preview_stop_button.pressed.connect(_on_preview_stop_pressed)
	_output_play_button.pressed.connect(_on_output_play_pressed)
	_output_stop_button.pressed.connect(_on_output_stop_pressed)
	_quick_switch_button.pressed.connect(_on_quick_switch_pressed)
	_hide_cast_button.pressed.connect(_on_hide_cast_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_cast_window.close_requested.connect(_on_cast_window_close_requested)
	_cast_window.visibility_changed.connect(func() -> void:
		AppLog.info("cast", "visibility_changed", {"visible": _cast_window.visible,
			"x": _cast_window.position.x, "y": _cast_window.position.y}))
	_cast_window.focus_entered.connect(func() -> void: AppLog.debug("cast", "focus_entered"))
	_cast_window.focus_exited.connect(func() -> void: AppLog.debug("cast", "focus_exited"))
	_settings_window.settings_changed.connect(_apply_settings)
	_settings_window.layout_command_requested.connect(_on_layout_command_requested)
	# 原生子窗口的键盘事件不会冒泡到主窗口。
	_cast_window.window_input.connect(_on_cast_hotkey_input)
	_settings_window.window_input.connect(_on_cast_hotkey_input)
	# 主窗口重新获得焦点时复查条目文件存在性（源文件被外部移动/删除/恢复后标记自动更新）
	get_window().focus_entered.connect(_refresh_missing_states)
	_preview_progress.drag_started.connect(func() -> void: _preview_dragging = true)
	_preview_progress.drag_ended.connect(_on_preview_progress_drag_ended)
	_output_progress.drag_started.connect(func() -> void: _output_dragging = true)
	_output_progress.drag_ended.connect(_on_output_progress_drag_ended)
	_output_mute_button.pressed.connect(_on_output_mute_pressed)
	_audio_master_mute_button.pressed.connect(_on_output_mute_pressed)
	_audio_master_slider.value_changed.connect(_on_output_volume_changed)
	# 六区域布局：外层十字分割 + 播放区内部预览/转场/输出双分割。
	_apply_layout(_current_layout_from_settings(), false)
	_quad_split.ratios_changed.connect(_on_quad_split_ratios_changed)
	_players_split.ratios_changed.connect(_on_players_split_ratios_changed)
	# PPT 翻页按钮（画面内底部 < >，仅 SLIDE 帧源时显示）
	%PreviewPagePrev.pressed.connect(_preview.prev_page)
	%PreviewPageNext.pressed.connect(_preview.next_page)
	%OutputPagePrev.pressed.connect(_output.prev_page)
	%OutputPageNext.pressed.connect(_output.next_page)
	for b: Button in [%PreviewPagePrev, %PreviewPageNext, %OutputPagePrev, %OutputPageNext]:
		b.custom_minimum_size = Vector2(30, 40)
		b.focus_mode = Control.FOCUS_NONE
	# 网页触点：可视化层叠加在预览/输出画面上（不挡鼠标，投屏窗口不叠加）；
	# 预览端「触点」开关进入编辑模式，点击画面加点/删点
	_preview_dots = TouchPointsLayerScript.new()
	%VideoView.get_parent().add_child(_preview_dots)
	_output_dots = TouchPointsLayerScript.new()
	%OutputVideoView.get_parent().add_child(_output_dots)
	%PreviewTouchEdit.toggled.connect(func(on: bool) -> void: _preview.touch_edit_mode = on)
	_preview.touch_edit_clicked.connect(_on_touch_edit_clicked)
	_setup_menus()
	_set_startup_progress(88.0, "正在恢复媒体项目…")
	await get_tree().process_frame
	_load_initial_project()
	_apply_settings()
	_update_status_bar()
	_startup_initializing = false
	_set_startup_progress(100.0, "准备完成")
	await get_tree().process_frame
	_hide_loading_overlay()
	var screens := []
	for index in DisplayServer.get_screen_count():
		screens.append({"index": index, "position": str(DisplayServer.screen_get_position(index)),
			"size": str(DisplayServer.screen_get_size(index)), "scale": DisplayServer.screen_get_scale(index)})
	AppLog.info("app", "main_ready", {"media_count": _media_items.size(), "screens": screens})


func _set_startup_progress(value: float, stage: String) -> void:
	_startup_progress.value = value
	_startup_stage.text = stage


func _cef_ready() -> bool:
	return _cef != null and is_instance_valid(_cef)


## 首次真正使用网页/PPT 时才初始化 CEF。initialize 本身是同步调用，所以先让
## 遮罩至少绘制一帧，避免用户误以为点击没有响应；并发请求共用同一次初始化。
func _ensure_cef(show_feedback := true) -> bool:
	if _cef_ready():
		return true
	if not cef_enabled or not ClassDB.class_exists(&"GdCEF"):
		return false
	if _cef_initializing:
		while _cef_initializing:
			await get_tree().process_frame
		return _cef_ready()

	_cef_initializing = true
	if show_feedback:
		_show_loading_overlay("首次使用，正在初始化网页组件…", 35.0)
		await get_tree().process_frame
	var started_msec := Time.get_ticks_msec()
	var instance := ClassDB.instantiate(&"GdCEF") as Node
	instance.name = "CEF"
	add_child(instance)
	var cef_config := {"locale": "zh-CN"}
	if OS.get_name() == "macOS":
		# .app/项目目录可能只读；浏览器持久数据放用户数据目录。
		var cache := ProjectSettings.globalize_path(cef_cache_path)
		DirAccess.make_dir_recursive_absolute(cache)
		cef_config["root_cache_path"] = cache
		cef_config["cache_path"] = cache
		cef_config["log_file"] = ProjectSettings.globalize_path("user://cef.log")
		cef_config["remote_debugging_port"] = 0
	if instance.initialize(cef_config):
		_cef = instance
		_preview.web_cef = _cef
		_output.web_cef = _cef
		if _pptx_converter != null:
			_pptx_converter.setup(_cef)
		if _web_thumbnailer != null:
			_web_thumbnailer.setup(_cef)
			_flush_web_cover_backlog()
	else:
		push_error("CEF 初始化失败：" + instance.get_error())
		instance.queue_free()
	_cef_initializing = false
	print("CEF_LAZY_INIT_MS=%d" % (Time.get_ticks_msec() - started_msec))
	if show_feedback:
		_set_startup_progress(100.0, "网页组件准备完成" if _cef_ready() else "网页组件初始化失败")
		await get_tree().process_frame
		_hide_loading_overlay()
	return _cef_ready()


func _show_loading_overlay(stage: String, progress: float) -> void:
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	_startup_overlay.visible = true
	_startup_overlay.modulate = Color.WHITE
	_set_startup_progress(progress, stage)


func _hide_loading_overlay() -> void:
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	_loading_tween = create_tween()
	_loading_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_loading_tween.tween_property(_startup_overlay, "modulate:a", 0.0, 0.22)
	_loading_tween.finished.connect(func() -> void: _startup_overlay.visible = false)


func _exit_tree() -> void:
	# CEF 子进程需显式 shutdown 才能干净退出
	if _cef != null and is_instance_valid(_cef):
		_cef.shutdown()


func _process(delta: float) -> void:
	if _startup_initializing:
		return
	_update_progress_ui()
	_status_timer += delta
	if _status_timer >= 0.5:
		_status_timer = 0.0
		_update_status_bar()
		_check_playlist_schedules()


func _input(event: InputEvent) -> void:
	_on_cast_hotkey_input(event)


func _on_cast_hotkey_input(event: InputEvent) -> void:
	if _settings_window.is_capturing_hotkey():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.get_keycode_with_modifiers() == SettingsWindow.get_hotkey("toggle_cast"):
			AppLog.info("hotkey", "cast_toggle", {"shortcut": OS.get_keycode_string(event.get_keycode_with_modifiers()), "visible_before": _cast_window.visible})
			_on_hide_cast_pressed()
			var focused := Window.get_focused_window()
			if focused != null:
				focused.set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.get_keycode_with_modifiers() == SettingsWindow.get_hotkey("quick_switch"):
		_on_quick_switch_pressed()
		get_viewport().set_input_as_handled()
		return
	for i in 3:
		if key_event.get_keycode_with_modifiers() == SettingsWindow.get_hotkey("switch_item_%d" % (i + 1)):
			_switch_item(i)
			get_viewport().set_input_as_handled()
			return


# ---------- 菜单栏 ----------

func _setup_menus() -> void:
	var file_popup := _menu_file.get_popup()
	file_popup.add_item("添加文件…", 0)
	file_popup.add_separator()
	file_popup.add_item("新建项目", 10)
	file_popup.add_item("打开项目…", 11)
	file_popup.add_item("保存项目", 12)
	file_popup.add_item("项目另存为…", 13)
	file_popup.add_separator()
	file_popup.add_item("退出", 1)
	file_popup.id_pressed.connect(_on_menu_file_id_pressed)

	var window_popup := _menu_window.get_popup()
	window_popup.add_item("显示/隐藏投屏窗口", 0)
	window_popup.id_pressed.connect(_on_menu_window_id_pressed)

	_menu_settings.pressed.connect(_on_menu_settings_pressed)

	var help_popup := _menu_help.get_popup()
	help_popup.add_item("关于 ScreenPlayer", 0)
	help_popup.add_item("打开日志文件夹", 1)
	help_popup.id_pressed.connect(_on_menu_help_id_pressed)


func _on_menu_file_id_pressed(id: int) -> void:
	match id:
		0:
			_on_add_file_pressed()
		1:
			_request_app_quit()
		10:
			_new_project()
		11:
			_project_open_dialog.popup_centered_ratio(0.6)
		12:
			_save_current_project_or_ask()
		13:
			_project_save_dialog.popup_centered_ratio(0.6)


func _on_menu_window_id_pressed(_id: int) -> void:
	_on_hide_cast_pressed()


func _on_menu_settings_pressed() -> void:
	var on_screen := false
	var window_rect := Rect2i(_settings_window.position, _settings_window.size)
	for screen_index in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(screen_index).encloses(window_rect):
			on_screen = true
			break
	if not _settings_window.visible or _settings_window.mode == Window.MODE_MINIMIZED or not on_screen:
		var main_win := get_window()
		var usable := DisplayServer.screen_get_usable_rect(main_win.current_screen)
		var centered := main_win.position + (main_win.size - _settings_window.size) / 2
		_settings_window.position = Vector2i(
			clampi(centered.x, usable.position.x, maxi(usable.position.x, usable.end.x - _settings_window.size.x)),
			clampi(centered.y, usable.position.y, maxi(usable.position.y, usable.end.y - _settings_window.size.y)))
	_settings_window.open()
	AppLog.info("settings", "window_opened", {"visible": _settings_window.visible,
		"position": str(_settings_window.position), "mode": _settings_window.mode})


func _on_menu_help_id_pressed(_id: int) -> void:
	if _id == 1:
		AppLog.open_folder()
		return
	_about_dialog.dialog_text = "ScreenPlayer v%s\n跨窗口同步播放器\n\n预览 → 快速切换 → 输出 + 投屏窗口\n输出与投屏窗口共享同一解码实例与纹理，画面声音完全一致。" \
		% ProjectSettings.get_setting("application/config/version", "0.1.1")
	_about_dialog.popup_centered()


# ---------- 设置应用 ----------

func _apply_settings() -> void:
	# 声音开关（set_volume 实生效）；输出端音频同时是投屏窗口的音频（共享实例）
	_output.set_muted(_output_muted_state())
	_apply_output_volume()
	_thumbnailer.capture_pos = float(ProjectStore.get_setting("thumbs", "position", 1.0))
	_refresh_audio_ui()
	# 投屏窗口几何
	var w := int(ProjectStore.get_setting("cast_window", "width", 960))
	var h := int(ProjectStore.get_setting("cast_window", "height", 540))
	_apply_cast_geometry()
	var zoom := float(ProjectStore.get_setting("cast_window", "zoom", 100)) / 100.0
	var pan := Vector2(
		float(ProjectStore.get_setting("cast_window", "pan_x", 0)),
		float(ProjectStore.get_setting("cast_window", "pan_y", 0))
	)
	# 投屏画面变换 = 全局窗口缩放/平移 × 当前输出媒体对象的缩放/偏移
	var item_scale := 1.0
	var item_offset := Vector2.ZERO
	if _output_media != null:
		item_scale = _output_media.scale
		item_offset = _output_media.offset()
	_cast_video_view.pivot_offset = Vector2(w, h) / 2.0
	_cast_video_view.scale = Vector2(zoom * item_scale, zoom * item_scale)
	_cast_video_view.position = pan + item_offset


func _apply_cast_geometry() -> void:
	_cast_geometry_request += 1
	var request := _cast_geometry_request
	var started_usec := Time.get_ticks_usec()
	var target_size := Vector2i(
		int(ProjectStore.get_setting("cast_window", "width", 960)),
		int(ProjectStore.get_setting("cast_window", "height", 540)))
	var centered := get_window().position + (get_window().size - target_size) / 2
	var x := int(ProjectStore.get_setting("cast_window", "pos_x", -1))
	var y := int(ProjectStore.get_setting("cast_window", "pos_y", -1))
	var target_position := Vector2i(centered.x if x == -1 else x, centered.y if y == -1 else y)
	AppLog.info("cast", "geometry_requested", {"request_id": request, "x": target_position.x, "y": target_position.y, "width": target_size.x, "height": target_size.y, "visible": _cast_window.visible, "actual_x": _cast_window.position.x, "actual_y": _cast_window.position.y})
	# 原生窗口的 resize/show 可能异步改写位置；按最终几何校验，旧请求立即让位。
	for attempt in 6:
		if request != _cast_geometry_request:
			AppLog.debug("cast", "geometry_superseded", {"request_id": request})
			return
		if attempt > 0:
			AppLog.debug("cast", "geometry_retry", {"request_id": request, "attempt": attempt + 1, "actual_x": _cast_window.position.x, "actual_y": _cast_window.position.y})
		if _cast_window.size != target_size:
			_cast_window.size = target_size
		_cast_window.position = target_position
		await get_tree().process_frame
		await get_tree().process_frame
		if request != _cast_geometry_request:
			AppLog.debug("cast", "geometry_superseded", {"request_id": request})
			return
		if _cast_window.size == target_size and _cast_window.position == target_position:
			AppLog.info("cast", "geometry_applied", {"request_id": request, "attempts": attempt + 1, "duration_us": Time.get_ticks_usec() - started_usec, "x": _cast_window.position.x, "y": _cast_window.position.y, "width": _cast_window.size.x, "height": _cast_window.size.y})
			return
	AppLog.warn("cast", "geometry_failed", {"request_id": request, "actual_x": _cast_window.position.x, "actual_y": _cast_window.position.y, "actual_width": _cast_window.size.x, "actual_height": _cast_window.size.y})
	push_warning("投屏窗口几何未被系统接受，请检查显示器布局。")


# ---------- 快捷键 ----------

func _switch_item(index: int) -> void:
	if index >= _media_items.size():
		return
	var m := _media_items[index]
	if not m.is_playable():
		return
	_load_preview(m)
	_on_quick_switch_pressed()


# ---------- 项目 ----------

func _load_initial_project() -> void:
	var path := ProjectStore.load_last_project_path()
	if path.is_empty() or not ProjectStore.project_exists(path):
		path = ProjectStore.DEFAULT_PROJECT_PATH
	if ProjectStore.project_exists(path):
		_load_project_from(path)
	else:
		# 首次运行：建立默认项目
		_project_path = ProjectStore.DEFAULT_PROJECT_PATH
		_project_name = ProjectStore.DEFAULT_PROJECT_NAME
		_project_cache_dir = ProjectStore.cache_dir_for(_project_path)
		ProjectStore.set_last_project_path(_project_path)
		_save_current_project()
		_update_title()


func _load_project_from(path: String) -> void:
	AppLog.info("project", "open_requested", AppLog.media_ref(path))
	var data := ProjectStore.load_project(path)
	if data.is_empty():
		push_warning("项目文件无法读取：" + path)
		return
	_project_path = path
	_project_name = str(data["name"])
	_project_cache_dir = ProjectStore.cache_dir_for(path)
	_clear_media_items()
	if not data["items"].is_empty():
		for d in data["items"]:
			_add_media_item(MediaObject.from_dict(d), false)
	else:
		# 旧版项目文件只有纯路径列表
		for media_path in data["media_paths"]:
			_add_media_item(MediaObject.create(str(media_path)), false)
	for pd in data["playlists"]:
		_add_playlist(PlaylistObject.from_dict(pd))
	_apply_library_order(data.get("library_order", []))
	ProjectStore.set_last_project_path(path)
	_update_title()


func _save_current_project() -> void:
	if _project_path.is_empty():
		return
	var err := ProjectStore.save_project(
		_project_path, _project_name, _media_items, _playlists, _library_order_data())
	if err != OK:
		push_error("项目保存失败（%s）：%s" % [_project_path, error_string(err)])
		return
	AppLog.debug("project", "saved", {"resource": AppLog.media_ref(_project_path), "items": _media_items.size()})
	# 同步项目缓存捆绑：封面 + PPT 转换结果复制进 X_cache/（缺失才复制）
	ProjectStore.sync_project_cache(_project_path, _media_items)


func _save_current_project_or_ask() -> void:
	if _project_path.is_empty():
		_project_save_dialog.popup_centered_ratio(0.6)
	else:
		_save_current_project()


func _new_project() -> void:
	_project_path = ""
	_project_name = "未命名项目"
	_project_cache_dir = ""
	_clear_media_items()
	_update_title()


func _on_project_open_file_selected(path: String) -> void:
	_load_project_from(path)


func _on_project_save_file_selected(path: String) -> void:
	if not path.ends_with(".splproj"):
		path += ".splproj"
	_project_path = path
	_project_name = path.get_file().get_basename()
	_save_current_project()
	ProjectStore.set_last_project_path(path)
	_update_title()


func _update_title() -> void:
	var t := "ScreenPlayer — " + _project_name
	get_window().title = t
	_title_bar.set_title(t)


# ---------- 媒体库（卡片式） ----------

func _add_media_item(media: MediaObject, generate_web_cover := true) -> void:
	if _find_media(media.path) != null:
		return  # 已在库中（条目设置窗口以路径为键，不允许重复）
	_media_items.append(media)
	var card := MediaItemCardScene.new()
	_media_grid.add_child(card)
	card.setup(media)
	card.apply_size(MediaItemCard.CARD_WIDTHS[_card_size_idx])
	card.preview_requested.connect(_on_card_preview)
	card.push_requested.connect(_on_card_push)
	card.settings_requested.connect(_on_card_settings)
	card.delete_requested.connect(_on_card_delete)
	card.loop_toggled.connect(_on_card_loop_toggled)
	card.mute_toggled.connect(_on_card_mute_toggled)
	card.move_requested.connect(_move_library_card)
	card.set_missing(not media.exists())
	_apply_card_cover(card, generate_web_cover)
	_refresh_card_indices()
	_refresh_order_controls()
	_rebuild_audio_channels()


func _on_order_edit_toggled(on: bool) -> void:
	_order_editing = on
	_order_edit_button.text = "完成排序" if on else "编辑顺序"
	_refresh_order_controls()


func _library_cards() -> Array[Control]:
	var cards: Array[Control] = []
	for child in _media_grid.get_children():
		if child is MediaItemCard or child is PlaylistCard:
			cards.append(child)
	return cards


func _refresh_order_controls() -> void:
	var cards := _library_cards()
	for i in cards.size():
		cards[i].set_order_editing(_order_editing, i > 0, i < cards.size() - 1)


func _move_library_card(card: Control, delta: int) -> void:
	var cards := _library_cards()
	var from := cards.find(card)
	var to := from + delta
	if from < 0 or to < 0 or to >= cards.size():
		return
	_media_grid.move_child(card, cards[to].get_index())
	_sync_library_arrays_from_grid()
	_refresh_card_indices()
	_refresh_order_controls()
	_save_current_project()


func _sync_library_arrays_from_grid() -> void:
	_media_items.clear()
	_playlists.clear()
	for card in _library_cards():
		if card is MediaItemCard:
			_media_items.append(card.media)
		elif card is PlaylistCard:
			_playlists.append(card.playlist)
	_rebuild_audio_channels()


func _library_order_data() -> Array:
	var result: Array = []
	for card in _library_cards():
		if card is MediaItemCard:
			var media_index := _media_items.find(card.media)
			if media_index >= 0:
				result.append({"kind": "media", "index": media_index})
		elif card is PlaylistCard:
			var playlist_index := _playlists.find(card.playlist)
			if playlist_index >= 0:
				result.append({"kind": "playlist", "index": playlist_index})
	return result


func _apply_library_order(order: Array) -> void:
	if order.is_empty():
		_refresh_order_controls()
		return
	var media_cards: Array[Control] = []
	var playlist_cards: Array[Control] = []
	for card in _library_cards():
		if card is MediaItemCard:
			media_cards.append(card)
		else:
			playlist_cards.append(card)
	var ordered: Array[Control] = []
	for entry in order:
		if not entry is Dictionary:
			continue
		var source := media_cards if str(entry.get("kind", "")) == "media" else playlist_cards
		var index := int(entry.get("index", -1))
		if index >= 0 and index < source.size() and not ordered.has(source[index]):
			ordered.append(source[index])
	for card in _library_cards():
		if not ordered.has(card):
			ordered.append(card)
	for i in ordered.size():
		_media_grid.move_child(ordered[i], i)
	_sync_library_arrays_from_grid()
	_refresh_card_indices()
	_refresh_order_controls()


## 卡片序号 = 媒体库顺序（标题栏蓝色数字，增删后重排）；列表卡片不编号
func _refresh_card_indices() -> void:
	var i := 1
	for card in _media_grid.get_children():
		if card is MediaItemCard:
			card.set_index(i)
			i += 1


## 媒体库卡片规格切换（尺寸菜单）：三档固定宽度，媒体卡片与列表卡片一起调
func _on_card_size_selected(id: int) -> void:
	_apply_card_size(id)
	ProjectStore.set_setting("ui", "card_size", id)


func _apply_card_size(idx: int) -> void:
	_card_size_idx = clampi(idx, 0, MediaItemCard.CARD_WIDTHS.size() - 1)
	var w: int = MediaItemCard.CARD_WIDTHS[_card_size_idx]
	for card in _media_grid.get_children():
		if card is MediaItemCard or card is PlaylistCard:
			card.apply_size(w)
	var popup := _card_size_button.get_popup()
	for i in MediaItemCard.CARD_WIDTHS.size():
		popup.set_item_checked(i, i == _card_size_idx)
	_card_size_button.text = "尺寸：" + MediaItemCard.CARD_SIZE_LABELS[_card_size_idx]


## 条目级循环开关：写回媒体对象并持久化；正在输出该条目时立即生效
func _on_card_loop_toggled(card: MediaItemCard) -> void:
	card.media.loop = not card.media.loop
	card.refresh_toggles()
	if _output_media == card.media:
		_output.set_looping(card.media.loop)
	_save_current_project()


## 条目级静音开关：与全局「输出/投屏声音」为或关系；
## 正在输出该条目时立即生效
func _on_card_mute_toggled(card: MediaItemCard) -> void:
	card.media.muted = not card.media.muted
	card.refresh_toggles()
	if _output_media == card.media:
		_output.set_muted(_output_muted_state())
	_refresh_audio_ui()
	_save_current_project()


## 输出端实际静音态 = 全局声音关闭 或 当前条目条目级静音
func _output_muted_state() -> bool:
	var global_muted := not bool(ProjectStore.get_setting("audio", "output", true))
	return global_muted or (_output_media != null and _output_media.muted)


## 复查全部条目的文件存在性并刷新丢失标记（主窗口重获焦点时调用）；
## 文件恢复的条目补做封面（丢失时跳过过）
func _refresh_missing_states() -> void:
	for card in _media_grid.get_children():
		if not card is MediaItemCard:
			continue
		var missing: bool = not card.media.exists()
		card.set_missing(missing)
		if not missing:
			_apply_card_cover(card)


func _find_media(path: String) -> MediaObject:
	for m in _media_items:
		if m.path == path:
			return m
	return null


func _first_playable() -> MediaObject:
	for m in _media_items:
		if m.is_playable() and m.exists():
			return m
	return null


func _apply_card_cover(card: MediaItemCard, generate_web_cover := false) -> void:
	# 所有媒体统一先读项目 X_cache/thumbs，再回退全局缓存；没有封面时按类型
	# 自动生成。HTML 使用独立 CEF 离屏浏览器，不会占用预览/输出播放器。
	if not card.media.exists():
		return  # 文件已丢失：不做封面（图片读不到、视频排队截取也只会失败）
	if _thumb_cache.has(card.media_path):
		card.set_thumbnail(_thumb_cache[card.media_path])
		return
	var cached := ProjectStore.find_cover(_project_cache_dir, card.media_path)
	if not cached.is_empty():
		var cached_image := Image.load_from_file(cached)
		if cached_image != null:
			var cached_texture := ImageTexture.create_from_image(cached_image)
			_thumb_cache[card.media_path] = cached_texture
			card.set_thumbnail(cached_texture)
			return
	match card.media.type:
		MediaObject.Type.VIDEO:
			_thumbnailer.enqueue([card.media_path])
		MediaObject.Type.PPT:
			pass  # 首次预览第一页后由 _schedule_ppt_cover_grab 抓取
		MediaObject.Type.IMAGE:
			var img := Image.load_from_file(card.media_path)
			if img == null:
				return
			_save_cover(card.media_path, img)
		MediaObject.Type.AUDIO:
			_save_cover(card.media_path, _make_audio_cover())
		MediaObject.Type.HTML:
			if not _web_cover_backlog.has(card.media_path):
				_web_cover_backlog.append(card.media_path)
			if generate_web_cover:
				_request_web_cover_generation()


func _request_web_cover_generation() -> void:
	if _web_cover_init_requested or _web_cover_backlog.is_empty():
		return
	_web_cover_init_requested = true
	var ok := await _ensure_cef()
	_web_cover_init_requested = false
	if ok:
		_flush_web_cover_backlog()


func _flush_web_cover_backlog() -> void:
	if _web_thumbnailer == null or not _cef_ready() or _web_cover_backlog.is_empty():
		return
	_web_thumbnailer.enqueue(_web_cover_backlog)
	_web_cover_backlog.clear()


func _make_audio_cover() -> Image:
	var image := Image.create(320, 180, false, Image.FORMAT_RGB8)
	image.fill(Color("10151f"))
	# 没有可截图画面的音频用统一波形封面，保证卡片和项目缓存仍有实际 PNG。
	var heights := [28, 52, 78, 108, 68, 42, 92, 120, 76, 48, 66, 98, 58]
	for i in heights.size():
		var height: int = heights[i]
		var x := 53 + i * 17
		var color := Color("3b82f6").lerp(Color("35d6c1"), float(i) / float(heights.size() - 1))
		image.fill_rect(Rect2i(x, (180 - height) / 2, 9, height), color)
	return image


## 封面写盘：同时写全局 user://thumbnails/ 和当前项目 X_cache/thumbs/。
## 视频、图片、音频生成图、HTML 网页截图与 PPT 首帧共用此通路。
func _save_cover(path: String, img: Image) -> void:
	if img == null or img.is_empty():
		return
	# 等比缩放到 320x180 以内，与 Thumbnailer 输出一致
	var scale := minf(320.0 / img.get_width(), 180.0 / img.get_height())
	if scale < 1.0:
		img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProjectStore.GLOBAL_THUMB_DIR))
	if err == OK:
		img.save_png(ProjectStore.GLOBAL_THUMB_DIR + "/" + path.md5_text() + ".png")
	if not _project_cache_dir.is_empty():
		var project_thumb_dir := _project_cache_dir + "/thumbs"
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(project_thumb_dir)) == OK:
			img.save_png(project_thumb_dir + "/" + path.md5_text() + ".png")
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[path] = tex
	for card in _media_grid.get_children():
		if card is MediaItemCard and card.media_path == path:
			card.set_thumbnail(tex)


func _on_thumbnail_ready(path: String, img: Image) -> void:
	_save_cover(path, img)


func _clear_media_items() -> void:
	_media_items.clear()
	_playlists.clear()
	if _runner != null:
		_runner.stop()
	for win in _playlist_windows.values():
		if is_instance_valid(win):
			win.queue_free()
	_playlist_windows.clear()
	for win: ItemSettingsWindow in _item_windows.values():
		win.queue_free()
	_item_windows.clear()
	for card in _media_grid.get_children():
		_media_grid.remove_child(card)
		card.queue_free()
	_rebuild_audio_channels()


## 按类型把条目加载到预览端：视频/音频走 mpv，图片走静态纹理通路，网页走 CEF，
## PPT 走预转 HTML（无缓存时触发转换并显示占位，完成后自动加载）
func _load_preview(m: MediaObject) -> void:
	AppLog.info("playback", "preview_requested", AppLog.media_ref(m.path))
	if m.type in [MediaObject.Type.HTML, MediaObject.Type.PPT] and not _cef_ready():
		_pending_cef_preview = m.path
		_load_preview_after_cef(m)
		return
	match m.type:
		MediaObject.Type.IMAGE:
			_preview.load_static(m.path)
		MediaObject.Type.HTML:
			_preview.load_web(m.path)
		MediaObject.Type.PPT:
			var html := _pptx_html_for(m)
			if not html.is_empty():
				_preview.load_slides(html, m.page_count, 0, m.path)
				_schedule_ppt_cover_grab(m)
			else:
				_request_ppt_conversion(m)
		_:
			_preview.load_media(m.path)
	_preview.set_view_transform(m.scale, m.offset())
	_preview.web_points = m.touch_points  # 共享引用：触点编辑即时生效


func _load_preview_after_cef(m: MediaObject) -> void:
	var path := m.path
	_preview_label.text = "网页组件初始化中…\n" + m.display_name()
	var ok := await _ensure_cef()
	if _pending_cef_preview != path:
		return  # 等待期间用户已经选择了另一个条目
	_pending_cef_preview = ""
	if not ok:
		_preview_label.text = "网页组件初始化失败\n" + m.display_name()
		return
	_load_preview(m)


## PPT 缓存查找：项目 X_cache 优先，回退全局 user://pptx；都没有返回 ""
func _pptx_html_for(m: MediaObject) -> String:
	return ProjectStore.find_pptx_html(_project_cache_dir, m.path)


## 触发 PPT 后台转换：预览端显示占位、卡片挂"转换中"徽标，
## 完成后由 _on_pptx_convert_done 自动加载预览
func _request_ppt_conversion(m: MediaObject) -> void:
	_preview.stop()
	_preview_label.text = "PPT 转换中…\n" + m.display_name()
	_pending_ppt_preview = m.path
	var card := _find_card(m.path)
	if card != null:
		card.set_converting(true)
	_pptx_converter.convert(m.path)


func _find_card(path: String) -> MediaItemCard:
	for card in _media_grid.get_children():
		if card is MediaItemCard and card.media_path == path:
			return card
	return null


func _on_pptx_convert_done(ok: bool, out_path: String, page_count: int) -> void:
	# 由输出文件名（md5）找回对应媒体条目
	var m: MediaObject = null
	for it in _media_items:
		if it.type == MediaObject.Type.PPT and PptxConverter.cache_file_name(it.path) == out_path.get_file():
			m = it
			break
	if m == null:
		return
	var card := _find_card(m.path)
	if card != null:
		card.set_converting(false)
	if not ok:
		push_warning("PPT 转换失败：" + m.path)
		if _pending_ppt_preview == m.path:
			_pending_ppt_preview = ""
			_preview_label.text = "PPT 转换失败\n" + m.display_name()
		if _pending_ppt_output == m.path:
			_pending_ppt_output = ""
		return
	if page_count > 0 and m.page_count != page_count:
		m.page_count = page_count
		_save_current_project()  # 页数随项目持久化
	# 用户正在等这个条目的预览：转换完成自动加载
	if _pending_ppt_preview == m.path:
		_pending_ppt_preview = ""
		_preview_label.text = "未加载预览媒体"
		_preview.load_slides(out_path, m.page_count, 0, m.path)
		_preview.set_view_transform(m.scale, m.offset())
		_schedule_ppt_cover_grab(m)
	# 卡片「播放」触发的转换：完成后直接在输出端 + 投屏窗口起播
	if _pending_ppt_output == m.path:
		_pending_ppt_output = ""
		_output_media = m
		_output.load_slides(out_path, m.page_count, 0, m.path)
		_apply_output_media_prefs()
		_show_cast_window()


## PPT 封面：预览加载缓存 HTML 后第 2 秒从浏览器纹理抓第一页画面
## （等页面渲染稳定），走与视频封面相同的缩略/落盘通路
func _schedule_ppt_cover_grab(m: MediaObject) -> void:
	if not ProjectStore.find_cover(_project_cache_dir, m.path).is_empty():
		return  # 已有封面
	var path := m.path
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if _preview.media_path != path or _preview.source_kind != PlayerSlot.SourceKind.SLIDE:
			return  # 预览已切走
		var img := _preview.get_frame_image()
		if img == null or img.is_empty():
			return
		_save_cover(path, img)
	)


func _on_card_preview(card: MediaItemCard) -> void:
	var m := card.media
	match m.type:
		MediaObject.Type.VIDEO:
			_preview_label.text = "未加载预览媒体"
			_load_preview(m)
		MediaObject.Type.AUDIO:
			# 音频由 mpv 正常播放，但没有画面：显示播放符号代替视频纹理
			_preview.load_media(m.path)
			%VideoView.visible = false
			_preview_label.text = "♪ " + m.display_name()
			_preview_label.visible = true
		MediaObject.Type.IMAGE:
			_preview_label.text = "未加载预览媒体"
			_load_preview(m)
		MediaObject.Type.HTML:
			_preview_label.text = "未加载预览媒体"
			_load_preview(m)
		MediaObject.Type.PPT:
			_preview_label.text = "未加载预览媒体"
			_load_preview(m)
		_:
			_preview.stop()
			_preview_label.text = "%s · %s\n（不支持的媒体类型）" % [MediaObject.type_label(m.type), m.display_name()]


func _on_card_push(card: MediaItemCard) -> void:
	if not card.media.is_playable():
		return
	# 卡片「播放」= 直接送输出端 + 投屏窗口播放，不经过预览端
	_runner.stop()  # 手动推送接管输出端：停掉正在跑的播放列表
	_load_output(card.media)


## 直接加载到输出端（从开头自动播放）：视频/音频走 mpv，图片走静态纹理，
## 网页走 CEF，PPT 走缓存 HTML（无缓存时后台转换，完成自动起播）
func _load_output(m: MediaObject) -> void:
	AppLog.info("playback", "output_requested", AppLog.media_ref(m.path))
	if m.type in [MediaObject.Type.HTML, MediaObject.Type.PPT] and not _cef_ready():
		_pending_cef_output = m.path
		_load_output_after_cef(m)
		return
	_output_media = m
	match m.type:
		MediaObject.Type.IMAGE:
			_output.load_static(m.path)
		MediaObject.Type.HTML:
			_output.load_web(m.path)
		MediaObject.Type.PPT:
			var html := _pptx_html_for(m)
			if html.is_empty():
				_pending_ppt_output = m.path
				var card := _find_card(m.path)
				if card != null:
					card.set_converting(true)
				_pptx_converter.convert(m.path)
				return  # 转换完成后由 _on_pptx_convert_done 起播
			_output.load_slides(html, m.page_count, 0, m.path)
		_:
			_output.load_media(m.path, true, 0.0)
	_output.web_points = m.touch_points  # 共享引用：触点编辑即时生效
	_apply_output_media_prefs()
	_show_cast_window()


func _load_output_after_cef(m: MediaObject) -> void:
	var path := m.path
	var ok := await _ensure_cef()
	if _pending_cef_output != path:
		return  # 等待期间输出请求已被后来的条目替代
	_pending_cef_output = ""
	if not ok:
		push_warning("网页组件初始化失败，无法播放：" + m.path)
		return
	_load_output(m)


## 输出端加载媒体后的统一收尾：条目级循环/静音偏好（静音与全局开关为或关系）、
## 画面变换、投屏画面变换；音频无画面时显示 ♪ 符号
func _apply_output_media_prefs() -> void:
	if _output_media == null:
		return
	_output.set_looping(_output_media.loop)
	_apply_output_volume()
	_output.set_muted(_output_muted_state())
	_refresh_audio_ui()
	_output.set_view_transform(_output_media.scale, _output_media.offset())
	_apply_settings()  # 投屏画面变换 = 全局缩放/平移 × 条目缩放/偏移
	if _output_media.type == MediaObject.Type.AUDIO:
		%OutputVideoView.visible = false
		%OutputScreenLabel.text = "♪ " + _output_media.display_name()
		%OutputScreenLabel.visible = true
		_cast_video_view.visible = false


func _on_card_settings(card: MediaItemCard) -> void:
	# 点击时创建独立条目设置窗口；同一条目已打开则聚焦已有窗口
	if _item_windows.has(card.media_path) and is_instance_valid(_item_windows[card.media_path]):
		_item_windows[card.media_path].grab_focus()
		return
	if card.media.type == MediaObject.Type.HTML and not _cef_ready():
		_open_web_settings_after_cef(card)
		return
	_open_item_settings(card)


func _open_web_settings_after_cef(card: MediaItemCard) -> void:
	if await _ensure_cef() and is_instance_valid(card):
		_open_item_settings(card)


func _open_item_settings(card: MediaItemCard) -> void:
	var win := ItemSettingsWindow.new()
	win.setup(card.media)
	win.cef = _cef  # 设置窗口右侧实时预览的内嵌浏览器用（无 gdcef 时预览区为空）
	add_child(win)
	_item_windows[card.media_path] = win
	win.properties_changed.connect(_on_item_properties_changed)
	win.window_closed.connect(func(path: String) -> void: _item_windows.erase(path))
	var main_win := get_window()
	win.position = main_win.position + (main_win.size - win.size) / 2
	win.show()


func _on_item_properties_changed(media: MediaObject) -> void:
	# 属性改动即时应用到正在播放该条目的播放端，并自动保存项目
	if _preview.media_path == media.path:
		_preview.set_view_transform(media.scale, media.offset())
	if _output.media_path == media.path:
		_output.set_view_transform(media.scale, media.offset())
		_apply_settings()  # 刷新投屏画面变换（全局缩放 × 条目缩放）
	_save_current_project()


func _on_card_delete(card: MediaItemCard) -> void:
	_media_items.erase(card.media)
	_rebuild_audio_channels()
	if _item_windows.has(card.media_path) and is_instance_valid(_item_windows[card.media_path]):
		_item_windows[card.media_path].queue_free()
	_item_windows.erase(card.media_path)
	card.queue_free()
	_save_current_project()
	# 删除的若是当前输出条目，刷新高亮（延迟到卡片真正释放后）
	_update_output_highlight.call_deferred()
	_refresh_card_indices.call_deferred()
	_refresh_order_controls.call_deferred()


func _update_output_highlight() -> void:
	for card in _media_grid.get_children():
		if card is MediaItemCard:
			card.set_highlighted(not _output.media_path.is_empty() and card.media_path == _output.media_path)


func _on_add_file_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.6)


func _on_files_selected(paths: PackedStringArray) -> void:
	_import_media_paths(paths)


## 从系统文件管理器拖到主窗口的文件快速加入媒体库。目录和不支持的扩展名忽略，
## 其余行为复用“添加文件”（复制入库、去重、封面和项目自动保存）。
func _on_files_dropped(paths: PackedStringArray) -> void:
	var media_paths := PackedStringArray()
	for raw_path in paths:
		var path := str(raw_path)
		if DirAccess.dir_exists_absolute(path):
			continue
		if MediaObject.detect_type(path) == MediaObject.Type.OTHER:
			continue
		media_paths.append(path)
	if media_paths.is_empty():
		push_warning("拖入的文件中没有支持的媒体")
		return
	_import_media_paths(media_paths)


func _import_media_paths(paths: PackedStringArray) -> void:
	# 「复制到项目目录」开关（设置窗口）：开启时把源文件真实复制进
	# X_cache/media/，条目指向副本，源文件被删除也不影响播放
	var copy := bool(ProjectStore.get_setting("media", "copy_to_project", false))
	for path in paths:
		var m := MediaObject.create(path)
		if copy and not m.is_remote():
			var copied := ProjectStore.copy_media_into_project(_project_path, path)
			if not copied.is_empty():
				m.origin_path = path
				m.path = copied
		_add_media_item(m)
	_save_current_project()


# ---------- 主窗口尺寸持久化 ----------

## 启动时恢复上次窗口态的宽高，并按当前显示器可用区域钳制。
func _restore_main_window_size() -> void:
	var win := get_window()
	var fallback := win.size
	var saved := Vector2i(
		int(ProjectStore.get_setting("main_window", "width", fallback.x)),
		int(ProjectStore.get_setting("main_window", "height", fallback.y))
	)
	var minimum := Vector2i(1024, 600)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var maximum := usable.size if usable.size.x > 0 and usable.size.y > 0 else saved
	maximum.x = maxi(maximum.x, minimum.x)
	maximum.y = maxi(maximum.y, minimum.y)
	saved.x = clampi(saved.x, minimum.x, maximum.x)
	saved.y = clampi(saved.y, minimum.y, maximum.y)
	_restoring_main_window_size = true
	win.size = saved
	_pending_main_window_size = saved
	_restoring_main_window_size = false


## 拖动边缘时 size_changed 会逐帧触发；延迟到停止变化后再落盘。
func _queue_main_window_size_save() -> void:
	var win := get_window()
	if _restoring_main_window_size or win.mode != Window.MODE_WINDOWED:
		return
	_pending_main_window_size = win.size
	_main_window_save_timer.start()


func _save_main_window_size() -> void:
	if _pending_main_window_size.x <= 0 or _pending_main_window_size.y <= 0:
		return
	ProjectStore.set_settings("main_window", {
		"width": _pending_main_window_size.x,
		"height": _pending_main_window_size.y,
	})


# ---------- 播放列表 ----------

func _on_add_list_pressed() -> void:
	var pl := PlaylistObject.new()
	pl.name = "播放列表 %d" % (_playlists.size() + 1)
	_add_playlist(pl)
	_save_current_project()


func _add_playlist(pl: PlaylistObject) -> void:
	_playlists.append(pl)
	var card := PlaylistCardScene.new()
	_media_grid.add_child(card)
	card.setup(pl)
	card.apply_size(MediaItemCard.CARD_WIDTHS[_card_size_idx])
	card.play_requested.connect(_on_playlist_play)
	card.preview_requested.connect(_on_playlist_preview)
	card.settings_requested.connect(_on_playlist_settings)
	card.delete_requested.connect(_on_playlist_delete)
	card.move_requested.connect(_move_library_card)
	_refresh_order_controls()


## 列表卡片「播放」：推送输出端顺序播放整个列表（再次点击 = 停止列表）
func _on_playlist_play(card: PlaylistCard) -> void:
	if _runner.playlist == card.playlist:
		_runner.stop()
		_output.stop()
		return
	_runner.stop()  # 停掉正在播放的其他列表
	if not _runner.start(card.playlist):
		push_warning("播放列表为空或全部条目不可播放：" + card.playlist.name)


func _on_playlist_preview(card: PlaylistCard) -> void:
	for entry in card.playlist.items:
		var media := _find_media(str(entry.get("path", "")))
		if media != null and media.is_playable() and media.exists():
			_load_preview(media)
			return
	push_warning("播放列表中没有可预览的媒体：" + card.playlist.name)


## Runner 加载回调：条目走卡片「播放」同一通路（投屏窗口自动弹出）
func _runner_load_item(path: String) -> bool:
	var m := _find_media(path)
	if m == null or not m.is_playable() or not m.exists():
		return false
	_load_output(m)
	return true


## Runner 查询：该路径正在初始化 CEF 或后台做 PPT 转换（此期间不算外部干预）
func _runner_is_pending(path: String) -> bool:
	return _pending_cef_output == path or _pending_ppt_output == path


func _on_playlist_stopped(_pl: PlaylistObject, reason: String) -> void:
	if reason == "finished":
		_output.stop()  # 一轮播完/播满列表时长：收尾清屏
	_refresh_playlist_cards()


func _refresh_playlist_cards() -> void:
	for card in _media_grid.get_children():
		if card is PlaylistCard:
			card.set_playing(_runner != null and _runner.playlist == card.playlist)


func _on_playlist_settings(card: PlaylistCard) -> void:
	if _playlist_windows.has(card.playlist) and is_instance_valid(_playlist_windows[card.playlist]):
		_playlist_windows[card.playlist].grab_focus()
		return
	var win := PlaylistSettingsWindow.new()
	add_child(win)
	win.setup(card.playlist, _media_items)
	_playlist_windows[card.playlist] = win
	win.changed.connect(func(_pl: PlaylistObject) -> void:
		card.refresh()
		_save_current_project()
	)
	win.window_closed.connect(func(pl: PlaylistObject) -> void: _playlist_windows.erase(pl))
	var main_win := get_window()
	win.position = main_win.position + (main_win.size - win.size) / 2
	win.show()


func _on_playlist_delete(card: PlaylistCard) -> void:
	if _runner.playlist == card.playlist:
		_runner.stop()
		_output.stop()
	if _playlist_windows.has(card.playlist) and is_instance_valid(_playlist_windows[card.playlist]):
		_playlist_windows[card.playlist].queue_free()
	_playlist_windows.erase(card.playlist)
	_playlists.erase(card.playlist)
	card.queue_free()
	_save_current_project()
	_refresh_order_controls.call_deferred()


## 定时自动播放：0.5s tick 检查各列表的开启/关闭时间，
## 到开启时段且执行器空闲则起播，出时段则停止
func _check_playlist_schedules() -> void:
	for pl in _playlists:
		if not pl.auto_enabled:
			continue
		if pl.is_in_schedule_now():
			if _runner.playlist != pl and not _runner.is_active():
				_runner.start(pl)
		elif _runner.playlist == pl:
			_runner.stop()
			_output.stop()


# ---------- 预览播放器 ----------

func _on_preview_play_pressed() -> void:
	if _preview.source_kind == PlayerSlot.SourceKind.WEB:
		_preview.step_web(-1)  # 网页模式：播放键 = 上一触点
		return
	if _preview.media_path.is_empty():
		var m := _first_playable()
		if m != null:
			_load_preview(m)
		return
	_preview.toggle_play()


func _on_preview_stop_pressed() -> void:
	if _preview.source_kind == PlayerSlot.SourceKind.WEB:
		_preview.step_web(1)  # 网页模式：停止键 = 下一触点
		return
	_preview.stop()


func _refresh_preview_ui() -> void:
	_preview_play_button.text = "⏸" if _preview.playing else "▶"
	if _preview.media_path.is_empty():
		_preview_time_label.text = "00:00 / 00:00"
		_preview_label.text = "未加载预览媒体"


# ---------- 输出播放器 ----------

func _on_output_play_pressed() -> void:
	if _output.source_kind == PlayerSlot.SourceKind.WEB:
		_output.step_web(-1)  # 网页模式：播放键 = 上一触点
		return
	_output.toggle_play()


func _on_output_stop_pressed() -> void:
	if _output.source_kind == PlayerSlot.SourceKind.WEB:
		_output.step_web(1)  # 网页模式：停止键 = 下一触点
		return
	_output.stop()


# ---------- 快速切换 / 投屏窗口 ----------

func _on_quick_switch_pressed() -> void:
	AppLog.info("playback", "quick_switch", {"preview": AppLog.media_ref(_preview.media_path), "time": _preview.elapsed, "playing": _preview.playing})
	# 预览为空但媒体库有内容时，先加载第一个可播放条目再切换
	if _preview.media_path.is_empty():
		var m := _first_playable()
		if m == null:
			return
		if m.type in [MediaObject.Type.HTML, MediaObject.Type.PPT] and not await _ensure_cef():
			return
		_load_preview(m)
	var state := _preview.get_state()
	var path := str(state["media_path"])
	if path.is_empty():
		return
	_runner.stop()  # 快速切换接管输出端：停掉正在跑的播放列表
	# 输出端与投屏窗口共享同一实例与纹理，天然完全同步；
	# 起播时一次性 seek 到预览当前进度（首帧到达后由 PlayerSlot 执行）；
	# 图片走静态纹理通路（无需 seek）；PPT 推送缓存 HTML + 当前页码
	_output_media = _find_media(path)
	if _output_media != null and _output_media.type == MediaObject.Type.IMAGE:
		_output.load_static(path)
	elif _output_media != null and _output_media.type == MediaObject.Type.HTML:
		_output.load_web(path)
	elif _output_media != null and _output_media.type == MediaObject.Type.PPT:
		var html := _pptx_html_for(_output_media)
		if html.is_empty():
			return  # 预览端能播说明已转换，这里只是兜底
		_output.load_slides(html, _output_media.page_count, int(state.get("page", 0)), path)
	else:
		_output.load_media(path, bool(state["playing"]), float(state["time_pos"]))
	if _output_media != null:
		_output.web_points = _output_media.touch_points  # 共享引用：触点编辑即时生效
	_apply_output_media_prefs()  # 条目级循环/静音/画面变换推送到输出端
	_show_cast_window()


func _show_cast_window() -> void:
	AppLog.info("cast", "show_requested", {"visible_before": _cast_window.visible})
	_cast_window.show()
	_apply_cast_geometry()
	_hide_cast_button.text = "隐藏投屏"


func _on_output_state_changed() -> void:
	_output_play_button.text = "⏸" if _output.playing else "▶"
	if _output.media_path.is_empty():
		_output_time_label.text = "00:00 / 00:00"
		%OutputScreenLabel.text = "未加载输出媒体"
		if _output_media != null:
			_output_media = null
			_apply_settings()  # 投屏画面变换回到全局设置
	var is_audio := _output_media != null and _output_media.type == MediaObject.Type.AUDIO
	_cast_video_view.visible = not _output.media_path.is_empty() and not is_audio
	_update_output_highlight()


func _on_hide_cast_pressed() -> void:
	AppLog.info("cast", "visibility_toggle", {"visible_before": _cast_window.visible})
	if _cast_window.visible:
		_cast_window.hide()
		_hide_cast_button.text = "显示投屏"
		get_window().grab_focus()
	else:
		_show_cast_window()


func _on_cast_window_close_requested() -> void:
	AppLog.info("cast", "close_requested")
	_cast_window.hide()
	_hide_cast_button.text = "显示投屏"


func _on_restart_pressed() -> void:
	OS.set_restart_on_exit(true)
	_request_app_quit()


## 关闭按钮动画结束后先隐藏主窗口，再主动停止后台解码/浏览器。
## 用户立即看到窗口消失；活动页面提前关闭也能缩短随后 CEF shutdown 的等待。
func _request_app_quit() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	# 最后一次缩放可能尚在 0.35s 防抖期，最小化前强制保存当前窗口态尺寸。
	if get_window().mode == Window.MODE_WINDOWED:
		_pending_main_window_size = get_window().size
		_save_main_window_size()
	set_process(false)
	# Godot 不允许隐藏主原生窗口；最小化能立即给出“窗口已关闭”的视觉反馈，
	# 随后的安全清理只在后台持续很短时间。
	get_window().mode = Window.MODE_MINIMIZED
	_cast_window.hide()
	_settings_window.hide()
	if _runner != null:
		_runner.stop("manual")
	for win in _item_windows.values():
		if is_instance_valid(win):
			win.hide()
	for win in _playlist_windows.values():
		if is_instance_valid(win):
			win.hide()
	if _preview != null:
		_preview.prepare_shutdown()
	if _output != null:
		_output.prepare_shutdown()
	if _thumbnailer != null and _thumbnailer.has_method("prepare_shutdown"):
		_thumbnailer.prepare_shutdown()
	if _web_thumbnailer != null and _web_thumbnailer.has_method("prepare_shutdown"):
		_web_thumbnailer.prepare_shutdown()
	if _pptx_converter != null and _pptx_converter.has_method("prepare_shutdown"):
		_pptx_converter.prepare_shutdown()
	# 给 queue_free 的浏览器一个消息循环周期，再进入全局 CEF shutdown。
	await get_tree().process_frame
	get_tree().quit()


# ---------- 状态栏 ----------

func _update_status_bar() -> void:
	_status_cpu.text = "FPS %d" % Engine.get_frames_per_second()
	_status_gpu.text = "帧耗时 %.1f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_status_mem.text = "内存 %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	_status_pid.text = "PID %d" % OS.get_process_id()
	_status_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1.1")


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


# ---------- 进度条 / 音量 ----------

func _on_preview_progress_drag_ended(value_changed: bool) -> void:
	_preview_dragging = false
	if value_changed:
		_preview.seek(_preview_progress.value)


func _on_output_progress_drag_ended(value_changed: bool) -> void:
	_output_dragging = false
	if value_changed:
		_output.seek(_output_progress.value)


func _update_progress_ui() -> void:
	_update_slot_progress(_preview, _preview_progress, _preview_time_label, _preview_dragging)
	_update_slot_progress(_output, _output_progress, _output_time_label, _output_dragging)
	_update_page_buttons(_preview, _preview_page_buttons)
	_update_page_buttons(_output, _output_page_buttons)
	_update_web_ui()


## 网页模式 UI：播放/停止键变成 ← →（触点步进，无触点或到边界则禁用）；
## 预览端「触点」编辑开关仅网页媒体可见，切走时自动退出编辑模式
func _update_web_ui() -> void:
	_update_slot_web_ui(_preview, _preview_play_button, _preview_stop_button)
	_update_slot_web_ui(_output, _output_play_button, _output_stop_button)
	var can_edit := _preview.source_kind == PlayerSlot.SourceKind.WEB
	%PreviewTouchEdit.visible = can_edit
	if not can_edit and %PreviewTouchEdit.button_pressed:
		%PreviewTouchEdit.set_pressed_no_signal(false)
		_preview.touch_edit_mode = false
	_refresh_touch_layers()


func _update_slot_web_ui(slot: PlayerSlot, play_btn: Button, stop_btn: Button) -> void:
	if slot.source_kind == PlayerSlot.SourceKind.WEB:
		play_btn.text = "←"
		stop_btn.text = "→"
		play_btn.disabled = slot.web_points.is_empty() or slot.web_step <= 0
		stop_btn.disabled = slot.web_points.is_empty() or slot.web_step >= slot.web_points.size() - 1
	else:
		play_btn.disabled = false
		stop_btn.disabled = false
		if stop_btn.text == "→":
			stop_btn.text = "■"  # 播放键文本由 state_changed 刷新（▶/⏸）


## 触点可视化层：预览端显示当前网页媒体的触点（编辑模式下空序列也显示），
## 输出端跟随输出媒体（无触点不显示）；投屏窗口不显示触点标记（只执行点击）
func _refresh_touch_layers() -> void:
	_preview_dots.set_points(_preview.web_points, _preview.web_step)
	_preview_dots.visible = _preview.source_kind == PlayerSlot.SourceKind.WEB \
		and (not _preview.web_points.is_empty() or _preview.touch_edit_mode)
	_output_dots.set_points(_output.web_points, _output.web_step)
	_output_dots.visible = _output.source_kind == PlayerSlot.SourceKind.WEB \
		and not _output.web_points.is_empty()


## 触点编辑：左键在预览画面上添加触点，右键删除最近触点；随项目持久化
func _on_touch_edit_clicked(pos_norm: Vector2, button_index: int) -> void:
	var m := _find_media(_preview.media_path)
	if m == null:
		return
	if button_index == MOUSE_BUTTON_LEFT:
		m.touch_points.append(pos_norm)
	else:
		var best := -1
		var best_d := 0.04  # 归一化距离阈值（约 1280×720 上的 40px）
		for i in m.touch_points.size():
			var d: float = m.touch_points[i].distance_to(pos_norm)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			m.touch_points.remove_at(best)
	_preview.web_step = mini(_preview.web_step, m.touch_points.size() - 1)
	_save_current_project()


## PPT 翻页按钮：仅 SLIDE 帧源显示；首页禁用 <，末页禁用 >（页数未知时不禁用）
func _update_page_buttons(slot: PlayerSlot, container: HBoxContainer) -> void:
	var is_slide := slot.source_kind == PlayerSlot.SourceKind.SLIDE
	if container.visible != is_slide:
		container.visible = is_slide
	if not is_slide:
		return
	(container.get_child(0) as Button).disabled = slot.current_page <= 0
	(container.get_child(1) as Button).disabled = slot.page_count > 0 and slot.current_page >= slot.page_count - 1


func _update_slot_progress(slot: PlayerSlot, slider: HSlider, time_label: Label, dragging: bool) -> void:
	if slot.media_path.is_empty():
		slider.editable = false
		slider.set_value_no_signal(0)
		return
	if slot.source_kind == PlayerSlot.SourceKind.STATIC or slot.source_kind == PlayerSlot.SourceKind.WEB:
		# 静态/网页媒体没有进度：进度条禁用，时间显示占位
		slider.editable = false
		slider.set_value_no_signal(0)
		time_label.text = "—"
		return
	if slot.source_kind == PlayerSlot.SourceKind.SLIDE:
		# PPT 幻灯片：进度条按页走（0..页数-1，步进 1），拖动 = 跳页
		if slot.page_count > 0:
			slider.editable = true
			slider.step = 1
			slider.max_value = slot.page_count - 1
			if not dragging:
				slider.set_value_no_signal(slot.current_page)
			time_label.text = "%d / %d" % [slot.current_page + 1, slot.page_count]
		else:
			slider.editable = false
			slider.set_value_no_signal(0)
			time_label.text = "—"
		return
	var dur_text := _format_time(slot.duration) if slot.duration > 0.0 else "--:--"
	time_label.text = _format_time(slot.elapsed) + " / " + dur_text
	slider.editable = slot.duration > 0.0
	if slot.duration > 0.0:
		slider.max_value = slot.duration
		if not dragging:
			slider.set_value_no_signal(slot.elapsed)


func _on_quad_split_ratios_changed(x_ratio: float, y_ratio: float) -> void:
	ProjectStore.set_settings("ui", {"split_x": x_ratio, "split_y": y_ratio})


func _on_players_split_ratios_changed(left_ratio: float, right_ratio: float) -> void:
	ProjectStore.set_settings("ui", {
		"player_left": left_ratio,
		"player_right": right_ratio,
	})


func get_current_layout() -> Dictionary:
	return {
		"version": 1,
		"split_x": _quad_split.split_x_ratio,
		"split_y": _quad_split.effective_split_y_ratio(),
		"player_left": _players_split.left_ratio,
		"player_right": _players_split.right_ratio,
	}


func _current_layout_from_settings() -> Dictionary:
	return {
		"version": 1,
		"split_x": ProjectStore.get_setting("ui", "split_x", BUILTIN_LAYOUT.split_x),
		"split_y": ProjectStore.get_setting("ui", "split_y", BUILTIN_LAYOUT.split_y),
		"player_left": ProjectStore.get_setting("ui", "player_left", BUILTIN_LAYOUT.player_left),
		"player_right": ProjectStore.get_setting("ui", "player_right", BUILTIN_LAYOUT.player_right),
	}


func _normalized_layout(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var layout: Dictionary = value
	for key in ["split_x", "split_y", "player_left", "player_right"]:
		if not layout.has(key) or not layout[key] is float and not layout[key] is int:
			return {}
	var left := clampf(float(layout.player_left), 0.0, 1.0)
	var right := clampf(float(layout.player_right), left, 1.0)
	return {
		"version": 1,
		"split_x": clampf(float(layout.split_x), 0.0, 1.0),
		"split_y": clampf(float(layout.split_y), 0.0, 1.0),
		"player_left": left,
		"player_right": right,
	}


func _apply_layout(value: Variant, persist := true) -> bool:
	var layout := _normalized_layout(value)
	if layout.is_empty():
		return false
	_quad_split.split_x_ratio = layout.split_x
	_quad_split.split_y_ratio = layout.split_y
	# 先扩展右边界再设置左边界，兼容两条边界交叉方向的布局。
	_players_split.right_ratio = 1.0
	_players_split.left_ratio = layout.player_left
	_players_split.right_ratio = layout.player_right
	if persist:
		ProjectStore.set_settings("ui", {
			"split_x": layout.split_x,
			"split_y": layout.split_y,
			"player_left": layout.player_left,
			"player_right": layout.player_right,
		})
	return true


func _on_layout_command_requested(command: String, path: String) -> void:
	match command:
		"save":
			ProjectStore.set_setting("ui", "saved_layout", get_current_layout())
			_settings_window.set_layout_status("当前布局已保存。")
		"restore_saved":
			var saved: Variant = ProjectStore.get_setting("ui", "saved_layout", {})
			_settings_window.set_layout_status(
				"已恢复保存的布局。" if _apply_layout(saved) else "还没有已保存的布局。",
				_normalized_layout(saved).is_empty())
		"set_default":
			ProjectStore.set_setting("ui", "default_layout", get_current_layout())
			_settings_window.set_layout_status("当前布局已设为默认布局。")
		"restore_default":
			var default_layout: Variant = ProjectStore.get_setting("ui", "default_layout", BUILTIN_LAYOUT)
			if not _apply_layout(default_layout):
				_apply_layout(BUILTIN_LAYOUT)
			_settings_window.set_layout_status("已恢复默认布局。")
		"export":
			_export_layout(path)
		"import":
			_import_layout(path)


func _export_layout(selected_path: String) -> void:
	var path := selected_path
	if not path.to_lower().ends_with(".spllayout"):
		path += ".spllayout"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_settings_window.set_layout_status("布局导出失败：无法写入文件。", true)
		return
	file.store_string(JSON.stringify(get_current_layout(), "\t"))
	_settings_window.set_layout_status("布局已导出：" + path)


func _import_layout(path: String) -> void:
	if not FileAccess.file_exists(path):
		_settings_window.set_layout_status("布局导入失败：文件不存在。", true)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _apply_layout(parsed):
		_settings_window.set_layout_status("布局导入失败：文件格式不正确。", true)
		return
	ProjectStore.set_setting("ui", "saved_layout", get_current_layout())
	_settings_window.set_layout_status("布局已导入并应用。")


func _on_output_volume_changed(value: float) -> void:
	# 主音量与当前媒体条目音量相乘，结果应用到输出/投屏共享实例。
	ProjectStore.set_setting("audio", "output_volume", int(value))
	_apply_output_volume()
	_refresh_audio_ui()


func _refresh_audio_ui() -> void:
	var master_volume := int(ProjectStore.get_setting("audio", "output_volume", 100))
	var global_muted := not bool(ProjectStore.get_setting("audio", "output", true))
	_audio_master_slider.set_value_no_signal(master_volume)
	_audio_master_value.text = str(master_volume)
	_output_mute_button.text = "🔇" if _output.muted else "🔊"
	_audio_master_mute_button.text = "🔇" if global_muted else "🔊"
	_audio_master_mute_button.button_pressed = global_muted
	for media: MediaObject in _audio_item_controls:
		var controls: Dictionary = _audio_item_controls[media]
		var slider := controls["slider"] as VSlider
		var value_label := controls["value"] as Label
		var mute_button := controls["mute"] as Button
		slider.set_value_no_signal(media.volume)
		value_label.text = str(media.volume)
		mute_button.text = "🔇" if media.muted else "🔊"
		mute_button.button_pressed = media.muted


func _on_output_mute_pressed() -> void:
	# 主静音控制 settings.cfg 中的输出声音总开关；条目静音仍独立保留。
	var enabled := bool(ProjectStore.get_setting("audio", "output", true))
	ProjectStore.set_setting("audio", "output", not enabled)
	_output.set_muted(_output_muted_state())
	_refresh_audio_ui()


func _apply_output_volume() -> void:
	var master_volume := int(ProjectStore.get_setting("audio", "output_volume", 100))
	var item_volume := _output_media.volume if _output_media != null else 100
	_output.set_volume(roundi(master_volume * item_volume / 100.0))


func _is_audio_controllable_media(media: MediaObject) -> bool:
	# 图片无声音；网页/PPT 使用 CEF 原生音频，目前只支持静音、不支持连续音量。
	return media.type == MediaObject.Type.VIDEO or media.type == MediaObject.Type.AUDIO


func _rebuild_audio_channels() -> void:
	if not is_instance_valid(_audio_channels) or not is_instance_valid(_audio_master_item):
		return
	for child in _audio_channels.get_children():
		if child != _audio_master_item:
			_audio_channels.remove_child(child)
			child.queue_free()
	_audio_item_controls.clear()
	for media in _media_items:
		if not _is_audio_controllable_media(media):
			continue
		_add_audio_channel(media)
	_refresh_audio_ui()


func _add_audio_channel(media: MediaObject) -> void:
	var item := PanelContainer.new()
	item.name = "AudioItem_" + media.path.md5_text().left(8)
	item.custom_minimum_size = Vector2(92, 236)
	item.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item.add_theme_stylebox_override("panel", _audio_master_item.get_theme_stylebox("panel").duplicate())
	_audio_channels.add_child(item)

	var item_stack := VBoxContainer.new()
	item_stack.add_theme_constant_override("separation", 0)
	item.add_child(item_stack)

	var header := PanelContainer.new()
	header.name = "ChannelHeader"
	header.custom_minimum_size = Vector2(0, 30)
	header.add_theme_stylebox_override("panel", _audio_master_header.get_theme_stylebox("panel").duplicate())
	item_stack.add_child(header)

	var title := Label.new()
	title.custom_minimum_size = Vector2(74, 0)
	title.text = media.display_name().get_basename()
	title.tooltip_text = media.display_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", Color(0.8196, 0.851, 0.902))
	title.add_theme_font_size_override("font_size", 12)
	header.add_child(title)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 8)
	body.add_theme_constant_override("margin_top", 6)
	body.add_theme_constant_override("margin_right", 8)
	body.add_theme_constant_override("margin_bottom", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_stack.add_child(body)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(column)

	var value_label := Label.new()
	value_label.text = str(media.volume)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(value_label)

	var slider := VSlider.new()
	slider.custom_minimum_size = Vector2(24, 130)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = media.volume
	column.add_child(slider)

	var mute_button := Button.new()
	mute_button.custom_minimum_size = Vector2(0, 30)
	mute_button.toggle_mode = true
	mute_button.tooltip_text = "静音：" + media.display_name()
	mute_button.text = "🔇" if media.muted else "🔊"
	column.add_child(mute_button)

	_audio_item_controls[media] = {
		"item": item,
		"header": header,
		"title": title,
		"slider": slider,
		"value": value_label,
		"mute": mute_button,
	}
	slider.value_changed.connect(_on_media_volume_changed.bind(media))
	mute_button.pressed.connect(_on_media_mixer_mute_pressed.bind(media))


func _on_media_volume_changed(value: float, media: MediaObject) -> void:
	media.volume = clampi(roundi(value), 0, 100)
	if _output_media == media:
		_apply_output_volume()
	_refresh_audio_ui()
	_save_current_project()


func _on_media_mixer_mute_pressed(media: MediaObject) -> void:
	media.muted = not media.muted
	var card := _find_card(media.path)
	if card != null:
		card.refresh_toggles()
	if _output_media == media:
		_output.set_muted(_output_muted_state())
	_refresh_audio_ui()
	_save_current_project()
