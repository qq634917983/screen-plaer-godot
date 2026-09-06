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

const MediaItemCardScene := preload("res://scripts/media_item_card.gd")
const ThumbnailerScene := preload("res://scripts/thumbnailer.gd")
const PptxConverterScene := preload("res://scripts/pptx_converter.gd")
const TitleBarScript := preload("res://scripts/title_bar.gd")
const WindowResizerScript := preload("res://scripts/window_resizer.gd")

var _preview: PlayerSlot
var _output: PlayerSlot
var _cef: Node  # GDCEF 浏览器内核管理节点（gdcef 未安装时为 null）
var _thumbnailer  # Thumbnailer（preload 实例化，不依赖全局类注册）
var _pptx_converter  # PptxConverter（同上）
var _media_items: Array[MediaObject] = []  # 与媒体卡片一一对应
var _item_windows := {}  # 媒体路径 -> ItemSettingsWindow（点击 ⚙ 时创建）
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
var _title_bar  # TitleBar（自绘标题栏，无边框主窗口用）

@onready var _menu_file: MenuButton = %MenuFile
@onready var _menu_window: MenuButton = %MenuWindow
@onready var _menu_settings: MenuButton = %MenuSettings
@onready var _menu_help: MenuButton = %MenuHelp
@onready var _add_file_button: Button = %AddFileButton
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _project_open_dialog: FileDialog = %ProjectOpenDialog
@onready var _project_save_dialog: FileDialog = %ProjectSaveDialog
@onready var _media_grid: HFlowContainer = %MediaGrid
@onready var _media_desc: Label = %MediaDesc
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
@onready var _audio_output_slider: HSlider = %AudioOutputSlider
@onready var _audio_output_value: Label = %AudioOutputValue
@onready var _status_cpu: Label = %StatusCpu
@onready var _status_gpu: Label = %StatusGpu
@onready var _status_mem: Label = %StatusMem
@onready var _status_pid: Label = %StatusPid
@onready var _status_version: Label = %StatusVersion


func _ready() -> void:
	# 无边框主窗口 + 自绘标题栏 + 手动边缘缩放：窗口拖动/缩放由代码逐帧完成，
	# 不进入 Windows 的模态移动/缩放消息循环（该循环会冻结整个进程主循环），
	# 因此拖动主窗口时播放与投屏画面不再中断
	get_window().borderless = true
	_title_bar = TitleBarScript.new()
	$RootVBox.add_child(_title_bar)
	$RootVBox.move_child(_title_bar, 0)
	add_child(WindowResizerScript.new())

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

	_thumbnailer = ThumbnailerScene.new()
	_thumbnailer.name = "Thumbnailer"
	add_child(_thumbnailer)
	_thumbnailer.thumbnail_ready.connect(_on_thumbnail_ready)

	# 浏览器内核（gdcef）：全局唯一 GDCEF 节点，预览/输出两端共用；
	# 未安装扩展时网页条目显示占位提示，其余功能不受影响
	if ClassDB.class_exists(&"GdCEF"):
		_cef = ClassDB.instantiate(&"GdCEF") as Node
		_cef.name = "CEF"
		add_child(_cef)
		if not _cef.initialize({"locale": "zh-CN"}):
			push_error("CEF 初始化失败：" + _cef.get_error())
			_cef.queue_free()
			_cef = null
	_preview.web_cef = _cef
	_output.web_cef = _cef

	# PPT 转换管理器：复用全局 GDCEF，隐藏浏览器后台把 pptx 转成自包含 HTML
	_pptx_converter = PptxConverterScene.new()
	_pptx_converter.name = "PptxConverter"
	add_child(_pptx_converter)
	_pptx_converter.setup(_cef)
	_pptx_converter.convert_done.connect(_on_pptx_convert_done)

	# 统一控制按钮图标：Segoe UI Symbol 全部为文字字形，尺寸一致
	# （默认主题里部分图标落到 emoji 字体渲染，导致大小参差）
	var icon_font := SystemFont.new()
	icon_font.font_names = PackedStringArray(["Segoe UI Symbol"])
	for b: Button in [_preview_play_button, _preview_stop_button, _output_play_button,
			_output_stop_button]:
		b.add_theme_font_override("font", icon_font)
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(34, 0)

	_add_file_button.pressed.connect(_on_add_file_pressed)
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
	_settings_window.settings_changed.connect(_apply_settings)
	# 主窗口重新获得焦点时复查条目文件存在性（源文件被外部移动/删除/恢复后标记自动更新）
	get_window().focus_entered.connect(_refresh_missing_states)
	_preview_progress.drag_started.connect(func() -> void: _preview_dragging = true)
	_preview_progress.drag_ended.connect(_on_preview_progress_drag_ended)
	_output_progress.drag_started.connect(func() -> void: _output_dragging = true)
	_output_progress.drag_ended.connect(_on_output_progress_drag_ended)
	_output_mute_button.pressed.connect(_on_output_mute_pressed)
	_audio_output_slider.value_changed.connect(_on_output_volume_changed)
	# PPT 翻页按钮（画面区右侧 < >，仅 SLIDE 帧源时显示）
	%PreviewPagePrev.pressed.connect(_preview.prev_page)
	%PreviewPageNext.pressed.connect(_preview.next_page)
	%OutputPagePrev.pressed.connect(_output.prev_page)
	%OutputPageNext.pressed.connect(_output.next_page)
	for b: Button in [%PreviewPagePrev, %PreviewPageNext, %OutputPagePrev, %OutputPageNext]:
		b.custom_minimum_size = Vector2(30, 40)
		b.focus_mode = Control.FOCUS_NONE
	_setup_menus()
	_load_initial_project()
	_apply_settings()
	_update_status_bar()


