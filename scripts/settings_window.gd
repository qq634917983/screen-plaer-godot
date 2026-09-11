class_name SettingsWindow
extends Window
## 设置窗口：基础设置 + 投屏窗口设置 + 主界面四分区尺寸约束 + 集中帮助。
## 控件修改先留在窗口中；“应用”保存并生效，“确定”保存、生效并关闭。

signal settings_changed

const HOTKEY_ACTIONS := [
	["quick_switch", "快速切换"],
	["switch_item_1", "切换条目 1"],
	["switch_item_2", "切换条目 2"],
	["switch_item_3", "切换条目 3"],
]

var _hotkey_buttons := {}  # action -> Button
var _capturing_action := ""
var _zoom_spin: SpinBox
var _pan_x_spin: SpinBox
var _pan_y_spin: SpinBox
var _pos_x_spin: SpinBox
var _pos_y_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _audio_output_check: CheckBox
var _cover_spin: SpinBox
var _copy_media_check: CheckBox
var _min_x_percent_spin: SpinBox
var _max_x_percent_spin: SpinBox
var _min_y_percent_spin: SpinBox
var _max_y_percent_spin: SpinBox
var _pending_hotkeys := {}
var _apply_button: Button
var _ok_button: Button


func _ready() -> void:
	close_requested.connect(hide)
	_build_ui()


func _input(event: InputEvent) -> void:
	if _capturing_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_ESCAPE:
			_pending_hotkeys[_capturing_action] = event.keycode
		_capturing_action = ""
		_refresh_hotkey_buttons()
		get_viewport().set_input_as_handled()


# ---------- 界面构建 ----------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var tabs := TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_basic_tab())
	tabs.add_child(_build_window_tab())
	tabs.add_child(_build_layout_tab())
	tabs.add_child(_build_help_tab())

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	_apply_button = Button.new()
	_apply_button.name = "ApplyButton"
	_apply_button.text = "应用"
	_apply_button.custom_minimum_size.x = 88
	_apply_button.pressed.connect(_apply_changes)
	actions.add_child(_apply_button)
	_ok_button = Button.new()
	_ok_button.name = "OkButton"
	_ok_button.text = "确定"
	_ok_button.custom_minimum_size.x = 88
	_ok_button.pressed.connect(_confirm_changes)
	actions.add_child(_ok_button)


func _build_basic_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "基础设置"
	tab.add_theme_constant_override("separation", 8)

	tab.add_child(_make_header("声音输出"))
	_audio_output_check = _make_audio_check("输出/投屏声音", "output", true)
	tab.add_child(_audio_output_check)
	var audio_note := Label.new()
	audio_note.text = "注：预览播放器始终静音（仅作预览用）；输出播放器与投屏窗口共享同一解码实例，声音只有一路。音量在主窗口右侧「音频控制」面板调节；输出端静音由此处勾选框控制。"
	audio_note.add_theme_font_size_override("font_size", 11)
	audio_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	audio_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(audio_note)

	tab.add_child(HSeparator.new())
	tab.add_child(_make_header("封面"))
	var cover_row := HBoxContainer.new()
	var cover_label := Label.new()
	cover_label.text = "封面截取位置（秒）"
	cover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cover_row.add_child(cover_label)
	_cover_spin = SpinBox.new()
	_cover_spin.min_value = 0.0
	_cover_spin.max_value = 120.0
	_cover_spin.step = 0.5
	cover_row.add_child(_cover_spin)
	tab.add_child(cover_row)
	var cover_note := Label.new()
	cover_note.text = "添加到媒体库时自动在视频的该时间点截图作为封面；已生成的封面不会重截。"
	cover_note.add_theme_font_size_override("font_size", 11)
	cover_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	cover_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(cover_note)

	tab.add_child(HSeparator.new())
	tab.add_child(_make_header("媒体库"))
	_copy_media_check = CheckBox.new()
	_copy_media_check.text = "添加文件时复制到项目目录"
	tab.add_child(_copy_media_check)
	var copy_note := Label.new()
	copy_note.text = "开启后，添加的媒体文件会被真实复制到项目缓存目录（X_cache/media/），条目引用副本——源文件之后被移动或删除也不影响播放。仅对已保存的项目生效；复制在添加时进行，大文件会花费数秒。"
	copy_note.add_theme_font_size_override("font_size", 11)
	copy_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	copy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(copy_note)

	tab.add_child(HSeparator.new())
	tab.add_child(_make_header("快捷键"))
	for entry in HOTKEY_ACTIONS:
		tab.add_child(_make_hotkey_row(entry[0], entry[1]))
	var key_note := Label.new()
	key_note.text = "点击右侧按钮后按下新按键（Esc 取消）。「切换条目 N」= 直接把媒体库第 N 个视频推送到输出端。"
	key_note.add_theme_font_size_override("font_size", 11)
	key_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	key_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(key_note)
	return tab


