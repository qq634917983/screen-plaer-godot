class_name ItemSettingsWindow
extends Window
## 单个媒体条目的设置窗口：点击卡片 ⚙ 时创建（每个条目一个独立窗口）。
## 水平三分区布局（无页签）：
## 1) 左侧：属性分区名列表（属性 / 触点（仅网页媒体））
## 2) 中间：选中分区对应的属性列表
## 3) 右侧：实时预览画面（仅网页媒体）——内嵌 CEF 浏览器一直显示，
##    相当于本窗口独享的独立播放器，不与预览/输出端同步，关窗即销毁。
## 选中「触点」分区时：左键点右侧画面加触点、右键删最近触点，白点+序号
## 叠加显示；触点归一化坐标存 MediaObject.touch_points，与预览/输出两端的
## 触点层共享同一引用，编辑即时同步（投屏窗口不显示触点标记，只执行点击）。
## 播放时按触点顺序步进用播放器的 ← → 键（见 PlayerSlot.step_web）。

signal properties_changed(media: MediaObject)
signal window_closed(path: String)

const TouchPointsLayerScript := preload("res://scripts/touch_points_layer.gd")
const WEB_VIEWPORT := Vector2(1280, 720)  # 与 PlayerSlot.WEB_VIEWPORT_SIZE 一致

# 色板与 ui/theme.tres / MediaItemCard 一致
const C_PANEL := Color(0.0941, 0.1098, 0.1373)    # 面板底（卡片/媒体库同形）
const C_INSET := Color(0.0588, 0.0706, 0.0902)    # 内嵌深色区（ItemList 面板同色）
const C_BORDER := Color(0.1529, 0.1765, 0.2196)   # 描边

var media: MediaObject
var cef: Node  # 全局 GdCEF 节点（main.gd 注入；无 gdcef 时预览区只显示提示）

var _path_label: Label
var _type_label: Label
var _scale_spin: SpinBox
var _offset_x_spin: SpinBox
var _offset_y_spin: SpinBox
var _section_list: ItemList
var _props_page: Control
var _touch_page: Control
var _web_view: TextureRect
var _dots_layer: Control
var _points_label: Label
var _browser: Node  # 右侧预览浏览器（本窗口独享，关窗即销毁）


func _init() -> void:
	title = "条目设置"
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


func _has_web_preview() -> bool:
	return media != null and media.type == MediaObject.Type.HTML


# ---------- 界面构建 ----------

func _build_ui() -> void:
	var web := _has_web_preview()
	size = Vector2i(1120, 640) if web else Vector2i(620, 520)
	min_size = Vector2i(980, 560) if web else Vector2i(560, 460)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	# 窗口底色统一为面板底（原生窗口默认是灰色，先铺一层面板底）
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = C_PANEL
	bg_style.set_content_margin_all(0)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.add_child(margin)
	add_child(bg)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", 11)
	_path_label.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	_path_label.clip_text = true
	root.add_child(_path_label)

	# 三分区：分区名 | 属性列表 | 实时画面
	var panes := HBoxContainer.new()
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_theme_constant_override("separation", 10)
	root.add_child(panes)

	# 1) 分区名列表
	_section_list = ItemList.new()
	_section_list.custom_minimum_size = Vector2(92, 0)
	_section_list.fixed_icon_size = Vector2i.ZERO
	_section_list.add_item("属性")
	if web:
		_section_list.add_item("触点")
	_section_list.select(0)
	_section_list.item_selected.connect(_on_section_selected)
	panes.add_child(_section_list)

	# 2) 属性列表（按选中分区切换）——内嵌深色面板，与 ItemList 面板同形
	var content_panel := PanelContainer.new()
	content_panel.custom_minimum_size = Vector2(320, 0)
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", _panel_style(C_INSET, 10))
	panes.add_child(content_panel)

	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	content_panel.add_child(content)

	_props_page = _build_props_page()
	content.add_child(_props_page)
	if web:
		_touch_page = _build_touch_page()
		_touch_page.visible = false
		content.add_child(_touch_page)

	# 3) 实时预览画面（仅网页媒体）
	if web:
		panes.add_child(_build_preview_pane())

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