func _exit_tree() -> void:
	# CEF 子进程需显式 shutdown 才能干净退出
	if _cef != null and is_instance_valid(_cef):
		_cef.shutdown()


func _process(delta: float) -> void:
	_update_progress_ui()
	_status_timer += delta
	if _status_timer >= 0.5:
		_status_timer = 0.0
		_update_status_bar()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == SettingsWindow.get_hotkey("quick_switch"):
		_on_quick_switch_pressed()
		get_viewport().set_input_as_handled()
		return
	for i in 3:
		if key_event.keycode == SettingsWindow.get_hotkey("switch_item_%d" % (i + 1)):
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

	var settings_popup := _menu_settings.get_popup()
	settings_popup.add_item("打开设置", 0)
	settings_popup.id_pressed.connect(_on_menu_settings_id_pressed)

	var help_popup := _menu_help.get_popup()
	help_popup.add_item("关于 ScreenPlayer", 0)
	help_popup.id_pressed.connect(_on_menu_help_id_pressed)


func _on_menu_file_id_pressed(id: int) -> void:
	match id:
		0:
			_on_add_file_pressed()
		1:
			get_tree().quit()
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


func _on_menu_settings_id_pressed(_id: int) -> void:
	if not _settings_window.visible:
		var main_win := get_window()
		_settings_window.position = main_win.position + (main_win.size - _settings_window.size) / 2
	_settings_window.open()


func _on_menu_help_id_pressed(_id: int) -> void:
	_about_dialog.dialog_text = "ScreenPlayer v%s\n跨窗口同步播放器\n\n预览 → 快速切换 → 输出 + 投屏窗口\n输出与投屏窗口共享同一解码实例与纹理，画面声音完全一致。" \
		% ProjectSettings.get_setting("application/config/version", "0.1.1")
	_about_dialog.popup_centered()


# ---------- 设置应用 ----------

func _apply_settings() -> void:
	# 声音开关（set_volume 实生效）；输出端音频同时是投屏窗口的音频（共享实例）
	_output.set_muted(_output_muted_state())
	_output.set_volume(int(ProjectStore.get_setting("audio", "output_volume", 100)))
	_thumbnailer.capture_pos = float(ProjectStore.get_setting("thumbs", "position", 1.0))
	_refresh_audio_ui()
	# 投屏窗口几何
	var w := int(ProjectStore.get_setting("cast_window", "width", 960))
	var h := int(ProjectStore.get_setting("cast_window", "height", 540))
	_cast_window.size = Vector2i(w, h)
	var pos_x := int(ProjectStore.get_setting("cast_window", "pos_x", -1))
	var pos_y := int(ProjectStore.get_setting("cast_window", "pos_y", -1))
	if pos_x >= 0 and pos_y >= 0:
		_cast_window.position = Vector2i(pos_x, pos_y)
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
			_add_media_item(MediaObject.from_dict(d))
	else:
		# 旧版项目文件只有纯路径列表
		for media_path in data["media_paths"]:
			_add_media_item(MediaObject.create(str(media_path)))
	ProjectStore.set_last_project_path(path)
	_update_title()


func _save_current_project() -> void:
	if _project_path.is_empty():
		return
	var err := ProjectStore.save_project(_project_path, _project_name, _media_items)
	if err != OK:
		push_error("项目保存失败（%s）：%s" % [_project_path, error_string(err)])
		return
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

