class_name PlaylistSettingsWindow
extends Window
## 播放列表设置窗口（每个列表一个独立窗口）：编辑列表名、列表播放时间、
## 定时自动播放（开启/关闭时间），以及条目管理——从媒体库添加、调序、
## 删除、逐项设置播放时长（秒，0 = 视频/音频播完、图片/网页/PPT 默认
## 10 秒）。所有改动即时写回 PlaylistObject 并发 changed 信号（主窗口
## 借此保存项目 + 刷新卡片）。

signal changed(playlist: PlaylistObject)
signal window_closed(playlist: PlaylistObject)

var playlist: PlaylistObject

var _library: Array = []  # Array[MediaObject]
var _name_edit: LineEdit
var _duration_spin: SpinBox
var _auto_check: CheckBox
var _start_edit: LineEdit
var _stop_edit: LineEdit
var _add_option: OptionButton
var _items_box: VBoxContainer


func _init() -> void:
	title = "播放列表设置"
	size = Vector2i(560, 600)
	min_size = Vector2i(480, 480)
	transient = true


func _ready() -> void:
	close_requested.connect(_on_close)
	_build_ui()
	_refresh()


func setup(pl: PlaylistObject, library: Array) -> void:
	playlist = pl
	_library = library
	title = "播放列表设置 — " + pl.name
	if is_node_ready():
		_refresh()


func set_library(library: Array) -> void:
	_library = library
	if is_node_ready():
		_refresh_library_options()


# ---------- 界面构建 ----------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	# 窗口底色统一为面板底（原生窗口默认是灰色，与条目设置窗口同板）
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0941, 0.1098, 0.1373)
	bg_style.set_content_margin_all(0)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.add_child(margin)
	add_child(bg)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	var name_label := Label.new()
	name_label.text = "列表名称"
	grid.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(text: String) -> void:
		playlist.name = text.strip_edges() if not text.strip_edges().is_empty() else "播放列表"
		_emit_changed()
	)
	grid.add_child(_name_edit)

	var dur_label := Label.new()
	dur_label.text = "列表播放时间（秒）"
	grid.add_child(dur_label)
	_duration_spin = SpinBox.new()
	_duration_spin.min_value = 0
	_duration_spin.max_value = 86400
	_duration_spin.step = 10
	_duration_spin.value_changed.connect(func(value: float) -> void:
		playlist.duration = value
		_emit_changed()
	)
	grid.add_child(_duration_spin)

	var dur_note := Label.new()
	dur_note.text = "0 = 播完一轮即停；>0 = 循环整个列表直到播满该时长"
	dur_note.add_theme_font_size_override("font_size", 11)
	dur_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	root.add_child(dur_note)

	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	root.add_child(auto_row)

	_auto_check = CheckBox.new()
	_auto_check.text = "定时自动播放"
	_auto_check.toggled.connect(func(on: bool) -> void:
		playlist.auto_enabled = on
		_emit_changed()
	)
	auto_row.add_child(_auto_check)

	var start_label := Label.new()
	start_label.text = "开启"
	auto_row.add_child(start_label)
	_start_edit = _make_time_edit(auto_row, "08:00", func(text: String) -> void: playlist.auto_start = text)
	var stop_label := Label.new()
	stop_label.text = "关闭"
	auto_row.add_child(stop_label)
	_stop_edit = _make_time_edit(auto_row, "20:00", func(text: String) -> void: playlist.auto_stop = text)

	var auto_note := Label.new()
	auto_note.text = "时间格式 HH:MM，到点自动起播/停止；支持跨午夜（如 22:00 - 06:00），开启=关闭 视为全天"
	auto_note.add_theme_font_size_override("font_size", 11)
	auto_note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(auto_note)

	root.add_child(HSeparator.new())

	# ---- 条目管理 ----
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	root.add_child(add_row)

	_add_option = OptionButton.new()
	_add_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_option.clip_text = true
	add_row.add_child(_add_option)

	var add_button := Button.new()
	add_button.text = "添加"
	add_button.pressed.connect(_on_add_item_pressed)
	add_row.add_child(add_button)

	# 条目列表：内嵌深色面板（与 ItemList 面板/条目设置窗口内嵌区同色）
	var items_panel := PanelContainer.new()
	items_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var items_style := StyleBoxFlat.new()
	items_style.bg_color = Color(0.0588, 0.0706, 0.0902)
	items_style.border_color = Color(0.1529, 0.1765, 0.2196)
	items_style.set_border_width_all(1)
	items_style.set_corner_radius_all(4)
	items_style.set_content_margin_all(8)
	items_panel.add_theme_stylebox_override("panel", items_style)
	root.add_child(items_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	items_panel.add_child(scroll)

	_items_box = VBoxContainer.new()
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_items_box)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_on_close)
	buttons.add_child(close_button)


