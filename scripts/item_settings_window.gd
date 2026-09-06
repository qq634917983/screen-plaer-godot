class_name ItemSettingsWindow
extends Window
## 单个媒体条目的设置窗口：点击卡片 ⚙ 时创建（每个条目一个独立窗口）。
## 两个模式页签：
## - 属性：缩放比例/水平/垂直偏移，改动即时写回 MediaObject 并应用到播放端；
## - 触点编辑（仅网页媒体）：内嵌 CEF 浏览器实时预览页面，左键点画面加触点、
##   右键删最近触点，白点+序号叠加显示；触点归一化坐标存 MediaObject.touch_points，
##   与预览/输出/投屏三端的触点层共享同一引用，编辑即时同步。
## 播放时按触点顺序步进用播放器的 ← → 键（见 PlayerSlot.step_web）。

signal properties_changed(media: MediaObject)
signal window_closed(path: String)

const TouchPointsLayerScript := preload("res://scripts/touch_points_layer.gd")
const WEB_VIEWPORT := Vector2(1280, 720)  # 与 PlayerSlot.WEB_VIEWPORT_SIZE 一致

var media: MediaObject
var cef: Node  # 全局 GdCEF 节点（main.gd 注入；无 gdcef 时触点页只显示提示）

var _path_label: Label
var _type_label: Label
var _scale_spin: SpinBox
var _offset_x_spin: SpinBox
var _offset_y_spin: SpinBox
var _web_view: TextureRect
var _dots_layer: Control
var _points_label: Label
var _browser: Node  # 触点页内嵌预览浏览器（本窗口独享，关窗即销毁）


func _init() -> void:
	title = "条目设置"
	size = Vector2i(880, 600)
	min_size = Vector2i(760, 520)
	transient = true


func _ready() -> void:
	close_requested.connect(_on_close)
	_build_ui()
	_refresh()
	_start_preview_browser()


func setup(m: MediaObject) -> void:
	media = m
	title = "条目设置 — " + m.display_name()
	if is_node_ready():
		_refresh()
		_start_preview_browser()


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

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	tabs.add_child(_build_props_tab())
	if media != null and media.type == MediaObject.Type.HTML:
		tabs.add_child(_build_touch_tab())

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


## 页签一：属性（缩放/偏移，改动即时生效）
func _build_props_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "属性"
	tab.add_theme_constant_override("separation", 10)

	_type_label = Label.new()
	tab.add_child(_type_label)

	tab.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_scale_spin = _make_spin(grid, "缩放比例 (%)", 10, 400, 5,
		func(value: float) -> void: media.scale = value / 100.0)
	_offset_x_spin = _make_spin(grid, "水平偏移 X", -8192, 8192, 1,
		func(value: float) -> void: media.offset_x = value)
	_offset_y_spin = _make_spin(grid, "垂直偏移 Y", -8192, 8192, 1,
		func(value: float) -> void: media.offset_y = value)

	var note := Label.new()
	note.text = "缩放/偏移即时作用于预览/输出/投屏画面；网页条目在「触点编辑」页签管理触点。"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	return tab


## 页签二：触点编辑（仅网页媒体）——内嵌浏览器实时预览，左键加点/右键删点
func _build_touch_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "触点编辑"
	tab.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "左键点击画面添加触点（白点），右键删除最近触点；播放时用播放器的 ← → 键按顺序模拟点击。"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(hint)

	# 预览画面：黑底面板内叠 浏览器纹理 + 触点层（PanelContainer 子节点全部铺满）
	var screen := PanelContainer.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var screen_style := StyleBoxFlat.new()
	screen_style.bg_color = Color.BLACK
	screen.add_theme_stylebox_override("panel", screen_style)
	tab.add_child(screen)

	_web_view = TextureRect.new()
	_web_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_web_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_web_view.gui_input.connect(_on_web_view_gui_input)
	screen.add_child(_web_view)

	_dots_layer = TouchPointsLayerScript.new()
	screen.add_child(_dots_layer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tab.add_child(row)

	_points_label = Label.new()
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_points_label)

	var undo_button := Button.new()
	undo_button.text = "撤销上一点"
	undo_button.pressed.connect(func() -> void:
		if not media.touch_points.is_empty():
			media.touch_points.remove_at(media.touch_points.size() - 1)
			_after_points_changed()
	)
	row.add_child(undo_button)

	var clear_button := Button.new()
	clear_button.text = "清空触点"
	clear_button.pressed.connect(func() -> void:
		media.touch_points.clear()
		_after_points_changed()
	)
	row.add_child(clear_button)
	return tab


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
		_apply_view_transform()
		properties_changed.emit(media)
	)
	parent.add_child(spin)
	return spin