func _add_media_item(media: MediaObject) -> void:
	if _find_media(media.path) != null:
		return  # 已在库中（条目设置窗口以路径为键，不允许重复）
	_media_items.append(media)
	var card := MediaItemCardScene.new()
	_media_grid.add_child(card)
	card.setup(media)
	card.preview_requested.connect(_on_card_preview)
	card.push_requested.connect(_on_card_push)
	card.settings_requested.connect(_on_card_settings)
	card.delete_requested.connect(_on_card_delete)
	card.loop_toggled.connect(_on_card_loop_toggled)
	card.mute_toggled.connect(_on_card_mute_toggled)
	card.set_missing(not media.exists())
	_media_desc.visible = false
	_apply_card_cover(card)
	_refresh_card_indices()


## 卡片序号 = 媒体库顺序（标题栏蓝色数字，增删后重排）
func _refresh_card_indices() -> void:
	var i := 1
	for card: MediaItemCard in _media_grid.get_children():
		card.set_index(i)
		i += 1


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
	for card: MediaItemCard in _media_grid.get_children():
		var missing := not card.media.exists()
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


func _apply_card_cover(card: MediaItemCard) -> void:
	# 视频：优先内存缓存，其次已持久化的封面文件（项目 X_cache 优先于全局
	# user://thumbnails），都没有则排队后台截取；
	# PPT：封面在首次预览时从幻灯片第一页抓帧（无队列截取器通路）；
	# 图片：直接读文件缩略；音频/网页保持卡片的类型占位字形
	if not card.media.exists():
		return  # 文件已丢失：不做封面（图片读不到、视频排队截取也只会失败）
	match card.media.type:
		MediaObject.Type.VIDEO:
			if _thumb_cache.has(card.media_path):
				card.set_thumbnail(_thumb_cache[card.media_path])
				return
			var cover := ProjectStore.find_cover(_project_cache_dir, card.media_path)
			if not cover.is_empty():
				var img := Image.load_from_file(cover)
				if img != null:
					var tex := ImageTexture.create_from_image(img)
					_thumb_cache[card.media_path] = tex
					card.set_thumbnail(tex)
					return
			_thumbnailer.enqueue([card.media_path])
		MediaObject.Type.PPT:
			if _thumb_cache.has(card.media_path):
				card.set_thumbnail(_thumb_cache[card.media_path])
				return
			var cover := ProjectStore.find_cover(_project_cache_dir, card.media_path)
			if not cover.is_empty():
				var img := Image.load_from_file(cover)
				if img != null:
					var tex := ImageTexture.create_from_image(img)
					_thumb_cache[card.media_path] = tex
					card.set_thumbnail(tex)
		MediaObject.Type.IMAGE:
			if _thumb_cache.has(card.media_path):
				card.set_thumbnail(_thumb_cache[card.media_path])
				return
			var img := Image.load_from_file(card.media_path)
			if img == null:
				return
			# 等比缩放到 320x180 以内，避免大图占内存
			var ratio := minf(320.0 / img.get_width(), 180.0 / img.get_height())
			if ratio < 1.0:
				img.resize(int(img.get_width() * ratio), int(img.get_height() * ratio), Image.INTERPOLATE_BILINEAR)
			var tex := ImageTexture.create_from_image(img)
			_thumb_cache[card.media_path] = tex
			card.set_thumbnail(tex)


## 封面写盘：全局 user://thumbnails/ 写穿（项目 X_cache 在保存项目时同步）。
## 视频封面（Thumbnailer）与 PPT 封面（幻灯片首帧抓图）共用此通路。
func _save_cover(path: String, img: Image) -> void:
	# 等比缩放到 320x180 以内，与 Thumbnailer 输出一致
	var scale := minf(320.0 / img.get_width(), 180.0 / img.get_height())
	if scale < 1.0:
		img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ProjectStore.GLOBAL_THUMB_DIR))
	if err == OK:
		img.save_png(ProjectStore.GLOBAL_THUMB_DIR + "/" + path.md5_text() + ".png")
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[path] = tex
	for card: MediaItemCard in _media_grid.get_children():
		if card.media_path == path:
			card.set_thumbnail(tex)


func _on_thumbnail_ready(path: String, img: Image) -> void:
	_save_cover(path, img)


func _clear_media_items() -> void:
	_media_items.clear()
	for win: ItemSettingsWindow in _item_windows.values():
		win.queue_free()
	_item_windows.clear()
	for card in _media_grid.get_children():
		card.queue_free()
	_media_desc.visible = true