func _build_window_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "窗口设置"
	tab.add_theme_constant_override("separation", 8)

	tab.add_child(_make_header("投屏窗口"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_width_spin = _make_spin(grid, "宽度", 160, 7680, 10, 960)
	_height_spin = _make_spin(grid, "高度", 90, 4320, 10, 540)
	_pos_x_spin = _make_spin(grid, "位置 X", -4096, 16384, 1, -1)
	_pos_y_spin = _make_spin(grid, "位置 Y", -4096, 16384, 1, -1)
	_zoom_spin = _make_spin(grid, "缩放 (%)", 10, 400, 5, 100)
	_pan_x_spin = _make_spin(grid, "平移 X", -4096, 4096, 1, 0)
	_pan_y_spin = _make_spin(grid, "平移 Y", -4096, 4096, 1, 0)

	var note := Label.new()
	note.text = "位置 X/Y 为 -1 时表示自动居中于主窗口；缩放/平移作用于窗口内的画面。"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	return tab


func _build_layout_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "界面布局"
	tab.add_theme_constant_override("separation", 8)
	tab.add_child(_make_header("四分区拖拽范围"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)
	for text in ["分区", "最小值", "最大值"]:
		var heading := Label.new()
		heading.text = text
		heading.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
		grid.add_child(heading)

	var first_column := _make_layout_bound_row(grid, "第一列宽度", 35, 85)
	_min_x_percent_spin = first_column[0]
	_max_x_percent_spin = first_column[1]
	var first_row := _make_layout_bound_row(grid, "第一排高度", 35, 75)
	_min_y_percent_spin = first_row[0]
	_max_y_percent_spin = first_row[1]

	var note := Label.new()
	note.text = "数值均为当前四分区可用宽高的百分比，第二列和第二排自动占用剩余空间。控件自身所需尺寸始终优先，避免播放器和按钮被压住。"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	return tab


func _build_help_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "帮助"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content := VBoxContainer.new()
	content.name = "HelpContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	_add_help_section(content, "播放器",
		"单击媒体卡片会加载到预览播放器，不影响正在输出的内容。卡片“播放”会从头直接送到输出和投屏；“快速切换”会把预览端当前媒体、进度和播放状态推送到输出端。")
	_add_help_section(content, "媒体库",
		"点击“添加文件”或从文件管理器拖入视频、音频、图片、网页和 PPT。“编辑顺序”可调整媒体与播放列表的位置，“尺寸”可切换卡片大小。")
	_add_help_section(content, "音频控制",
		"主音量作用于所有输出；每个视频和音频 item 有独立纵向音量条与静音按钮。最终音量为主音量乘以 item 音量。预览端始终静音，输出播放器与投屏窗口共享一路声音。")
	_add_help_section(content, "实用功能",
		"“隐藏投屏”切换独立投屏窗口的显示状态；“重启软件”会先清理播放器和浏览器资源，再重新启动程序。")
	_add_help_section(content, "投屏窗口",
		"输出播放器与投屏窗口共享同一解码实例和画面纹理，因此画面与声音保持一致。投屏窗口的大小、位置、缩放和平移可在“窗口设置”页调整。")
	return scroll


func _add_help_section(parent: VBoxContainer, title_text: String, body_text: String) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
	section.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(body)


func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_audio_check(text: String, key: String, default: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = ProjectStore.get_setting("audio", key, default)
	return check


func _make_hotkey_row(action: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size.x = 120
	button.pressed.connect(func() -> void:
		_capturing_action = action
		_refresh_hotkey_buttons()
	)
	_hotkey_buttons[action] = button
	row.add_child(button)
	return row


func _make_spin(parent: Control, label_text: String, minv: float, maxv: float, step: float, default: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.step = step
	spin.value = default
	parent.add_child(spin)
	return spin


func _make_layout_bound_row(parent: GridContainer, label_text: String, default_min: int, default_max: int) -> Array[SpinBox]:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var min_spin := SpinBox.new()
	min_spin.min_value = 5
	min_spin.max_value = 95
	min_spin.step = 1
	min_spin.value = default_min
	min_spin.suffix = " %"
	min_spin.custom_minimum_size.x = 105
	parent.add_child(min_spin)
	var max_spin := SpinBox.new()
	max_spin.min_value = 5
	max_spin.max_value = 95
	max_spin.step = 1
	max_spin.value = default_max
	max_spin.suffix = " %"
	max_spin.custom_minimum_size.x = 105
	parent.add_child(max_spin)
	return [min_spin, max_spin]


func _save_window_settings() -> void:
	ProjectStore.set_setting("cast_window", "width", int(_width_spin.value))
	ProjectStore.set_setting("cast_window", "height", int(_height_spin.value))
	ProjectStore.set_setting("cast_window", "pos_x", int(_pos_x_spin.value))
	ProjectStore.set_setting("cast_window", "pos_y", int(_pos_y_spin.value))
	ProjectStore.set_setting("cast_window", "zoom", int(_zoom_spin.value))
	ProjectStore.set_setting("cast_window", "pan_x", int(_pan_x_spin.value))
	ProjectStore.set_setting("cast_window", "pan_y", int(_pan_y_spin.value))


func _save_layout_settings() -> void:
	_normalize_layout_max(_max_x_percent_spin, _min_x_percent_spin)
	_normalize_layout_max(_max_y_percent_spin, _min_y_percent_spin)
	ProjectStore.set_settings("ui", {
		"min_x_percent": int(_min_x_percent_spin.value),
		"max_x_percent": int(_max_x_percent_spin.value),
		"min_y_percent": int(_min_y_percent_spin.value),
		"max_y_percent": int(_max_y_percent_spin.value),
	})


func _normalize_layout_max(max_spin: SpinBox, min_spin: SpinBox) -> void:
	if max_spin.value > 0 and max_spin.value < min_spin.value:
		max_spin.set_value_no_signal(min_spin.value)


func _apply_changes() -> void:
	ProjectStore.set_setting("audio", "output", _audio_output_check.button_pressed)
	ProjectStore.set_setting("thumbs", "position", _cover_spin.value)
	ProjectStore.set_setting("media", "copy_to_project", _copy_media_check.button_pressed)
	for entry in HOTKEY_ACTIONS:
		var action: String = entry[0]
		ProjectStore.set_setting("hotkeys", action,
			int(_pending_hotkeys.get(action, _default_hotkey(action))))
	_save_window_settings()
	_save_layout_settings()
	settings_changed.emit()


func _confirm_changes() -> void:
	_apply_changes()
	hide()


# ---------- 与主窗口交互 ----------

func open() -> void:
	_load_basic_settings()
	_load_window_settings()
	_load_layout_settings()
	_refresh_hotkey_buttons()
	show()
	grab_focus()


func _refresh_hotkey_buttons() -> void:
	for entry in HOTKEY_ACTIONS:
		var action: String = entry[0]
		var button: Button = _hotkey_buttons[action]
		if action == _capturing_action:
			button.text = "按下新按键…"
		else:
			var keycode := int(_pending_hotkeys.get(action, _default_hotkey(action)))
			button.text = OS.get_keycode_string(keycode)


func _load_basic_settings() -> void:
	_audio_output_check.set_pressed_no_signal(bool(ProjectStore.get_setting("audio", "output", true)))
	_cover_spin.set_value_no_signal(float(ProjectStore.get_setting("thumbs", "position", 1.0)))
	_copy_media_check.set_pressed_no_signal(bool(ProjectStore.get_setting("media", "copy_to_project", false)))
	_pending_hotkeys.clear()
	for entry in HOTKEY_ACTIONS:
		var action: String = entry[0]
		_pending_hotkeys[action] = int(ProjectStore.get_setting("hotkeys", action, _default_hotkey(action)))


func _load_window_settings() -> void:
	_set_spin_no_signal(_width_spin, ProjectStore.get_setting("cast_window", "width", 960))
	_set_spin_no_signal(_height_spin, ProjectStore.get_setting("cast_window", "height", 540))
	_set_spin_no_signal(_pos_x_spin, ProjectStore.get_setting("cast_window", "pos_x", -1))
	_set_spin_no_signal(_pos_y_spin, ProjectStore.get_setting("cast_window", "pos_y", -1))
	_set_spin_no_signal(_zoom_spin, ProjectStore.get_setting("cast_window", "zoom", 100))
	_set_spin_no_signal(_pan_x_spin, ProjectStore.get_setting("cast_window", "pan_x", 0))
	_set_spin_no_signal(_pan_y_spin, ProjectStore.get_setting("cast_window", "pan_y", 0))


func _load_layout_settings() -> void:
	_set_spin_no_signal(_min_x_percent_spin, ProjectStore.get_setting("ui", "min_x_percent", 35))
	_set_spin_no_signal(_max_x_percent_spin, ProjectStore.get_setting("ui", "max_x_percent", 85))
	_set_spin_no_signal(_min_y_percent_spin, ProjectStore.get_setting("ui", "min_y_percent", 35))
	_set_spin_no_signal(_max_y_percent_spin, ProjectStore.get_setting("ui", "max_y_percent", 75))


func _set_spin_no_signal(spin: SpinBox, value: Variant) -> void:
	spin.set_value_no_signal(float(value))


static func _default_hotkey(action: String) -> int:
	match action:
		"quick_switch":
			return KEY_Q
		"switch_item_1":
			return KEY_1
		"switch_item_2":
			return KEY_2
		"switch_item_3":
			return KEY_3
	return 0


static func get_hotkey(action: String) -> int:
	return int(ProjectStore.get_setting("hotkeys", action, _default_hotkey(action)))
