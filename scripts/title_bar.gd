@tool
extends PanelContainer
## 无边框主窗口的自绘标题栏。
## 拖动由代码逐帧设置 window.position 实现，不进入 Windows 拖动窗口时的
## 模态消息循环——拖动主窗口时播放与投屏画面不再冻结。
## 窗口边缘 6px 是 WindowResizer 的手动缩放区，本组件不响应。

const RESIZE_MARGIN := 6.0

signal close_requested

var _title_label: Label
var _max_button: Button
var _close_button: Button
var _closing := false
var _dragging := false
var _drag_offset := Vector2i.ZERO
var _windowed_rect := Rect2i()  # 最近的窗口态几何（最大化还原时手动恢复）
var _restoring := false  # 还原几何写回期间暂停记录 _windowed_rect
var _want_mode := -1  # 期望的窗口 mode：无边框窗口的 mode 切换偶发被系统丢弃，逐帧校验重试
var _want_mode_frames := 0


func _ready() -> void:
	name = "TitleBar"
	custom_minimum_size = Vector2(0, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.145, 0.205)
	style.border_width_bottom = 1
	style.border_color = Color(0.1529, 0.1765, 0.2196)
	style.content_margin_left = 10
	style.content_margin_right = 0
	add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hbox)

	_title_label = Label.new()
	_title_label.text = "ScreenPlayer"
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = MOUSE_FILTER_IGNORE  # 让拖动在文字上也生效
	_title_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	hbox.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var min_button := _make_button("─", Color(0.2, 0.23, 0.28))
	min_button.pressed.connect(func() -> void: _request_mode(Window.MODE_MINIMIZED))
	hbox.add_child(min_button)

	_max_button = _make_button("▢", Color(0.2, 0.23, 0.28))
	_max_button.pressed.connect(_toggle_maximize)
	hbox.add_child(_max_button)

	_close_button = _make_button("✕", Color(0.75, 0.2, 0.2))
	_close_button.name = "CloseButton"
	_close_button.pressed.connect(_begin_close)
	hbox.add_child(_close_button)

	gui_input.connect(_on_gui_input)


func set_title(text: String) -> void:
	_title_label.text = text


func _make_button(text: String, hover_color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 30)
	b.mouse_default_cursor_shape = CURSOR_ARROW
	b.add_theme_font_size_override("font_size", 13)
	var hover := StyleBoxFlat.new()
	hover.bg_color = hover_color
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = hover_color.darkened(0.2)
	b.add_theme_stylebox_override("pressed", pressed)
	return b


## 先给出明确的按压/关闭反馈，再让主场景执行资源清理和退出。
## 约 0.14 秒的动画足够被看见，不会明显增加等待感。
func _begin_close() -> void:
	if Engine.is_editor_hint() or _closing:
		return
	_closing = true
	_dragging = false
	_close_button.disabled = true
	_close_button.text = "…"
	_close_button.pivot_offset = _close_button.size * 0.5
	_title_label.text = "ScreenPlayer · 正在关闭…"
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_close_button, "scale", Vector2(0.78, 0.78), 0.055)
	tween.tween_property(_close_button, "scale", Vector2.ONE, 0.085)
	await tween.finished
	close_requested.emit()


func _toggle_maximize() -> void:
	if get_window().mode == Window.MODE_MAXIMIZED:
		_request_mode(Window.MODE_WINDOWED)
		_restore_windowed_rect()
	else:
		_windowed_rect = Rect2i(get_window().position, get_window().size)
		_request_mode(Window.MODE_MAXIMIZED)


## mode 切换请求在无边框窗口上偶发被系统丢弃，记录期望值逐帧校验并重试
func _request_mode(m: int) -> void:
	if Engine.is_editor_hint():
		return
	get_window().mode = m as Window.Mode
	_want_mode = m
	_want_mode_frames = 0


## 无边框窗口从最大化还原时系统不恢复旧几何（保持最大化时的铺满尺寸），
## 手动恢复；mode 切换异步生效，等两帧再写回
func _restore_windowed_rect() -> void:
	_restoring = true
	await get_tree().process_frame
	await get_tree().process_frame
	var win := get_window()
	if win.mode != Window.MODE_MAXIMIZED and _windowed_rect.size.x > 0:
		win.position = _windowed_rect.position
		win.size = _windowed_rect.size
	_restoring = false


func _on_gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		# 边缘 6px 留给 WindowResizer 做手动缩放
		if mb.position.x < RESIZE_MARGIN or mb.position.x > size.x - RESIZE_MARGIN or mb.position.y < RESIZE_MARGIN:
			return
		var win := get_window()
		if mb.double_click:
			_dragging = false
			_toggle_maximize()
		else:
			if win.mode == Window.MODE_MAXIMIZED:
				# 最大化下拖动：先还原，让标题栏跟随光标（保持水平相对位置）；
				# mode 异步生效，还原后的尺寸取最大化前记录的 _windowed_rect
				var frac := clampf(float(DisplayServer.mouse_get_position().x - win.position.x) / maxf(1.0, float(win.size.x)), 0.0, 1.0)
				var restored_w := _windowed_rect.size.x if _windowed_rect.size.x > 0 else win.size.x
				_request_mode(Window.MODE_WINDOWED)
				_restore_windowed_rect()
				_drag_offset = Vector2i(int(restored_w * frac), int(size.y / 2.0))
			else:
				_drag_offset = DisplayServer.mouse_get_position() - win.position
			_dragging = true
	else:
		_dragging = false
	accept_event()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var win := get_window()
	# mode 切换请求偶发被系统丢弃：逐帧校验，5 帧未落地就重试
	if _want_mode != -1:
		if win.mode == _want_mode:
			_want_mode = -1
		else:
			_want_mode_frames += 1
			if _want_mode_frames >= 5:
				win.mode = _want_mode as Window.Mode
				_want_mode_frames = 0
	# 最大化/还原的 mode 异步生效，每帧轮询同步按钮字形
	var want := "❐" if win.mode == Window.MODE_MAXIMIZED else "▢"
	if _max_button.text != want:
		_max_button.text = want
	# 持续记录窗口态几何供最大化还原（mode 切换过渡/拖动/还原写回期间不记）
	if _want_mode == -1 and win.mode == Window.MODE_WINDOWED and not _dragging and not _restoring:
		_windowed_rect = Rect2i(win.position, win.size)
	if not _dragging:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		return
	win.position = DisplayServer.mouse_get_position() - _drag_offset
