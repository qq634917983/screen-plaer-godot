extends Node
## 无边框主窗口的手动边缘缩放。
## 鼠标靠近窗口边缘 6px 显示缩放光标；按下左键后逐帧按鼠标位移调整
## window.position / window.size。全程不进入 Windows 模态缩放循环，
## 播放与投屏画面不冻结。边缘按下会 accept 掉事件，避免同时触发标题栏拖动。

const EDGE := 6

var _resizing := false
var _dir := Vector2i.ZERO  # 各轴 -1/0/1：负 = 拖左/上边，正 = 拖右/下边
var _start_mouse := Vector2i.ZERO
var _start_rect := Rect2i()


func _ready() -> void:
	name = "WindowResizer"
	get_window().min_size = Vector2i(1024, 600)


func _input(event: InputEvent) -> void:
	var win := get_window()
	if win.mode != Window.MODE_WINDOWED:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and not _resizing:
			var d := _edge_dir(win, mb.position)
			if d != Vector2i.ZERO:
				_resizing = true
				_dir = d
				_start_mouse = DisplayServer.mouse_get_position()
				_start_rect = Rect2i(win.position, win.size)
				_set_cursor(d)
				get_viewport().set_input_as_handled()  # 防止同一点击再触发标题栏拖动
		elif not mb.pressed:
			_resizing = false
	elif event is InputEventMouseMotion and not _resizing:
		_set_cursor(_edge_dir(win, (event as InputEventMouseMotion).position))


func _process(_delta: float) -> void:
	if not _resizing:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_resizing = false
		return
	_apply_resize()


func _edge_dir(win: Window, m: Vector2) -> Vector2i:
	var s := Vector2(win.size)
	var d := Vector2i.ZERO
	if m.x < EDGE:
		d.x = -1
	elif m.x >= s.x - EDGE:
		d.x = 1
	if m.y < EDGE:
		d.y = -1
	elif m.y >= s.y - EDGE:
		d.y = 1
	return d


func _set_cursor(d: Vector2i) -> void:
	var shape := Input.CURSOR_ARROW
	if d.x != 0 and d.y != 0:
		shape = Input.CURSOR_BDIAGSIZE if d.x == d.y else Input.CURSOR_FDIAGSIZE
	elif d.x != 0:
		shape = Input.CURSOR_HSIZE
	elif d.y != 0:
		shape = Input.CURSOR_VSIZE
	Input.set_default_cursor_shape(shape)


func _apply_resize() -> void:
	var win := get_window()
	var delta := DisplayServer.mouse_get_position() - _start_mouse
	var rect := _start_rect
	if _dir.x < 0:
		rect.position.x = _start_rect.position.x + delta.x
		rect.size.x = _start_rect.size.x - delta.x
	elif _dir.x > 0:
		rect.size.x = _start_rect.size.x + delta.x
	if _dir.y < 0:
		rect.position.y = _start_rect.position.y + delta.y
		rect.size.y = _start_rect.size.y - delta.y
	elif _dir.y > 0:
		rect.size.y = _start_rect.size.y + delta.y
	var min_sz: Vector2i = win.min_size
	if rect.size.x < min_sz.x:
		if _dir.x < 0:
			rect.position.x = _start_rect.position.x + _start_rect.size.x - min_sz.x
		rect.size.x = min_sz.x
	if rect.size.y < min_sz.y:
		if _dir.y < 0:
			rect.position.y = _start_rect.position.y + _start_rect.size.y - min_sz.y
		rect.size.y = min_sz.y
	win.position = rect.position
	win.size = rect.size
