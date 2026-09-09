class_name MediaItemCard
extends PanelContainer
## 媒体库条目卡片（布局参照 doc/item.html，配色与全局主题 ui/theme.tres 一致）：
## 标题栏（蓝色序号 + 文件名 + 类型徽标）+ 16:9 黑色画面区（缩略图/占位字形）
## + 无缝 3×2 按钮网格（播放 / 静音 / 循环 / 预览 / 设置 / 删除）。
## 点击标题栏/画面区任意处 = 加载到预览；「播放」= 推送到输出端；
## 静音/循环是条目级偏好（随项目持久化，推送到输出端时生效，
## 正在输出该条目时立即生效）。
## 视频封面由 Thumbnailer 后台抓帧生成；图片直接读文件缩略；
## 音频/网页/PPT 等无封面类型显示类型占位字形。

signal preview_requested(card: MediaItemCard)
signal push_requested(card: MediaItemCard)
signal settings_requested(card: MediaItemCard)
signal delete_requested(card: MediaItemCard)
signal loop_toggled(card: MediaItemCard)
signal mute_toggled(card: MediaItemCard)

const HIGHLIGHT_COLOR := Color(0.45, 0.85, 0.55)  # 当前输出条目（绿色）
## 卡片三档固定宽度（小/中/大），不随窗口拉伸；高度按 16:9 画面区推导
const CARD_WIDTHS: Array[int] = [160, 210, 280]
const CARD_SIZE_LABELS: Array[String] = ["小", "中", "大"]
# 色板与 ui/theme.tres 一致
const ACCENT := Color(0.2314, 0.5098, 0.9657)     # 主题蓝：序号 / 开关高亮
const C_PANEL := Color(0.0941, 0.1098, 0.1373)    # 卡片底
const C_ELEVATED := Color(0.1451, 0.1686, 0.2118) # 标题栏 / 按钮底
const C_HOVER := Color(0.1765, 0.2078, 0.2627)    # 按钮悬停
const C_PRESSED := Color(0.1176, 0.1373, 0.1765)  # 按钮按下
const C_DISABLED := Color(0.1059, 0.1216, 0.1529) # 按钮禁用
const C_BORDER := Color(0.1529, 0.1765, 0.2196)   # 描边
const C_BTN_LINE := Color(0.5, 0.56, 0.65)        # 按钮间亮线分隔
const C_TEXT := Color(0.7569, 0.7922, 0.8510)     # 主文字
const C_TEXT_DIM := Color(0.5569, 0.6, 0.6588)    # 次文字

var media: MediaObject
var media_path := ""

var _index_label: Label
var _name_label: Label
var _type_label: Label
var _display: PanelContainer
var _thumb: TextureRect
var _glyph: Label
var _btn_play: Button
var _btn_mute: Button
var _btn_loop: Button
var _btn_preview: Button
var _missing := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 固定宽度 210：内容宽 206，16:9 画面区高 116，标题栏 26，按钮区 ~56
	# （宽高全部写死为最小尺寸，避免 AspectRatioContainer 在流式布局里协商失败被压扁）
	custom_minimum_size = Vector2(210, 202)
	# 卡片轮廓 = 全局面板样式（与播放器/媒体库面板同形）：
	# #181C22 底 + 1px #27303A 描边 + 4px 圆角
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# ---- 标题行：纯文字（蓝色序号 + 文件名 + 类型徽标），与面板标题同形 ----
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.custom_minimum_size = Vector2(0, 26)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0, 0, 0, 0)  # 透明：标题行不单独成块
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

	_index_label = Label.new()
	_index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_index_label.add_theme_font_size_override("font_size", 12)
	_index_label.add_theme_color_override("font_color", ACCENT)
	name_row.add_child(_index_label)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", C_TEXT)
	_name_label.clip_text = true
	name_row.add_child(_name_label)

	_type_label = Label.new()
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_label.add_theme_font_size_override("font_size", 10)
	_type_label.add_theme_color_override("font_color", C_TEXT_DIM)
	name_row.add_child(_type_label)

	# ---- 画面区：16:9 黑底 + 1px 描边（与播放器屏幕块同形） ----
	_display = PanelContainer.new()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.custom_minimum_size = Vector2(0, 116)  # 206 内容宽 × 9/16
	var display_style := StyleBoxFlat.new()
	display_style.bg_color = Color.BLACK
	display_style.border_color = C_BORDER
	display_style.set_border_width_all(1)
	_display.add_theme_stylebox_override("panel", display_style)
	vbox.add_child(_display)

	var thumb_area := Control.new()
	thumb_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_area.clip_contents = true
	_display.add_child(thumb_area)

	_glyph = Label.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.add_theme_font_size_override("font_size", 26)
	_glyph.add_theme_color_override("font_color", Color(0.36, 0.4, 0.47))
	thumb_area.add_child(_glyph)

	_thumb = TextureRect.new()
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb_area.add_child(_thumb)

	# ---- 按钮网格：3×2 无缝网格（负间距让相邻 1px 描边重叠成单线） ----
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", -1)
	grid.add_theme_constant_override("v_separation", -1)
	vbox.add_child(grid)

	# U+FE0E 强制文本呈现（防止 🔇🖥 落到彩色 emoji 字体渲染）
	_btn_play = _make_button(grid, "▶", "播放", "推送到输出/投屏播放", func() -> void: push_requested.emit(self))
	_btn_mute = _make_button(grid, "🔇\uFE0E", "静音", "条目级静音（推送到输出时生效）", func() -> void: mute_toggled.emit(self))
	_btn_loop = _make_button(grid, "⟳", "循环", "条目级循环（推送到输出时生效）", func() -> void: loop_toggled.emit(self))
	_btn_preview = _make_button(grid, "🖥\uFE0E", "预览", "加载到预览", func() -> void: preview_requested.emit(self))
	_make_button(grid, "⚙", "设置", "条目设置（缩放/偏移）", func() -> void: settings_requested.emit(self))
	var del := _make_button(grid, "✕", "删除", "从列表移除", func() -> void: delete_requested.emit(self))
	del.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))