## 分区一：属性（缩放/偏移，改动即时生效）
func _build_props_page() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)

	_type_label = Label.new()
	page.add_child(_type_label)

	page.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)

	_scale_spin = _make_spin(grid, "缩放比例 (%)", 10, 400, 5,
		func(value: float) -> void: media.scale = value / 100.0)
	_offset_x_spin = _make_spin(grid, "水平偏移 X", -8192, 8192, 1,
		func(value: float) -> void: media.offset_x = value)
	_offset_y_spin = _make_spin(grid, "垂直偏移 Y", -8192, 8192, 1,
		func(value: float) -> void: media.offset_y = value)

	var note := Label.new()
	note.text = "缩放/偏移即时作用于预览/输出/投屏画面%s。" % ("；触点管理见「触点」分区" if _has_web_preview() else "")
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
	return page


## 分区二：触点编辑（仅网页媒体）——操作说明与触点管理，画面在右侧预览区
func _build_touch_page() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)

	var hint := Label.new()
	hint.text = "左键点击右侧画面添加触点（白点），右键删除最近触点；播放时用播放器的 ← → 键按顺序模拟点击。"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.56, 0.6, 0.66))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)

	page.add_child(HSeparator.new())

	_points_label = Label.new()
	page.add_child(_points_label)

	var undo_button := Button.new()
	undo_button.text = "撤销上一点"
	undo_button.pressed.connect(func() -> void:
		if not media.touch_points.is_empty():
			media.touch_points.remove_at(media.touch_points.size() - 1)
			_after_points_changed()
	)
	page.add_child(undo_button)

	var clear_button := Button.new()
	clear_button.text = "清空触点"
	clear_button.pressed.connect(func() -> void:
		media.touch_points.clear()
		_after_points_changed()
	)
	page.add_child(clear_button)
	return page


## 分区三：实时预览画面——浏览器纹理 + 触点层，一直显示、关窗即销毁
## （黑底 + 1px 描边 + 圆角，与卡片画面区/播放器屏幕块同形）
func _build_preview_pane() -> Control:
	var screen := PanelContainer.new()
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var screen_style := StyleBoxFlat.new()
	screen_style.bg_color = Color.BLACK
	screen_style.border_color = C_BORDER
	screen_style.set_border_width_all(1)
	screen_style.set_corner_radius_all(4)
	screen_style.set_content_margin_all(2)
	screen.add_theme_stylebox_override("panel", screen_style)

	_web_view = TextureRect.new()
	_web_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_web_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_web_view.gui_input.connect(_on_web_view_gui_input)
	screen.add_child(_web_view)

	_dots_layer = TouchPointsLayerScript.new()
	screen.add_child(_dots_layer)
	return screen


## 面板样式：bg 底 + 1px 描边 + 4px 圆角（与 ui/theme.tres 面板/内嵌面板同形）
static func _panel_style(bg: Color, margin_all: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(margin_all)
	return s


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


func _on_section_selected(index: int) -> void:
	_props_page.visible = index == 0
	if _touch_page != null:
		_touch_page.visible = index == 1
	_refresh_dots()


func _is_touch_section() -> bool:
	return _touch_page != null and _touch_page.visible


# ---------- 内嵌浏览器预览 ----------

func _start_preview_browser() -> void:
	if _browser != null or _web_view == null:
		return
	if cef == null or not _has_web_preview():
		return
	var url := PlatformPaths.browser_url(media.path)
	_browser = cef.create_browser(url, _web_view, {"frame_rate": 15})
	if _browser == null:
		push_warning("条目预览浏览器创建失败：" + cef.get_error())
		return
	_browser.set_muted(true)  # 设置窗口预览始终静音
	_browser.resize(WEB_VIEWPORT)
	_apply_view_transform()


## 预览画面点击 → 触点增删（仅在「触点」分区下编辑，其余时间画面只是纯预览）。
## 显示区坐标按 KEEP_ASPECT_CENTERED 的纹理摆放矩形换算回固定视口的归一化
## 坐标（与 PlayerSlot._web_to_browser_pos 同模型）
func _on_web_view_gui_input(event: InputEvent) -> void:
	if not _is_touch_section():
		return
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
	if _points_label != null:
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