## 按类型把条目加载到预览端：视频/音频走 mpv，图片走静态纹理通路，网页走 CEF，
## PPT 走预转 HTML（无缓存时触发转换并显示占位，完成后自动加载）
func _load_preview(m: MediaObject) -> void:
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
	for card: MediaItemCard in _media_grid.get_children():
		if card.media_path == path:
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
	_load_output(card.media)


## 直接加载到输出端（从开头自动播放）：视频/音频走 mpv，图片走静态纹理，
## 网页走 CEF，PPT 走缓存 HTML（无缓存时后台转换，完成自动起播）
func _load_output(m: MediaObject) -> void:
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
	_apply_output_media_prefs()
	_show_cast_window()


## 输出端加载媒体后的统一收尾：条目级循环/静音偏好（静音与全局开关为或关系）、
## 画面变换、投屏画面变换；音频无画面时显示 ♪ 符号
func _apply_output_media_prefs() -> void:
	if _output_media == null:
		return
	_output.set_looping(_output_media.loop)
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
	var win := ItemSettingsWindow.new()
	win.setup(card.media)
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
	if _item_windows.has(card.media_path) and is_instance_valid(_item_windows[card.media_path]):
		_item_windows[card.media_path].queue_free()
	_item_windows.erase(card.media_path)
	card.queue_free()
	_media_desc.visible = _media_items.is_empty()
	_save_current_project()
	# 删除的若是当前输出条目，刷新高亮（延迟到卡片真正释放后）
	_update_output_highlight.call_deferred()
	_refresh_card_indices.call_deferred()


func _update_output_highlight() -> void:
	for card: MediaItemCard in _media_grid.get_children():
		card.set_highlighted(not _output.media_path.is_empty() and card.media_path == _output.media_path)


func _on_add_file_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.6)


func _on_files_selected(paths: PackedStringArray) -> void:
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


# ---------- 预览播放器 ----------

func _on_preview_play_pressed() -> void:
	if _preview.media_path.is_empty():
		var m := _first_playable()
		if m != null:
			_load_preview(m)
		return
	_preview.toggle_play()


func _on_preview_stop_pressed() -> void:
	_preview.stop()


func _refresh_preview_ui() -> void:
	_preview_play_button.text = "⏸" if _preview.playing else "▶"
	if _preview.media_path.is_empty():
		_preview_time_label.text = "00:00 / 00:00"
		_preview_label.text = "未加载预览媒体"


# ---------- 输出播放器 ----------

func _on_output_play_pressed() -> void:
	_output.toggle_play()


func _on_output_stop_pressed() -> void:
	_output.stop()


# ---------- 快速切换 / 投屏窗口 ----------

func _on_quick_switch_pressed() -> void:
	# 预览为空但媒体库有内容时，先加载第一个可播放条目再切换
	if _preview.media_path.is_empty():
		var m := _first_playable()
		if m == null:
			return
		_load_preview(m)
	var state := _preview.get_state()
	var path := str(state["media_path"])
	if path.is_empty():
		return
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
	_apply_output_media_prefs()  # 条目级循环/静音/画面变换推送到输出端
	_show_cast_window()


func _show_cast_window() -> void:
	# 首次弹出时若未设置固定位置，则居中于主窗口
	if not _cast_window.visible:
		var pos_x := int(ProjectStore.get_setting("cast_window", "pos_x", -1))
		if pos_x < 0:
			var main_win := get_window()
			_cast_window.position = main_win.position + (main_win.size - _cast_window.size) / 2
	_cast_window.show()


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
	_cast_window.visible = not _cast_window.visible
	_hide_cast_button.text = "隐藏投屏" if _cast_window.visible else "显示投屏"


func _on_cast_window_close_requested() -> void:
	_cast_window.hide()
	_hide_cast_button.text = "显示投屏"


func _on_restart_pressed() -> void:
	OS.set_restart_on_exit(true)
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


func _on_output_volume_changed(value: float) -> void:
	# 输出端音量同时是投屏窗口的音量（共享实例），持久化到 settings.cfg
	_output.set_volume(int(value))
	ProjectStore.set_setting("audio", "output_volume", int(value))
	_refresh_audio_ui()


func _refresh_audio_ui() -> void:
	_audio_output_slider.set_value_no_signal(_output.volume)
	_audio_output_value.text = str(_output.volume)
	_output_mute_button.text = "🔇" if _output.muted else "🔊"


func _on_output_mute_pressed() -> void:
	# 输出端静音同时是投屏窗口的静音（共享实例），持久化到 settings.cfg
	_output.set_muted(not _output.muted)
	ProjectStore.set_setting("audio", "output", not _output.muted)
	_refresh_audio_ui()