func setup(m: MediaObject) -> void:
	media = m
	media_path = m.path
	_name_label.text = m.display_name()
	_type_label.text = MediaObject.type_label(m.type)
	_glyph.text = MediaObject.type_glyph(m.type)
	tooltip_text = m.path
	_refresh_toggles()


func set_index(i: int) -> void:
	_index_label.text = str(i)


## 卡片总高 = 标题 26 + 16:9 画面区 + 按钮区 56 + 描边 4
static func height_for_width(w: int) -> int:
	return 86 + roundi((w - 4) * 9.0 / 16.0)


## 应用卡片规格：宽高全部写死为最小尺寸，卡片不随窗口/分区拉伸
func apply_size(w: int) -> void:
	var dh := roundi((w - 4) * 9.0 / 16.0)
	custom_minimum_size = Vector2(w, 86 + dh)
	_display.custom_minimum_size = Vector2(0, dh)


func set_thumbnail(texture: Texture2D) -> void:
	_thumb.texture = texture
	_glyph.visible = false


func set_highlighted(on: bool) -> void:
	if on:
		_name_label.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	elif not _missing:
		_name_label.add_theme_color_override("font_color", C_TEXT)


## PPT 转换中徽标：类型标签临时替换为"转换中"，结束后恢复类型名
func set_converting(on: bool) -> void:
	if _missing:
		return  # 丢失状态优先，不覆盖
	if on:
		_type_label.text = "转换中"
		_type_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	else:
		_type_label.text = MediaObject.type_label(media.type)
		_type_label.add_theme_color_override("font_color", C_TEXT_DIM)


## 文件丢失标记：源文件被移动/删除后置灰缩略图、禁用播放/预览，
## 类型徽标显示"已丢失"；文件恢复后可取消标记
func set_missing(on: bool) -> void:
	_missing = on
	if on:
		_name_label.add_theme_color_override("font_color", Color(0.45, 0.44, 0.47))
		_type_label.text = "已丢失"
		_type_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.45))
		_thumb.modulate.a = 0.3
		_glyph.modulate.a = 0.3
		_btn_play.disabled = true
		_btn_preview.disabled = true
		tooltip_text = media.path + "\n⚠ 文件不存在（可能已被移动或删除）"
	else:
		_name_label.add_theme_color_override("font_color", C_TEXT)
		_type_label.text = MediaObject.type_label(media.type)
		_type_label.add_theme_color_override("font_color", C_TEXT_DIM)
		_thumb.modulate.a = 1.0
		_glyph.modulate.a = 1.0
		_btn_play.disabled = false
		_btn_preview.disabled = false
		tooltip_text = media.path


## 静音/循环开关状态刷新（条目属性变更后由主窗口调用）
func refresh_toggles() -> void:
	for pair in [[_btn_mute, media.muted], [_btn_loop, media.loop]]:
		var b: Button = pair[0]
		if pair[1]:
			b.add_theme_color_override("font_color", ACCENT)
		else:
			b.remove_theme_color_override("font_color")


func _refresh_toggles() -> void:
	refresh_toggles()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _missing:
			preview_requested.emit(self)
		accept_event()


func _make_button(parent: Control, icon: String, text: String, tip: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	# 图标字形走 Segoe UI Symbol、中文回落微软雅黑（微软雅黑不含 ▶⟳⚙✕ 等符号）；
	# 图标+文字作为整体居中
	b.text = icon + " " + text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


static func _btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = C_BTN_LINE  # 按钮间亮线分隔
	s.set_border_width_all(1)
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
