extends Control
## 网页触点序列的可视化层：叠加在播放画面上（mouse_filter 忽略，不挡点击）。
## 白点 + 序号标注触点位置，当前步高亮为红色。点位为归一化坐标
## （相对 1280×720 浏览器视口），按 KEEP_ASPECT_CENTERED 的纹理摆放
## 矩形映射到本层尺寸——与 PlayerSlot._web_to_browser_pos 互逆。

var _points: Array[Vector2] = []
var _current := -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func set_points(points: Array[Vector2], current: int) -> void:
	if points == _points and current == _current:
		return
	_points = points.duplicate()
	_current = current
	queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		return
	var s := minf(size.x / 1280.0, size.y / 720.0)
	var drawn := Vector2(1280.0, 720.0) * s
	var origin := (size - drawn) / 2.0
	var font := get_theme_default_font()
	for i in _points.size():
		var c := origin + _points[i] * drawn
		var is_cur := i == _current
		draw_circle(c, 8.0 if is_cur else 6.0, Color(0, 0, 0, 0.6))
		draw_circle(c, 6.5 if is_cur else 4.5, Color(1, 0.35, 0.3) if is_cur else Color.WHITE)
		var label := str(i + 1)
		var text_pos := c + Vector2(10, -8)
		draw_string(font, text_pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.8))
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
