class_name PlaylistCard
extends PanelContainer
## 播放列表卡片（媒体库中与普通媒体卡片同板混排）：
## 标题行（≡ 图标 + 列表名 + "列表"徽标）+ 信息区（条目数/播放时间/定时时段）
## + 与媒体条目一致的 3×2 按钮网格。播放中列表名绿色高亮、播放键变 ■ 停止。

signal play_requested(card: PlaylistCard)
signal preview_requested(card: PlaylistCard)
signal settings_requested(card: PlaylistCard)
signal delete_requested(card: PlaylistCard)
signal move_requested(card: PlaylistCard, delta: int)

# 色板与 ui/theme.tres / MediaItemCard 一致
const ACCENT := Color(0.2314, 0.5098, 0.9657)
const HIGHLIGHT_COLOR := Color(0.45, 0.85, 0.55)
const C_PANEL := Color(0.0941, 0.1098, 0.1373)
const C_ELEVATED := Color(0.1451, 0.1686, 0.2118)
const C_HOVER := Color(0.1765, 0.2078, 0.2627)
const C_PRESSED := Color(0.1176, 0.1373, 0.1765)
const C_DISABLED := Color(0.1059, 0.1216, 0.1529)
const C_TEXT := Color(0.7569, 0.7922, 0.8510)
const C_TEXT_DIM := Color(0.5569, 0.6, 0.6588)

var playlist: PlaylistObject

var _playing := false
var _name_label: Label
var _info_label: Label
var _btn_play: Button
var _order_box: HBoxContainer
var _btn_up: Button
var _btn_down: Button


func _init() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(210, 202)
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "CardSections"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# ---- 标题行：≡ + 列表名 + 列表徽标 ----
	var header := PanelContainer.new()
	header.name = "TitleSection"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.custom_minimum_size = Vector2(0, 26)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0, 0, 0, 0)
	header_style.content_margin_left = 10
	header_style.content_margin_right = 10
	header_style.content_margin_top = 5
	header_style.content_margin_bottom = 5
	header.add_theme_stylebox_override("panel", header_style)
	vbox.add_child(header)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 6)
	header.add_child(name_row)

	var icon_label := Label.new()
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.add_theme_color_override("font_color", ACCENT)
	icon_label.text = "≡"
	name_row.add_child(icon_label)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", C_TEXT)
	_name_label.clip_text = true
	name_row.add_child(_name_label)

	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", C_TEXT_DIM)
	badge.text = "列表"
	name_row.add_child(badge)

	_order_box = HBoxContainer.new()
	_order_box.name = "OrderControls"
	_order_box.visible = false
	_order_box.add_theme_constant_override("separation", 2)
	name_row.add_child(_order_box)
	_btn_up = _make_order_button("↑", -1)
	_btn_down = _make_order_button("↓", 1)

	# ---- 信息区：条目数 / 播放时间 / 定时时段 ----
	var info := PanelContainer.new()
	info.name = "PreviewSection"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color.BLACK
	info_style.content_margin_left = 8
	info_style.content_margin_top = 6
	info.add_theme_stylebox_override("panel", info_style)
	vbox.add_child(info)

	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_label)

	# ---- 按钮网格：与普通媒体卡片相同的 3×2 结构 ----
	var grid := GridContainer.new()
	grid.name = "ButtonsSection"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 3
	grid.custom_minimum_size = Vector2(0, 58)
	grid.add_theme_constant_override("h_separation", 1)
	vbox.add_child(grid)

	_btn_play = _make_button(grid, "▶", "播放", "推送输出端顺序播放整个列表", func() -> void: play_requested.emit(self))
	var mute := _make_button(grid, "🔇\uFE0E", "静音", "列表播放沿用各媒体的静音设置", Callable())
	mute.disabled = true
	var loop := _make_button(grid, "⟳", "循环", "列表循环由列表总播放时间控制", Callable())
	loop.disabled = true
	_make_button(grid, "🖥\uFE0E", "预览", "预览列表中的第一个有效媒体", func() -> void: preview_requested.emit(self))
	_make_button(grid, "⚙", "设置", "列表设置（条目/时长/定时）", func() -> void: settings_requested.emit(self))
	var del := _make_button(grid, "✕", "删除", "删除该列表", func() -> void: delete_requested.emit(self))
	del.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))


func setup(pl: PlaylistObject) -> void:
	playlist = pl
	tooltip_text = pl.name
	refresh()


## 应用卡片规格：与媒体卡片同宽同高（网格混排对齐），固定尺寸不随窗口拉伸
func apply_size(w: int) -> void:
	custom_minimum_size = Vector2(w, MediaItemCard.height_for_width(w))


func set_order_editing(on: bool, can_move_up := true, can_move_down := true) -> void:
	_order_box.visible = on
	_btn_up.disabled = not can_move_up
	_btn_down.disabled = not can_move_down


## 列表内容/状态变化后刷新显示
func refresh() -> void:
	if playlist == null:
		return
	_name_label.text = playlist.name
	var lines := ["共 %d 项" % playlist.items.size()]
	if playlist.duration > 0.0:
		lines.append("播放 %s" % _fmt(playlist.duration))
	else:
		var est := playlist.estimated_round_duration()
		lines.append("一轮 %s" % (_fmt(est) if est > 0.0 else "按媒体长度"))
	if playlist.auto_enabled:
		lines.append("定时 %s-%s" % [playlist.auto_start, playlist.auto_stop])
	_info_label.text = "\n".join(lines)
	_btn_play.text = ("■" if _playing else "▶") + " " + ("停止" if _playing else "播放")
	_name_label.add_theme_color_override("font_color",
		HIGHLIGHT_COLOR if _playing else C_TEXT)


func set_playing(on: bool) -> void:
	_playing = on
	refresh()


func _fmt(seconds: float) -> String:
	var total := int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
	return "%02d:%02d" % [total / 60, total % 60]


func _make_button(parent: Control, icon: String, text: String, tip: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = icon + " " + text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Symbol", "Apple Symbols", "Microsoft YaHei", "PingFang SC"])
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_stylebox_override("normal", _btn_style(C_ELEVATED))
	b.add_theme_stylebox_override("hover", _btn_style(C_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_style(C_PRESSED))
	b.add_theme_stylebox_override("disabled", _btn_style(C_DISABLED))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _make_order_button(text: String, delta: int) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = "上移" if delta < 0 else "下移"
	b.custom_minimum_size = Vector2(24, 20)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", _btn_style(C_ELEVATED, 2))
	b.add_theme_stylebox_override("hover", _btn_style(C_HOVER, 2))
	b.add_theme_stylebox_override("pressed", _btn_style(C_PRESSED, 2))
	b.add_theme_stylebox_override("disabled", _btn_style(C_DISABLED, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: move_requested.emit(self, delta))
	_order_box.add_child(b)
	return b


static func _btn_style(bg: Color, vertical_margin := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_top = vertical_margin
	s.content_margin_bottom = vertical_margin
	return s
