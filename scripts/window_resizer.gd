extends Node
## 无边框主窗口的手动边缘缩放。
## 鼠标靠近窗口边缘 8px（物理像素）显示缩放光标；按下左键后逐帧按鼠标
## 位移调整 window.position / window.size。全程不进入 Windows 模态缩放
## 循环，播放与投屏画面不冻结。边缘按下会 accept 掉事件，避免同时触发
## 标题栏拖动。
##
## 注意：
## - 边缘判定必须用物理屏幕坐标（DisplayServer.mouse_get_position() 减
##   win.position）：GUI 事件的 position 是视口逻辑坐标，而 win.size 是
##   物理像素——窗口被拉伸时两者不等比（实测逻辑 1229 宽 ↔ 物理 1548），
##   用逻辑坐标比物理宽度会让右/下边缘永远够不到、左/上边缘区变窄
## - 悬停在按钮/滑条等交互控件上时不抢点击也不改光标（标题栏右上角
##   最小化/最大化/关闭按钮的顶部会落进上边缘区，否则点击被吞、
##   光标卡在缩放形状）
## - 光标提示改的是「当前悬停控件」的 mouse_default_cursor_shape：
##   Input.set_default_cursor_shape 在根面板铺满全窗口时永不生效
##   （悬停控件的形状优先，CURSOR_ARROW 是显式箭头而非回落默认）；
##   且必须每帧轮询（_input 先于视口悬停更新，事件驱动目标落后一拍）

const EDGE := 8

var _resizing := false
var _dir := Vector2i.ZERO  # 各轴 -1/0/1：负 = 拖左/上边，正 = 拖右/下边
var _start_mouse := Vector2i.ZERO
var _start_rect := Rect2i()
var _cursor_ctrl: Control = null  # 被临时改了光标的悬停控件
var _cursor_ctrl_orig := Control.CURSOR_ARROW


func _ready() -> void:
	name = "WindowResizer"
	get_window().min_size = Vector2i(1024, 600)


func _input(event: InputEvent) -> void:
	var win := get_window()
	if win.mode != Window.MODE_WINDOWED:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _resizing or _hover_is_interactive():
			return  # 交互控件上的点击不抢（标题栏窗口按钮顶部落在边缘区内）
		var d := _edge_dir(win, DisplayServer.mouse_get_position())
		if d != Vector2i.ZERO:
			_resizing = true
			_dir = d
			_start_mouse = DisplayServer.mouse_get_position()
			_start_rect = Rect2i(win.position, win.size)
			_set_cursor(d)
			get_viewport().set_input_as_handled()  # 防止同一点击再触发标题栏拖动
	else:
		_resizing = false


func _process(_delta: float) -> void:
	var win := get_window()
	if win.mode != Window.MODE_WINDOWED:
		_restore_cursor()
		return
	if _resizing:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_resizing = false
			return
		_apply_resize()
		return
	_set_cursor(_edge_dir(win, DisplayServer.mouse_get_position()))


## 边缘判定（物理屏幕坐标，m_screen 取 DisplayServer.mouse_get_position()）
func _edge_dir(win: Window, m_screen: Vector2i) -> Vector2i:
	var m := Vector2(m_screen - win.position)
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


## 悬停在交互控件（按钮/滑条）上不抢光标不抢点击
func _hover_is_interactive() -> bool:
	var h := get_viewport().gui_get_hovered_control()
	return h is BaseButton or h is Range


func _set_cursor(d: Vector2i) -> void:
	if d == Vector2i.ZERO or _hover_is_interactive():
		_restore_cursor()
		return
	var shape := Control.CURSOR_ARROW
	if d.x != 0 and d.y != 0:
		shape = Control.CURSOR_BDIAGSIZE if d.x == d.y else Control.CURSOR_FDIAGSIZE
	elif d.x != 0:
		shape = Control.CURSOR_HSIZE
	elif d.y != 0:
		shape = Control.CURSOR_VSIZE
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		_restore_cursor()
		return
	if hovered != _cursor_ctrl:
		_restore_cursor()
		_cursor_ctrl = hovered
		_cursor_ctrl_orig = hovered.mouse_default_cursor_shape
	_cursor_ctrl.mouse_default_cursor_shape = shape


func _restore_cursor() -> void:
	if _cursor_ctrl != null:
		if is_instance_valid(_cursor_ctrl):
			_cursor_ctrl.mouse_default_cursor_shape = _cursor_ctrl_orig
		_cursor_ctrl = null


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