func _make_time_edit(parent: Control, placeholder: String, apply: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(64, 0)
	edit.placeholder_text = placeholder
	edit.max_length = 5
	var commit := func() -> void:
		if PlaylistObject.parse_hhmm(edit.text) >= 0:
			apply.call(edit.text.strip_edges())
			edit.remove_theme_color_override("font_color")
			_emit_changed()
		else:
			edit.add_theme_color_override("font_color", Color(0.9, 0.45, 0.45))
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	edit.focus_exited.connect(func() -> void: commit.call())
	parent.add_child(edit)
	return edit


# ---------- 数据交互 ----------

func _refresh() -> void:
	if playlist == null:
		return
	_name_edit.text = playlist.name
	_duration_spin.set_value_no_signal(playlist.duration)
	_auto_check.set_pressed_no_signal(playlist.auto_enabled)
	_start_edit.text = playlist.auto_start
	_stop_edit.text = playlist.auto_stop
	_refresh_library_options()
	_refresh_items()


func _refresh_library_options() -> void:
	_add_option.clear()
	for m: MediaObject in _library:
		_add_option.add_item("%s · %s" % [MediaObject.type_label(m.type), m.display_name()])
		_add_option.set_item_metadata(_add_option.item_count - 1, m.path)


func _refresh_items() -> void:
	for child in _items_box.get_children():
		child.queue_free()
	for i in playlist.items.size():
		_items_box.add_child(_make_item_row(i))


func _make_item_row(index: int) -> Control:
	var item := playlist.items[index]
	var path := str(item["path"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var num := Label.new()
	num.add_theme_font_size_override("font_size", 11)
	num.add_theme_color_override("font_color", Color(0.2314, 0.5098, 0.9657))
	num.text = str(index + 1)
	row.add_child(num)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.clip_text = true
	name_label.tooltip_text = path
	name_label.text = _item_display_name(path)
	row.add_child(name_label)

	var dur := SpinBox.new()
	dur.min_value = 0
	dur.max_value = 86400
	dur.step = 1
	dur.suffix = "秒"
	dur.custom_minimum_size = Vector2(96, 0)
	dur.set_value_no_signal(float(item["duration"]))
	dur.value_changed.connect(func(value: float) -> void:
		playlist.items[index]["duration"] = value
		_emit_changed()
	)
	row.add_child(dur)

	var up := _make_row_button(row, "↑", index > 0)
	up.pressed.connect(func() -> void:
		playlist.move_item(index, -1)
		_refresh_items()
		_emit_changed()
	)
	var down := _make_row_button(row, "↓", index < playlist.items.size() - 1)
	down.pressed.connect(func() -> void:
		playlist.move_item(index, 1)
		_refresh_items()
		_emit_changed()
	)
	var del := _make_row_button(row, "✕", true)
	del.pressed.connect(func() -> void:
		playlist.remove_item(index)
		_refresh_items()
		_emit_changed()
	)
	return row


func _make_row_button(parent: Control, text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(26, 0)
	parent.add_child(b)
	return b


func _item_display_name(path: String) -> String:
	for m: MediaObject in _library:
		if m.path == path:
			return m.display_name()
	return path.get_file() + "（已不在媒体库）"


func _on_add_item_pressed() -> void:
	var idx := _add_option.selected
	if idx < 0:
		return
	var path = _add_option.get_item_metadata(idx)
	if path == null:
		return
	playlist.add_item(str(path))
	_refresh_items()
	# 滚动到底让新行可见
	await get_tree().process_frame
	var scroll := _items_box.get_parent() as ScrollContainer
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	_emit_changed()


func _emit_changed() -> void:
	changed.emit(playlist)


func _on_close() -> void:
	window_closed.emit(playlist)
	queue_free()
