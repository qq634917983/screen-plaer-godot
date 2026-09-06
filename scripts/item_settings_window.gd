class_name ItemSettingsWindow
extends Window
## 单个媒体条目的设置窗口：点击卡片 ⚙ 时创建（每个条目一个独立窗口）。
## 编辑媒体对象的基础属性（缩放比例、水平/垂直偏移），改动立即写回
## MediaObject 并发出 properties_changed，由主窗口应用到播放端并自动保存项目。

signal properties_changed(media: MediaObject)
signal window_closed(path: String)

var media: MediaObject

var _path_label: Label
var _type_label: Label
var _scale_spin: SpinBox
var _offset_x_spin: SpinBox
var _offset_y_spin: SpinBox


func _init() -> void:
	title = "条目设置"
	size = Vector2i(420, 300)
	transient = true


func _ready() -> void:
	close_requested.connect(_on_close)
	_build_ui()
	_refresh()


func setup(m: MediaObject) -> void:
	media = m
	title = "条目设置 — " + m.display_name()
	if is_node_ready():
		_refresh()


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

	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", 11)
	_path_label.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	_path_label.clip_text = true
	root.add_child(_path_label)

	_type_label = Label.new()
	root.add_child(_type_label)

	root.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	_scale_spin = _make_spin(grid, "缩放比例 (%)", 10, 400, 5,
		func(value: float) -> void: media.scale = value / 100.0)
	_offset_x_spin = _make_spin(grid, "水平偏移 X", -8192, 8192, 1,
		func(value: float) -> void: media.offset_x = value)
	_offset_y_spin = _make_spin(grid, "垂直偏移 Y", -8192, 8192, 1,
		func(value: float) -> void: media.offset_y = value)

	var note := Label.new()
	note.text = "缩放/偏移作用于预览与输出画面；图片/网页/PPT 的播放暂未实现，当前仅入库管理。"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)

	var reset_button := Button.new()
	reset_button.text = "重置"
	reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_button)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_on_close)
	buttons.add_child(close_button)


func _make_spin(parent: Control, label_text: String, minv: float, maxv: float,
		step: float, on_changed: Callable) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.step = step
	spin.value_changed.connect(func(value: float) -> void:
		on_changed.call(value)
		properties_changed.emit(media)
	)
	parent.add_child(spin)
	return spin


# ---------- 数据交互 ----------

func _refresh() -> void:
	if media == null:
		return
	_path_label.text = media.path
	_type_label.text = "类型：%s" % MediaObject.type_label(media.type)
	_scale_spin.set_value_no_signal(media.scale * 100.0)
	_offset_x_spin.set_value_no_signal(media.offset_x)
	_offset_y_spin.set_value_no_signal(media.offset_y)


func _on_reset_pressed() -> void:
	media.scale = 1.0
	media.offset_x = 0.0
	media.offset_y = 0.0
	_refresh()
	properties_changed.emit(media)


func _on_close() -> void:
	window_closed.emit(media.path)
	queue_free()