# ---------- 内嵌浏览器预览 ----------

func _start_preview_browser() -> void:
	if _browser != null or _web_view == null:
		return
	if cef == null or media == null or media.type != MediaObject.Type.HTML:
		return
	var url := media.path
	if not url.contains("://") or url.begins_with("user://") or url.begins_with("res://"):
		url = "file:///" + ProjectSettings.globalize_path(media.path).replace("\\", "/")
	_browser = cef.create_browser(url, _web_view, {"frame_rate": 15})
	if _browser == null:
		push_warning("触点预览浏览器创建失败：" + cef.get_error())
		return
	_browser.set_muted(true)  # 设置窗口预览始终静音
	_browser.resize(WEB_VIEWPORT)
	_apply_view_transform()


## 画面区点击 → 触点增删。显示区坐标按 KEEP_ASPECT_CENTERED 的纹理摆放
## 矩形换算回固定视口的归一化坐标（与 PlayerSlot._web_to_browser_pos 同模型）
func _on_web_view_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var vs := _web_view.size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var s := minf(vs.x / WEB_VIEWPORT.x, vs.y / WEB_VIEWPORT.y)
	var origin := (vs - WEB_VIEWPORT * s) / 2.0
	var norm := (mb.position - origin) / s / WEB_VIEWPORT
	norm.x = clampf(norm.x, 0.0, 1.0)
	norm.y = clampf(norm.y, 0.0, 1.0)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		media.touch_points.append(norm)
	else:
		var best := -1
		var best_d := 0.04
		for i in media.touch_points.size():
			var d: float = media.touch_points[i].distance_to(norm)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			media.touch_points.remove_at(best)
	_after_points_changed()
	_web_view.accept_event()


func _after_points_changed() -> void:
	_refresh_dots()
	properties_changed.emit(media)  # 主窗口借此自动保存项目（触点层每帧自动刷新）


## 缩放/偏移即时反映到内嵌预览画面（与 PlayerSlot._apply_view_transform 同模型）
func _apply_view_transform() -> void:
	if _web_view == null or media == null:
		return
	_web_view.pivot_offset = _web_view.size / 2.0
	_web_view.scale = Vector2.ONE * maxf(media.scale, 0.01)
	_web_view.position = media.offset()


# ---------- 数据交互 ----------

func _refresh() -> void:
	if media == null:
		return
	_path_label.text = media.path
	_type_label.text = "类型：%s" % MediaObject.type_label(media.type)
	_scale_spin.set_value_no_signal(media.scale * 100.0)
	_offset_x_spin.set_value_no_signal(media.offset_x)
	_offset_y_spin.set_value_no_signal(media.offset_y)
	_apply_view_transform()
	_refresh_dots()


func _refresh_dots() -> void:
	if _dots_layer == null:
		return
	_dots_layer.set_points(media.touch_points, -1)
	_points_label.text = "触点：%d 个" % media.touch_points.size()


func _on_reset_pressed() -> void:
	media.scale = 1.0
	media.offset_x = 0.0
	media.offset_y = 0.0
	_refresh()
	properties_changed.emit(media)


func _on_close() -> void:
	if _browser != null and is_instance_valid(_browser):
		_browser.close()
		_browser.queue_free()
	_browser = null
	window_closed.emit(media.path)
	queue_free()
